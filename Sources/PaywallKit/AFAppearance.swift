// AFAppearance.swift
// AdaptyFlowKit SDK
//
// Centralized appearance configuration for all kits.
// Replaces scattered static properties across OnboardingKit, PaywallKit, and RatingKit.

import UIKit

// MARK: - AFAppearance

/// Centralized appearance configuration for the entire SDK.
///
/// **Usage:**
/// ```swift
/// // In AppDelegate
/// AFAppearance.accentColor = UIColor(red: 0.91, green: 0.137, blue: 0.102, alpha: 1)
///
/// // All kits (Onboarding, Paywall, Rating) will use this color automatically
/// ```
@MainActor
public final class AFAppearance {
    
    /// Global accent color for all UI components (buttons, page controls, selected states).
    /// Default: `.systemBlue`
    ///
    /// Set this once in AppDelegate before configuring any kits.
    public static var accentColor: UIColor = .systemBlue
    
    /// Color for the Submit button in RatingKit.
    /// Default: uses `accentColor`
    ///
    /// Set this to customize the rating prompt submit button separately from other UI elements.
    public static var ratingSubmitButtonColor: UIColor? = nil
    
    // MARK: - Private Init
    
    private init() {}
}
