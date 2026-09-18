import XCTest
@testable import Wissh

final class WisshSmokeTests: XCTestCase {
    @MainActor
    func testRootViewInitializes() {
        _ = RootView()
    }
}
