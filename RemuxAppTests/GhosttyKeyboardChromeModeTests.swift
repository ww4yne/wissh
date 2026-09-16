import XCTest
@testable import Remux

final class GhosttyKeyboardChromeModeTests: XCTestCase {
    func testKeyboardToggleShowsSystemKeyboardFromHiddenMode() {
        XCTAssertEqual(GhosttyKeyboardChromeMode.hidden.toggledKeyboard(), .system)
    }

    func testKeyboardToggleHidesSystemKeyboard() {
        XCTAssertEqual(GhosttyKeyboardChromeMode.system.toggledKeyboard(), .hidden)
    }

    func testSystemKeyboardVisibilitySyncsHiddenAndSystemModes() {
        XCTAssertEqual(
            GhosttyKeyboardChromeMode.hidden.applyingSystemKeyboardVisibility(true),
            .system
        )
        XCTAssertEqual(
            GhosttyKeyboardChromeMode.system.applyingSystemKeyboardVisibility(false),
            .hidden
        )
    }

    func testKeyboardModeOnlyControlsKeyboardIntent() {
        XCTAssertFalse(GhosttyKeyboardChromeMode.hidden.enablesSystemKeyboard)
        XCTAssertTrue(GhosttyKeyboardChromeMode.system.enablesSystemKeyboard)
    }
}
