// AFOnboardingKitUI.swift
// AdaptyFlowKit SDK
//
// Protocol for connecting custom onboarding UI.
// Mirrors PaywallKitUI.swift — same idioms.

import UIKit

// MARK: - OnboardingKitUI

/// Implement this protocol on your `UIViewController` to use it as fallback onboarding.
///
/// ```swift
/// final class MyOnboardingVC: UIViewController, AFOnboardingKitUI {
///
///     private var context: AFOnboardingUIContext!
///
///     static func make(context: AFOnboardingUIContext) -> UIViewController {
///         let vc = MyOnboardingVC()
///         vc.context = context
///         return vc
///     }
///
///     // User tapped "Continue" on the last step
///     @objc func doneTapped()   { context.complete() }
///
///     // User tapped "Skip"
///     @objc func skipTapped()   { context.skip() }
/// }
/// ```
public protocol AFOnboardingKitUI: UIViewController {
    @MainActor
    static func make(context: AFOnboardingUIContext) -> UIViewController
}

// MARK: - OnboardingUIContext

/// All data and actions that SDK passes to your ViewController.
@MainActor
public final class AFOnboardingUIContext {

    // MARK: - Data

    /// Placement identifier (for logging/analytics).
    public let placementId: String

    // MARK: - Actions

    /// Call when user completed all onboarding steps.
    public let complete: () -> Void

    /// Call when user tapped Skip.
    public let skip: () -> Void

    // MARK: - Init (SDK internal)

    internal init(
        placementId: String,
        complete: @escaping () -> Void,
        skip: @escaping () -> Void
    ) {
        self.placementId = placementId
        self.complete = complete
        self.skip = skip
    }
}

// MARK: - FallbackOnboardingProvider

/// Provider that shows your custom AFOnboardingKitUI ViewController.
/// Used as fallback when Adapty is unavailable.
public final class AFFallbackOnboardingProvider: AFOnboardingProvider {

    private let uiType: any AFOnboardingKitUI.Type

    public init(uiType: any AFOnboardingKitUI.Type) {
        self.uiType = uiType
        print("[AFFallbackOnboardingProvider]  Initialized with UI type: \(uiType)")
    }

    @MainActor
    public func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> AFOnboardingResult {
        print("[AFFallbackOnboardingProvider]  present() called - placementId: \(placementId)")
        print("[AFFallbackOnboardingProvider]  Presenter: \(type(of: presenter))")
        
        return await withCheckedContinuation { continuation in
            let sink = AFSingleFireContinuation(continuation)

            let context = AFOnboardingUIContext(
                placementId: placementId,
                complete: { 
                    print("[AFFallbackOnboardingProvider]  Context complete() called")
                    sink.resume(with: .completed) 
                },
                skip: { 
                    print("[AFFallbackOnboardingProvider]  Context skip() called")
                    sink.resume(with: .skipped) 
                }
            )

            print("[AFFallbackOnboardingProvider]  Creating controller from UI type...")
            let controller = uiType.make(context: context)
            controller.modalPresentationStyle = .fullScreen
            print("[AFFallbackOnboardingProvider]  Controller created: \(type(of: controller))")

            // Attach context (and sink) to controller
            objc_setAssociatedObject(
                controller,
                &AFFallbackOnboardingProvider.contextKey,
                context,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            print("[AFFallbackOnboardingProvider]  Presenting controller...")
            print("[AFFallbackOnboardingProvider]  Presenter view: \(presenter.view.frame), window: \(presenter.view.window != nil)")
            presenter.present(controller, animated: true) {
                print("[AFFallbackOnboardingProvider]  Controller presented successfully")
                print("[AFFallbackOnboardingProvider]  Presented controller: \(presenter.presentedViewController != nil ? "" : "")")
                if let presented = presenter.presentedViewController {
                    print("[AFFallbackOnboardingProvider]  Presented VC type: \(type(of: presented))")
                    print("[AFFallbackOnboardingProvider]  Presented VC frame: \(presented.view.frame)")
                }
            }
        }
    }

    private static var contextKey: UInt8 = 0
}
