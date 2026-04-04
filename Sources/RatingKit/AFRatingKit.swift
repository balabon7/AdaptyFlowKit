// AFRatingKit.swift
// AppSceneKit
//
// Smart rating request with pre-prompt.
// Protects Apple quota (3 times/year) from unhappy users.

import UIKit
import StoreKit

// MARK: - RatingKit

/// Requests rating through custom pre-prompt.
///
/// **Flow:**
/// ```
/// requestIfNeeded() → pre-prompt "Do you like it?"
///     ├── Yes → SKStoreReviewController.requestReview()
///     └── No  → feedback URL or silent dismiss
/// ```
///
/// **Usage:**
/// ```swift
/// // AppDelegate
/// RatingKit.configure(
///     configuration: .init(
///         appName: "PDF Editor",
///         minDaysBetweenPrompts: 14,
///         negativeFeedbackURL: URL(string: "mailto:support@app.com")
///     )
/// )
///
/// // After successful user action
/// RatingKit.shared.requestIfNeeded(from: self)
/// ```
@MainActor
public final class AFRatingKit {

    // MARK: - Singleton

    public static let shared = AFRatingKit()
    private init() {}

    // MARK: - State

    private var configuration: AFRatingKitConfiguration = .init()
    private var eventHandler: AFRatingEventHandler?

    // MARK: - Configure

    public static func configure(
        configuration: AFRatingKitConfiguration = .init(),
        eventHandler: AFRatingEventHandler? = nil
    ) {
        shared.configuration = configuration
        shared.eventHandler = eventHandler
    }

    // MARK: - Public API

    /// Shows pre-prompt if throttle allows.
    /// Does nothing if: shown recently, version limit exhausted, or user already rated.
    ///
    /// - Parameter presenter: ViewController for presentation.
    /// - Parameter force: Ignores throttle. For testing.
    @discardableResult
    public func requestIfNeeded(
        from presenter: UIViewController,
        force: Bool = false
    ) async -> AFRatingResult {
        guard force || shouldShowPrompt() else {
            return .throttled
        }
        return await showPrompt(from: presenter)
    }

    /// Resets all statistics. For testing.
    public func resetState() {
        storage.reset()
    }

    // MARK: - Throttle

    private func shouldShowPrompt() -> Bool {
        // 1. User already clicked "Like" and we already showed Apple prompt
        if storage.hasRatedThisVersion { return false }

        // 2. Minimum interval between prompts
        if let lastDate = storage.lastPromptDate {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            guard daysSince >= configuration.minDaysBetweenPrompts else { return false }
        }

        return true
    }

    // MARK: - Show

    private func showPrompt(from presenter: UIViewController) async -> AFRatingResult {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<AFRatingResult, Never>) in
            let sink = AFSingleFireContinuation(continuation)
            let vc = AFRatingPromptViewController(
                configuration: configuration,
                accentColor: AFAppearance.accentColor,
                onResult: { result in
                    sink.resume(with: result)
                }
            )
            vc.modalPresentationStyle = .overFullScreen
            vc.modalTransitionStyle = .crossDissolve
            presenter.present(vc, animated: false)
        }

        handleResult(result)
        return result
    }

    // MARK: - Handle result

    private func handleResult(_ result: AFRatingResult) {
        let version = appVersion

        switch result {
        case .positive:
            storage.setHasRated(for: version)
            storage.lastPromptDate = Date()
            requestAppleReview()
            eventHandler?.onPositiveFeedback()

        case .negative:
            storage.lastPromptDate = Date()
            if let url = configuration.negativeFeedbackURL {
                UIApplication.shared.open(url)
            }
            eventHandler?.onNegativeFeedback()

        case .dismissed:
            // DON'T save statistics on dismiss - user just closed without choosing
            // This will allow showing rating again on next launch
            eventHandler?.onDismissed()

        case .throttled:
            break
        }
    }

    // MARK: - Apple Review

    private func requestAppleReview() {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            if #available(iOS 16.0, *) {
                AppStore.requestReview(in: scene)
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    // MARK: - Storage

    private let storage = AFRatingStorage()
}

// MARK: - AFRatingKitConfiguration

public struct AFRatingKitConfiguration: Sendable {

    /// App name — displayed in pre-prompt.
    public let appName: String

    /// Minimum days between pre-prompt displays. Default: 30.
    public let minDaysBetweenPrompts: Int

    /// URL for unhappy users. For example: mailto:support@app.com
    /// If `nil` — just dismiss without action.
    public let negativeFeedbackURL: URL?

    nonisolated public init(
        appName: String = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
        minDaysBetweenPrompts: Int = 30,
        negativeFeedbackURL: URL? = nil
    ) {
        self.appName = appName
        self.minDaysBetweenPrompts = minDaysBetweenPrompts
        self.negativeFeedbackURL = negativeFeedbackURL
    }
}

// MARK: - AFRatingResult

public enum AFRatingResult: Sendable {
    case positive    // User is happy → Apple prompt shown
    case negative    // User is unhappy → feedback URL opened (or dismiss)
    case dismissed   // User closed without answering
    case throttled   // Throttle — prompt was not shown
}

// MARK: - AFRatingEventHandler

public protocol AFRatingEventHandler: AnyObject {
    func onPositiveFeedback()
    func onNegativeFeedback()
    func onDismissed()
}

public extension AFRatingEventHandler {
    func onPositiveFeedback() {}
    func onNegativeFeedback() {}
    func onDismissed()        {}
}

// MARK: - AFRatingStorage (internal)

private final class AFRatingStorage {

    private enum Keys {
        static let lastPromptDate = "RatingKit.lastPromptDate"
        static let ratedVersions  = "RatingKit.ratedVersions"   // [String]
    }

    private let defaults = UserDefaults.standard

    var lastPromptDate: Date? {
        get { defaults.object(forKey: Keys.lastPromptDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastPromptDate) }
    }

    var hasRatedThisVersion: Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let rated = defaults.stringArray(forKey: Keys.ratedVersions) ?? []
        return rated.contains(version)
    }

    func setHasRated(for version: String) {
        var rated = defaults.stringArray(forKey: Keys.ratedVersions) ?? []
        if !rated.contains(version) { rated.append(version) }
        defaults.set(rated, forKey: Keys.ratedVersions)
    }

    func reset() {
        [Keys.lastPromptDate, Keys.ratedVersions]
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
