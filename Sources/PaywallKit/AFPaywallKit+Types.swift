// AFPaywallKit+Types.swift
// PaywallKit SDK
//
// Public types: results, errors, configuration.

import Foundation
import UIKit

// MARK: - AFPaywallResult

/// Paywall presentation result.
public enum AFPaywallResult: Sendable, Equatable {
    case purchased              // Just purchased subscription
    case restored               // Restored purchase
    case alreadyPurchased       // Already has active subscription (paywall was not shown)
    case cancelled              // User closed paywall without purchase
    case failed(AFPaywallKitError)
}

extension AFPaywallResult {
    /// `true` if user has active subscription (purchased, restored or already had).
    public var isSuccess: Bool {
        switch self {
        case .purchased, .restored, .alreadyPurchased: return true
        default: return false
        }
    }
}

// MARK: - AFPaywallKitError

public enum AFPaywallKitError: LocalizedError, Sendable {
    // Configuration
    case notConfigured
    case noProductIds

    // Network / loading
    case timeout
    case noProducts

    // Purchase
    case subscriptionNotActive
    case noActiveSubscription
    case verificationFailed
    case providerError(Error)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .notConfigured:         return "[PaywallKit] SDK not configured. Call PaywallKit.configure() first."
        case .noProductIds:          return "[PaywallKit] No product IDs provided in configuration."
        case .timeout:               return "[PaywallKit] Request timed out."
        case .noProducts:            return "[PaywallKit] No products available for purchase."
        case .subscriptionNotActive: return "[PaywallKit] Purchase completed but subscription is not active."
        case .noActiveSubscription:  return "[PaywallKit] No active subscription found."
        case .verificationFailed:    return "[PaywallKit] Transaction verification failed."
        case .providerError(let e):  return "[PaywallKit] Provider error: \(e.localizedDescription)"
        case .unknown:               return "[PaywallKit] Unknown error occurred."
        }
    }
}

extension AFPaywallKitError: Equatable {
    public static func == (lhs: AFPaywallKitError, rhs: AFPaywallKitError) -> Bool {
        switch (lhs, rhs) {
        case (.notConfigured, .notConfigured),
             (.noProductIds, .noProductIds),
             (.timeout, .timeout),
             (.noProducts, .noProducts),
             (.subscriptionNotActive, .subscriptionNotActive),
             (.noActiveSubscription, .noActiveSubscription),
             (.verificationFailed, .verificationFailed),
             (.unknown, .unknown):
            return true
        case (.providerError, .providerError):
            // Errors themselves don't conform to Equatable, so we treat all providerError cases as equal
            return true
        default:
            return false
        }
    }
}

// MARK: - AFProductFilter

/// Controls which products are shown in the fallback paywall (StoreKit path).
///
/// Applied automatically in `AFPaywallKitUIFactory` before products reach your UI.
///
/// ```swift
/// // Show only non-trial products
/// AFPaywallKit.productFilter = .nonTrialOnly
///
/// // Show only trial products (free trial / intro offer)
/// AFPaywallKit.productFilter = .trialOnly
///
/// // Show all (default)
/// AFPaywallKit.productFilter = .all
/// ```
public enum AFProductFilter: Sendable {
    /// Show all products. Default.
    case all
    /// Show only products that have an introductory offer (free trial / reduced price).
    case trialOnly
    /// Show only products without an introductory offer.
    case nonTrialOnly
}

// MARK: - AFPaywallKitLogger

/// Logger protocol. Substitute any tool: OSLog, Firebase, custom.
public protocol AFPaywallKitLogger: Sendable {
    func log(_ message: String, level: AFPaywallKitLogLevel)
}

public enum AFPaywallKitLogLevel: Sendable {
    case debug, info, warning, error
}

/// Default logger via `print`.
public struct AFConsoleLogger: AFPaywallKitLogger {
    public init() {}
    public func log(_ message: String, level: AFPaywallKitLogLevel) {
        print("[PaywallKit][\(level)] \(message)")
    }
}
