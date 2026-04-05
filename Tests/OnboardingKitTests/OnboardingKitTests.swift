import XCTest
@testable import AdaptyFlowKit

final class OnboardingKitTests: XCTestCase {

    // MARK: - Static Properties

    func testDefaultStaticProperties() {
        AFOnboardingKit.fetchTimeout = 10.0
        AFOnboardingKit.displayTimeout = 15.0
        AFOnboardingKit.skipNetworkCheck = false

        XCTAssertEqual(AFOnboardingKit.fetchTimeout, 10.0)
        XCTAssertEqual(AFOnboardingKit.displayTimeout, 15.0)
        XCTAssertFalse(AFOnboardingKit.skipNetworkCheck)
    }

    func testStaticPropertiesAssignment() {
        AFOnboardingKit.fetchTimeout = 5.0
        AFOnboardingKit.displayTimeout = 8.0
        AFOnboardingKit.skipNetworkCheck = true

        XCTAssertEqual(AFOnboardingKit.fetchTimeout, 5.0)
        XCTAssertEqual(AFOnboardingKit.displayTimeout, 8.0)
        XCTAssertTrue(AFOnboardingKit.skipNetworkCheck)

        // Cleanup
        AFOnboardingKit.fetchTimeout = 10.0
        AFOnboardingKit.displayTimeout = 15.0
        AFOnboardingKit.skipNetworkCheck = false
    }

    // MARK: - AFOnboardingResult

    func testOnboardingResultIsFinished() {
        XCTAssertTrue(AFOnboardingResult.completed.isFinished)
        XCTAssertTrue(AFOnboardingResult.skipped.isFinished)
        XCTAssertFalse(AFOnboardingResult.failed(.notConfigured).isFinished)
        XCTAssertFalse(AFOnboardingResult.failed(.fetchTimeout).isFinished)
        XCTAssertFalse(AFOnboardingResult.failed(.noFallbackUI).isFinished)
    }

    // MARK: - AFOnboardingKitError

    func testErrorDescriptions() {
        XCTAssertNotNil(AFOnboardingKitError.notConfigured.errorDescription)
        XCTAssertNotNil(AFOnboardingKitError.fetchTimeout.errorDescription)
        XCTAssertNotNil(AFOnboardingKitError.displayTimeout.errorDescription)
        XCTAssertNotNil(AFOnboardingKitError.noFallbackUI.errorDescription)
        XCTAssertNotNil(AFOnboardingKitError.unknown.errorDescription)
    }

    // MARK: - AFAppFlowResult

    func testAppFlowResultIsSubscribed() {
        let subscribedFlow = AFAppFlowResult(onboarding: .completed, paywall: .purchased)
        XCTAssertTrue(subscribedFlow.isSubscribed)

        let restoredFlow = AFAppFlowResult(onboarding: .completed, paywall: .restored)
        XCTAssertTrue(restoredFlow.isSubscribed)

        let cancelledFlow = AFAppFlowResult(onboarding: .completed, paywall: .cancelled)
        XCTAssertFalse(cancelledFlow.isSubscribed)

        let noPaywallFlow = AFAppFlowResult(onboarding: .completed, paywall: nil)
        XCTAssertFalse(noPaywallFlow.isSubscribed)
    }

    // MARK: - AFOnboardingPermissionAction

    func testPermissionActionParsing() {
        let notifications = AFOnboardingPermissionAction(actionId: "request_notifications")
        if case .notifications = notifications { } else {
            XCTFail("Expected .notifications")
        }

        let tracking = AFOnboardingPermissionAction(actionId: "request_tracking")
        if case .tracking = tracking { } else {
            XCTFail("Expected .tracking")
        }

        let custom = AFOnboardingPermissionAction(actionId: "some_custom_action")
        if case .custom(let id) = custom {
            XCTAssertEqual(id, "some_custom_action")
        } else {
            XCTFail("Expected .custom")
        }
    }
}
