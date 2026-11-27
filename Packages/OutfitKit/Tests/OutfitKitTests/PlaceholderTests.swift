import XCTest
@testable import OutfitKit

final class PlaceholderTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(GarmentCategory.top.rawValue, "top")
    }
}
