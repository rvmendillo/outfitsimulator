import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

final class ColorTests: XCTestCase {
    func testHexRoundTrip() {
        for hex in ["#000000", "#FFFFFF", "#1F2A44", "#C62828", "#8EC5F0"] {
            XCTAssertEqual(SRGBColor(hex: hex)?.hex, hex)
        }
        XCTAssertEqual(SRGBColor(hex: "1f2a44")?.hex, "#1F2A44")
        XCTAssertNil(SRGBColor(hex: "#12345"))
        XCTAssertNil(SRGBColor(hex: "#GGGGGG"))
    }

    func testComponentsAreClamped() {
        let c = SRGBColor(r: 2, g: -1, b: 0.5)
        XCTAssertEqual(c.r, 1)
        XCTAssertEqual(c.g, 0)
        XCTAssertEqual(c.b, 0.5)
    }

    func testLabReferenceValues() {
        let white = SRGBColor.white.lab
        XCTAssertEqual(white.l, 100, accuracy: 0.1)
        XCTAssertEqual(white.a, 0, accuracy: 0.1)
        XCTAssertEqual(white.b, 0, accuracy: 0.1)
        let black = SRGBColor.black.lab
        XCTAssertEqual(black.l, 0, accuracy: 0.1)
        // sRGB red ≈ L 53.2, a 80.1, b 67.2
        let red = SRGBColor(r: 1, g: 0, b: 0).lab
        XCTAssertEqual(red.l, 53.2, accuracy: 0.3)
        XCTAssertEqual(red.a, 80.1, accuracy: 0.5)
        XCTAssertEqual(red.b, 67.2, accuracy: 0.5)
    }

    func testLuminanceAndContrast() {
        XCTAssertEqual(SRGBColor.white.contrastRatio(with: .black), 21, accuracy: 0.01)
        XCTAssertEqual(SRGBColor.white.contrastRatio(with: .white), 1, accuracy: 1e-9)
    }

    func testHSV() {
        let (h, s, v) = SRGBColor(r: 0, g: 0, b: 1).hsv
        XCTAssertEqual(h, 240, accuracy: 1e-9)
        XCTAssertEqual(s, 1)
        XCTAssertEqual(v, 1)
        XCTAssertEqual(SRGBColor(r: 1, g: 0, b: 0.5).hsv.h, 330, accuracy: 1e-9)
    }

    func testNaming() {
        XCTAssertEqual(ColorNaming.name(for: SRGBColor(hex: "#1B2540")!), "Navy")
        XCTAssertEqual(ColorNaming.name(for: SRGBColor(hex: "#D01818")!), "Red")
        XCTAssertEqual(ColorNaming.name(for: SRGBColor(hex: "#FAFAFA")!), "White")
        XCTAssertEqual(ColorNaming.name(for: SRGBColor(hex: "#0A0A0A")!), "Black")
        XCTAssertTrue(ColorNaming.isNeutral(SRGBColor(hex: "#808080")!))
        XCTAssertTrue(ColorNaming.isNeutral(SRGBColor(hex: "#5B7DA8")!)) // denim
        XCTAssertFalse(ColorNaming.isNeutral(SRGBColor(hex: "#E0218A")!))
    }

    func testHarmonyRules() {
        let navy = SRGBColor(hex: "#1F2A44")!, white = SRGBColor.white
        let red = SRGBColor(hex: "#C62828")!, lime = SRGBColor(hex: "#9ACD32")!
        let teal = SRGBColor(hex: "#1F7A7A")!, pink = SRGBColor(hex: "#EE8FB0")!
        XCTAssertGreaterThanOrEqual(ColorHarmony.pairScore(navy, white), 0.85)
        XCTAssertGreaterThanOrEqual(ColorHarmony.pairScore(navy, red), 0.85)
        XCTAssertLessThan(ColorHarmony.pairScore(red, lime), ColorHarmony.pairScore(red, pink))
        XCTAssertEqual(ColorHarmony.hueDistance(350, 10), 20, accuracy: 1e-9)
        XCTAssertEqual(ColorHarmony.hueDistance(0, 180), 180, accuracy: 1e-9)

        let calm = ColorHarmony.outfitScore([(navy, 1), (white, 1), (SRGBColor(hex: "#6B4428")!, 0.4)])
        let loud = ColorHarmony.outfitScore([(red, 1), (lime, 1), (teal, 1), (pink, 0.4)])
        XCTAssertGreaterThan(calm, loud)
        XCTAssertTrue((0...1).contains(calm))
        XCTAssertTrue((0...1).contains(loud))
        XCTAssertEqual(ColorHarmony.outfitScore([]), 0)
    }

    func testDominantColors() {
        let samples = Array(repeating: SRGBColor(hex: "#1F2A44")!, count: 70) + Array(repeating: SRGBColor(hex: "#F2CF3A")!, count: 30)
        let swatches = ColorPalette.dominantColors(samples: samples, k: 3)
        XCTAssertEqual(swatches.count, 2, "identical samples collapse into two clusters")
        XCTAssertEqual(swatches[0].color.hex, "#1F2A44")
        XCTAssertEqual(swatches[0].weight, 0.7, accuracy: 1e-9)
        XCTAssertEqual(swatches[1].color.hex, "#F2CF3A")
        XCTAssertEqual(swatches.map(\.weight).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertTrue(ColorPalette.dominantColors(samples: [], k: 3).isEmpty)
    }

    func testMedianColorIgnoresOutliers() throws {
        let skin = SRGBColor(hex: "#C8946E")!
        let samples = Array(repeating: skin, count: 20) + [SRGBColor.black, SRGBColor.white, SRGBColor(r: 1, g: 0, b: 0)]
        let median = try XCTUnwrap(ColorPalette.medianColor(samples))
        XCTAssertEqual(median.hex, skin.hex)
        XCTAssertNil(ColorPalette.medianColor([]))
    }
}
