// AFAdaptyOnboardingProvider.swift
// AdaptyFlowKit SDK
//
// Implementation of OnboardingProvider for Adapty Onboarding SDK.

import UIKit
import Adapty
import AdaptyUI

// MARK: - AFAdaptyOnboardingProvider

/// Onboarding provider based on Adapty.
/// Conforms to `AFOnboardingProvider` — fully replaceable.
///
/// Timeouts are read from `AFOnboardingKit.fetchTimeout` / `AFOnboardingKit.displayTimeout`
/// at presentation time — no need to pass them manually.
///
/// **What it solves compared to the original:**
/// - Instead of 4 bool flags — `OnboardingState` enum
/// - Timeout logic encapsulated in `AFAdaptyOnboardingDelegateHandler`
/// - "Alive signal" (octopusbuilder bug fix) in delegate, not in VC
/// - Permission requests through `AFOnboardingPermissionHandler` protocol
/// - Shared `AFNetworkReachability` instead of creating a new monitor each time
public final class AFAdaptyOnboardingProvider: AFOnboardingProvider {

    // MARK: - Dependencies

    private let permissionHandler: AFOnboardingPermissionHandler?

    // MARK: - Init

    /// - Parameter permissionHandler: Handles permission requests from Adapty onboarding
    ///   (e.g. notifications, ATT). Usually `self` from AppDelegate.
    public init(permissionHandler: AFOnboardingPermissionHandler? = nil) {
        self.permissionHandler = permissionHandler
    }

    // MARK: - AFOnboardingProvider

    @MainActor
    public func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> AFOnboardingResult {
        // Read timeouts from global static properties at call time
        let fetchTimeout = AFOnboardingKit.fetchTimeout
        let displayTimeout = AFOnboardingKit.displayTimeout

        do {
            // 1. Fetch
            let onboarding = try await withTimeout(fetchTimeout) {
                try await Adapty.getOnboarding(placementId: placementId)
            }

            // 2. Configuration
            let configuration = try AdaptyUI.getOnboardingConfiguration(forOnboarding: onboarding)

            // 3. Show controller via continuation
            return await showController(
                configuration: configuration,
                from: presenter,
                displayTimeout: displayTimeout
            )

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
        from presenter: UIViewController,
        displayTimeout: TimeInterval
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

    // MARK: - Timeout helper

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

    private enum State {
        case waitingForLoad
        case alive
        case done
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

    func beginDisplayTimeout() {
        guard case .waitingForLoad = state else { return }

        displayTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.displayTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard case .waitingForLoad = self.state else { return }
            self.finish(controller: nil, with: .failed(.displayTimeout))
        }
    }

    private func cancelDisplayTimeout() {
        displayTimeoutTask?.cancel()
        displayTimeoutTask = nil
    }

    // MARK: - Alive signal
    // Adapty onboarding may never send `didFinishLoading` due to octopusbuilder bug.
    // Any analytics/state event confirms the content is alive — cancel timeout.

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

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        didFinishLoading action: OnboardingsDidFinishLoadingAction
    ) {
        handleAliveSignal()
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onAnalyticsEvent event: AdaptyOnboardingsAnalyticsEvent
    ) {
        handleAliveSignal()
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onStateUpdatedAction action: AdaptyOnboardingsStateUpdatedAction
    ) {
        handleAliveSignal()
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onCloseAction action: AdaptyOnboardingsCloseAction
    ) {
        finish(controller: controller, with: .completed)
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        didFailWithError error: AdaptyUIError
    ) {
        finish(controller: controller, with: .failed(.providerError(error)))
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onCustomAction action: AdaptyOnboardingsCustomAction
    ) {
        let permAction = AFOnboardingPermissionAction(actionId: action.actionId)
        permissionHandler?.handlePermission(permAction)
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onPaywallAction action: AdaptyOnboardingsOpenPaywallAction
    ) {
        // Adapty SDK opens paywall automatically.
    }
}
