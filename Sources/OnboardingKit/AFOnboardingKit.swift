// AFOnboardingKit.swift
// AdaptyFlowKit SDK
//
// Main entry point for OnboardingKit.
// Mirrors PaywallKit.swift — same idioms, same configure/show pattern.

import UIKit

// MARK: - OnboardingKit

/// Main OnboardingKit class.
///
/// ```swift
/// // AppDelegate
/// OnboardingKit.configure(
///     configuration: .init(fetchTimeout: 10, displayTimeout: 15),
///     primaryProvider: AFAdaptyOnboardingProvider(
///         fetchTimeout: 10,    // ← must match configuration.fetchTimeout
///         displayTimeout: 15   // ← must match configuration.displayTimeout
///     ),
///     fallbackUI: MyOnboardingViewController.self
/// )
///
/// // Anywhere
/// let result = await OnboardingKit.shared.show(placementId: "main", from: self)
/// ```
///
/// > **Important about timeouts:**
/// > `OnboardingKitConfiguration.fetchTimeout` / `displayTimeout` are used
/// > for logging and documenting intent. Actual timeouts are controlled by the provider
/// > (e.g. `AFAdaptyOnboardingProvider.init(fetchTimeout:displayTimeout:)`).
/// > Ensure values match — SDK cannot pass them automatically,
/// > because the provider is already created before `configure()` is called.
@MainActor
public final class AFOnboardingKit {

    // MARK: - Singleton

    public static let shared = AFOnboardingKit()
    private init() {}

    // MARK: - State

    private var configuration: AFOnboardingKitConfiguration?
    private var primaryProvider: AFOnboardingProvider?
    private var fallbackProvider: AFOnboardingProvider?
    private var eventHandler: AFOnboardingEventHandler?
    private var logger: AFPaywallKitLogger = AFConsoleLogger()

    // MARK: - Storage key for "has completed onboarding"

    private let completionKey = "FlowKit.onboardingCompleted"

    /// `true` if user has already completed onboarding (persisted in UserDefaults).
    public var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completionKey) }
        set { UserDefaults.standard.set(newValue, forKey: completionKey) }
    }

    // MARK: - Configure

    /// Basic configuration with custom fallback provider.
    public static func configure(
        configuration: AFOnboardingKitConfiguration = .init(),
        primaryProvider: AFOnboardingProvider,
        fallbackProvider: AFOnboardingProvider? = nil,
        eventHandler: AFOnboardingEventHandler? = nil
    ) {
        let kit = AFOnboardingKit.shared
        kit.configuration = configuration
        kit.primaryProvider = primaryProvider
        kit.fallbackProvider = fallbackProvider
        kit.eventHandler = eventHandler
        kit.logger = configuration.logger ?? AFConsoleLogger()
        kit.log("Configured. Primary: \(type(of: primaryProvider))", level: .info)
    }

    /// Convenient configuration — pass your class as fallback UI.
    ///
    /// ```swift
    /// OnboardingKit.configure(
    ///     primaryProvider: AFAdaptyOnboardingProvider(),
    ///     fallbackUI: MyOnboardingViewController.self
    /// )
    /// ```
    public static func configure(
        configuration: AFOnboardingKitConfiguration = .init(),
        primaryProvider: AFOnboardingProvider,
        fallbackUI: (any AFOnboardingKitUI.Type)? = nil,
        eventHandler: AFOnboardingEventHandler? = nil
    ) {
        let fallback = fallbackUI.map { AFFallbackOnboardingProvider(uiType: $0) }
        configure(
            configuration: configuration,
            primaryProvider: primaryProvider,
            fallbackProvider: fallback,
            eventHandler: eventHandler
        )
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
            log("show() called before configure().", level: .error)
            return .failed(.notConfigured)
        }

        // FIX #1: `force` was previously declared but never used.
        // If user has already completed onboarding and force == false — return .skipped
        // without showing any UI. This check is the main purpose of `hasCompleted`.
        guard force || !hasCompleted else {
            log("Already completed — skipping. Use force: true to override.", level: .debug)
            return .skipped
        }

        // Check network — if unavailable, fallback immediately
        let cfg = configuration!
        let hasNetwork: Bool

        if cfg.skipNetworkCheck {
            hasNetwork = true
        } else {
            hasNetwork = await AFNetworkReachability.shared.isAvailable()
        }

        log("Network: \(hasNetwork ? "✓" : "✗"), placement: \(placementId)", level: .debug)

        let result: AFOnboardingResult

        if hasNetwork {
            result = await showWithPrimary(placementId: placementId, from: presenter)
        } else {
            log("No network — going directly to fallback.", level: .info)
            result = await showFallback(placementId: placementId, from: presenter)
        }

        // Persist and notify
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
            log("Primary failed — switching to fallback.", level: .warning)
            return await showFallback(placementId: placementId, from: presenter)
        }

        return result
    }

    private func showFallback(placementId: String, from presenter: UIViewController) async -> AFOnboardingResult {
        guard let provider = fallbackProvider else {
            log("❌ No fallback provider registered.", level: .error)
            return .failed(.noFallbackUI)
        }
        log("🔄 Showing fallback provider: \(type(of: provider))", level: .info)
        let result = await provider.present(placementId: placementId, from: presenter)
        log("✅ Fallback provider finished with result: \(result)", level: .info)
        return result
    }

    private func handleResult(_ result: AFOnboardingResult, placementId: String) {
        switch result {
        case .completed:
            log("✅ Onboarding completed.", level: .info)
            eventHandler?.onOnboardingCompleted(placementId: placementId)
            // FIX #2: Notification now sent for both .completed and .skipped.
            // Comment in Notification.Name said "after .completed or .skipped",
            // but .skipped previously didn't send notification — listeners never knew.
            NotificationCenter.default.post(name: .onboardingKitCompleted, object: nil)

        case .skipped:
            log("↩️ Onboarding skipped.", level: .info)
            eventHandler?.onOnboardingSkipped(placementId: placementId)
            // FIX #2: added — symmetric to .completed.
            NotificationCenter.default.post(name: .onboardingKitCompleted, object: nil)

        case .failed(let error):
            log("❌ \(error.localizedDescription)", level: .error)
            eventHandler?.onOnboardingFailed(error: error, placementId: placementId)
        }
    }

    // MARK: - Helpers

    private var isConfigured: Bool {
        configuration != nil && primaryProvider != nil
    }

    private func log(_ message: String, level: AFPaywallKitLogLevel) {
        logger.log("[OnboardingKit] \(message)", level: level)
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Sent after .completed or .skipped.
    /// Listen to this notification to know when onboarding is finished in any scenario.
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
