// AFOnboardingKitUI.swift
// AdaptyFlowKit SDK
//
// Protocol for connecting custom onboarding UI.

import UIKit

// MARK: - AFOnboardingKitUI

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
///     @objc func doneTapped() { context.complete() }
///     @objc func skipTapped() { context.skip() }
/// }
/// ```
public protocol AFOnboardingKitUI: UIViewController {
    @MainActor
    static func make(context: AFOnboardingUIContext) -> UIViewController
}

// MARK: - AFOnboardingUIContext

/// All data and actions that SDK passes to your ViewController.
@MainActor
public final class AFOnboardingUIContext {

    // MARK: - Data

    /// Placement identifier (for analytics).
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

// MARK: - AFFallbackOnboardingProvider

/// Provider that shows a custom `AFOnboardingKitUI` ViewController.
/// Used as fallback when Adapty is unavailable or fails.
public final class AFFallbackOnboardingProvider: AFOnboardingProvider {

    private let uiType: any AFOnboardingKitUI.Type

    public init(uiType: any AFOnboardingKitUI.Type) {
        self.uiType = uiType
    }

    @MainActor
    public func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> AFOnboardingResult {
        return await withCheckedContinuation { continuation in
            let sink = AFSingleFireContinuation(continuation)

            let context = AFOnboardingUIContext(
                placementId: placementId,
                complete: { sink.resume(with: .completed) },
                skip: { sink.resume(with: .skipped) }
            )

            let controller = uiType.make(context: context)
            controller.modalPresentationStyle = .fullScreen

            // Attach context (and sink) to controller lifetime
            objc_setAssociatedObject(
                controller,
                &AFFallbackOnboardingProvider.contextKey,
                context,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            presenter.present(controller, animated: true)
        }
    }

    private static var contextKey: UInt8 = 0
}
