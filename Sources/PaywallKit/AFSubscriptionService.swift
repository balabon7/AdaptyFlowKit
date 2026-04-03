// AFSubscriptionService.swift
// AdaptyFlowKit SDK
//

// Simple service for subscription validation.
// Conforms to SubscriptionValidator for PaywallKit.

import Foundation
import Adapty
import StoreKit

/// Service for checking subscription status.
@MainActor
final class AFSubscriptionService: AFSubscriptionValidator {

    static let shared = AFSubscriptionService()
    private init() {}
    
    // MARK: - Adapty Profile (optional)
    
    private var cachedProfile: AdaptyProfile?
    
    // MARK: - SubscriptionValidator
    
    /// Checks if there is an active subscription.
    public func isSubscriptionActive() async -> Bool {
        // 1. First check the cached Adapty profile
        if let profile = cachedProfile,
           profile.accessLevels["premium"]?.isActive == true {
            return true
        }
        
        // 2. Try to fetch a fresh profile from Adapty
        do {
            let profile = try await Adapty.getProfile()
            cachedProfile = profile
            
            if profile.accessLevels["premium"]?.isActive == true {
                return true
            }
        } catch {
            print("[SubscriptionService] Adapty profile fetch failed: \(error)")
            // Continue to StoreKit fallback
        }
        
        // 3. Fallback to StoreKit 2 (local check)
        return await checkStoreKitSubscription()
    }
    
    // MARK: - StoreKit 2 Check
    
    private func checkStoreKitSubscription() async -> Bool {
        // Check all transactions
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                // If there is an active subscription transaction, consider it premium
                if transaction.productType == .autoRenewable {
                    return true
                }
            case .unverified:
                continue
            }
        }
        return false
    }
}

// MARK: - AFProfileApplicable (for Adapty)

extension AFSubscriptionService: AFProfileApplicable {
    
    /// Updates the cached profile after purchase through Adapty.
    func apply(profile: AdaptyProfile) {
        cachedProfile = profile
        
        let isPremium = profile.accessLevels["premium"]?.isActive == true
        print("[SubscriptionService] Profile applied. Premium: \(isPremium)")
    }
}
