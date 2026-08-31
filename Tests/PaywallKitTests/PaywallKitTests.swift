import XCTest
@testable import AdaptyFlowKit

@MainActor
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

    // MARK: - Access Level

    func testAccessLevelIdDefaultsToPremium() {
        XCTAssertEqual(AFPaywallKit.accessLevelId, "premium")
    }

    func testAccessLevelIdIsConfigurable() {
        AFPaywallKit.accessLevelId = "pro"
        XCTAssertEqual(AFPaywallKit.accessLevelId, "pro")

        // Cleanup
        AFPaywallKit.accessLevelId = "premium"
    }

    // MARK: - Purchase confirmation

    /// Reports "not active" for the first `activeAfterCalls` checks, then active.
    private final class StubValidator: AFSubscriptionValidator, @unchecked Sendable {
        private let activeAfterCalls: Int
        private(set) var callCount = 0

        init(activeAfterCalls: Int) { self.activeAfterCalls = activeAfterCalls }

        @MainActor
        func isSubscriptionActive() async -> Bool {
            callCount += 1
            return callCount > activeAfterCalls
        }
    }

    /// Stands in for a provider that took the payment but could not confirm it.
    private final class UnconfirmedPurchaseProvider: AFPaywallProvider, @unchecked Sendable {
        @MainActor
        func present(placementId: String, from presenter: UIViewController) async -> AFPaywallResult {
            .failed(.subscriptionNotActive)
        }
    }

    private func configureForConfirmation(validator: AFSubscriptionValidator) {
        AFPaywallKit.configure(
            primaryProvider: UnconfirmedPurchaseProvider(),
            fallbackProvider: nil,
            validator: validator
        )
    }

    func testUnconfirmedPurchaseIsReportedAsPurchasedOnceEntitlementAppears() async {
        AFPaywallKit.purchaseConfirmationTimeout = 3.0
        let validator = StubValidator(activeAfterCalls: 1)
        configureForConfirmation(validator: validator)

        let result = await AFPaywallKit.show(
            placementId: "test",
            from: UIViewController(),
            forceShow: true
        )

        XCTAssertEqual(result, .purchased)
        XCTAssertGreaterThan(validator.callCount, 1)
    }

    func testUnconfirmedPurchaseStaysFailedWhenEntitlementNeverAppears() async {
        AFPaywallKit.purchaseConfirmationTimeout = 0.1
        let validator = StubValidator(activeAfterCalls: .max)
        configureForConfirmation(validator: validator)

        let result = await AFPaywallKit.show(
            placementId: "test",
            from: UIViewController(),
            forceShow: true
        )

        XCTAssertEqual(result, .failed(.subscriptionNotActive))
    }

    func testZeroTimeoutSkipsConfirmationEntirely() async {
        AFPaywallKit.purchaseConfirmationTimeout = 0
        let validator = StubValidator(activeAfterCalls: 0)
        configureForConfirmation(validator: validator)

        let result = await AFPaywallKit.show(
            placementId: "test",
            from: UIViewController(),
            forceShow: true
        )

        // The validator would have said "active" on its first call; a zero
        // timeout must not consult it at all.
        XCTAssertEqual(result, .failed(.subscriptionNotActive))
        XCTAssertEqual(validator.callCount, 0)

        AFPaywallKit.purchaseConfirmationTimeout = 3.0
    }
}
