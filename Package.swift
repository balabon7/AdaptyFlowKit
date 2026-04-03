// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AdaptyFlowKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        // Main product - exports all three kits
        .library(
            name: "AdaptyFlowKit",
            targets: ["AdaptyFlowKit"]
        ),
        // Individual products (if someone wants to use only one)
        .library(
            name: "OnboardingKit",
            targets: ["OnboardingKit"]
        ),
        .library(
            name: "PaywallKit",
            targets: ["PaywallKit"]
        ),
        .library(
            name: "RatingKit",
            targets: ["RatingKit"]
        ),
    ],
    dependencies: [
        // External dependencies - matching MrScan project versions
        .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS.git", from: "3.15.0"),
        .package(url: "https://github.com/adaptyteam/AdaptyUI-iOS.git", from: "3.0.0"),
    ],
    targets: [
        // Main module (re-exports all three)
        .target(
            name: "AdaptyFlowKit",
            dependencies: [
                "OnboardingKit",
                "PaywallKit",
                "RatingKit"
            ]
        ),
        
        // OnboardingKit
        .target(
            name: "OnboardingKit",
            dependencies: [
                .product(name: "Adapty", package: "AdaptySDK-iOS"),
                .product(name: "AdaptyUI", package: "AdaptyUI-iOS"),
                "PaywallKit" // For AFAppFlowKit and shared types
            ]
        ),
        
        // PaywallKit
        .target(
            name: "PaywallKit",
            dependencies: [
                .product(name: "Adapty", package: "AdaptySDK-iOS"),
                .product(name: "AdaptyUI", package: "AdaptyUI-iOS"),
            ]
        ),
        
        // RatingKit (minimal dependencies)
        .target(
            name: "RatingKit",
            dependencies: [
                "PaywallKit" // Only for AFPaywallKitLogger protocol
            ]
        ),
        
        // Tests
        .testTarget(
            name: "OnboardingKitTests",
            dependencies: ["OnboardingKit"]
        ),
        .testTarget(
            name: "PaywallKitTests",
            dependencies: ["PaywallKit"]
        ),
        .testTarget(
            name: "RatingKitTests",
            dependencies: ["RatingKit"]
        ),
    ]
)
