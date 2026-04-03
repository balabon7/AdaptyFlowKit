// AFDefaultOnboardingAdapter.swift
// AdaptyFlowKit SDK
//
// Adapter for existing OnboardingViewController to work with OnboardingKit.

import UIKit

/// Adapter that wraps `AFOnboardingViewController` and makes it compatible with `AFOnboardingKitUI`.
///
/// SDK uses this adapter automatically when you pass `fallbackUI: AFDefaultOnboardingAdapter.self`.
/// You don't need to create `AFDefaultOnboardingAdapter()` directly — always use `make(context:)`.
///
/// **Example with custom pages and red accent color:**
/// ```swift
/// let redAccentColor = UIColor(red: 0.91, green: 0.137, blue: 0.102, alpha: 1)
/// AFAppearance.accentColor = redAccentColor  // Set accent color for all kits
/// 
/// let pages = [
///     AFOnboardingPage(
///         title: "Welcome",
///         subtitle: "Get started with our app",
///         iconName: "star.fill",
///         iconBackgroundColor: redAccentColor
///     ),
///     AFOnboardingPage(
///         title: "Explore",
///         subtitle: "Discover amazing features",
///         iconName: "magnifyingglass",
///         iconBackgroundColor: redAccentColor
///     )
/// ]
/// AFDefaultOnboardingAdapter.setCustomPages(pages)
/// AFOnboardingKit.configure(fallbackUI: AFDefaultOnboardingAdapter.self)
/// ```
/// 
/// **Note:** Default accent color is .systemBlue if not set via AFAppearance.
public final class AFDefaultOnboardingAdapter: UIViewController, AFOnboardingKitUI {

    // MARK: - Static Configuration
    
    /// Custom pages for all adapter instances. Set via setCustomPages(_:).
    private static var sharedCustomPages: [AFOnboardingPage]?
    
    /// Configures custom onboarding pages.
    /// Call this method before configure() if you want to use custom data.
    /// - Parameter pages: Array of pages. At least one page is required.
    @MainActor
    public static func setCustomPages(_ pages: [AFOnboardingPage]) {
        guard !pages.isEmpty else {
            assertionFailure("[AFDefaultOnboardingAdapter] pages cannot be empty. At least one page is required.")
            return
        }
        sharedCustomPages = pages
    }
    
    /// Clears custom pages — adapter will return to defaults.
    @MainActor
    public static func resetPages() {
        sharedCustomPages = nil
    }

    // MARK: - Properties

    // FIX #1: force-unwrap replaced with optional and guard.
    // If someone creates AFDefaultOnboardingAdapter() directly (not via make),
    // context will be nil — guard in viewDidLoad will protect from crash.
    private var context: AFOnboardingUIContext?

    // MARK: - AFOnboardingKitUI

    // FIX #2: Added @MainActor — required by AFOnboardingKitUI protocol.
    // Without it Swift 6 strict concurrency produces compile error.
    @MainActor
    public static func make(context: AFOnboardingUIContext) -> UIViewController {
        print("[AFDefaultOnboardingAdapter] 🏗️ make(context:) called - creating adapter")
        let adapter = AFDefaultOnboardingAdapter()
        adapter.context = context
        print("[AFDefaultOnboardingAdapter] ✅ Adapter created with context")
        return adapter
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // FIX #3: Set background color to prevent transparent view
        view.backgroundColor = .systemBackground
        
        print("[AFDefaultOnboardingAdapter] 🎬 viewDidLoad - context: \(context != nil ? "✓" : "✗")")
        print("[AFDefaultOnboardingAdapter] 📄 Custom pages count: \(Self.sharedCustomPages?.count ?? 0)")

        // FIX #1: guard instead of force-unwrap on context.
        // If adapter was created not via make(context:) — log and show nothing,
        // instead of crash when calling context.complete().
        guard context != nil else {
            print("[AFDefaultOnboardingAdapter] ❌ context is nil. Always create via make(context:).")
            assertionFailure("[AFDefaultOnboardingAdapter] context is nil. Always create via make(context:).")
            return
        }

        // Create AFOnboardingViewController with custom pages and accent color from AFAppearance
        print("[AFDefaultOnboardingAdapter] 🔨 Creating AFOnboardingViewController...")
        let onboardingVC = AFOnboardingViewController(pages: Self.sharedCustomPages, accentColor: AFAppearance.accentColor)
        onboardingVC.onCompletion = { [weak self] in
            // User tapped Continue on last page or Skip —
            // dismiss the adapter and notify SDK that onboarding is complete.
            // [weak self] to not retain adapter after dismiss.
            print("[AFDefaultOnboardingAdapter] ✅ User completed onboarding - dismissing and calling context.complete()")
            self?.dismiss(animated: true) {
                self?.context?.complete()
            }
        }

        // Embed as child controller — correct pattern for containment.
        print("[AFDefaultOnboardingAdapter] 📦 Embedding AFOnboardingViewController as child...")
        addChild(onboardingVC)
        view.addSubview(onboardingVC.view)
        onboardingVC.view.frame = view.bounds
        onboardingVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        onboardingVC.didMove(toParent: self)
        print("[AFDefaultOnboardingAdapter] ✅ AFOnboardingViewController embedded successfully")
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("[AFDefaultOnboardingAdapter] 👁️ viewDidAppear - adapter is now visible on screen")
        print("[AFDefaultOnboardingAdapter] 📱 View frame: \(view.frame)")
        print("[AFDefaultOnboardingAdapter] 🎨 Background color: \(view.backgroundColor?.description ?? "nil")")
        print("[AFDefaultOnboardingAdapter] 🔍 Subviews count: \(view.subviews.count)")
        print("[AFDefaultOnboardingAdapter] 🪟 Window: \(view.window != nil ? "✓" : "✗")")
        print("[AFDefaultOnboardingAdapter] 👀 Alpha: \(view.alpha), Hidden: \(view.isHidden)")
        
        // Debug: List all subviews
        for (index, subview) in view.subviews.enumerated() {
            print("[AFDefaultOnboardingAdapter]   └─ Subview[\(index)]: \(type(of: subview)) - frame: \(subview.frame), alpha: \(subview.alpha), hidden: \(subview.isHidden)")
        }
    }
}
