// AFDefaultOnboardingAdapter.swift
// AdaptyFlowKit SDK
//
// Adapter for existing OnboardingViewController to work with OnboardingKit.

import UIKit

/// Adapter that wraps `AFOnboardingViewController` and makes it compatible with `AFOnboardingKitUI`.
///
/// SDK uses this adapter automatically when you pass `fallbackUI: AFDefaultOnboardingAdapter.self`.
///
/// **Example:**
/// ```swift
/// AFDefaultOnboardingAdapter.pages = [
///     AFOnboardingPage(
///         title: "Welcome",
///         subtitle: "Get started",
///         iconName: "star.fill",
///         iconBackgroundColor: .systemBlue
///     )
/// ]
/// AFOnboardingKit.configure(fallbackUI: AFDefaultOnboardingAdapter.self)
/// ```
public final class AFDefaultOnboardingAdapter: UIViewController, AFOnboardingKitUI {

    // MARK: - Static Configuration

    private static var sharedPages: [AFOnboardingPage]?

    /// Custom onboarding pages displayed in fallback UI.
    /// Set before calling `AFOnboardingKit.configure()`.
    /// At least one page is required.
    @MainActor
    public static var pages: [AFOnboardingPage] {
        get { sharedPages ?? [] }
        set {
            guard !newValue.isEmpty else {
                assertionFailure("[AFDefaultOnboardingAdapter] pages cannot be empty.")
                return
            }
            sharedPages = newValue
        }
    }

    /// Resets pages to default (empty). For testing.
    @MainActor
    public static func resetPages() {
        sharedPages = nil
    }

    // MARK: - Properties

    private var context: AFOnboardingUIContext?

    // MARK: - AFOnboardingKitUI

    @MainActor
    public static func make(context: AFOnboardingUIContext) -> UIViewController {
        let adapter = AFDefaultOnboardingAdapter()
        adapter.context = context
        return adapter
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        guard context != nil else {
            assertionFailure("[AFDefaultOnboardingAdapter] context is nil. Always create via make(context:).")
            return
        }

        let onboardingVC = AFOnboardingViewController(
            pages: Self.sharedPages,
            accentColor: AFAppearance.accentColor
        )
        onboardingVC.onCompletion = { [weak self] in
            self?.dismiss(animated: true) {
                self?.context?.complete()
            }
        }

        addChild(onboardingVC)
        view.addSubview(onboardingVC.view)
        onboardingVC.view.frame = view.bounds
        onboardingVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        onboardingVC.didMove(toParent: self)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
}
