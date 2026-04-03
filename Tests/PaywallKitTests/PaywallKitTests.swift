import XCTest
@testable import PaywallKit

final class PaywallKitTests: XCTestCase {
    
    func testPaywallKitConfiguration() {
        let config = AFPaywallKitConfiguration(
            productIds: ["com.test.premium"],
            fetchTimeout: 15.0
        )
        
        XCTAssertEqual(config.productIds, ["com.test.premium"])
        XCTAssertEqual(config.fetchTimeout, 15.0)
    }
    
    func testPaywallResult() {
        let purchasedResult = AFPaywallResult.purchased
        XCTAssertTrue(purchasedResult.isSuccess)
        
        let restoredResult = AFPaywallResult.restored
        XCTAssertTrue(restoredResult.isSuccess)
        
        let cancelledResult = AFPaywallResult.cancelled
        XCTAssertFalse(cancelledResult.isSuccess)
    }
}
