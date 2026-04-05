// AFStoreKitProvider.swift
// AdaptyFlowKit SDK
//
// Fallback paywall provider based on StoreKit 2.

import UIKit
import StoreKit

// MARK: - AFStoreKitProvider

/// Fallback provider — fetches products via StoreKit 2 and presents your custom UI.
public final class AFStoreKitProvider: AFPaywallProvider {

    // MARK: - Dependencies

    private let productIds: [String]
    private let validator: AFSubscriptionValidator
    private let paywallFactory: AFStoreKitPaywallFactory

    // MARK: - Init

    /// Initialization with a custom factory.
    public init(
        productIds: [String],
        validator: AFSubscriptionValidator,
        paywallFactory: AFStoreKitPaywallFactory
    ) {
        self.productIds = productIds
        self.validator = validator
        self.paywallFactory = paywallFactory
    }

    /// Convenience initializer — pass any `AFPaywallKitUI` class.
    ///
    /// ```swift
    /// AFStoreKitProvider(
    ///     productIds: ["com.app.premium"],
    ///     validator: subscriptionService,
    ///     uiType: MyPaywallViewController.self
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
        // Preserve order from productIds (yearly → monthly → weekly)
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

            eventBridge.retain(on: controller)
            presenter.present(controller, animated: true)
        }
    }
}

// MARK: - AFStoreKitPaywallFactory

/// Protocol for creating a paywall controller from StoreKit products.
///
/// Default implementation: `AFPaywallKitUIFactory`.
/// For advanced customization — implement this protocol yourself.
public protocol AFStoreKitPaywallFactory: AnyObject {

    /// Creates and returns the paywall controller.
    @MainActor
    func makeController(
        products: [Product],
        placementId: String,
        delegate: AFStoreKitPaywallDelegate,
        accentColor: UIColor
    ) -> UIViewController

    /// Called on every purchase state change.
    /// Pass through to `context.onStateChange` to update your UI.
    func notifyState(_ state: AFPaywallUIState)
}

/// Default no-op implementation — custom factories can opt out of state handling.
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

/// Default SDK factory. Accepts any `AFPaywallKitUI` class, builds `AFPaywallUIContext`,
/// and connects state updates: bridge → context → ViewController.
public final class AFPaywallKitUIFactory: AFStoreKitPaywallFactory {

    private let uiType: any AFPaywallKitUI.Type
    private weak var activeContext: AFPaywallUIContext?

    public init(uiType: any AFPaywallKitUI.Type) {
        self.uiType = uiType
    }

    @MainActor
    public func makeController(
        products: [Product],
        placementId: String,
        delegate: AFStoreKitPaywallDelegate,
        accentColor: UIColor
    ) -> UIViewController {

        var paywallProducts = products.map(AFPaywallProduct.init(from:))
        paywallProducts.applyFilter(AFPaywallKit.productFilter)
        paywallProducts.markMostPopular()

        weak var controllerRef: UIViewController?

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
            onDismiss: nil
        )

        self.activeContext = ctx

        let controller = uiType.make(context: ctx)
        controllerRef = controller
        return controller
    }

    public func notifyState(_ state: AFPaywallUIState) {
        Task { @MainActor [weak self] in
            self?.activeContext?.onStateChange?(state)
        }
    }
}

// MARK: - AFStoreKitEventBridge

/// Handles StoreKit 2 purchases, validation, and restore.
/// Notifies the factory about state changes via `stateHandler`.
final class AFStoreKitEventBridge: AFStoreKitPaywallDelegate {

    private let completion: AFSingleFireContinuation<AFPaywallResult>
    private let validator: AFSubscriptionValidator
    private let stateHandler: (AFPaywallUIState) -> Void

    init(
        completion: AFSingleFireContinuation<AFPaywallResult>,
        validator: AFSubscriptionValidator,
        stateHandler: @escaping (AFPaywallUIState) -> Void
    ) {
        self.completion = completion
        self.validator = validator
        self.stateHandler = stateHandler
    }

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
            stateHandler(.purchasing(productId: product.id))
            let result = await executePurchase(product)

            switch result {
            case .cancelled:
                stateHandler(.idle)
                completion.resume(with: .cancelled)
            case .failed(let error):
                stateHandler(.error(error.localizedDescription))
                dismiss(controller) { self.completion.resume(with: result) }
            case .purchased, .restored, .alreadyPurchased:
                stateHandler(.success(result))
                dismiss(controller) { self.completion.resume(with: result) }
            }
        }
    }

    func paywallDidRequestRestore(from controller: UIViewController) {
        Task { @MainActor in
            stateHandler(.restoring)
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

    private func dismiss(_ controller: UIViewController, completion: @escaping () -> Void) {
        controller.dismiss(animated: true, completion: completion)
    }
}

// MARK: - Array<AFPaywallProduct> (internal)

private extension Array where Element == AFPaywallProduct {
    /// Filters products according to `AFPaywallKit.productFilter`.
    mutating func applyFilter(_ filter: AFProductFilter) {
        switch filter {
        case .all:
            break
        case .trialOnly:
            self = self.filter { $0.introductoryOffer != nil }
        case .nonTrialOnly:
            self = self.filter { $0.introductoryOffer == nil }
        }
    }

    /// Marks the first product as "popular" (typically the yearly plan with the best value).
    mutating func markMostPopular() {
        guard !isEmpty else { return }
        self[0].isPopular = true
    }
}
