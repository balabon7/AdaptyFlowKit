// AdaptyFlowKit.swift
// AdaptyFlowKit SDK
//
// Main module - re-exports all three kits for convenient usage.

@_exported import OnboardingKit
@_exported import PaywallKit
@_exported import RatingKit

/// Main AdaptyFlowKit module.
/// 
/// This module provides a complete solution for managing:
/// - Onboarding flows with Adapty integration
/// - Paywall presentations with fallback support
/// - Smart rating requests
///
/// **Usage:**
/// ```swift
/// import AdaptyFlowKit
///
/// // All three kits are available automatically:
/// OnboardingKit.configure(...)
/// PaywallKit.configure(...)
/// RatingKit.configure(...)
/// ```
public enum AdaptyFlowKit {
    /// Current SDK version
    public static let version = "1.0.0"
    
    /// SDK name
    public static let name = "AdaptyFlowKit"
}
