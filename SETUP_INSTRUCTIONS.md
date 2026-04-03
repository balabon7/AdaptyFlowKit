# AdaptyFlowKit Setup Instructions

## Current Status

✅ Package structure created
✅ All files copied from MrScan project
✅ Package.swift manifest configured
✅ README.md documentation written
✅ Test files scaffolded

⚠️ **ACTION REQUIRED**: Code compatibility update needed

## Issue

The code in AdaptyFlowKit was written for Adapty SDK 3.x API, but the Package.swift currently references 2.11.x (for compatibility). This causes build errors.

## Solution Options

### Option 1: Update to Adapty SDK 3.x (Recommended)

Update your MrScan project to use Adapty SDK 3.x, then update AdaptyFlowKit Package.swift:

```swift
dependencies: [
    .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS.git", from: "3.2.0"),
    .package(url: "https://github.com/adaptyteam/AdaptyUI-iOS.git", from: "3.0.0"),
]
```

**Migration guide**: https://docs.adapty.io/docs/ios-sdk-migration-to-3-0

### Option 2: Backport Code to Adapty SDK 2.11.x

If you must stay on 2.11.x, update these files in `Sources/`:

#### PaywallKit/AFAdaptyProvider.swift

1. Line 68: Change `AdaptyUI.getPaywallConfiguration` → use 2.11.x API
2. Line 142: Update `AdaptyUI.paywallController(with:delegate:showDebugOverlay:)` signature
3. Lines 218-246: Update delegate methods for 2.11.x
4. Line 252: Update `AdaptyError.adaptyErrorCode` → 2.11.x error handling

#### OnboardingKit/AFAdaptyOnboardingProvider.swift

1. Line 52-56: Update Adapty Onboarding API to 2.11.x format
2. Line 84-87: Update controller creation

Check Adapty 2.11.x documentation: https://docs.adapty.io/v2.0/docs/ios-sdk-overview

## Next Steps

### After fixing compatibility:

1. **Build the package**:
   ```bash
   cd /path/to/AdaptyFlowKit
   swift build
   ```

2. **Run tests**:
   ```bash
   swift test
   ```

3. **Initialize Git repository**:
   ```bash
   git init
   git add .
   git commit -m "Initial commit: AdaptyFlowKit v1.0.0"
   ```

4. **Push to GitHub** (create repo first):
   ```bash
   git remote add origin https://github.com/YourUsername/AdaptyFlowKit.git
   git branch -M main
   git push -u origin main
   
   # Create version tag
   git tag 1.0.0
   git push origin 1.0.0
   ```

5. **Add to MrScan project**:
   - In Xcode: File → Add Package Dependencies
   - Enter your GitHub URL or use "Add Local..." for development
   - Select version or branch

## Using in MrScan

Once the package is ready, update your imports:

```swift
// Before (local files):
// No imports needed

// After (package):
import AdaptyFlowKit

// Or import individually:
import OnboardingKit
import PaywallKit
import RatingKit
```

The API remains the same - only imports change!

## Package Location

Current location: `/Users/oleksandrbalabon/Documents/Developer/SsoftTeam/AdaptyFlowKit`

## Support

For issues:
- Check Adapty SDK documentation
- Review API changes between 2.x and 3.x
- Test each module independently

## Files Structure

```
AdaptyFlowKit/
├── Package.swift                    # SPM manifest
├── README.md                        # User documentation
├── LICENSE                          # MIT License
├── .gitignore                       # Git ignore rules
├── SETUP_INSTRUCTIONS.md            # This file
├── Sources/
│   ├── AdaptyFlowKit/              # Main module
│   ├── OnboardingKit/              # 10 files
│   ├── PaywallKit/                 # 10 files
│   └── RatingKit/                  # 2 files
└── Tests/
    ├── OnboardingKitTests/
    ├── PaywallKitTests/
    └── RatingKitTests/
```

Total: 22 Swift source files + 3 test files + documentation
