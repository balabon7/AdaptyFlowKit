// AFPaywallKit.swift
// PaywallKit SDK
//
// Main SDK class for managing paywall.

import UIKit

// MARK: - PaywallKit

/// Main SDK class. Singleton for convenience.
///
/// **Usage:**
/// ```swift
/// // AppDelegate — set static properties, then call configure()
/// AFPaywallKit.productIds = ["com.app.premium.yearly"]
/// AFDefaultPaywallAdapter.privacyURL = URL(string: "https://...")
/// AFDefaultPaywallAdapter.termsURL   = URL(string: "https://...")
/// AFPaywallKit.configure(
///     primaryProvider: AFAdaptyProvider(validator: subscriptionService),
///     fallbackUI: MyPaywallViewController.self,
///     validator: subscriptionService
/// )
///
/// // Anywhere
/// let result = await AFPaywallKit.show(placementId: "onboarding", from: self)
/// ```
@MainActor
public final class AFPaywallKit {

    // MARK: - Global Configuration Properties

    /// Product IDs used by the StoreKit fallback provider.
    /// Set before calling `configure()`.
    public static var productIds: [String] = []

    /// Per-placement product ID overrides for the StoreKit fallback.
    /// When a placement is listed here its products replace `productIds` in the fallback paywall.
    /// Placements not listed fall back to `productIds`.
    /// Set before calling `configure()`.
    public static var placementProductIds: [String: [String]] = [:]

    /// Per-placement "most popular" product ID for the StoreKit fallback.
    /// When set for a placement, that product gets the MOST POPULAR badge.
    /// Placements not listed fall back to the first product.
    /// Set before calling `configure()`.
    public static var placementMostPopularId: [String: String] = [:]

    /// Timeout for provider network requests. Default: 15 seconds.
    public static var fetchTimeout: TimeInterval = 15.0

    /// Filters products passed to the fallback paywall UI.
    /// Applied before products reach `AFPaywallUIContext` — works with any `AFPaywallKitUI`.
    /// Default: `.all` (no filtering).
    public static var productFilter: AFProductFilter = .all

    /// Title shown on the built-in StoreKit fallback paywall (`AFDefaultPaywallAdapter`).
    /// The primary AdaptyUI paywall takes its title from the Adapty dashboard instead.
    /// Set before calling `configure()`. Default: `"Unlock Premium"`.
    public static var fallbackPaywallTitle: String = "Unlock Premium"

    /// Subtitle shown on the built-in StoreKit fallback paywall (`AFDefaultPaywallAdapter`).
    /// The primary AdaptyUI paywall takes its subtitle from the Adapty dashboard instead.
    /// Set before calling `configure()`. Default: `"Full access. Cancel anytime."`.
    public static var fallbackPaywallSubtitle: String = "Full access. Cancel anytime."

    // MARK: - Singleton

    public static let shared = AFPaywallKit()
    private init() {}

    // MARK: - Internal State

    private var isConfigured = false
    private var primaryProvider: AFPaywallProvider?
    private var fallbackProvider: AFPaywallProvider?
    private var validator: AFSubscriptionValidator?
    private var eventHandler: AFPurchaseEventHandler?

    // MARK: - Configure

    /// Configures SDK with a primary provider and custom fallback UI.
    ///
    /// - Parameters:
    ///   - primaryProvider: Main paywall provider (e.g. `AFAdaptyProvider`).
    ///   - fallbackUI: ViewController type conforming to `AFPaywallKitUI` used as fallback.
    ///   - validator: Service that checks active subscription status.
    ///   - eventHandler: Optional purchase events delegate.
    public static func configure(
        primaryProvider: AFPaywallProvider,
        fallbackUI: (any AFPaywallKitUI.Type)?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler? = nil
    ) {
        let fallbackProvider: AFStoreKitProvider? = fallbackUI.map {
            AFStoreKitProvider(
                productIds: productIds,
                validator: validator,
                uiType: $0
            )
        }
        shared.setup(
            primaryProvider: primaryProvider,
            fallbackProvider: fallbackProvider,
            validator: validator,
            eventHandler: eventHandler
        )
    }

    /// Full configuration with custom providers (advanced).
    public static func configure(
        primaryProvider: AFPaywallProvider,
        fallbackProvider: AFPaywallProvider?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler? = nil
    ) {
        shared.setup(
            primaryProvider: primaryProvider,
            fallbackProvider: fallbackProvider,
            validator: validator,
            eventHandler: eventHandler
        )
    }

    private func setup(
        primaryProvider: AFPaywallProvider,
        fallbackProvider: AFPaywallProvider?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler?
    ) {
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.validator = validator
        self.eventHandler = eventHandler
        self.isConfigured = true
    }

    // MARK: - Present / Show

    /// Shows paywall. First tries primary provider, on error — falls back to StoreKit.
    ///
    /// - Parameters:
    ///   - placementId: Placement ID from Adapty dashboard.
    ///   - presenter: UIViewController from which to present paywall.
    ///   - forceShow: If `true`, shows paywall even with active subscription. Default `false`.
    ///   - onDismiss: Called when user closes paywall without purchasing.
    @discardableResult
    public static func present(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        await shared.present(placementId: placementId, from: presenter, forceShow: forceShow, onDismiss: onDismiss)
    }

    /// Alias for `present()`.
    @discardableResult
    public static func show(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        await present(placementId: placementId, from: presenter, forceShow: forceShow, onDismiss: onDismiss)
    }

    /// Instance method for calling through `AFPaywallKit.shared.show()`.
    @discardableResult
    public func show(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        await Self.show(placementId: placementId, from: presenter, forceShow: forceShow, onDismiss: onDismiss)
    }

    private func present(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        guard isConfigured else {
            return .failed(.notConfigured)
        }

        guard let presentationLease = AFModalPresentationCoordinator.shared.acquire(.paywall) else {
            print(
                "[PaywallKit] Presentation blocked by active "
                    + "\(String(describing: AFModalPresentationCoordinator.shared.activeKind)) flow"
            )
            return .cancelled
        }
        defer { AFModalPresentationCoordinator.shared.release(presentationLease) }

        if !forceShow, let validator = validator {
            let hasActiveSubscription = await validator.isSubscriptionActive()
            if hasActiveSubscription {
                return .alreadyPurchased
            }
        }

        // Present from the real top-most controller. If `presenter` is already
        // presenting something (e.g. a rating overlay / system review sheet that
        // just appeared or is mid-dismiss), `UIViewController.present` fails
        // silently — the provider's continuation never resumes, `present()` never
        // returns, and `isPresenting` stays stuck `true`, blocking every later paywall.
        let target = Self.topMostPresenter(from: presenter)

        // 1. Try primary provider
        if let primary = primaryProvider {
            let result = await primary.present(placementId: placementId, from: target)
            print("[PaywallKit] Primary provider result: \(result) (placement=\(placementId))")

            switch result {
            case .purchased, .restored, .alreadyPurchased:
                handleResult(result)
                return result

            case .cancelled:
                handleResult(result)
                onDismiss?()
                return result

            case .failed(let error):
                // .subscriptionNotActive means Adapty completed the StoreKit purchase but
                // its server hasn't confirmed premium status yet (common in sandbox).
                // The user already paid — do NOT show the StoreKit fallback paywall.
                if case .subscriptionNotActive = error {
                    print("[PaywallKit] Purchase succeeded but Adapty premium not confirmed yet — skipping StoreKit fallback")
                    handleResult(result)
                    return result
                }
                print("[PaywallKit] Primary provider failed (\(error.localizedDescription)) — falling back to StoreKit")
                break // fall through to fallback for real errors (timeout, network, etc.)
            }
        }

        // 2. Fallback to StoreKit with custom UI
        if let fallback = fallbackProvider {
            print("[PaywallKit] Showing StoreKit fallback (placement=\(placementId))")
            let result = await fallback.present(placementId: placementId, from: target)
            handleResult(result)
            if case .cancelled = result { onDismiss?() }
            return result
        }

        // 3. No fallback available
        return .failed(.noProducts)
    }

    // MARK: - Presenter resolution

    /// Walks down the presentation chain to the controller that is actually on top
    /// and can present. Skips a controller that is mid-dismiss, since presenting
    /// from it would fail silently.
    private static func topMostPresenter(from presenter: UIViewController) -> UIViewController {
        var vc = presenter
        while let presented = vc.presentedViewController, !presented.isBeingDismissed {
            vc = presented
        }
        return vc
    }

    // MARK: - Event handling

    private func handleResult(_ result: AFPaywallResult) {
        switch result {
        case .purchased, .restored, .alreadyPurchased:
            eventHandler?.onPurchaseSuccess(result: result)
        case .failed(let error):
            eventHandler?.onPurchaseFailure(error: error)
        case .cancelled:
            break
        }
    }
}
