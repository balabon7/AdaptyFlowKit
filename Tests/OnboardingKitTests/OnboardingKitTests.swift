import XCTest
@testable import OnboardingKit

final class OnboardingKitTests: XCTestCase {
    
    func testOnboardingKitConfiguration() {
        // Test that OnboardingKit can be configured
        let config = AFOnboardingKitConfiguration(
            fetchTimeout: 10,
            displayTimeout: 15,
            skipNetworkCheck: false
        )
        
        XCTAssertEqual(config.fetchTimeout, 10)
        XCTAssertEqual(config.displayTimeout, 15)
        XCTAssertFalse(config.skipNetworkCheck)
    }
    
    func testOnboardingResult() {
        let completedResult = AFOnboardingResult.completed
        XCTAssertTrue(completedResult.isFinished)
        
        let skippedResult = AFOnboardingResult.skipped
        XCTAssertTrue(skippedResult.isFinished)
        
        let failedResult = AFOnboardingResult.failed(.notConfigured)
        XCTAssertFalse(failedResult.isFinished)
    }
}
