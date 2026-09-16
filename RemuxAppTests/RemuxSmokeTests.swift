import XCTest
@testable import Remux

final class RemuxSmokeTests: XCTestCase {
    @MainActor
    func testRootViewInitializes() {
        _ = RootView()
    }
}
