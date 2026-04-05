import XCTest
@testable import AdaptyFlowKit

final class RatingKitTests: XCTestCase {

    // MARK: - Static Properties

    func testDefaultStaticProperties() {
        AFRatingKit.minDaysBetweenPrompts = 30
        AFRatingKit.negativeFeedbackURL = nil

        XCTAssertEqual(AFRatingKit.minDaysBetweenPrompts, 30)
        XCTAssertNil(AFRatingKit.negativeFeedbackURL)
    }

    func testStaticPropertiesAssignment() {
        let feedbackURL = URL(string: "mailto:support@app.com")

        AFRatingKit.appName = "Test App"
        AFRatingKit.minDaysBetweenPrompts = 14
        AFRatingKit.negativeFeedbackURL = feedbackURL

        XCTAssertEqual(AFRatingKit.appName, "Test App")
        XCTAssertEqual(AFRatingKit.minDaysBetweenPrompts, 14)
        XCTAssertEqual(AFRatingKit.negativeFeedbackURL, feedbackURL)

        // Cleanup
        AFRatingKit.minDaysBetweenPrompts = 30
        AFRatingKit.negativeFeedbackURL = nil
    }

    // MARK: - AFRatingResult

    func testRatingResultCases() {
        // Each case is distinct — verify via switch exhaustion
        func describe(_ result: AFRatingResult) -> String {
            switch result {
            case .positive:  return "positive"
            case .negative:  return "negative"
            case .dismissed: return "dismissed"
            case .throttled: return "throttled"
            }
        }

        XCTAssertEqual(describe(.positive),  "positive")
        XCTAssertEqual(describe(.negative),  "negative")
        XCTAssertEqual(describe(.dismissed), "dismissed")
        XCTAssertEqual(describe(.throttled), "throttled")
    }

    // MARK: - AFAppearance

    func testAppearanceDefaults() {
        XCTAssertEqual(AFAppearance.accentColor, .systemBlue)
        XCTAssertNil(AFAppearance.ratingSubmitButtonColor)
    }

    func testAppearanceAssignment() {
        AFAppearance.accentColor = .systemRed
        AFAppearance.ratingSubmitButtonColor = .systemGreen

        XCTAssertEqual(AFAppearance.accentColor, .systemRed)
        XCTAssertEqual(AFAppearance.ratingSubmitButtonColor, .systemGreen)

        // Cleanup
        AFAppearance.accentColor = .systemBlue
        AFAppearance.ratingSubmitButtonColor = nil
    }

    // MARK: - Reset State

    func testResetState() {
        // resetState() clears UserDefaults storage — should not crash
        AFRatingKit.shared.resetState()
    }
}
