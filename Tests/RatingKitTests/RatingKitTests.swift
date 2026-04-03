import XCTest
@testable import RatingKit

final class RatingKitTests: XCTestCase {
    
    func testRatingKitConfiguration() {
        let config = AFRatingKitConfiguration(
            appName: "Test App",
            minDaysBetweenPrompts: 30
        )
        
        XCTAssertEqual(config.appName, "Test App")
        XCTAssertEqual(config.minDaysBetweenPrompts, 30)
    }
    
    func testRatingResult() {
        let positiveResult = AFRatingResult.positive
        XCTAssertNotNil(positiveResult)
        
        let negativeResult = AFRatingResult.negative
        XCTAssertNotNil(negativeResult)
        
        let throttledResult = AFRatingResult.throttled
        XCTAssertNotNil(throttledResult)
    }
}
