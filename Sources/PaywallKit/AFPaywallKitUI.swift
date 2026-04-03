// AFPaywallKitUI.swift
// PaywallKit SDK
//
// Protocol for connecting custom paywall UI to the SDK.
// User implements this protocol on their ViewController — SDK handles the rest.

import UIKit
import StoreKit

// MARK: - AFPaywallKitUI

/// Implement this protocol on your `UIViewController` to connect it to PaywallKit.
///
/// **Minimal integration — 3 steps:**
/// ```swift
/// // 1. Conformance
/// final class MyPaywall: UIViewController, AFPaywallKitUI {
///
///     // 2. SDK passes products through initializer
///     static func make(context: AFPaywallUIContext) -> UIViewController {
///         return MyPaywall(context: context)
///     }
///
///     // 3. When user taps button — pass events through context
///     @IBAction func buyTapped() {
///         context.purchase(products[selectedIndex])
///     }
/// }
///
/// // 4. Registration
/// PaywallKit.configure(..., customUI: MyPaywall.self)
/// ```
public protocol AFPaywallKitUI: UIViewController {

    /// SDK calls this to create your controller.
    /// You receive `AFPaywallUIContext` with all data and callbacks.
    @MainActor
    static func make(context: AFPaywallUIContext) -> UIViewController
}

// MARK: - AFPaywallUIContext

/// All data and actions that SDK passes to your ViewController.
/// Store as `let context: AFPaywallUIContext` and use where needed.
@MainActor
public final class AFPaywallUIContext {

    // MARK: - Data

    /// Sorted list of products (from cheapest to most expensive).
    public let products: [AFPaywallProduct]

    /// Placement identifier from where the paywall was opened.
    public let placementId: String

    /// Accent color for paywall UI (defaults to .systemBlue).
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
    /// Subscribe to update UI.
    public var onStateChange: ((AFPaywallUIState) -> Void)?
    
    /// Called after paywall is dismissed (closed by user).
    /// Use this to show rating prompt or other post-paywall actions.
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
    public let displayPrice: String           // "4.99 USD"
    public let pricePerMonth: String?         // "1.67 USD/mo" — for annual plans
    public let introductoryOffer: String?     // "3 days free"
    public let subscriptionPeriod: AFSubscriptionPeriod

    public var isPopular: Bool = false        // SDK sets automatically for most popular
}

// MARK: - AFSubscriptionPeriod

public enum AFSubscriptionPeriod: Sendable {
    case weekly, monthly, quarterly, yearly, lifetime, unknown
}

// MARK: - AFPaywallUIState

/// State that SDK passes to your UI during purchase.
public enum AFPaywallUIState: Sendable {
    case idle
    case loading                              // Show spinner
    case purchasing(productId: String)        // Specific product is being purchased
    case restoring
    case success(AFPaywallResult)             // SDK will close paywall itself
    case error(String)                        // Show alert / inline error
}

// MARK: - PaywallKit.configure overload

//public extension PaywallKit {
//
//    /// Registers your custom UI for StoreKit fallback provider.
//    ///
//    /// **Usage:**
//    /// ```swift
//    /// PaywallKit.configure(
//    ///     configuration: config,
//    ///     primaryProvider: adaptyProvider,
//    ///     fallbackUI: MyPaywallViewController.self,   // ← your class
//    ///     validator: subscriptionService
//    /// )
//    /// ```
//    @MainActor
//    static func configure(
//        configuration: PaywallKitConfiguration,
//        primaryProvider: PaywallProvider,
//        fallbackUI: (any PaywallKitUI.Type)?,
//        validator: SubscriptionValidator,
//        eventHandler: PurchaseEventHandler? = nil
//    ) {
//        let fallbackProvider: StoreKitProvider? = fallbackUI.map { uiType in
//            StoreKitProvider(
//                productIds: configuration.productIds,
//                validator: validator,
//                paywallFactory: ProtocolBasedPaywallFactory(uiType: uiType)
//            )
//        }
//
//        PaywallKit.configure(
//            configuration: configuration,
//            primaryProvider: primaryProvider,
//            fallbackProvider: fallbackProvider,
//            validator: validator,
//            eventHandler: eventHandler
//        )
//    }
//}

// MARK: - ProtocolBasedPaywallFactory (internal)

/// Factory that creates AFPaywallKitUI controller and passes context.
final class ProtocolBasedPaywallFactory: AFStoreKitPaywallFactory {

    private let uiType: any AFPaywallKitUI.Type

    init(uiType: any AFPaywallKitUI.Type) {
        self.uiType = uiType
    }

    @MainActor
    func makeController(products: [Product], placementId: String, delegate: AFStoreKitPaywallDelegate, accentColor: UIColor) -> UIViewController {
        // Convert StoreKit Product → AFPaywallProduct
        var paywallProducts = products.map { AFPaywallProduct(from: $0) }

        // Mark most popular product
        if paywallProducts.count > 1,
           let maxIdx = paywallProducts.indices.max(by: { paywallProducts[$0].displayPrice < paywallProducts[$1].displayPrice }) {
            paywallProducts[maxIdx].isPopular = true
        }

        // Weak ref to controller for delegate callbacks (safer than UIApplication.shared.topViewController)
        weak var controllerRef: UIViewController?

        // Create context with callbacks → delegate
        let context = AFPaywallUIContext(
            products: paywallProducts,
            placementId: placementId,
            accentColor: accentColor,
            purchase: { [weak delegate] product in
                // Convert back to StoreKit Product
                guard let original = products.first(where: { $0.id == product.id }),
                      let vc = controllerRef else { return }
                delegate?.paywallDidRequestPurchase(original, from: vc)
            },
            restore: { [weak delegate] in
                guard let vc = controllerRef else { return }
                delegate?.paywallDidRequestRestore(from: vc)
            },
            close: { [weak delegate] in
                guard let vc = controllerRef else { return }
                delegate?.paywallDidClose(vc)
            }
        )

        let controller = uiType.make(context: context)
        controllerRef = controller
        return controller
    }
}

// MARK: - AFPaywallProduct(from:) StoreKit initializer

extension AFPaywallProduct {
    init(from product: Product) {
        self.id = product.id
        self.displayName = product.displayName
        self.description = product.description
        self.displayPrice = product.displayPrice
        self.pricePerMonth = nil // Can be calculated from subscription info
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

// MARK: - UIApplication helper (internal)

private extension UIApplication {
    var topViewController: UIViewController? {
        guard let windowScene = connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController
        else { return nil }
        return root.topPresentedViewController
    }
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        presentedViewController?.topPresentedViewController ?? self
    }
}
