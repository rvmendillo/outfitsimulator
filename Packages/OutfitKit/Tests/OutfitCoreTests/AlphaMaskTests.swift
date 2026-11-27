import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

final class AlphaMaskTests: XCTestCase {
    func testBoundingBoxAndExtents() throws {
        let mask = AlphaMask.with(width: 20, height: 10, rects: [PixelRect(minX: 3, minY: 2, maxX: 8, maxY: 6)])
        XCTAssertEqual(mask.boundingBox(), PixelRect(minX: 3, minY: 2, maxX: 8, maxY: 6))
        let extent = try XCTUnwrap(mask.rowExtent(4))
        XCTAssertEqual(extent.minX, 3)
        XCTAssertEqual(extent.maxX, 8)
        XCTAssertEqual(extent.span, 6)
        XCTAssertEqual(extent.fill, 1)
        XCTAssertEqual(extent.center, 6)
        XCTAssertNil(mask.rowExtent(0))
        XCTAssertNil(mask.rowExtent(-1))
        XCTAssertEqual(mask.setCount(), 30)
        XCTAssertEqual(mask.coverage(), 30.0 / 200.0, accuracy: 1e-12)
        XCTAssertNil(AlphaMask(width: 5, height: 5).boundingBox())
    }

    func testRuns() {
        var mask = AlphaMask(width: 12, height: 1)
        mask.fillRect(PixelRect(minX: 0, minY: 0, maxX: 2, maxY: 0))
        mask.fillRect(PixelRect(minX: 5, minY: 0, maxX: 6, maxY: 0))
        mask.fillRect(PixelRect(minX: 10, minY: 0, maxX: 11, maxY: 0))
        XCTAssertEqual(mask.runs(inRow: 0), [0...2, 5...6, 10...11])
    }

    func testConnectedComponents() {
        let mask = AlphaMask.with(width: 30, height: 20, rects: [
            PixelRect(minX: 0, minY: 0, maxX: 9, maxY: 9),     // 100 px, touches border
            PixelRect(minX: 15, minY: 5, maxX: 19, maxY: 9),   // 25 px
            PixelRect(minX: 25, minY: 15, maxX: 25, maxY: 15), // 1 px
        ])
        let (labels, components) = mask.connectedComponents()
        XCTAssertEqual(components.map(\.pixelCount), [100, 25, 1])
        XCTAssertTrue(components[0].touchesBorder)
        XCTAssertFalse(components[1].touchesBorder)
        XCTAssertEqual(components[1].bounds, PixelRect(minX: 15, minY: 5, maxX: 19, maxY: 9))
        XCTAssertEqual(labels.filter { $0 != 0 }.count, 126)
    }

    func testDiagonalConnectivity() {
        var mask = AlphaMask(width: 3, height: 3)
        mask[0, 0] = 255
        mask[1, 1] = 255
        XCTAssertEqual(mask.connectedComponents(connectivity8: true).components.count, 1)
        XCTAssertEqual(mask.connectedComponents(connectivity8: false).components.count, 2)
    }

    func testKeepingLargestComponentsPreservesSoftFringe() {
        var mask = AlphaMask.with(width: 30, height: 20, rects: [
            PixelRect(minX: 2, minY: 2, maxX: 11, maxY: 11),
            PixelRect(minX: 20, minY: 2, maxX: 21, maxY: 3),
        ])
        mask[12, 5] = 60 // soft edge next to the big blob
        let kept = mask.keepingLargestComponents(maxCount: 1)
        XCTAssertEqual(kept.setCount(), 100)
        XCTAssertEqual(kept[12, 5], 60)
        XCTAssertEqual(kept[20, 2], 0)
        // Two components kept when allowed and big enough.
        let both = mask.keepingLargestComponents(maxCount: 2, minRelativeArea: 0.01)
        XCTAssertEqual(both.setCount(), 104)
        XCTAssertEqual(AlphaMask(width: 4, height: 4).keepingLargestComponents().setCount(), 0)
    }

    func testFillingSmallHolesOnly() {
        var mask = AlphaMask.with(width: 40, height: 40, rects: [PixelRect(minX: 5, minY: 5, maxX: 34, maxY: 34)])
        mask.fillRect(PixelRect(minX: 10, minY: 10, maxX: 11, maxY: 11), value: 0) // 4 px hole
        mask.fillRect(PixelRect(minX: 15, minY: 15, maxX: 29, maxY: 29), value: 0) // 225 px hole
        let filled = mask.fillingHoles(maxHoleFraction: 0.02)
        XCTAssertEqual(filled[10, 10], 255)
        XCTAssertEqual(filled[20, 20], 0)
        // Background touching the border is never filled.
        XCTAssertEqual(filled[0, 0], 0)
    }

    func testCropAndResize() {
        let mask = AlphaMask.with(width: 10, height: 10, rects: [PixelRect(minX: 0, minY: 0, maxX: 4, maxY: 9)])
        let crop = mask.cropped(to: PixelRect(minX: 3, minY: 2, maxX: 7, maxY: 5))
        XCTAssertEqual(crop.width, 5)
        XCTAssertEqual(crop.height, 4)
        XCTAssertEqual(crop[0, 0], 255)
        XCTAssertEqual(crop[2, 0], 0)
        let outside = mask.cropped(to: PixelRect(minX: 20, minY: 20, maxX: 30, maxY: 30))
        XCTAssertTrue(outside.isEmpty)

        let constant = AlphaMask(width: 7, height: 5, fill: 200)
        let up = constant.resized(width: 31, height: 17)
        XCTAssertEqual(up.width, 31)
        XCTAssertTrue(up.values.allSatisfy { $0 == 200 })
        let half = mask.resized(width: 5, height: 5)
        XCTAssertGreaterThan(half[0, 2], 200)
        XCTAssertLessThan(half[4, 2], 60)
    }

    func testBlurKeepsInteriorAndSoftensEdges() {
        let mask = AlphaMask.with(width: 40, height: 40, rects: [PixelRect(minX: 10, minY: 10, maxX: 29, maxY: 29)])
        let blurred = mask.blurred(radius: 2)
        XCTAssertEqual(blurred[20, 20], 255)
        XCTAssertEqual(blurred[0, 0], 0)
        XCTAssertGreaterThan(blurred[10, 20], 0)
        XCTAssertLessThan(blurred[10, 20], 255)
        XCTAssertEqual(mask.blurred(radius: 0), mask)
    }

    func testBooleanOperations() {
        let a = AlphaMask(width: 2, height: 1, values: [255, 128])
        let b = AlphaMask(width: 2, height: 1, values: [255, 0])
        XCTAssertEqual(a.multiplied(by: b).values, [255, 0])
        XCTAssertEqual(a.union(b).values, [255, 128])
        XCTAssertEqual(a.subtracting(b).values, [0, 128])
        XCTAssertEqual(a.thresholded(200).values, [255, 0])
    }

    func testContrastStretch() {
        let m = AlphaMask(width: 5, height: 1, values: [0, 90, 128, 166, 255])
        XCTAssertEqual(m.contrastStretched(low: 90, high: 166).values, [0, 0, 128, 255, 255])
    }

    func testDilation() {
        var mask = AlphaMask(width: 9, height: 9)
        mask[4, 4] = 255
        let d = mask.dilated(radius: 2)
        XCTAssertEqual(d.setCount(), 25)
        XCTAssertEqual(d[2, 2], 255)
        XCTAssertEqual(d[1, 1], 0)
    }

    func testBrushEraseAndRestore() {
        var mask = AlphaMask(width: 50, height: 50, fill: 255)
        mask.paintDab(center: CGPoint(x: 25, y: 25), radius: 6, mode: .erase, hardness: 1)
        XCTAssertEqual(mask[25, 25], 0)
        XCTAssertEqual(mask[25, 40], 255)
        mask.paintDab(center: CGPoint(x: 25, y: 25), radius: 3, mode: .restore, hardness: 1)
        XCTAssertEqual(mask[25, 25], 255)

        var stroke = AlphaMask(width: 100, height: 20)
        stroke.paintStroke(from: CGPoint(x: 5, y: 10), to: CGPoint(x: 95, y: 10), radius: 3, mode: .restore, hardness: 1)
        for x in 5...95 { XCTAssertEqual(stroke[x, 10], 255, "gap at \(x)") }
        XCTAssertEqual(stroke[50, 2], 0)
    }

    func testSoftBrushFalloff() {
        var mask = AlphaMask(width: 41, height: 41)
        mask.paintDab(center: CGPoint(x: 20.5, y: 20.5), radius: 10, mode: .restore, hardness: 0)
        XCTAssertGreaterThan(mask[20, 20], mask[26, 20])
        XCTAssertGreaterThan(mask[26, 20], 0)
        XCTAssertEqual(mask[20, 32], 0)
    }

    func testShapeFills() {
        var poly = AlphaMask(width: 100, height: 100)
        poly.fillPolygon([CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10), CGPoint(x: 90, y: 90), CGPoint(x: 10, y: 90)])
        XCTAssertEqual(poly.setCount(), 80 * 80)

        var tri = AlphaMask(width: 100, height: 100)
        tri.fillPolygon([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 100)])
        XCTAssertEqual(Double(tri.setCount()), 5000, accuracy: 120)

        var ellipse = AlphaMask(width: 200, height: 200)
        ellipse.fillEllipse(center: CGPoint(x: 100, y: 100), radiusX: 60, radiusY: 40)
        XCTAssertEqual(Double(ellipse.setCount()), Double.pi * 60 * 40, accuracy: 120)
    }
}
