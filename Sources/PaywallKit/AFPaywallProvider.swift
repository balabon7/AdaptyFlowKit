// AFPaywallProvider.swift
// PaywallKit SDK
//
// Protocol-based abstraction. Plug in Adapty, RevenueCat, or your own provider.

import UIKit

// MARK: - PaywallProvider

/// Paywall provider abstraction.
/// Implement this protocol to connect any SDK: Adapty, RevenueCat, etc.
public protocol AFPaywallProvider: AnyObject, Sendable {

    /// Shows paywall for the given `placementId`.
    /// - Returns: `AFPaywallResult` after completion (purchase / restore / cancel / error).
    @MainActor
    func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> AFPaywallResult
}

// MARK: - AFSubscriptionValidator

/// Protocol for checking subscription activity after purchase.
/// Separated from provider — can be used with any backend.
public protocol AFSubscriptionValidator: AnyObject, Sendable {

    /// Checks if there is an active subscription. Can make a network request.
    @MainActor
    func isSubscriptionActive() async -> Bool
}

// MARK: - AFPurchaseEventHandler

/// Protocol for handling purchase events (analytics, UI updates, etc.).
public protocol AFPurchaseEventHandler: AnyObject {

    /// Called immediately after successful purchase or restore.
    @MainActor
    func onPurchaseSuccess(result: AFPaywallResult)

    /// Called after any error.
    @MainActor
    func onPurchaseFailure(error: AFPaywallKitError)
}

// Default implementation — event handler is optional.
public extension AFPurchaseEventHandler {
    func onPurchaseSuccess(result: AFPaywallResult) {}
    func onPurchaseFailure(error: AFPaywallKitError) {}
}
