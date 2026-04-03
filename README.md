# AdaptyFlowKit

A comprehensive iOS SDK for managing onboarding flows, paywall presentations, and smart rating requests with seamless [Adapty](https://adapty.io) integration.

[![Swift Version](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2016.0+-blue.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

### 📱 OnboardingKit
- Seamless Adapty onboarding integration with fallback support
- Automatic network availability checking
- Timeout handling with smart retry logic
- Permission request handling
- First launch flow coordination via `AFAppFlowKit`

### 💳 PaywallKit
- Primary Adapty provider with StoreKit fallback
- Customizable UI with protocol-based architecture
- Subscription validation
- Automatic subscription status checking
- Purchase event handling

### ⭐ RatingKit
- Smart rating request with pre-prompt
- Protects Apple's 3-per-year quota from unhappy users
- Configurable throttling
- Negative feedback redirection
- Version-based tracking

## Installation

### Swift Package Manager

Add AdaptyFlowKit to your project via Xcode:

1. File → Add Package Dependencies
2. Enter package URL: `https://github.com/YourUsername/AdaptyFlowKit.git`
3. Select version: `from 1.0.0`

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/YourUsername/AdaptyFlowKit.git", from: "1.0.0")
]
```

### Import Options

Import all kits at once:
```swift
import AdaptyFlowKit
```

Or import individually:
```swift
import OnboardingKit
import PaywallKit
import RatingKit
```

## Quick Start

### 1. Configure Adapty (Required)

First, configure Adapty SDK in your AppDelegate:

```swift
import Adapty
import AdaptyFlowKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize Adapty
        let adaptyConfig = Adapty.Configuration
            .builder(withAPIKey: "YOUR_ADAPTY_API_KEY")
            .build()
        Adapty.activate(with: adaptyConfig)
        
        // Configure all kits
        configureAdaptyFlowKit()
        
        return true
    }
}
```

### 2. Configure AdaptyFlowKit

```swift
func configureAdaptyFlowKit() {
    // Subscription validator
    let subscriptionService = AFSubscriptionService()
    
    // Configure PaywallKit
    AFPaywallKit.configure(
        configuration: .init(
            productIds: ["com.app.premium.yearly", "com.app.premium.monthly"]
        ),
        primaryProvider: AFAdaptyProvider(validator: subscriptionService),
        fallbackUI: MyPaywallViewController.self,
        validator: subscriptionService
    )
    
    // Configure OnboardingKit
    AFOnboardingKit.configure(
        configuration: .init(fetchTimeout: 10, displayTimeout: 15),
        primaryProvider: AFAdaptyOnboardingProvider(
            fetchTimeout: 10,
            displayTimeout: 15
        ),
        fallbackUI: MyOnboardingViewController.self
    )
    
    // Configure RatingKit
    AFRatingKit.configure(
        configuration: .init(
            appName: "Your App Name",
            minDaysBetweenPrompts: 14,
            negativeFeedbackURL: URL(string: "mailto:support@yourapp.com")
        )
    )
    
    // Configure AppFlowKit (coordinates first launch)
    AFAppFlowKit.configure(
        onboardingPlacementId: "onboarding_main",
        paywallPlacementId: "paywall_after_onboarding",
        showPaywallAfterOnboarding: true
    )
}
```

### 3. First Launch Flow

Use `AFAppFlowKit` to coordinate the complete first launch experience:

```swift
class WelcomeViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !AFOnboardingKit.shared.hasCompleted {
            Task {
                // Run complete first launch flow (onboarding → paywall)
                let result = await AFAppFlowKit.shared.runFirstLaunch(from: self)
                
                // Navigate to main screen
                navigateToMainScreen()
                
                if result.isSubscribed {
                    print("User subscribed during onboarding!")
                }
            }
        } else {
            navigateToMainScreen()
        }
    }
}
```

## Detailed Usage

### OnboardingKit

Show onboarding manually:

```swift
let result = await AFOnboardingKit.shared.show(
    placementId: "onboarding_main",
    from: self
)

switch result {
case .completed:
    print("Onboarding completed")
case .skipped:
    print("User skipped onboarding")
case .failed(let error):
    print("Error: \(error)")
}
```

Check if onboarding was completed:

```swift
if AFOnboardingKit.shared.hasCompleted {
    // User has seen onboarding
}
```

### PaywallKit

Present paywall:

```swift
let result = await AFPaywallKit.present(
    placementId: "premium_upsell",
    from: self
)

switch result {
case .purchased:
    print("User purchased subscription")
case .restored:
    print("User restored purchase")
case .alreadyPurchased:
    print("User already has subscription")
case .cancelled:
    print("User closed paywall")
case .failed(let error):
    print("Error: \(error)")
}
```

Force show paywall (even if subscribed):

```swift
await AFPaywallKit.present(
    placementId: "settings_subscription",
    from: self,
    forceShow: true
)
```

### RatingKit

Request rating at appropriate moments:

```swift
// After successful user action
Task {
    await AFRatingKit.shared.requestIfNeeded(from: self)
}
```

Force show for testing:

```swift
await AFRatingKit.shared.requestIfNeeded(from: self, force: true)
```

Reset state (for testing):

```swift
AFRatingKit.shared.resetState()
```

## Custom UI

### Custom Paywall UI

Implement `AFPaywallKitUI` protocol:

```swift
class MyPaywallViewController: UIViewController, AFPaywallKitUI {
    var productIds: [String] = []
    var onPurchaseSuccess: ((String) -> Void)?
    var onRestoreSuccess: (() -> Void)?
    var onClose: (() -> Void)?
    
    static func create(
        productIds: [String],
        onPurchaseSuccess: @escaping (String) -> Void,
        onRestoreSuccess: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) -> Self {
        let vc = Self()
        vc.productIds = productIds
        vc.onPurchaseSuccess = onPurchaseSuccess
        vc.onRestoreSuccess = onRestoreSuccess
        vc.onClose = onClose
        return vc
    }
}
```

### Custom Onboarding UI

Implement `AFOnboardingKitUI` protocol:

```swift
class MyOnboardingViewController: UIViewController, AFOnboardingKitUI {
    var onComplete: (() -> Void)?
    
    static func create(onComplete: @escaping () -> Void) -> Self {
        let vc = Self()
        vc.onComplete = onComplete
        return vc
    }
}
```

## Event Handling

### Paywall Events

```swift
class MyPurchaseEventHandler: AFPurchaseEventHandler {
    func onPurchaseSuccess(result: AFPaywallResult) {
        print("Purchase successful: \(result)")
        // Send analytics, update UI, etc.
    }
    
    func onPurchaseFailure(error: AFPaywallKitError) {
        print("Purchase failed: \(error)")
    }
}

// Pass to configure:
AFPaywallKit.configure(
    // ... other parameters
    eventHandler: MyPurchaseEventHandler()
)
```

### Onboarding Events

```swift
class MyOnboardingEventHandler: AFOnboardingEventHandler {
    func onOnboardingCompleted(placementId: String) {
        print("Onboarding completed: \(placementId)")
    }
    
    func onOnboardingSkipped(placementId: String) {
        print("Onboarding skipped: \(placementId)")
    }
    
    func onOnboardingFailed(error: AFOnboardingKitError, placementId: String) {
        print("Onboarding failed: \(error)")
    }
}

// Pass to configure:
AFOnboardingKit.configure(
    // ... other parameters
    eventHandler: MyOnboardingEventHandler()
)
```

### Rating Events

```swift
class MyRatingEventHandler: AFRatingEventHandler {
    func onPositiveFeedback() {
        print("User is happy! Showing Apple rating prompt")
    }
    
    func onNegativeFeedback() {
        print("User is unhappy, redirecting to feedback")
    }
    
    func onDismissed() {
        print("User dismissed rating prompt")
    }
}

// Pass to configure:
AFRatingKit.configure(
    // ... other parameters
    eventHandler: MyRatingEventHandler()
)
```

## Architecture

### Module Structure

```
AdaptyFlowKit/
├── OnboardingKit/
│   ├── Core: AFOnboardingKit, AFOnboardingProvider
│   ├── Adapty: AFAdaptyOnboardingProvider
│   ├── Fallback: AFDefaultOnboardingAdapter
│   ├── UI: AFOnboardingKitUI, AFOnboardingViewController
│   ├── Utilities: AFNetworkReachability
│   └── Coordinator: AFAppFlowKit
├── PaywallKit/
│   ├── Core: AFPaywallKit, AFPaywallProvider
│   ├── Adapty: AFAdaptyProvider
│   ├── StoreKit: AFStoreKitProvider
│   ├── UI: AFPaywallKitUI
│   └── Service: AFSubscriptionService
└── RatingKit/
    ├── Core: AFRatingKit
    └── UI: AFRatingPromptViewController
```

### Provider Pattern

Both OnboardingKit and PaywallKit use a provider pattern for flexibility:
- **Primary Provider**: Adapty integration (rich features, A/B testing)
- **Fallback Provider**: Local implementation (works offline, no network required)

### Dependency Flow

```
AdaptyFlowKit (main)
    ├── OnboardingKit
    │   └── PaywallKit (for AFAppFlowKit)
    ├── PaywallKit
    │   ├── Adapty SDK
    │   └── AdaptyUI SDK
    └── RatingKit
        └── PaywallKit (for logging only)
```

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15.0+
- Adapty SDK 3.0+

## License

AdaptyFlowKit is available under the MIT license. See LICENSE for details.

## Support

For issues and questions:
- GitHub Issues: [Create an issue](https://github.com/YourUsername/AdaptyFlowKit/issues)
- Email: support@yourcompany.com

## Credits

Built with ❤️ using [Adapty](https://adapty.io) SDK.
