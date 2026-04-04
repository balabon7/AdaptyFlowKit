// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AdaptyFlowKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "AdaptyFlowKit",
            targets: ["AdaptyFlowKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS.git", from: "3.15.0"),
    ],
    targets: [
        // Single module — all kits in one target
        .target(
            name: "AdaptyFlowKit",
            dependencies: [
                .product(name: "Adapty", package: "AdaptySDK-iOS"),
                .product(name: "AdaptyUI", package: "AdaptySDK-iOS"),
            ],
            path: "Sources",
            sources: [
                "AdaptyFlowKit",
                "PaywallKit",
                "OnboardingKit",
                "RatingKit",
            ]
        ),

        // Tests
        .testTarget(
            name: "PaywallKitTests",
            dependencies: ["AdaptyFlowKit"],
            path: "Tests/PaywallKitTests"
        ),
        .testTarget(
            name: "OnboardingKitTests",
            dependencies: ["AdaptyFlowKit"],
            path: "Tests/OnboardingKitTests"
        ),
        .testTarget(
            name: "RatingKitTests",
            dependencies: ["AdaptyFlowKit"],
            path: "Tests/RatingKitTests"
        ),
    ]
)
