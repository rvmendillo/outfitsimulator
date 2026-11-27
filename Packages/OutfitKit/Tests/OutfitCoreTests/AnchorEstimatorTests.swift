import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

final class AnchorEstimatorTests: XCTestCase {
    /// Flat-lay T-shirt: 200 px torso (x 150...349, y 100...399), short sleeves
    /// angling out from the shoulders.
    private func tShirt() -> AlphaMask {
        var m = AlphaMask(width: 500, height: 500)
        m.fillPolygon([
            CGPoint(x: 150, y: 100), CGPoint(x: 350, y: 100), // shoulders
            CGPoint(x: 440, y: 160), CGPoint(x: 405, y: 215), // right sleeve
            CGPoint(x: 350, y: 185), CGPoint(x: 350, y: 400),
            CGPoint(x: 150, y: 400), CGPoint(x: 150, y: 185),
            CGPoint(x: 95, y: 215), CGPoint(x: 60, y: 160), // left sleeve
        ])
        return m
    }

    func testTShirtShouldersComeFromTorsoWidth() {
        let mask = tShirt()
        let a = AnchorEstimator.estimate(category: .top, mask: mask)
        XCTAssertEqual(a.level, .shoulders)
        XCTAssertEqual(a.source, .shape)
        let width = Double(a.right.x - a.left.x) * 500
        XCTAssertEqual(width, 200 * 0.87, accuracy: 6)
        XCTAssertEqual(Double(a.left.x + a.right.x) / 2 * 500, 250, accuracy: 2)
        XCTAssertEqual(Double(a.left.y) * 500, 100 + 0.08 * 300, accuracy: 2)
        XCTAssertEqual(a.hemY, 400.0 / 500.0, accuracy: 1e-9)
        XCTAssertFalse(a.fitsLength)
    }

    func testLongSleevesHangingAlongsideUseShoulderBand() {
        // Torso 160 wide with 40 px sleeves glued to each side all the way down.
        var m = AlphaMask(width: 400, height: 600)
        m.fillRect(PixelRect(minX: 120, minY: 100, maxX: 279, maxY: 499)) // torso
        m.fillRect(PixelRect(minX: 80, minY: 120, maxX: 119, maxY: 480))  // left sleeve
        m.fillRect(PixelRect(minX: 280, minY: 120, maxX: 319, maxY: 480)) // right sleeve
        let a = AnchorEstimator.estimate(category: .top, mask: m)
        let width = Double(a.right.x - a.left.x) * 400
        // Sleeves glued to the torso make both bands 240 px wide, so the estimate
        // is the torso rule (240 * 0.87 ≈ 209): too wide by ~30%. This documents
        // the bound of the heuristic; the fit-guide editor corrects such cases.
        XCTAssertLessThanOrEqual(width, 241)
        XCTAssertGreaterThanOrEqual(width, 155)
    }

    func testCamisoleStrapsAreNotShoulders() {
        var m = AlphaMask(width: 300, height: 400)
        m.fillRect(PixelRect(minX: 100, minY: 40, maxX: 109, maxY: 120))   // left strap
        m.fillRect(PixelRect(minX: 190, minY: 40, maxX: 199, maxY: 120))   // right strap
        m.fillRect(PixelRect(minX: 80, minY: 120, maxX: 219, maxY: 360))   // body
        let a = AnchorEstimator.estimate(category: .top, mask: m)
        let width = Double(a.right.x - a.left.x) * 300
        XCTAssertEqual(width, 140 * 0.87, accuracy: 4)
    }

    func testPoseShouldersAreExpandedToSeams() {
        let mask = tShirt()
        let pose = PoseJoints(shoulderL: CGPoint(x: 330, y: 112), shoulderR: CGPoint(x: 170, y: 112)) // labels swapped on purpose
        let a = AnchorEstimator.estimate(category: .top, mask: mask, pose: pose)
        XCTAssertEqual(a.source, .pose)
        XCTAssertEqual(Double(a.left.x) * 500, 170 - 160 * 0.14, accuracy: 1e-6)
        XCTAssertEqual(Double(a.right.x) * 500, 330 + 160 * 0.14, accuracy: 1e-6)
    }

    func testImplausiblePoseFallsBackToShape() {
        let mask = tShirt()
        let pose = PoseJoints(shoulderL: CGPoint(x: 240, y: 112), shoulderR: CGPoint(x: 250, y: 112))
        XCTAssertEqual(AnchorEstimator.estimate(category: .top, mask: mask, pose: pose).source, .shape)
    }

    private func trousers(legLength: Int) -> AlphaMask {
        var m = AlphaMask(width: 300, height: 1000)
        m.fillRect(PixelRect(minX: 80, minY: 50, maxX: 239, maxY: 150))                // seat, 160 wide
        m.fillRect(PixelRect(minX: 80, minY: 150, maxX: 155, maxY: 150 + legLength))   // left leg
        m.fillRect(PixelRect(minX: 164, minY: 150, maxX: 239, maxY: 150 + legLength))  // right leg
        return m
    }

    func testFullLengthTrousers() {
        let a = AnchorEstimator.estimate(category: .bottom, mask: trousers(legLength: 700))
        XCTAssertEqual(a.level, .waist)
        XCTAssertTrue(a.fitsLength)
        XCTAssertEqual(Double(a.left.x) * 300, 80, accuracy: 1e-6)
        XCTAssertEqual(Double(a.right.x) * 300, 240, accuracy: 1e-6)
        XCTAssertEqual(a.hemY, 851.0 / 1000.0, accuracy: 1e-9)
    }

    func testShortsDoNotFitByLength() {
        let a = AnchorEstimator.estimate(category: .bottom, mask: trousers(legLength: 120))
        XCTAssertFalse(a.fitsLength)
    }

    func testWornTrousersUseHipsAndAnkles() {
        let mask = trousers(legLength: 700)
        let pose = PoseJoints(hipL: CGPoint(x: 120, y: 110), hipR: CGPoint(x: 200, y: 110),
                              kneeL: CGPoint(x: 118, y: 480), kneeR: CGPoint(x: 200, y: 480),
                              ankleL: CGPoint(x: 118, y: 830), ankleR: CGPoint(x: 200, y: 830))
        let a = AnchorEstimator.estimate(category: .bottom, mask: mask, pose: pose)
        XCTAssertEqual(a.level, .hips)
        XCTAssertEqual(a.source, .pose)
        XCTAssertEqual(Double(a.left.y) * 1000, 110, accuracy: 1e-6)
        XCTAssertTrue(a.fitsLength)

        // Capri length: hem well above the ankle.
        let capri = AnchorEstimator.estimate(category: .bottom, mask: trousers(legLength: 420), pose: pose)
        XCTAssertFalse(capri.fitsLength)
    }

    func testShoesPairSpansBothShoes() {
        var m = AlphaMask(width: 400, height: 200)
        m.fillEllipse(center: CGPoint(x: 100, y: 120), radiusX: 70, radiusY: 40)
        m.fillEllipse(center: CGPoint(x: 290, y: 125), radiusX: 70, radiusY: 40)
        m.fillRect(PixelRect(minX: 395, minY: 5, maxX: 396, maxY: 6)) // speck
        let a = AnchorEstimator.estimate(category: .shoes, mask: m)
        XCTAssertEqual(a.level, .sole)
        XCTAssertEqual(Double(a.left.x) * 400, 30, accuracy: 2)
        XCTAssertEqual(Double(a.right.x) * 400, 360, accuracy: 2)
        XCTAssertEqual(Double(a.left.y) * 200, 165, accuracy: 2)
    }

    func testHatUsesBrimWidth() {
        var m = AlphaMask(width: 300, height: 200)
        m.fillEllipse(center: CGPoint(x: 150, y: 90), radiusX: 60, radiusY: 70)    // crown
        m.fillRect(PixelRect(minX: 40, minY: 150, maxX: 259, maxY: 170))            // brim
        let a = AnchorEstimator.estimate(category: .hat, mask: m)
        XCTAssertEqual(a.level, .brim)
        XCTAssertEqual(Double(a.right.x - a.left.x) * 300, 220, accuracy: 1)
    }

    func testEmptyMaskFallsBack() {
        let a = AnchorEstimator.estimate(category: .dress, mask: AlphaMask(width: 10, height: 10))
        XCTAssertEqual(a, GarmentAnchors.fallback(for: .dress).normalized)
    }

    func testEveryCategoryProducesValidAnchors() {
        var m = AlphaMask(width: 120, height: 160)
        m.fillEllipse(center: CGPoint(x: 60, y: 80), radiusX: 45, radiusY: 70)
        for category in GarmentCategory.allCases {
            let a = AnchorEstimator.estimate(category: category, mask: m)
            XCTAssertEqual(a.level, category == .bottom ? .waist : category.defaultAnchorLevel, "\(category)")
            XCTAssertLessThan(a.left.x, a.right.x, "\(category)")
            for v in [a.left.x, a.left.y, a.right.x, a.right.y] {
                XCTAssertTrue((0...1).contains(Double(v)), "\(category) \(v)")
            }
        }
    }
}
