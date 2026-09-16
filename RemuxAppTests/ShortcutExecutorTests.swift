import XCTest
@testable import Remux

@MainActor
final class ShortcutExecutorTests: XCTestCase {
    func testTextShortcutAutoSubmitSendsTextThenEnterKeyTap() async {
        var operations: [SentShortcutOperation] = []
        let executor = ShortcutExecutor(
            sendText: {
                operations.append(.text($0))
                return true
            },
            sendKey: {
                operations.append(.key($0))
                return true
            },
            autoSubmitBoundary: {
                operations.append(.autoSubmitBoundary)
                return true
            }
        )

        let didExecute = await executor.execute(.text("/clear", submit: true))

        XCTAssertTrue(didExecute)

        XCTAssertEqual(
            operations,
            [
                .text("/clear"),
                .autoSubmitBoundary,
                .key(GhosttySurfaceKeyEvent(action: .press, keyCode: .enter)),
                .key(GhosttySurfaceKeyEvent(action: .release, keyCode: .enter)),
            ]
        )
    }

    func testTextShortcutWithoutSubmitSendsOnlyText() async {
        var operations: [SentShortcutOperation] = []
        let executor = ShortcutExecutor(
            sendText: {
                operations.append(.text($0))
                return true
            },
            sendKey: {
                operations.append(.key($0))
                return true
            },
            autoSubmitBoundary: {
                operations.append(.autoSubmitBoundary)
                return true
            }
        )

        let didExecute = await executor.execute(.text("draft", submit: false))

        XCTAssertTrue(didExecute)

        XCTAssertEqual(operations, [.text("draft")])
    }

    func testTextShortcutRejectedBeforeSubmitDoesNotSendEnter() async {
        var operations: [SentShortcutOperation] = []
        let executor = ShortcutExecutor(
            sendText: {
                operations.append(.text($0))
                return false
            },
            sendKey: {
                operations.append(.key($0))
                return true
            },
            autoSubmitBoundary: {
                operations.append(.autoSubmitBoundary)
                return true
            }
        )

        let didExecute = await executor.execute(.text("/status", submit: true))

        XCTAssertFalse(didExecute)

        XCTAssertEqual(operations, [.text("/status")])
    }

    func testTextShortcutAutoSubmitSucceedsWhenEnterReleaseIsIgnored() async {
        var operations: [SentShortcutOperation] = []
        let executor = ShortcutExecutor(
            sendText: {
                operations.append(.text($0))
                return true
            },
            sendKey: {
                operations.append(.key($0))
                return $0.action == .press
            },
            autoSubmitBoundary: {
                operations.append(.autoSubmitBoundary)
                return true
            }
        )

        let didExecute = await executor.execute(.text("/resume", submit: true))

        XCTAssertTrue(didExecute)
        XCTAssertEqual(
            operations,
            [
                .text("/resume"),
                .autoSubmitBoundary,
                .key(GhosttySurfaceKeyEvent(action: .press, keyCode: .enter)),
                .key(GhosttySurfaceKeyEvent(action: .release, keyCode: .enter)),
            ]
        )
    }

    func testTextShortcutStopsWhenAutoSubmitBoundaryIsCancelled() async {
        var operations: [SentShortcutOperation] = []
        let executor = ShortcutExecutor(
            sendText: {
                operations.append(.text($0))
                return true
            },
            sendKey: {
                operations.append(.key($0))
                return true
            },
            autoSubmitBoundary: {
                operations.append(.autoSubmitBoundary)
                return false
            }
        )

        let didExecute = await executor.execute(.text("/status", submit: true))

        XCTAssertFalse(didExecute)
        XCTAssertEqual(operations, [.text("/status"), .autoSubmitBoundary])
    }

    func testControlShortcutSendsTranslatedControlCharacter() async {
        var sentTexts: [String] = []
        let executor = ShortcutExecutor(
            sendText: {
                sentTexts.append($0)
                return true
            },
            sendKey: { _ in
                XCTFail("Control shortcut should not send a key event")
                return false
            }
        )

        let didExecute = await executor.execute(.control("c"))

        XCTAssertTrue(didExecute)

        XCTAssertEqual(sentTexts, ["\u{03}"])
    }

    func testInvalidControlShortcutIsRejected() async {
        let executor = ShortcutExecutor(
            sendText: { _ in
                XCTFail("Invalid control shortcut should not send text")
                return true
            },
            sendKey: { _ in
                XCTFail("Invalid control shortcut should not send key event")
                return true
            }
        )

        let didExecute = await executor.execute(.control("invalid"))

        XCTAssertFalse(didExecute)
    }

    func testKeyShortcutSendsMappedKeyEvent() async {
        var sentEvents: [GhosttySurfaceKeyEvent] = []
        let executor = ShortcutExecutor(
            sendText: { _ in
                XCTFail("Key shortcut should not send text")
                return false
            },
            sendKey: {
                sentEvents.append($0)
                return true
            }
        )

        let didExecute = await executor.execute(.key(.tab, modifiers: [.shift, .control]))

        XCTAssertTrue(didExecute)

        XCTAssertEqual(sentEvents.count, 1)
        XCTAssertEqual(sentEvents.first?.keyCode, .tab)
        XCTAssertEqual(sentEvents.first?.mods, [.shift, .ctrl])
    }
}

private enum SentShortcutOperation: Equatable {
    case text(String)
    case autoSubmitBoundary
    case key(GhosttySurfaceKeyEvent)
}
