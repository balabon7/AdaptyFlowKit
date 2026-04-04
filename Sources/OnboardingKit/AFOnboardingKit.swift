// AFOnboardingKit.swift
// AdaptyFlowKit SDK
//
// Main entry point for OnboardingKit.

import UIKit

// MARK: - OnboardingKit

/// Main OnboardingKit class.
///
/// **Usage:**
/// ```swift
/// // AppDelegate — set static properties, then call configure()
/// AFOnboardingKit.fetchTimeout = 10
/// AFOnboardingKit.displayTimeout = 15
/// AFDefaultOnboardingAdapter.pages = [ ... ]
/// AFOnboardingKit.configure(
///     primaryProvider: AFAdaptyOnboardingProvider(permissionHandler: self),
///     fallbackUI: AFDefaultOnboardingAdapter.self
/// )
///
/// // Anywhere
/// let result = await AFOnboardingKit.shared.show(placementId: "main", from: self)
/// ```
@MainActor
public final class AFOnboardingKit {

    // MARK: - Global Configuration Properties

    /// Timeout for loading onboarding from server. Default: 10 seconds.
    public static var fetchTimeout: TimeInterval = 10.0

    /// Timeout after showing controller — if didFinishLoading never arrives.
    /// SDK falls back to fallback UI. Default: 15 seconds.
    public static var displayTimeout: TimeInterval = 15.0

    /// Skip network check before attempting primary provider.
    /// Use `true` for testing. Default: false.
    public static var skipNetworkCheck: Bool = false

    // MARK: - Singleton

    public static let shared = AFOnboardingKit()
    private init() {}

    // MARK: - Internal State

    private var isSetup = false
    private var primaryProvider: AFOnboardingProvider?
    private var fallbackProvider: AFOnboardingProvider?
    private var eventHandler: AFOnboardingEventHandler?

    // MARK: - Storage key for "has completed onboarding"

    private let completionKey = "FlowKit.onboardingCompleted"

    /// `true` if user has already completed onboarding (persisted in UserDefaults).
    public var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completionKey) }
        set { UserDefaults.standard.set(newValue, forKey: completionKey) }
    }

    // MARK: - Configure

    /// Configures with a primary provider and custom fallback UI type.
    ///
    /// - Parameters:
    ///   - primaryProvider: Main onboarding provider (e.g. `AFAdaptyOnboardingProvider`).
    ///   - fallbackUI: ViewController type used as fallback (e.g. `AFDefaultOnboardingAdapter.self`).
    ///   - eventHandler: Optional delegate for onboarding lifecycle events.
    public static func configure(
        primaryProvider: AFOnboardingProvider,
        fallbackUI: (any AFOnboardingKitUI.Type)? = nil,
        eventHandler: AFOnboardingEventHandler? = nil
    ) {
        let fallback = fallbackUI.map { AFFallbackOnboardingProvider(uiType: $0) }
        configure(
            primaryProvider: primaryProvider,
            fallbackProvider: fallback,
            eventHandler: eventHandler
        )
    }

    /// Full configuration with custom providers (advanced).
    public static func configure(
        primaryProvider: AFOnboardingProvider,
        fallbackProvider: AFOnboardingProvider? = nil,
        eventHandler: AFOnboardingEventHandler? = nil
    ) {
        let kit = AFOnboardingKit.shared
        kit.primaryProvider = primaryProvider
        kit.fallbackProvider = fallbackProvider
        kit.eventHandler = eventHandler
        kit.isSetup = true
    }

    // MARK: - Show

    /// Shows onboarding. Automatically falls back on primary failure.
    ///
    /// - Parameters:
    ///   - placementId: Placement identifier from Adapty dashboard.
    ///   - from: ViewController for presentation.
    ///   - force: Ignores `hasCompleted` and always shows. For testing.
    @discardableResult
    public func show(
        placementId: String,
        from presenter: UIViewController,
        force: Bool = false
    ) async -> AFOnboardingResult {
        guard isConfigured else {
            return .failed(.notConfigured)
        }

        guard force || !hasCompleted else {
            return .skipped
        }

        let hasNetwork: Bool
        if Self.skipNetworkCheck {
            hasNetwork = true
        } else {
            hasNetwork = await AFNetworkReachability.shared.isAvailable()
        }

        let result: AFOnboardingResult
        if hasNetwork {
            result = await showWithPrimary(placementId: placementId, from: presenter)
        } else {
            result = await showFallback(placementId: placementId, from: presenter)
        }

        if result.isFinished {
            hasCompleted = true
        }

        handleResult(result, placementId: placementId)
        return result
    }

    // MARK: - Internal

    private func showWithPrimary(placementId: String, from presenter: UIViewController) async -> AFOnboardingResult {
        guard let provider = primaryProvider else { return .failed(.notConfigured) }
        let result = await provider.present(placementId: placementId, from: presenter)
        // Fallback only on technical error — not on .completed/.skipped
        if case .failed = result {
            return await showFallback(placementId: placementId, from: presenter)
        }
        return result
    }

    private func showFallback(placementId: String, from presenter: UIViewController) async -> AFOnboardingResult {
        guard let provider = fallbackProvider else {
            return .failed(.noFallbackUI)
        }
        return await provider.present(placementId: placementId, from: presenter)
    }

    private func handleResult(_ result: AFOnboardingResult, placementId: String) {
        switch result {
        case .completed:
            eventHandler?.onOnboardingCompleted(placementId: placementId)
            NotificationCenter.default.post(name: .onboardingKitCompleted, object: nil)
        case .skipped:
            eventHandler?.onOnboardingSkipped(placementId: placementId)
            NotificationCenter.default.post(name: .onboardingKitCompleted, object: nil)
        case .failed(let error):
            eventHandler?.onOnboardingFailed(error: error, placementId: placementId)
        }
    }

    // MARK: - Helpers

    private var isConfigured: Bool { isSetup && primaryProvider != nil }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Sent after onboarding is finished (.completed or .skipped).
    ///
    /// ```swift
    /// NotificationCenter.default.addObserver(
    ///     forName: .onboardingKitCompleted,
    ///     object: nil,
    ///     queue: .main
    /// ) { _ in
    ///     // Navigate to main screen
    /// }
    /// ```
    static let onboardingKitCompleted = Notification.Name("OnboardingKit.completed")
}
