import Foundation
import XCTest
@testable import OutfitCore

final class ColorTests: XCTestCase {
    func testHexRoundTrip() {
        for hex in ["#000000", "#FFFFFF", "#1F2A44", "#C62828", "#8EC5F0"] {
            XCTAssertEqual(RGBColor(hex: hex)?.hex, hex)
        }
        XCTAssertEqual(RGBColor(hex: "1f2a44")?.hex, "#1F2A44")
        XCTAssertNil(RGBColor(hex: "#12345"))
        XCTAssertNil(RGBColor(hex: "#GGGGGG"))
    }

    func testComponentsAreClamped() {
        let c = RGBColor(r: 2, g: -1, b: 0.5)
        XCTAssertEqual(c.r, 1)
        XCTAssertEqual(c.g, 0)
        XCTAssertEqual(c.b, 0.5)
    }

    func testLabReferenceValues() {
        let white = RGBColor.white.lab
        XCTAssertEqual(white.l, 100, accuracy: 0.1)
        XCTAssertEqual(white.a, 0, accuracy: 0.1)
        XCTAssertEqual(white.b, 0, accuracy: 0.1)
        let black = RGBColor.black.lab
        XCTAssertEqual(black.l, 0, accuracy: 0.1)
        // sRGB red ≈ L 53.2, a 80.1, b 67.2
        let red = RGBColor(r: 1, g: 0, b: 0).lab
        XCTAssertEqual(red.l, 53.2, accuracy: 0.3)
        XCTAssertEqual(red.a, 80.1, accuracy: 0.5)
        XCTAssertEqual(red.b, 67.2, accuracy: 0.5)
    }

    func testLuminanceAndContrast() {
        XCTAssertEqual(RGBColor.white.contrastRatio(with: .black), 21, accuracy: 0.01)
        XCTAssertEqual(RGBColor.white.contrastRatio(with: .white), 1, accuracy: 1e-9)
    }

    func testHSV() {
        let (h, s, v) = RGBColor(r: 0, g: 0, b: 1).hsv
        XCTAssertEqual(h, 240, accuracy: 1e-9)
        XCTAssertEqual(s, 1)
        XCTAssertEqual(v, 1)
        XCTAssertEqual(RGBColor(r: 1, g: 0, b: 0.5).hsv.h, 330, accuracy: 1e-9)
    }

    func testNaming() {
        XCTAssertEqual(ColorNaming.name(for: RGBColor(hex: "#1B2540")!), "Navy")
        XCTAssertEqual(ColorNaming.name(for: RGBColor(hex: "#D01818")!), "Red")
        XCTAssertEqual(ColorNaming.name(for: RGBColor(hex: "#FAFAFA")!), "White")
        XCTAssertEqual(ColorNaming.name(for: RGBColor(hex: "#0A0A0A")!), "Black")
        XCTAssertTrue(ColorNaming.isNeutral(RGBColor(hex: "#808080")!))
        XCTAssertTrue(ColorNaming.isNeutral(RGBColor(hex: "#5B7DA8")!)) // denim
        XCTAssertFalse(ColorNaming.isNeutral(RGBColor(hex: "#E0218A")!))
    }

    func testHarmonyRules() {
        let navy = RGBColor(hex: "#1F2A44")!, white = RGBColor.white
        let red = RGBColor(hex: "#C62828")!, lime = RGBColor(hex: "#9ACD32")!
        let teal = RGBColor(hex: "#1F7A7A")!, pink = RGBColor(hex: "#EE8FB0")!
        XCTAssertGreaterThanOrEqual(ColorHarmony.pairScore(navy, white), 0.85)
        XCTAssertGreaterThanOrEqual(ColorHarmony.pairScore(navy, red), 0.85)
        XCTAssertLessThan(ColorHarmony.pairScore(red, lime), ColorHarmony.pairScore(red, pink))
        XCTAssertEqual(ColorHarmony.hueDistance(350, 10), 20, accuracy: 1e-9)
        XCTAssertEqual(ColorHarmony.hueDistance(0, 180), 180, accuracy: 1e-9)

        let calm = ColorHarmony.outfitScore([(navy, 1), (white, 1), (RGBColor(hex: "#6B4428")!, 0.4)])
        let loud = ColorHarmony.outfitScore([(red, 1), (lime, 1), (teal, 1), (pink, 0.4)])
        XCTAssertGreaterThan(calm, loud)
        XCTAssertTrue((0...1).contains(calm))
        XCTAssertTrue((0...1).contains(loud))
        XCTAssertEqual(ColorHarmony.outfitScore([]), 0)
    }

    func testDominantColors() {
        let samples = Array(repeating: RGBColor(hex: "#1F2A44")!, count: 70) + Array(repeating: RGBColor(hex: "#F2CF3A")!, count: 30)
        let swatches = ColorPalette.dominantColors(samples: samples, k: 3)
        XCTAssertEqual(swatches.count, 2, "identical samples collapse into two clusters")
        XCTAssertEqual(swatches[0].color.hex, "#1F2A44")
        XCTAssertEqual(swatches[0].weight, 0.7, accuracy: 1e-9)
        XCTAssertEqual(swatches[1].color.hex, "#F2CF3A")
        XCTAssertEqual(swatches.map(\.weight).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertTrue(ColorPalette.dominantColors(samples: [], k: 3).isEmpty)
    }

    func testMedianColorIgnoresOutliers() throws {
        let skin = RGBColor(hex: "#C8946E")!
        let samples = Array(repeating: skin, count: 20) + [RGBColor.black, RGBColor.white, RGBColor(r: 1, g: 0, b: 0)]
        let median = try XCTUnwrap(ColorPalette.medianColor(samples))
        XCTAssertEqual(median.hex, skin.hex)
        XCTAssertNil(ColorPalette.medianColor([]))
    }
}
