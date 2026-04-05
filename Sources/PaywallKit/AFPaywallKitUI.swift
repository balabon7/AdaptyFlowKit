// AFPaywallKitUI.swift
// AdaptyFlowKit SDK
//
// Protocol for connecting custom paywall UI to the SDK.

import UIKit
import StoreKit

// MARK: - AFPaywallKitUI

/// Implement this protocol on your `UIViewController` to connect it to PaywallKit.
///
/// ```swift
/// final class MyPaywall: UIViewController, AFPaywallKitUI {
///
///     static func make(context: AFPaywallUIContext) -> UIViewController {
///         return MyPaywall(context: context)
///     }
///
///     @IBAction func buyTapped() {
///         context.purchase(products[selectedIndex])
///     }
/// }
///
/// // Registration
/// AFPaywallKit.configure(..., fallbackUI: MyPaywall.self, ...)
/// ```
public protocol AFPaywallKitUI: UIViewController {

    /// SDK calls this to create your controller.
    /// Receive `AFPaywallUIContext` with all data and callbacks.
    @MainActor
    static func make(context: AFPaywallUIContext) -> UIViewController
}

// MARK: - AFPaywallUIContext

/// All data and actions that SDK passes to your ViewController.
/// Store as `let context: AFPaywallUIContext` and use where needed.
@MainActor
public final class AFPaywallUIContext {

    // MARK: - Data

    /// Products list in the order defined by `AFPaywallKit.productIds`.
    public let products: [AFPaywallProduct]

    /// Placement identifier from where the paywall was opened.
    public let placementId: String

    /// Accent color for paywall UI (from `AFAppearance.accentColor`).
    public let accentColor: UIColor

    /// Paywall title (defaults to "Unlock Premium").
    public let title: String

    /// Paywall subtitle (defaults to "Full access. Cancel anytime.").
    public let subtitle: String

    // MARK: - Actions

    /// Call when user taps "Buy" / "Subscribe".
    public let purchase: (AFPaywallProduct) -> Void

    /// Call when user taps "Restore".
    public let restore: () -> Void

    /// Call when user taps "Close" / "X".
    public let close: () -> Void

    // MARK: - State updates

    /// SDK passes purchase state (loading / error / success).
    /// Subscribe to update UI accordingly.
    public var onStateChange: ((AFPaywallUIState) -> Void)?

    /// Called after paywall is dismissed by user.
    public var onDismiss: (() -> Void)?

    // MARK: - Init (SDK internal)

    internal init(
        products: [AFPaywallProduct],
        placementId: String,
        accentColor: UIColor = .systemBlue,
        title: String = "Unlock Premium",
        subtitle: String = "Full access. Cancel anytime.",
        purchase: @escaping (AFPaywallProduct) -> Void,
        restore: @escaping () -> Void,
        close: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.products = products
        self.placementId = placementId
        self.accentColor = accentColor
        self.title = title
        self.subtitle = subtitle
        self.purchase = purchase
        self.restore = restore
        self.close = close
        self.onDismiss = onDismiss
    }
}

// MARK: - AFPaywallProduct

/// Unified product wrapper.
/// Regardless of provider (Adapty or StoreKit) — you receive the same object.
public struct AFPaywallProduct: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    public let displayPrice: String
    public let pricePerMonth: String?
    public let introductoryOffer: String?
    public let subscriptionPeriod: AFSubscriptionPeriod

    /// `true` for the most popular product (set automatically by the SDK).
    public var isPopular: Bool = false
}

// MARK: - AFSubscriptionPeriod

public enum AFSubscriptionPeriod: Sendable {
    case weekly, monthly, quarterly, yearly, lifetime, unknown
}

// MARK: - AFPaywallUIState

/// State that SDK passes to your UI during purchase operations.
public enum AFPaywallUIState: Sendable {
    case idle
    case loading
    case purchasing(productId: String)
    case restoring
    case success(AFPaywallResult)
    case error(String)
}

// MARK: - AFPaywallProduct StoreKit initializer (internal)

extension AFPaywallProduct {
    init(from product: Product) {
        self.id = product.id
        self.displayName = product.displayName
        self.description = product.description
        self.displayPrice = product.displayPrice
        self.pricePerMonth = nil
        self.introductoryOffer = product.subscription?.introductoryOffer?.period.debugDescription
        self.subscriptionPeriod = AFSubscriptionPeriod(from: product.subscription?.subscriptionPeriod)
    }
}

extension AFSubscriptionPeriod {
    init(from period: Product.SubscriptionPeriod?) {
        guard let period else { self = .unknown; return }
        switch period.unit {
        case .week:  self = .weekly
        case .month: self = period.value >= 3 ? .quarterly : .monthly
        case .year:  self = .yearly
        case .day:   self = .unknown
        @unknown default: self = .unknown
        }
    }
}
