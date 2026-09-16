import XCTest

@testable import Remux

final class GhosttyFlowTraceStoreTests: XCTestCase {
    func testMarkOnceReturnsStartExactlyOncePerFlowLifetime() {
        let store = GhosttyFlowTraceStore()
        store.begin(flow: "session.open.A", at: 100)

        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.init"), 100)
        XCTAssertNil(store.markOnce(flow: "session.open.A", event: "ui.init"))
    }

    func testMarkOnceIsNilForInactiveFlow() {
        let store = GhosttyFlowTraceStore()

        XCTAssertNil(store.markOnce(flow: "session.open.A", event: "ui.init"))
    }

    func testMarkOnceTracksEventsIndependently() {
        let store = GhosttyFlowTraceStore()
        store.begin(flow: "session.open.A", at: 100)

        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.init"), 100)
        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.mount"), 100)
        XCTAssertNil(store.markOnce(flow: "session.open.A", event: "ui.mount"))
    }

    func testMarkOnceRearmsOnNewFlowBegin() {
        let store = GhosttyFlowTraceStore()
        store.begin(flow: "session.open.A", at: 100)
        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.init"), 100)

        store.begin(flow: "session.open.A", at: 200)

        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.init"), 200)
    }

    func testEndClearsOnceEventsAndDeactivatesFlow() {
        let store = GhosttyFlowTraceStore()
        store.begin(flow: "session.open.A", at: 100)
        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.init"), 100)

        XCTAssertEqual(store.end(flow: "session.open.A"), 100)

        XCTAssertNil(store.markOnce(flow: "session.open.A", event: "ui.init"))
        store.begin(flow: "session.open.A", at: 300)
        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.init"), 300)
    }

    func testMarkOnceScopesEventsToTheirFlow() {
        let store = GhosttyFlowTraceStore()
        store.begin(flow: "session.open.A", at: 100)
        store.begin(flow: "session.open.B", at: 200)

        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.init"), 100)
        XCTAssertEqual(store.markOnce(flow: "session.open.B", event: "ui.init"), 200)

        // Re-beginning A must not disturb B's once-state.
        store.begin(flow: "session.open.A", at: 300)
        XCTAssertEqual(store.markOnce(flow: "session.open.A", event: "ui.init"), 300)
        XCTAssertNil(store.markOnce(flow: "session.open.B", event: "ui.init"))
    }
}
