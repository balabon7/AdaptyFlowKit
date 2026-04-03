// AFStoreKitProvider.swift
// PaywallKit SDK
//
// Fallback provider based on StoreKit 2.
// Completely replaces CustomPaywallViewController / CustomPaywallDelegate.

import UIKit
import StoreKit

// MARK: - AFStoreKitProvider

/// Fallback provider — shows your ViewController through StoreKit 2.
public final class AFStoreKitProvider: AFPaywallProvider {

    // MARK: - Dependencies

    private let productIds: [String]
    private let validator: AFSubscriptionValidator
    private let paywallFactory: AFStoreKitPaywallFactory

    // MARK: - Init

    /// Initialization with any factory (for custom cases).
    public init(
        productIds: [String],
        validator: AFSubscriptionValidator,
        paywallFactory: AFStoreKitPaywallFactory
    ) {
        self.productIds = productIds
        self.validator = validator
        self.paywallFactory = paywallFactory
    }

    /// Convenience initializer — just pass your class.
    ///
    /// ```swift
    /// AFStoreKitProvider(
    ///     productIds: ["com.app.premium"],
    ///     validator: subscriptionService,
    ///     uiType: MyPaywallViewController.self   // ← that's it
    /// )
    /// ```
    public convenience init(
        productIds: [String],
        validator: AFSubscriptionValidator,
        uiType: any AFPaywallKitUI.Type
    ) {
        self.init(
            productIds: productIds,
            validator: validator,
            paywallFactory: AFPaywallKitUIFactory(uiType: uiType)
        )
    }

    // MARK: - AFPaywallProvider

    @MainActor
    public func present(placementId: String, from presenter: UIViewController) async -> AFPaywallResult {
        do {
            let products = try await loadProducts()
            guard !products.isEmpty else { return .failed(.noProducts) }
            return await showPaywall(products: products, placementId: placementId, from: presenter)
        } catch {
            return .failed(.providerError(error))
        }
    }

    // MARK: - Private

    private func loadProducts() async throws -> [Product] {
        guard !productIds.isEmpty else { throw AFPaywallKitError.noProductIds }
        let products = try await Product.products(for: Set(productIds))
        // Keep the order from productIds instead of sorting by price
        // This allows controlling the display order (yearly → monthly → weekly)
        return productIds.compactMap { id in products.first(where: { $0.id == id }) }
    }

    @MainActor
    private func showPaywall(
        products: [Product],
        placementId: String,
        from presenter: UIViewController
    ) async -> AFPaywallResult {
        await withCheckedContinuation { continuation in
            let sink = AFSingleFireContinuation(continuation)

            // Bridge receives state handler → passes to factory → factory → context.onStateChange
            let eventBridge = AFStoreKitEventBridge(
                completion: sink,
                validator: validator,
                stateHandler: { [weak paywallFactory] state in
                    paywallFactory?.notifyState(state)
                }
            )

            let controller = paywallFactory.makeController(
                products: products,
                placementId: placementId,
                delegate: eventBridge,
                accentColor: AFAppearance.accentColor
            )
            controller.modalPresentationStyle = .fullScreen

            // Bridge lives as long as the controller lives
            eventBridge.retain(on: controller)
            presenter.present(controller, animated: false)
        }
    }
}

// MARK: - AFStoreKitPaywallFactory

/// Paywall controller factory protocol.
///
/// Default implementation — `AFPaywallKitUIFactory`.
/// For custom cases — implement this protocol yourself.
public protocol AFStoreKitPaywallFactory: AnyObject {

    /// Creates and returns the controller.
    @MainActor
    func makeController(
        products: [Product],
        placementId: String,
        delegate: AFStoreKitPaywallDelegate,
        accentColor: UIColor
    ) -> UIViewController

    /// Bridge calls this on every purchase state change.
    /// Factory passes this to `context.onStateChange` → VC updates UI.
    func notifyState(_ state: AFPaywallUIState)
}

/// Default — no-op. Custom factory can skip state handling.
public extension AFStoreKitPaywallFactory {
    func notifyState(_ state: AFPaywallUIState) {}
}

// MARK: - AFStoreKitPaywallDelegate

/// Bridge between your ViewController and purchase logic.
/// Called automatically through `AFPaywallUIContext` — no need to implement manually.
public protocol AFStoreKitPaywallDelegate: AnyObject {
    func paywallDidRequestPurchase(_ product: Product, from controller: UIViewController)
    func paywallDidRequestRestore(from controller: UIViewController)
    func paywallDidClose(_ controller: UIViewController)
}

// MARK: - AFPaywallKitUIFactory

/// Default SDK factory.
///
/// Accepts any `AFPaywallKitUI`-class, builds `AFPaywallUIContext`
/// and connects state updates bridge → context → VC.
///
/// **What it replaces:**
/// - `CustomPaywallViewController` (no longer needed)
/// - `CustomPaywallDelegate` (no longer needed)
/// - `DefaultStoreKitPaywallFactory` (no longer needed)
///
/// **Instead the user only implements `AFPaywallKitUI`.**
public final class AFPaywallKitUIFactory: AFStoreKitPaywallFactory {

    // MARK: - Properties

    private let uiType: any AFPaywallKitUI.Type

    /// Weak reference to context after controller creation.
    /// `notifyState()` writes here → `onStateChange` → VC updates UI.
    private weak var activeContext: AFPaywallUIContext?

    // MARK: - Init

    public init(uiType: any AFPaywallKitUI.Type) {
        self.uiType = uiType
    }

    // MARK: - AFStoreKitPaywallFactory

    @MainActor
    public func makeController(
        products: [Product],
        placementId: String,
        delegate: AFStoreKitPaywallDelegate,
        accentColor: UIColor
    ) -> UIViewController {

        // 1. StoreKit.Product → AFPaywallProduct (VC doesn't know about StoreKit)
        var paywallProducts = products.map(AFPaywallProduct.init(from:))
        paywallProducts.markMostPopular()

        // 2. Weak ref to controller for delegate callbacks.
        //    Safe alternative to UIApplication.topViewController.
        weak var controllerRef: UIViewController?

        // 3. Context — single point of contact SDK ↔ VC.
        //    Three closures instead of three delegate methods.
        let ctx = AFPaywallUIContext(
            products: paywallProducts,
            placementId: placementId,
            accentColor: accentColor,
            purchase: { [weak delegate] paywallProduct in
                guard
                    let original = products.first(where: { $0.id == paywallProduct.id }),
                    let vc = controllerRef
                else { return }
                delegate?.paywallDidRequestPurchase(original, from: vc)
            },
            restore: { [weak delegate] in
                guard let vc = controllerRef else { return }
                delegate?.paywallDidRequestRestore(from: vc)
            },
            close: { [weak delegate] in
                guard let vc = controllerRef else { return }
                delegate?.paywallDidClose(vc)
            },
            onDismiss: nil  // Will be set by PaywallKit if needed
        )

        // 4. Store weak ref → notifyState() will deliver states
        self.activeContext = ctx

        // 5. Your ViewController receives ready context
        let controller = uiType.make(context: ctx)
        controllerRef = controller
        return controller
    }

    // MARK: - State relay  (Bridge → Factory → Context → VC)

    /// Called by `AFStoreKitEventBridge` on every state change.
    /// Pass to `context.onStateChange` — VC receives and updates UI.
    public func notifyState(_ state: AFPaywallUIState) {
        Task { @MainActor [weak self] in
            self?.activeContext?.onStateChange?(state)
        }
    }
}

// MARK: - AFStoreKitEventBridge

/// Handles StoreKit 2 purchase, validation and restore.
/// Notifies factory about state changes through `stateHandler`.
/// User never interacts with this class directly.
final class AFStoreKitEventBridge: AFStoreKitPaywallDelegate {

    // MARK: - Dependencies

    private let completion: AFSingleFireContinuation<AFPaywallResult>
    private let validator: AFSubscriptionValidator
    /// Bridge → AFPaywallKitUIFactory.notifyState → context.onStateChange → VC
    private let stateHandler: (AFPaywallUIState) -> Void

    // MARK: - Init

    init(
        completion: AFSingleFireContinuation<AFPaywallResult>,
        validator: AFSubscriptionValidator,
        stateHandler: @escaping (AFPaywallUIState) -> Void
    ) {
        self.completion = completion
        self.validator = validator
        self.stateHandler = stateHandler
    }

    // MARK: - Lifetime

    func retain(on controller: UIViewController) {
        objc_setAssociatedObject(
            controller,
            &AFStoreKitEventBridge.retainKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
    private static var retainKey: UInt8 = 0

    // MARK: - AFStoreKitPaywallDelegate

    func paywallDidRequestPurchase(_ product: Product, from controller: UIViewController) {
        Task { @MainActor in
            stateHandler(.purchasing(productId: product.id))      // VC: show spinner
            let result = await executePurchase(product)

            switch result {
            case .cancelled:
                // Don't close — user can choose another plan or try again
                stateHandler(.idle)
                completion.resume(with: .cancelled)

            case .failed(let error):
                stateHandler(.error(error.localizedDescription))  // VC: show error
                dismiss(controller) { self.completion.resume(with: result) }

            case .purchased, .restored, .alreadyPurchased:
                stateHandler(.success(result))                    // VC: SDK will close itself
                dismiss(controller) { self.completion.resume(with: result) }
            }
        }
    }

    func paywallDidRequestRestore(from controller: UIViewController) {
        Task { @MainActor in
            stateHandler(.restoring)                              // VC: show spinner
            let isActive = await validator.isSubscriptionActive()
            let result: AFPaywallResult = isActive ? .restored : .failed(.noActiveSubscription)

            if case .failed(let error) = result {
                stateHandler(.error(error.localizedDescription))
            } else {
                stateHandler(.success(result))
            }

            dismiss(controller) { self.completion.resume(with: result) }
        }
    }

    func paywallDidClose(_ controller: UIViewController) {
        dismiss(controller) {
            Task { @MainActor in
                self.completion.resume(with: .cancelled)
            }
        }
    }

    // MARK: - Purchase

    @MainActor
    private func executePurchase(_ product: Product) async -> AFPaywallResult {
        do {
            switch try await product.purchase() {
            case .success(let verification): return await handleVerification(verification)
            case .userCancelled:             return .cancelled
            case .pending:                   return .cancelled
            @unknown default:                return .failed(.unknown)
            }
        } catch {
            return .failed(.providerError(error))
        }
    }

    @MainActor
    private func handleVerification(_ verification: VerificationResult<Transaction>) async -> AFPaywallResult {
        switch verification {
        case .verified(let transaction):
            await transaction.finish()
            return await validator.isSubscriptionActive() ? .purchased : .failed(.subscriptionNotActive)
        case .unverified:
            return .failed(.verificationFailed)
        }
    }

    // MARK: - Helper

    private func dismiss(_ controller: UIViewController, completion: @escaping () -> Void) {
        controller.dismiss(animated: true, completion: completion)
    }
}

// MARK: - Array<AFPaywallProduct> helpers (internal)

private extension Array where Element == AFPaywallProduct {
    /// Marks the first product as "popular" (usually yearly plan with best value).
    /// Assumes products are already sorted in the desired order.
    mutating func markMostPopular() {
        guard count > 0 else { return }
        // Mark the first product in the list as BEST VALUE
        self[0].isPopular = true
    }
}
