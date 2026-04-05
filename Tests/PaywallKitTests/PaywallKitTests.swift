import XCTest
@testable import AdaptyFlowKit

final class PaywallKitTests: XCTestCase {

    // MARK: - Static Properties

    func testDefaultStaticProperties() {
        // Reset to defaults before testing
        AFPaywallKit.productIds = []
        AFPaywallKit.fetchTimeout = 15.0

        XCTAssertEqual(AFPaywallKit.productIds, [])
        XCTAssertEqual(AFPaywallKit.fetchTimeout, 15.0)
    }

    func testStaticPropertiesAssignment() {
        let ids = ["com.app.premium.yearly", "com.app.premium.monthly"]
        AFPaywallKit.productIds = ids
        AFPaywallKit.fetchTimeout = 10.0

        XCTAssertEqual(AFPaywallKit.productIds, ids)
        XCTAssertEqual(AFPaywallKit.fetchTimeout, 10.0)

        // Cleanup
        AFPaywallKit.productIds = []
        AFPaywallKit.fetchTimeout = 15.0
    }

    // MARK: - AFPaywallResult

    func testPaywallResultIsSuccess() {
        XCTAssertTrue(AFPaywallResult.purchased.isSuccess)
        XCTAssertTrue(AFPaywallResult.restored.isSuccess)
        XCTAssertTrue(AFPaywallResult.alreadyPurchased.isSuccess)
        XCTAssertFalse(AFPaywallResult.cancelled.isSuccess)
        XCTAssertFalse(AFPaywallResult.failed(.notConfigured).isSuccess)
        XCTAssertFalse(AFPaywallResult.failed(.timeout).isSuccess)
    }

    func testPaywallResultEquality() {
        XCTAssertEqual(AFPaywallResult.purchased, .purchased)
        XCTAssertEqual(AFPaywallResult.restored, .restored)
        XCTAssertEqual(AFPaywallResult.cancelled, .cancelled)
        XCTAssertEqual(AFPaywallResult.failed(.notConfigured), .failed(.notConfigured))
        XCTAssertNotEqual(AFPaywallResult.purchased, .cancelled)
    }

    // MARK: - AFPaywallKitError

    func testErrorDescriptions() {
        XCTAssertNotNil(AFPaywallKitError.notConfigured.errorDescription)
        XCTAssertNotNil(AFPaywallKitError.noProductIds.errorDescription)
        XCTAssertNotNil(AFPaywallKitError.timeout.errorDescription)
        XCTAssertNotNil(AFPaywallKitError.noProducts.errorDescription)
        XCTAssertNotNil(AFPaywallKitError.subscriptionNotActive.errorDescription)
        XCTAssertNotNil(AFPaywallKitError.noActiveSubscription.errorDescription)
        XCTAssertNotNil(AFPaywallKitError.verificationFailed.errorDescription)
        XCTAssertNotNil(AFPaywallKitError.unknown.errorDescription)
    }
}
