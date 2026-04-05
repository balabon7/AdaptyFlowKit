# AdaptyFlowKit

A comprehensive iOS SDK for managing onboarding flows, paywall presentations, and smart rating requests with seamless [Adapty](https://adapty.io) integration.

[![Swift Version](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2016.0+-blue.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Features

### OnboardingKit
- Adapty onboarding integration with automatic fallback
- Network availability check before attempting primary provider
- Fetch & display timeout handling
- Permission request handling (notifications, ATT, custom)
- First launch flow coordination via `AFAppFlowKit`

### PaywallKit
- Primary Adapty provider with StoreKit fallback
- Protocol-based UI architecture
- Subscription validation and status checking
- Parallel presentation guard (prevents double paywall)

### RatingKit
- Smart pre-prompt before Apple's SKStoreReviewController
- Protects Apple's 3-per-year quota from unhappy users
- Configurable throttling (days between prompts)
- Negative feedback redirection to custom URL

---

## Installation

### Swift Package Manager

**Via Xcode:**
1. File → Add Package Dependencies
2. Enter URL: `https://github.com/balabon7/AdaptyFlowKit.git`
3. Select version: `from 1.0.0`

**Via `Package.swift`:**
```swift
dependencies: [
    .package(url: "https://github.com/balabon7/AdaptyFlowKit.git", from: "1.0.0")
]
```

### Import

Single import for all kits:
```swift
import AdaptyFlowKit
```

---

## Quick Start

### AppDelegate Setup

```swift
import UIKit
import Adapty
import AdaptyUI
import AdaptyFlowKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate, AFOnboardingPermissionHandler {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        Task { await setupAdapty() }
        configureOnboarding()
        configurePaywall()
        configureRating()
        return true
    }

    func handlePermission(_ action: AFOnboardingPermissionAction) {
        // Handle notifications / ATT / custom permission requests from onboarding
    }
}

// MARK: - AdaptyFlowKit Configuration

extension AppDelegate: AFOnboardingPermissionHandler {

    func configureOnboarding() {
        AFOnboardingKit.fetchTimeout = 10
        AFOnboardingKit.displayTimeout = 15
        AFDefaultOnboardingAdapter.pages = [
            .init(
                title: "Welcome",
                subtitle: "Get started with our app",
                iconName: "star.fill",
                iconBackgroundColor: .systemBlue
            )
        ]
        AFOnboardingKit.configure(
            primaryProvider: AFAdaptyOnboardingProvider(permissionHandler: self),
            fallbackUI: AFDefaultOnboardingAdapter.self
        )
    }

    func configurePaywall() {
        AFPaywallKit.productIds = ["com.app.premium.yearly", "com.app.premium.monthly"]
        AFDefaultPaywallAdapter.privacyURL = URL(string: "https://yourapp.com/privacy")
        AFDefaultPaywallAdapter.termsURL   = URL(string: "https://yourapp.com/terms")
        AFPaywallKit.configure(
            primaryProvider: AFAdaptyProvider(validator: AFSubscriptionService.shared),
            fallbackUI: AFDefaultPaywallAdapter.self,
            validator: AFSubscriptionService.shared
        )
    }

    func configureRating() {
        AFAppearance.ratingSubmitButtonColor = .systemBlue
        AFRatingKit.appName = "Your App"
        AFRatingKit.minDaysBetweenPrompts = 30
        AFRatingKit.negativeFeedbackURL = URL(string: "mailto:support@yourapp.com")
        AFRatingKit.configure()
    }
}
```

---

## Configuration — Static Properties

All kits use a **static properties** pattern. Set values before calling `configure()`.

### AFAppearance

Global appearance shared across all kits:

```swift
AFAppearance.accentColor             = .systemBlue   // default
AFAppearance.ratingSubmitButtonColor = .systemBlue   // nil = uses accentColor
```

### AFOnboardingKit

```swift
AFOnboardingKit.fetchTimeout        = 10.0   // seconds, default: 10
AFOnboardingKit.displayTimeout      = 15.0   // seconds, default: 15
AFOnboardingKit.skipNetworkCheck    = false  // true = skip reachability check (for testing)
```

### AFPaywallKit

```swift
AFPaywallKit.productIds    = ["com.app.premium.yearly"]  // required for StoreKit fallback
AFPaywallKit.fetchTimeout  = 15.0                         // seconds, default: 15
```

### AFRatingKit

```swift
AFRatingKit.appName                = "My App"                               // default: CFBundleName
AFRatingKit.minDaysBetweenPrompts  = 30                                     // default: 30
AFRatingKit.negativeFeedbackURL    = URL(string: "mailto:support@app.com")  // default: nil
```

### AFDefaultOnboardingAdapter

```swift
AFDefaultOnboardingAdapter.pages = [
    AFOnboardingPage(
        title: "Scan Documents",
        subtitle: "Quickly scan any document",
        iconName: "doc.text.viewfinder",
        iconBackgroundColor: .systemBlue
    ),
    // ...
]
```

### AFDefaultPaywallAdapter

```swift
AFDefaultPaywallAdapter.privacyURL = URL(string: "https://yourapp.com/privacy")
AFDefaultPaywallAdapter.termsURL   = URL(string: "https://yourapp.com/terms")
```

---

## OnboardingKit

### Show Onboarding

```swift
let result = await AFOnboardingKit.shared.show(
    placementId: "onboarding_main",
    from: self
)

switch result {
case .completed:
    // User completed onboarding
case .skipped:
    // User pressed Skip
case .failed(let error):
    print("Error: \(error)")
}
```

### Check Completion Status

```swift
if AFOnboardingKit.shared.hasCompleted {
    // User has already seen onboarding — skip to main screen
}
```

### Force Show (for testing)

```swift
await AFOnboardingKit.shared.show(placementId: "onboarding_main", from: self, force: true)
```

### Permission Handling

Adapty onboarding can request system permissions via custom actions:

```swift
class AppDelegate: AFOnboardingPermissionHandler {

    func handlePermission(_ action: AFOnboardingPermissionAction) {
        switch action {
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        case .tracking:
            ATTrackingManager.requestTrackingAuthorization { _ in }
        case .custom(let id):
            print("Custom action: \(id)")
        }
    }
}
```

### Onboarding Completed Notification

Listen for onboarding completion from anywhere in the app:

```swift
NotificationCenter.default.addObserver(
    forName: .onboardingKitCompleted,
    object: nil,
    queue: .main
) { _ in
    // Navigate to main screen
}
```

### Custom Onboarding UI

Implement `AFOnboardingKitUI` on your `UIViewController`:

```swift
final class MyOnboardingViewController: UIViewController, AFOnboardingKitUI {

    private var context: AFOnboardingUIContext?

    static func make(context: AFOnboardingUIContext) -> UIViewController {
        let vc = MyOnboardingViewController()
        vc.context = context
        return vc
    }

    func userDidComplete() {
        dismiss(animated: true) {
            self.context?.complete()
        }
    }
}

// Configure with custom UI
AFOnboardingKit.configure(
    primaryProvider: AFAdaptyOnboardingProvider(permissionHandler: self),
    fallbackUI: MyOnboardingViewController.self
)
```

---

## PaywallKit

### Present Paywall

```swift
let result = await AFPaywallKit.show(
    placementId: "premium_upsell",
    from: self
)

switch result {
case .purchased:
    // User purchased subscription
case .restored:
    // User restored previous purchase
case .alreadyPurchased:
    // User already has active subscription (paywall was not shown)
case .cancelled:
    // User closed paywall without action
case .failed(let error):
    print("Error: \(error)")
}
```

### Force Show (e.g. from Settings)

```swift
await AFPaywallKit.show(
    placementId: "settings_subscription",
    from: self,
    forceShow: true   // shows even if subscription is active
)
```

### Dismiss Callback

```swift
await AFPaywallKit.show(
    placementId: "onboarding_paywall",
    from: self,
    onDismiss: {
        // Called when user closes paywall without purchasing
    }
)
```

### Subscription Validator

`AFSubscriptionService` is included and tracks subscription status from Adapty:

```swift
// In AdaptyDelegate
func didLoadLatestProfile(_ profile: AdaptyProfile) {
    AFSubscriptionService.shared.apply(profile: profile)
}

// Check anywhere
let isActive = await AFSubscriptionService.shared.isSubscriptionActive()
```

### Custom Paywall UI

Implement `AFPaywallKitUI` on your `UIViewController`:

```swift
final class MyPaywallViewController: UIViewController, AFPaywallKitUI {

    private var context: AFPaywallUIContext?

    static func make(context: AFPaywallUIContext) -> UIViewController {
        let vc = MyPaywallViewController()
        vc.context = context
        return vc
    }

    func userDidPurchase(productId: String) {
        Task {
            let result = await context?.purchase(productId: productId)
            dismiss(animated: true)
        }
    }

    func userDidClose() {
        context?.cancel()
        dismiss(animated: true)
    }
}

// Configure with custom UI
AFPaywallKit.configure(
    primaryProvider: AFAdaptyProvider(validator: AFSubscriptionService.shared),
    fallbackUI: MyPaywallViewController.self,
    validator: AFSubscriptionService.shared
)
```

---

## RatingKit

### Request Rating

Call after a positive user action (e.g. successful scan, export, etc.):

```swift
Task {
    await AFRatingKit.shared.requestIfNeeded(from: self)
}
```

The pre-prompt flow:
```
requestIfNeeded()
    ↓
"Do you like the app?"
    ├── Yes → SKStoreReviewController.requestReview()
    └── No  → opens negativeFeedbackURL (or dismisses silently)
```

### Force Show (for testing)

```swift
await AFRatingKit.shared.requestIfNeeded(from: self, force: true)
```

### Reset State (for testing)

```swift
AFRatingKit.shared.resetState()
```

---

## First Launch Flow — AFAppFlowKit

Coordinates the complete first-launch experience: onboarding → paywall → main screen.

### Configure

```swift
AFAppFlowKit.configure(
    onboardingPlacementId: "onboarding_main",
    paywallPlacementId: "paywall_after_onboarding",
    showPaywallAfterOnboarding: true
)
```

### Run

```swift
class RootViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task {
            let result = await AFAppFlowKit.shared.runFirstLaunch(from: self)
            navigateToMainScreen()

            if result.isSubscribed {
                // User subscribed during onboarding flow
            }
        }
    }
}
```

### AFAppFlowResult

```swift
let result: AFAppFlowResult
result.onboarding   // AFOnboardingResult — completed / skipped / failed
result.paywall      // AFPaywallResult? — nil if paywall was not shown
result.isSubscribed // true if user purchased or already had subscription
```

---

## Event Handlers

### Paywall Events

```swift
class MyPurchaseEventHandler: AFPurchaseEventHandler {
    func onPurchaseSuccess(result: AFPaywallResult) { ... }
    func onPurchaseFailure(error: AFPaywallKitError) { ... }
}

AFPaywallKit.configure(
    primaryProvider: ...,
    fallbackUI: ...,
    validator: ...,
    eventHandler: MyPurchaseEventHandler()
)
```

### Onboarding Events

```swift
class MyOnboardingEventHandler: AFOnboardingEventHandler {
    func onOnboardingCompleted(placementId: String) { ... }
    func onOnboardingSkipped(placementId: String) { ... }
    func onOnboardingFailed(error: AFOnboardingKitError, placementId: String) { ... }
}

AFOnboardingKit.configure(
    primaryProvider: ...,
    fallbackUI: ...,
    eventHandler: MyOnboardingEventHandler()
)
```

### Rating Events

```swift
class MyRatingEventHandler: AFRatingEventHandler {
    func onPositiveFeedback() { ... }   // User tapped "Yes" → Apple prompt shown
    func onNegativeFeedback() { ... }   // User tapped "No" → feedback URL opened
    func onDismissed() { ... }          // User closed pre-prompt without choosing
}

AFRatingKit.configure(eventHandler: MyRatingEventHandler())
```

---

## Architecture

### Source Structure

```
Sources/
├── AdaptyFlowKit/          ← umbrella (re-exports everything)
├── OnboardingKit/
│   ├── AFOnboardingKit.swift           ← main class + static config
│   ├── AFOnboardingKit+Types.swift     ← AFOnboardingResult, AFOnboardingKitError
│   ├── AFOnboardingProvider.swift      ← protocol
│   ├── AFOnboardingKitUI.swift         ← AFOnboardingKitUI protocol
│   ├── AFAdaptyOnboardingProvider.swift
│   ├── AFDefaultOnboardingAdapter.swift
│   ├── AFOnboardingViewController.swift
│   ├── AFAppFlowKit.swift
│   └── AFNetworkReachability.swift
└── PaywallKit/
    ├── AFPaywallKit.swift              ← main class + static config
    ├── AFPaywallKit+Types.swift        ← AFPaywallResult, AFPaywallKitError
    ├── AFPaywallProvider.swift         ← protocol
    ├── AFPaywallKitUI.swift            ← AFPaywallKitUI protocol
    ├── AFAdaptyProvider.swift
    ├── AFStoreKitProvider.swift
    ├── AFDefaultPaywallAdapter.swift
    ├── AFSubscriptionService.swift
    ├── AFAppearance.swift
    └── AFSingleFireContinuation.swift
RatingKit/
    └── AFRatingKit.swift               ← main class + static config + UI
```

### Provider Pattern

```
configure() called
     │
     ▼
show(placementId:)
     │
     ├──► Primary Provider (Adapty) ──► success → return result
     │                                ↘
     │                            failure (network / timeout)
     │                                  ↓
     └──► Fallback Provider (StoreKit / Custom UI) → return result
```

### Design Principles

| Concept | Implementation |
|---|---|
| Appearance | `AFAppearance.accentColor = ...` |
| Kit config | `AFPaywallKit.productIds = ...` |
| Adapter config | `AFDefaultPaywallAdapter.privacyURL = ...` |
| Activation | `AFPaywallKit.configure(...)` |
| Usage | `await AFPaywallKit.show(placementId:from:)` |

---

## Requirements

| Requirement | Version |
|---|---|
| iOS | 16.0+ |
| Swift | 5.9+ |
| Xcode | 15.0+ |
| Adapty SDK | 3.15+ |

---

## License

AdaptyFlowKit is available under the MIT license. See [LICENSE](LICENSE) for details.

## Support

- GitHub Issues: [Create an issue](https://github.com/balabon7/AdaptyFlowKit/issues)
