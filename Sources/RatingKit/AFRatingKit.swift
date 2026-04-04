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
/// // AppDelegate — configure via static properties, then call configure()
/// AFRatingKit.appName = "My App"
/// AFRatingKit.minDaysBetweenPrompts = 14
/// AFRatingKit.negativeFeedbackURL = URL(string: "mailto:support@app.com")
/// AFRatingKit.configure()
///
/// // After successful user action
/// await AFRatingKit.shared.requestIfNeeded(from: self)
/// ```
@MainActor
public final class AFRatingKit {

    // MARK: - Global Configuration Properties

    /// App name displayed in the pre-prompt dialog.
    /// Default: CFBundleName from Info.plist.
    public static var appName: String =
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"

    /// Minimum number of days between consecutive prompts.
    /// Default: 30 days.
    public static var minDaysBetweenPrompts: Int = 30

    /// URL opened when the user gives negative feedback.
    /// Example: `URL(string: "mailto:support@app.com")`
    /// If `nil` — silently dismissed.
    public static var negativeFeedbackURL: URL? = nil

    // MARK: - Singleton

    public static let shared = AFRatingKit()
    private init() {}

    // MARK: - Internal State

    private var configuration: AFRatingKitConfiguration = .init()
    private var eventHandler: AFRatingEventHandler?

    // MARK: - Configure

    /// Applies current static properties and activates RatingKit.
    /// Call this after setting `appName`, `minDaysBetweenPrompts`, etc.
    public static func configure(eventHandler: AFRatingEventHandler? = nil) {
        shared.configuration = AFRatingKitConfiguration(
            appName: appName,
            minDaysBetweenPrompts: minDaysBetweenPrompts,
            negativeFeedbackURL: negativeFeedbackURL
        )
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

    /// Resets all stored statistics. For testing.
    public func resetState() {
        storage.reset()
    }

    // MARK: - Throttle

    private func shouldShowPrompt() -> Bool {
        if storage.hasRatedThisVersion { return false }

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
                onResult: { sink.resume(with: $0) }
            )
            vc.modalPresentationStyle = .overFullScreen
            vc.modalTransitionStyle = .crossDissolve
            presenter.present(vc, animated: false)
        }

        handleResult(result)
        return result
    }

    // MARK: - Handle Result

    private func handleResult(_ result: AFRatingResult) {
        switch result {
        case .positive:
            storage.setHasRated(for: appVersion)
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
            // Don't save stats on dismiss — allow showing again on next launch
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

// MARK: - AFRatingKitConfiguration (internal)

struct AFRatingKitConfiguration {
    let appName: String
    let minDaysBetweenPrompts: Int
    let negativeFeedbackURL: URL?

    init(
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

// MARK: - AFRatingStorage (private)

private final class AFRatingStorage {

    private enum Keys {
        static let lastPromptDate = "RatingKit.lastPromptDate"
        static let ratedVersions  = "RatingKit.ratedVersions"
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
