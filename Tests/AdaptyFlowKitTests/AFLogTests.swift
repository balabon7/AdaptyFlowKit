import XCTest
@testable import AdaptyFlowKit

final class AFLogTests: XCTestCase {

    /// Collects records emitted through `AdaptyFlowKit.logHandler`.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [(AFLogLevel, String)] = []

        func append(_ level: AFLogLevel, _ message: String) {
            lock.lock()
            defer { lock.unlock() }
            storage.append((level, message))
        }

        var records: [(AFLogLevel, String)] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private var sink: Sink!
    private var originalLevel: AFLogLevel!

    override func setUp() {
        super.setUp()
        sink = Sink()
        originalLevel = AdaptyFlowKit.logLevel
        let sink = self.sink!
        AdaptyFlowKit.logHandler = { level, message in sink.append(level, message) }
    }

    override func tearDown() {
        AdaptyFlowKit.logHandler = nil
        AdaptyFlowKit.logLevel = originalLevel
        sink = nil
        super.tearDown()
    }

    // MARK: - Level ordering

    func testLevelOrdering() {
        XCTAssertLessThan(AFLogLevel.debug, .info)
        XCTAssertLessThan(AFLogLevel.info, .warning)
        XCTAssertLessThan(AFLogLevel.warning, .error)
        XCTAssertLessThan(AFLogLevel.error, .off)
    }

    // MARK: - Filtering

    func testHandlerReceivesRecordsAtOrAboveLogLevel() {
        AdaptyFlowKit.logLevel = .warning

        AFLog.debug("dropped")
        AFLog.info("dropped")
        AFLog.warning("kept")
        AFLog.error("kept")

        let records = sink.records
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.1), ["kept", "kept"])
        XCTAssertEqual(records.map(\.0), [.warning, .error])
    }

    func testDebugLevelLetsEverythingThrough() {
        AdaptyFlowKit.logLevel = .debug

        AFLog.debug("a")
        AFLog.info("b")
        AFLog.warning("c")
        AFLog.error("d")

        XCTAssertEqual(sink.records.map(\.1), ["a", "b", "c", "d"])
    }

    func testOffSilencesEverything() {
        AdaptyFlowKit.logLevel = .off

        AFLog.debug("a")
        AFLog.info("b")
        AFLog.warning("c")
        AFLog.error("d")

        XCTAssertTrue(sink.records.isEmpty)
    }

    // MARK: - Laziness

    func testFilteredMessageIsNeverEvaluated() {
        AdaptyFlowKit.logLevel = .error

        var didEvaluate = false
        AFLog.debug({ didEvaluate = true; return "expensive" }())

        XCTAssertFalse(didEvaluate, "Filtered-out records must not build their message")
    }
}
