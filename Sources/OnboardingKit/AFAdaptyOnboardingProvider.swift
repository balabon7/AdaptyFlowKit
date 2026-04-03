// AFAdaptyOnboardingProvider.swift
// AdaptyFlowKit SDK
//
// Implementation of OnboardingProvider for Adapty Onboarding SDK.
// Solves all issues with AdaptyOnboardingViewController + OnboardingService.

import UIKit
import Adapty
import AdaptyUI

// MARK: - AFAdaptyOnboardingProvider

/// Onboarding provider based on Adapty.
/// Conforms to `AFOnboardingProvider` — fully replaceable.
///
/// **What it solves compared to the original:**
/// - Instead of 4 bool flags — `OnboardingState` enum
/// - Timeout logic encapsulated in `AFAdaptyOnboardingDelegateHandler`
/// - "Alive signal" (octopusbuilder bug fix) in delegate, not in VC
/// - Permission requests through `AFOnboardingPermissionHandler` protocol
/// - Shared `AFNetworkReachability` instead of creating a new monitor each time
public final class AFAdaptyOnboardingProvider: AFOnboardingProvider {

    // MARK: - Dependencies

    private let fetchTimeout: TimeInterval
    private let displayTimeout: TimeInterval
    private let permissionHandler: AFOnboardingPermissionHandler?

    // MARK: - Init

    public init(
        fetchTimeout: TimeInterval = 10.0,
        displayTimeout: TimeInterval = 15.0,
        permissionHandler: AFOnboardingPermissionHandler? = nil
    ) {
        self.fetchTimeout = fetchTimeout
        self.displayTimeout = displayTimeout
        self.permissionHandler = permissionHandler
    }

    // MARK: - AFOnboardingProvider

    @MainActor
    public func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> AFOnboardingResult {
        do {
            // 1. Fetch
            let onboarding = try await withTimeout(fetchTimeout) {
                try await Adapty.getOnboarding(placementId: placementId)
            }

            // 2. Configuration
            let configuration = try AdaptyUI.getOnboardingConfiguration(forOnboarding: onboarding)

            // 3. Show controller via continuation
            return await showController(configuration: configuration, from: presenter)

        } catch let error as AFOnboardingKitError {
            return .failed(error)
        } catch {
            return .failed(.providerError(error))
        }
    }

    // MARK: - Private

    @MainActor
    private func showController(
        configuration: AdaptyUI.OnboardingConfiguration,
        from presenter: UIViewController
    ) async -> AFOnboardingResult {
        await withCheckedContinuation { continuation in
            let sink = AFSingleFireContinuation(continuation)
            let delegate = AFAdaptyOnboardingDelegateHandler(
                completion: sink,
                displayTimeout: displayTimeout,
                permissionHandler: permissionHandler
            )

            do {
                let controller = try AdaptyUI.onboardingController(
                    with: configuration,
                    delegate: delegate
                )
                controller.modalPresentationStyle = .fullScreen
                delegate.retain(on: controller)

                presenter.present(controller, animated: true) {
                    // Timeout starts only after the controller is actually displayed
                    delegate.beginDisplayTimeout()
                }
            } catch {
                sink.resume(with: .failed(.providerError(error)))
            }
        }
    }

    // MARK: - Timeout

    private func withTimeout<T>(
        _ seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AFOnboardingKitError.fetchTimeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

// MARK: - AFAdaptyOnboardingDelegateHandler

/// Receives events from AdaptyUI and converts them to `AFOnboardingResult`.
///
/// **Key differences from the original:**
/// 1. `AFSingleFireContinuation` instead of `isCompleted` bool
/// 2. State machine instead of separate flags
/// 3. "Alive signal" logic encapsulated here
/// 4. `beginDisplayTimeout()` is called after the controller is actually displayed
private final class AFAdaptyOnboardingDelegateHandler: NSObject, AdaptyOnboardingControllerDelegate {

    // MARK: - State

    /// Replaces 4 bool flags from the original code.
    private enum State {
        case waitingForLoad     // Controller displayed, waiting for didFinishLoading or alive signal
        case alive              // Content is alive — timeout canceled
        case done               // Continuation already called
    }

    private var state: State = .waitingForLoad

    // MARK: - Dependencies

    private let completion: AFSingleFireContinuation<AFOnboardingResult>
    private let displayTimeout: TimeInterval
    private weak var permissionHandler: AFOnboardingPermissionHandler?

    // MARK: - Timeout

    private var displayTimeoutTask: Task<Void, Never>?

    // MARK: - Init

    init(
        completion: AFSingleFireContinuation<AFOnboardingResult>,
        displayTimeout: TimeInterval,
        permissionHandler: AFOnboardingPermissionHandler?
    ) {
        self.completion = completion
        self.displayTimeout = displayTimeout
        self.permissionHandler = permissionHandler
    }

    // MARK: - Lifetime

    func retain(on controller: UIViewController) {
        objc_setAssociatedObject(
            controller,
            &AFAdaptyOnboardingDelegateHandler.retainKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
    private static var retainKey: UInt8 = 0

    // MARK: - Display timeout

    /// Called after `present(_:animated:completion:)` — that is, when the controller is actually visible.
    /// The original code started the timeout before display, which gave inaccurate results.
    func beginDisplayTimeout() {
        guard case .waitingForLoad = state else { return }

        displayTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.displayTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard case .waitingForLoad = self.state else { return }

            // Timeout triggered — onboarding never loaded
            // Finish as failed so OnboardingKit can show fallback
            self.finish(controller: nil, with: .failed(.displayTimeout))
        }
    }

    private func cancelDisplayTimeout() {
        displayTimeoutTask?.cancel()
        displayTimeoutTask = nil
    }

    // MARK: - "Alive signal" (octopusbuilder bug fix)
    //
    // Adapty onboarding may never send `didFinishLoading`
    // due to the "Unable to hide query parameters from script (missing data)" bug.
    // But if analytics or state events arrive — the content is clearly alive and visible.
    // Therefore, any of them cancels the display timeout.

    private func handleAliveSignal() {
        guard case .waitingForLoad = state else { return }
        state = .alive
        cancelDisplayTimeout()
    }

    // MARK: - Completion

    private func finish(controller: AdaptyOnboardingController?, with result: AFOnboardingResult) {
        guard case .done = state else {
            state = .done
            cancelDisplayTimeout()

            guard let controller else {
                completion.resume(with: result)
                return
            }
            controller.dismiss(animated: true) {
                self.completion.resume(with: result)
            }
            return
        }
    }

    // MARK: - AdaptyOnboardingControllerDelegate

    // ── Loading ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        didFinishLoading action: OnboardingsDidFinishLoadingAction
    ) {
        handleAliveSignal()  // didFinishLoading — the most reliable alive signal
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onAnalyticsEvent event: AdaptyOnboardingsAnalyticsEvent
    ) {
        // Analytics events come from web content → content is clearly alive
        handleAliveSignal()
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onStateUpdatedAction action: AdaptyOnboardingsStateUpdatedAction
    ) {
        // State updates also confirm that content is working
        handleAliveSignal()
    }

    // ── Close ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onCloseAction action: AdaptyOnboardingsCloseAction
    ) {
        finish(controller: controller, with: .completed)
    }

    // ── Error ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        didFailWithError error: AdaptyUIError
    ) {
        finish(controller: controller, with: .failed(.providerError(error)))
    }

    // ── Custom actions (permissions) ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onCustomAction action: AdaptyOnboardingsCustomAction
    ) {
        let permAction = AFOnboardingPermissionAction(actionId: action.actionId)
        permissionHandler?.handlePermission(permAction)
    }

    // ── Paywall from onboarding ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onPaywallAction action: AdaptyOnboardingsOpenPaywallAction
    ) {
        // Adapty SDK opens paywall automatically.
        // If custom logic is needed — extend through AFOnboardingEventHandler.
    }
}
