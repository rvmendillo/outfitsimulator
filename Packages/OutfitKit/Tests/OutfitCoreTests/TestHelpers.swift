import Foundation
import XCTest
@testable import OutfitCore

func XCTAssertPointEqual(_ a: CGPoint, _ b: CGPoint, accuracy: Double, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(Double(a.x), Double(b.x), accuracy: accuracy, "x: \(message) \(a) vs \(b)", file: file, line: line)
    XCTAssertEqual(Double(a.y), Double(b.y), accuracy: accuracy, "y: \(message) \(a) vs \(b)", file: file, line: line)
}

extension AlphaMask {
    /// Builds a mask from rectangles (inclusive pixel bounds).
    static func with(width: Int, height: Int, rects: [PixelRect]) -> AlphaMask {
        var mask = AlphaMask(width: width, height: height)
        for r in rects { mask.fillRect(r) }
        return mask
    }
}

func makeGarment(
    id: UUID = UUID(),
    category: GarmentCategory,
    color: RGBColor = .white,
    size: CGSize = CGSize(width: 400, height: 500),
    anchors: GarmentAnchors? = nil
) -> Garment {
    Garment(id: id, name: category.displayName, category: category,
            imageFile: "garment-\(id.uuidString.lowercased())-image.png",
            imageSize: size,
            anchors: anchors ?? .fallback(for: category),
            dominantColor: color)
}
