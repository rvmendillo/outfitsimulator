import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Deterministic pseudo-random generator (SplitMix64) so suggestions are
/// reproducible in tests and stable for a given seed.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1).
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

/// Minimal information the generator needs about a garment.
public struct GarmentSummary: Equatable, Sendable {
    public var id: UUID
    public var category: GarmentCategory
    public var color: SRGBColor

    public init(id: UUID, category: GarmentCategory, color: SRGBColor) {
        self.id = id
        self.category = category
        self.color = color
    }

    public init(_ garment: Garment) {
        self.init(id: garment.id, category: garment.category, color: garment.dominantColor)
    }
}

public struct OutfitSuggestion: Equatable, Sendable {
    public var garmentIDs: [UUID]
    public var score: Double

    public var signature: [UUID] {
        garmentIDs.sorted { $0.uuidString < $1.uuidString }
    }
}

public struct GeneratorOptions: Sendable {
    public var count: Int
    /// Garments that must appear in every suggestion.
    public var locked: Set<UUID>
    /// Garment sets that already exist (e.g. saved outfits) and should not be suggested again.
    public var excludedSignatures: Set<[UUID]>
    public var includeOuterwear: Bool
    public var includeAccessories: Bool
    public var seed: UInt64

    public init(count: Int = 6, locked: Set<UUID> = [], excludedSignatures: Set<[UUID]> = [], includeOuterwear: Bool = true, includeAccessories: Bool = true, seed: UInt64 = 1) {
        self.count = count
        self.locked = locked
        self.excludedSignatures = excludedSignatures
        self.includeOuterwear = includeOuterwear
        self.includeAccessories = includeAccessories
        self.seed = seed
    }
}

public struct GeneratorResult: Equatable, Sendable {
    public var suggestions: [OutfitSuggestion]
    /// Categories the user should add to get suggestions (empty when not needed).
    public var missing: [GarmentCategory]
}

/// Mixes the closet into outfits: tops with bottoms (or dresses), shoes, and
/// optional layers/accessories, ranked by colour harmony and kept varied.
public enum OutfitGenerator {
    static let maxCandidates = 4000
    static let accessoryCategories: [GarmentCategory] = [.bag, .hat, .eyewear, .scarf, .belt]

    public static func generate(from garments: [GarmentSummary], options: GeneratorOptions) -> GeneratorResult {
        var rng = SeededGenerator(seed: options.seed)
        var byCategory: [GarmentCategory: [GarmentSummary]] = [:]
        for g in garments { byCategory[g.category, default: []].append(g) }
        let lockedGarments = garments.filter { options.locked.contains($0.id) }
        let lockedByCategory = Dictionary(grouping: lockedGarments, by: \.category)

        func pool(_ category: GarmentCategory) -> [GarmentSummary] {
            if let locked = lockedByCategory[category], !locked.isEmpty {
                return Array(locked.prefix(category.isExclusive ? 1 : locked.count))
            }
            return byCategory[category] ?? []
        }

        // Base: top + bottom, or a dress.
        let lockedDress = lockedByCategory[.dress]?.first
        let lockedTopOrBottom = lockedByCategory[.top] != nil || lockedByCategory[.bottom] != nil
        var bases: [[GarmentSummary]] = []
        if lockedDress == nil {
            for top in pool(.top) {
                for bottom in pool(.bottom) { bases.append([top, bottom]) }
            }
        }
        if !lockedTopOrBottom {
            for dress in pool(.dress) { bases.append([dress]) }
        }
        guard !bases.isEmpty else {
            var missing: [GarmentCategory] = []
            if (byCategory[.dress] ?? []).isEmpty {
                if (byCategory[.top] ?? []).isEmpty { missing.append(.top) }
                if (byCategory[.bottom] ?? []).isEmpty { missing.append(.bottom) }
                if missing.isEmpty { missing.append(.dress) }
            }
            return GeneratorResult(suggestions: [], missing: missing)
        }

        let shoesOptions: [GarmentSummary?] = pool(.shoes).isEmpty ? [nil] : pool(.shoes).map { Optional($0) }
        var outerOptions: [GarmentSummary?] = [nil]
        if let lockedOuter = lockedByCategory[.outerwear]?.first {
            outerOptions = [lockedOuter]
        } else if options.includeOuterwear {
            outerOptions += pool(.outerwear).map { Optional($0) }
        }

        // Enumerate (or sample) base × shoes × outerwear.
        let total = bases.count * shoesOptions.count * outerOptions.count
        var combos: [[GarmentSummary]] = []
        if total <= maxCandidates {
            for base in bases {
                for shoes in shoesOptions {
                    for outer in outerOptions {
                        combos.append(base + [shoes, outer].compactMap { $0 })
                    }
                }
            }
        } else {
            var seen = Set<[Int]>()
            var attempts = 0
            while combos.count < maxCandidates && attempts < maxCandidates * 4 {
                attempts += 1
                let bi = Int(rng.next() % UInt64(bases.count))
                let si = Int(rng.next() % UInt64(shoesOptions.count))
                let oi = Int(rng.next() % UInt64(outerOptions.count))
                if seen.insert([bi, si, oi]).inserted {
                    combos.append(bases[bi] + [shoesOptions[si], outerOptions[oi]].compactMap { $0 })
                }
            }
        }

        // Accessories: locked ones always, otherwise occasionally one extra.
        let lockedAccessories = lockedGarments.filter { accessoryCategories.contains($0.category) || $0.category == .accessory }
        let accessoryPool = accessoryCategories.flatMap { pool($0) }.filter { !options.locked.contains($0.id) }

        struct Candidate {
            var items: [GarmentSummary]
            var score: Double
        }
        var candidates: [Candidate] = []
        candidates.reserveCapacity(combos.count)
        for var items in combos {
            for accessory in lockedAccessories where !items.contains(where: { $0.id == accessory.id }) {
                items.append(accessory)
            }
            if options.includeAccessories, !accessoryPool.isEmpty, rng.nextUnit() < 0.35 {
                let extra = accessoryPool[Int(rng.next() % UInt64(accessoryPool.count))]
                let clashes = items.contains { $0.category == extra.category && extra.category.isExclusive }
                if !clashes { items.append(extra) }
            }
            let harmony = ColorHarmony.outfitScore(items.map { ($0.color, $0.category.colorWeight) })
            let jitter = rng.nextUnit() * 0.12
            candidates.append(Candidate(items: items, score: harmony + jitter))
        }

        // Greedy selection with a penalty for reusing the same core pieces.
        var usage: [UUID: Int] = [:]
        var chosen: [OutfitSuggestion] = []
        var chosenSignatures = Set<[UUID]>()
        var remaining = candidates
        while chosen.count < max(0, options.count) && !remaining.isEmpty {
            var bestIndex = -1
            var bestValue = -Double.infinity
            for (i, candidate) in remaining.enumerated() {
                let signature = candidate.items.map(\.id).sorted { $0.uuidString < $1.uuidString }
                if chosenSignatures.contains(signature) || options.excludedSignatures.contains(signature) { continue }
                var penalty = 0.0
                for item in candidate.items where item.category.isCore || item.category == .shoes {
                    if options.locked.contains(item.id) { continue }
                    penalty += 0.15 * Double(usage[item.id, default: 0])
                }
                let value = candidate.score - penalty
                if value > bestValue {
                    bestValue = value
                    bestIndex = i
                }
            }
            guard bestIndex >= 0 else { break }
            let pick = remaining.remove(at: bestIndex)
            let ids = orderedForDisplay(pick.items).map(\.id)
            chosen.append(OutfitSuggestion(garmentIDs: ids, score: clamp(pick.score, 0, 1)))
            chosenSignatures.insert(ids.sorted { $0.uuidString < $1.uuidString })
            for item in pick.items { usage[item.id, default: 0] += 1 }
        }
        return GeneratorResult(suggestions: chosen, missing: [])
    }

    /// Back-to-front order so outfits are created with natural layering.
    static func orderedForDisplay(_ items: [GarmentSummary]) -> [GarmentSummary] {
        items.sorted { $0.category.baseZ < $1.category.baseZ }
    }
}
