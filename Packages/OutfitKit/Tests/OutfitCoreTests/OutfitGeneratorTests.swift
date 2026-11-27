import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

final class OutfitGeneratorTests: XCTestCase {
    private func closet() -> [GarmentSummary] {
        var items: [GarmentSummary] = []
        let tops = ["#FFFFFF", "#1F2A44", "#C62828", "#9CAF88"]
        let bottoms = ["#5B7DA8", "#151515", "#D6C3A3"]
        for hex in tops { items.append(GarmentSummary(id: UUID(), category: .top, color: SRGBColor(hex: hex)!)) }
        for hex in bottoms { items.append(GarmentSummary(id: UUID(), category: .bottom, color: SRGBColor(hex: hex)!)) }
        items.append(GarmentSummary(id: UUID(), category: .dress, color: SRGBColor(hex: "#6D1A2B")!))
        items.append(GarmentSummary(id: UUID(), category: .shoes, color: SRGBColor(hex: "#F4F4F2")!))
        items.append(GarmentSummary(id: UUID(), category: .shoes, color: SRGBColor(hex: "#6B4428")!))
        items.append(GarmentSummary(id: UUID(), category: .outerwear, color: SRGBColor(hex: "#B98B5B")!))
        items.append(GarmentSummary(id: UUID(), category: .bag, color: SRGBColor(hex: "#151515")!))
        items.append(GarmentSummary(id: UUID(), category: .hat, color: SRGBColor(hex: "#3B3B3F")!))
        return items
    }

    private func categories(_ suggestion: OutfitSuggestion, in closet: [GarmentSummary]) -> [GarmentCategory] {
        suggestion.garmentIDs.compactMap { id in closet.first { $0.id == id }?.category }
    }

    func testGeneratesRequestedNumberOfValidUniqueOutfits() {
        let items = closet()
        let result = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 8, seed: 3))
        XCTAssertEqual(result.suggestions.count, 8)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertEqual(Set(result.suggestions.map(\.signature)).count, 8, "no duplicates")
        for s in result.suggestions {
            let cats = categories(s, in: items)
            let hasTopAndBottom = cats.contains(.top) && cats.contains(.bottom)
            let hasDress = cats.contains(.dress)
            XCTAssertTrue(hasTopAndBottom != hasDress, "exactly one base: \(cats)")
            for c in GarmentCategory.allCases where c.isExclusive {
                XCTAssertLessThanOrEqual(cats.filter { $0 == c }.count, 1, "\(c) at most once")
            }
            XCTAssertTrue(cats.contains(.shoes), "shoes available so always worn")
            XCTAssertTrue((0...1).contains(s.score))
            // Back-to-front order.
            let zs = cats.map(\.baseZ)
            XCTAssertEqual(zs, zs.sorted())
        }
    }

    func testDeterministicForSeed() {
        let items = closet()
        let a = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 5, seed: 99))
        let b = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 5, seed: 99))
        XCTAssertEqual(a, b)
        let c = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 5, seed: 100))
        XCTAssertNotEqual(a.suggestions.map(\.signature), c.suggestions.map(\.signature))
    }

    func testLockedGarmentAppearsEverywhere() throws {
        let items = closet()
        let lockedTop = try XCTUnwrap(items.first { $0.category == .top })
        let result = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 6, locked: [lockedTop.id], seed: 5))
        XCTAssertFalse(result.suggestions.isEmpty)
        for s in result.suggestions {
            XCTAssertTrue(s.garmentIDs.contains(lockedTop.id))
            XCTAssertFalse(categories(s, in: items).contains(.dress))
        }
    }

    func testLockedDressExcludesSeparates() throws {
        let items = closet()
        let dress = try XCTUnwrap(items.first { $0.category == .dress })
        let result = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 4, locked: [dress.id], seed: 5))
        XCTAssertFalse(result.suggestions.isEmpty)
        for s in result.suggestions {
            let cats = categories(s, in: items)
            XCTAssertTrue(s.garmentIDs.contains(dress.id))
            XCTAssertFalse(cats.contains(.top))
            XCTAssertFalse(cats.contains(.bottom))
        }
    }

    func testLockedAccessoryIsAlwaysIncluded() throws {
        let items = closet()
        let bag = try XCTUnwrap(items.first { $0.category == .bag })
        let result = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 5, locked: [bag.id], seed: 8))
        XCTAssertTrue(result.suggestions.allSatisfy { $0.garmentIDs.contains(bag.id) })
    }

    func testExcludedSignaturesAreSkipped() {
        let items = closet()
        let first = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 3, includeAccessories: false, seed: 11))
        let excluded = Set(first.suggestions.map(\.signature))
        let second = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 3, excludedSignatures: excluded, includeAccessories: false, seed: 11))
        XCTAssertTrue(Set(second.suggestions.map(\.signature)).isDisjoint(with: excluded))
    }

    func testReportsMissingCategories() {
        let onlyTops = [GarmentSummary(id: UUID(), category: .top, color: .white)]
        XCTAssertEqual(OutfitGenerator.generate(from: onlyTops, options: GeneratorOptions()).missing, [.bottom])
        XCTAssertEqual(OutfitGenerator.generate(from: [], options: GeneratorOptions()).missing, [.top, .bottom])
        let onlyShoes = [GarmentSummary(id: UUID(), category: .shoes, color: .white)]
        XCTAssertTrue(OutfitGenerator.generate(from: onlyShoes, options: GeneratorOptions()).suggestions.isEmpty)
    }

    func testWorksWithoutShoesAndLimitsToAvailableCombos() {
        let items = [
            GarmentSummary(id: UUID(), category: .top, color: .white),
            GarmentSummary(id: UUID(), category: .bottom, color: .black),
        ]
        let result = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 10, includeAccessories: false, seed: 1))
        XCTAssertEqual(result.suggestions.count, 1)
        XCTAssertEqual(result.suggestions[0].garmentIDs.count, 2)
    }

    func testLargeClosetUsesSamplingAndStaysValid() {
        var items: [GarmentSummary] = []
        var rng = SeededGenerator(seed: 1)
        func randomColor() -> SRGBColor { SRGBColor(r: rng.nextUnit(), g: rng.nextUnit(), b: rng.nextUnit()) }
        for _ in 0..<40 { items.append(GarmentSummary(id: UUID(), category: .top, color: randomColor())) }
        for _ in 0..<30 { items.append(GarmentSummary(id: UUID(), category: .bottom, color: randomColor())) }
        for _ in 0..<10 { items.append(GarmentSummary(id: UUID(), category: .shoes, color: randomColor())) }
        for _ in 0..<5 { items.append(GarmentSummary(id: UUID(), category: .outerwear, color: randomColor())) }
        let result = OutfitGenerator.generate(from: items, options: GeneratorOptions(count: 12, seed: 2))
        XCTAssertEqual(result.suggestions.count, 12)
        XCTAssertEqual(Set(result.suggestions.map(\.signature)).count, 12)
        // Variety: the same top should not dominate the batch.
        var topUse: [UUID: Int] = [:]
        for s in result.suggestions {
            for id in s.garmentIDs where items.first(where: { $0.id == id })?.category == .top { topUse[id, default: 0] += 1 }
        }
        XCTAssertLessThanOrEqual(topUse.values.max() ?? 0, 3)
    }
}
