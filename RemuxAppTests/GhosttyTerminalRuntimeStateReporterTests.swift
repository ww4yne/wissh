import Foundation
import XCTest
@testable import Remux

@MainActor
final class GhosttyTerminalRuntimeStateReporterTests: XCTestCase {

    func testRuntimeStateRequiresRunningAndFocusedSurfaceForConnected() {
        XCTAssertEqual(
            TerminalReadinessProjector.runtimeState(
                Self.readinessSnapshot(
                    phase: .running,
                    transportWritable: true,
                    topLevelCount: 1,
                    focused: false
                )
            ),
            .connecting
        )
        XCTAssertEqual(
            TerminalReadinessProjector.runtimeState(
                Self.readinessSnapshot(
                    phase: .running,
                    transportWritable: false,
                    topLevelCount: 0,
                    focused: true
                )
            ),
            .connecting
        )
    }


    func testFailedSnapshotWithoutReasonUsesUnknownMessage() {
        let state = TerminalReadinessProjector.runtimeState(
            Self.readinessSnapshot(
                phase: .failed(message: "runtime failed", reason: nil),
                focused: false
            )
        )

        XCTAssertEqual(
            state,
            .disconnected(
                TerminalDisconnectReason(
                    kind: .unknown,
                    message: "runtime failed"
                )
            )
        )
    }


    private static func readinessSnapshot(
        phase: GhosttyTerminalRuntimePhase,
        transportWritable: Bool = false,
        topLevelCount: Int = 0,
        focused: Bool = false
    ) -> TerminalReadinessSnapshot {
        TerminalReadinessProjector.snapshot(
            phase: phase,
            transportWritable: transportWritable,
            topLevelCount: topLevelCount,
            selectedActiveLeafID: focused ? UUID() : nil,
            selectedPanePresentation: focused ? .ready : .pending
        )
    }
}
