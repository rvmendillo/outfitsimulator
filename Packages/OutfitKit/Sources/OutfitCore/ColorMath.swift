import Foundation

/// An sRGB colour with components in 0...1.
public struct RGBColor: Codable, Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = clamp(r, 0, 1)
        self.g = clamp(g, 0, 1)
        self.b = clamp(b, 0, 1)
    }

    public init(r8: UInt8, g8: UInt8, b8: UInt8) {
        self.init(r: Double(r8) / 255, g: Double(g8) / 255, b: Double(b8) / 255)
    }

    /// Parses `#RRGGBB` or `RRGGBB`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(r8: UInt8((value >> 16) & 0xFF), g8: UInt8((value >> 8) & 0xFF), b8: UInt8(value & 0xFF))
    }

    public var hex: String {
        func byte(_ v: Double) -> Int { Int((clamp(v, 0, 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    public static let black = RGBColor(r: 0, g: 0, b: 0)
    public static let white = RGBColor(r: 1, g: 1, b: 1)

    // MARK: Conversions

    private static func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        0.2126 * Self.linearize(r) + 0.7152 * Self.linearize(g) + 0.0722 * Self.linearize(b)
    }

    /// WCAG contrast ratio between two colours (1...21).
    public func contrastRatio(with other: RGBColor) -> Double {
        let l1 = relativeLuminance, l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// CIE L*a*b* (D65).
    public var lab: LabColor {
        let rl = Self.linearize(r), gl = Self.linearize(g), bl = Self.linearize(b)
        let x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
        let y = (0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl) / 1.0
        let z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883
        func f(_ t: Double) -> Double {
            t > 0.008856 ? cbrt(t) : (7.787 * t + 16.0 / 116.0)
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return LabColor(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// Hue (degrees 0..<360), saturation and value (0...1).
    public var hsv: (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 1e-9 {
            if maxC == r {
                h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = 60 * ((b - r) / delta + 2)
            } else {
                h = 60 * ((r - g) / delta + 4)
            }
        }
        if h < 0 { h += 360 }
        let s = maxC <= 1e-9 ? 0 : delta / maxC
        return (h, s, maxC)
    }

    public func mixed(with other: RGBColor, amount t: Double) -> RGBColor {
        RGBColor(r: lerp(r, other.r, t), g: lerp(g, other.g, t), b: lerp(b, other.b, t))
    }

    /// Darkens (negative) or lightens (positive) by mixing toward black/white.
    public func adjustingBrightness(_ amount: Double) -> RGBColor {
        amount >= 0 ? mixed(with: .white, amount: amount) : mixed(with: .black, amount: -amount)
    }
}

/// CIE L*a*b* colour.
public struct LabColor: Equatable, Sendable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    public var chroma: Double { (a * a + b * b).squareRoot() }

    /// Hue angle in degrees (0..<360).
    public var hue: Double {
        var h = atan2(b, a) * 180 / .pi
        if h < 0 { h += 360 }
        return h
    }

    /// CIE76 colour difference.
    public func distance(to other: LabColor) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}

// MARK: - Naming

public enum ColorNaming {
    public struct NamedColor: Sendable {
        public let name: String
        public let color: RGBColor
        public let isNeutral: Bool
    }

    /// A compact fashion-oriented palette used to name garment colours.
    public static let palette: [NamedColor] = [
        NamedColor(name: "Black", color: RGBColor(hex: "#151515")!, isNeutral: true),
        NamedColor(name: "Charcoal", color: RGBColor(hex: "#3B3B3F")!, isNeutral: true),
        NamedColor(name: "Gray", color: RGBColor(hex: "#8C8C8C")!, isNeutral: true),
        NamedColor(name: "Light Gray", color: RGBColor(hex: "#C8C8C8")!, isNeutral: true),
        NamedColor(name: "White", color: RGBColor(hex: "#F4F4F2")!, isNeutral: true),
        NamedColor(name: "Cream", color: RGBColor(hex: "#EFE6D2")!, isNeutral: true),
        NamedColor(name: "Beige", color: RGBColor(hex: "#D6C3A3")!, isNeutral: true),
        NamedColor(name: "Camel", color: RGBColor(hex: "#B98B5B")!, isNeutral: true),
        NamedColor(name: "Brown", color: RGBColor(hex: "#6B4428")!, isNeutral: true),
        NamedColor(name: "Navy", color: RGBColor(hex: "#1F2A44")!, isNeutral: true),
        NamedColor(name: "Denim", color: RGBColor(hex: "#5B7DA8")!, isNeutral: true),
        NamedColor(name: "Olive", color: RGBColor(hex: "#6B6B3A")!, isNeutral: true),
        NamedColor(name: "Khaki", color: RGBColor(hex: "#A89F72")!, isNeutral: true),
        NamedColor(name: "Red", color: RGBColor(hex: "#C62828")!, isNeutral: false),
        NamedColor(name: "Burgundy", color: RGBColor(hex: "#6D1A2B")!, isNeutral: false),
        NamedColor(name: "Pink", color: RGBColor(hex: "#EE8FB0")!, isNeutral: false),
        NamedColor(name: "Blush", color: RGBColor(hex: "#E9C2C0")!, isNeutral: false),
        NamedColor(name: "Orange", color: RGBColor(hex: "#EF7A1A")!, isNeutral: false),
        NamedColor(name: "Rust", color: RGBColor(hex: "#A8492A")!, isNeutral: false),
        NamedColor(name: "Yellow", color: RGBColor(hex: "#F2CF3A")!, isNeutral: false),
        NamedColor(name: "Mustard", color: RGBColor(hex: "#C9A227")!, isNeutral: false),
        NamedColor(name: "Green", color: RGBColor(hex: "#2E8B57")!, isNeutral: false),
        NamedColor(name: "Sage", color: RGBColor(hex: "#9CAF88")!, isNeutral: false),
        NamedColor(name: "Teal", color: RGBColor(hex: "#1F7A7A")!, isNeutral: false),
        NamedColor(name: "Blue", color: RGBColor(hex: "#2F5FD0")!, isNeutral: false),
        NamedColor(name: "Sky Blue", color: RGBColor(hex: "#8EC5F0")!, isNeutral: false),
        NamedColor(name: "Purple", color: RGBColor(hex: "#6A3FA0")!, isNeutral: false),
        NamedColor(name: "Lavender", color: RGBColor(hex: "#B9A7E0")!, isNeutral: false),
    ]

    public static func nearest(to color: RGBColor) -> NamedColor {
        let lab = color.lab
        var best = palette[0]
        var bestDistance = Double.infinity
        for candidate in palette {
            let d = candidate.color.lab.distance(to: lab)
            if d < bestDistance {
                bestDistance = d
                best = candidate
            }
        }
        return best
    }

    public static func name(for color: RGBColor) -> String {
        nearest(to: color).name
    }

    /// Neutral colours combine with anything: low chroma, or a classic neutral
    /// such as navy, denim, camel or olive.
    public static func isNeutral(_ color: RGBColor) -> Bool {
        if color.lab.chroma < 14 { return true }
        return nearest(to: color).isNeutral
    }
}

// MARK: - Harmony

public enum ColorHarmony {
    /// Compatibility of two colours in 0...1.
    public static func pairScore(_ c1: RGBColor, _ c2: RGBColor) -> Double {
        let n1 = ColorNaming.isNeutral(c1), n2 = ColorNaming.isNeutral(c2)
        let l1 = c1.lab, l2 = c2.lab
        if n1 && n2 {
            // Two neutrals always work; a bit of light/dark contrast reads better.
            return abs(l1.l - l2.l) >= 12 ? 0.95 : 0.85
        }
        if n1 || n2 { return 0.9 }
        let dh = hueDistance(l1.hue, l2.hue)
        switch dh {
        case ..<30: return abs(l1.l - l2.l) >= 10 ? 0.9 : 0.8   // monochrome / analogous
        case 30..<60: return 0.65                              // analogous-ish
        case 60..<100: return 0.35                             // tends to clash
        case 100..<140: return 0.55                            // triadic
        case 140..<160: return 0.6                             // split-complementary
        default: return 0.75                                    // complementary
        }
    }

    /// Smallest angle between two hues, in degrees (0...180).
    public static func hueDistance(_ h1: Double, _ h2: Double) -> Double {
        let d = abs(h1 - h2).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// Overall harmony of an outfit's colours in 0...1. Colours are weighted
    /// (e.g. by how much of the outfit they cover).
    public static func outfitScore(_ colors: [(color: RGBColor, weight: Double)]) -> Double {
        let items = colors.filter { $0.weight > 0 }
        guard items.count >= 2 else { return items.isEmpty ? 0 : 0.8 }
        var total = 0.0, weightSum = 0.0
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                let w = items[i].weight * items[j].weight
                total += w * pairScore(items[i].color, items[j].color)
                weightSum += w
            }
        }
        var score = weightSum > 0 ? total / weightSum : 0.8
        // More than two loud colours gets busy.
        let chromaticCount = items.filter { !ColorNaming.isNeutral($0.color) }.count
        if chromaticCount > 2 {
            score -= 0.08 * Double(chromaticCount - 2)
        }
        return clamp(score, 0, 1)
    }
}

// MARK: - Palette extraction

public enum ColorPalette {
    public struct Swatch: Equatable, Sendable {
        public var color: RGBColor
        public var weight: Double
    }

    /// Deterministic k-means clustering in Lab space. Returns clusters sorted
    /// by weight (largest first); weights sum to 1.
    public static func dominantColors(samples: [RGBColor], k: Int = 3, iterations: Int = 12) -> [Swatch] {
        guard !samples.isEmpty, k > 0 else { return [] }
        let labs = samples.map { $0.lab }
        let clusterCount = min(k, samples.count)

        // k-means++ style deterministic seeding: start with the sample closest to
        // the mean, then repeatedly take the sample farthest from existing centres.
        var centers: [LabColor] = []
        let mean = LabColor(
            l: labs.map(\.l).reduce(0, +) / Double(labs.count),
            a: labs.map(\.a).reduce(0, +) / Double(labs.count),
            b: labs.map(\.b).reduce(0, +) / Double(labs.count)
        )
        if let first = labs.min(by: { $0.distance(to: mean) < $1.distance(to: mean) }) {
            centers.append(first)
        }
        while centers.count < clusterCount {
            var bestIndex = 0
            var bestDistance = -1.0
            for (i, lab) in labs.enumerated() {
                let d = centers.map { $0.distance(to: lab) }.min() ?? 0
                if d > bestDistance {
                    bestDistance = d
                    bestIndex = i
                }
            }
            if bestDistance <= 1e-6 { break }
            centers.append(labs[bestIndex])
        }

        var assignment = [Int](repeating: 0, count: labs.count)
        for _ in 0..<max(1, iterations) {
            var changed = false
            for (i, lab) in labs.enumerated() {
                var best = 0
                var bestDistance = Double.infinity
                for (c, center) in centers.enumerated() {
                    let d = center.distance(to: lab)
                    if d < bestDistance {
                        bestDistance = d
                        best = c
                    }
                }
                if assignment[i] != best {
                    assignment[i] = best
                    changed = true
                }
            }
            var sums = [(l: Double, a: Double, b: Double, n: Int)](repeating: (0, 0, 0, 0), count: centers.count)
            for (i, lab) in labs.enumerated() {
                let c = assignment[i]
                sums[c].l += lab.l
                sums[c].a += lab.a
                sums[c].b += lab.b
                sums[c].n += 1
            }
            for c in 0..<centers.count where sums[c].n > 0 {
                let n = Double(sums[c].n)
                centers[c] = LabColor(l: sums[c].l / n, a: sums[c].a / n, b: sums[c].b / n)
            }
            if !changed { break }
        }

        // Report the average sRGB colour of each cluster (exact, no Lab round trip).
        var rgbSums = [(r: Double, g: Double, b: Double, n: Int)](repeating: (0, 0, 0, 0), count: centers.count)
        for (i, sample) in samples.enumerated() {
            let c = assignment[i]
            rgbSums[c].r += sample.r
            rgbSums[c].g += sample.g
            rgbSums[c].b += sample.b
            rgbSums[c].n += 1
        }
        let total = Double(samples.count)
        return rgbSums
            .filter { $0.n > 0 }
            .map { s in
                let n = Double(s.n)
                return Swatch(color: RGBColor(r: s.r / n, g: s.g / n, b: s.b / n), weight: n / total)
            }
            .sorted { $0.weight > $1.weight }
    }

    /// Robust "typical" colour: per-channel median.
    public static func medianColor(_ samples: [RGBColor]) -> RGBColor? {
        guard !samples.isEmpty else { return nil }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        return RGBColor(r: median(samples.map(\.r)), g: median(samples.map(\.g)), b: median(samples.map(\.b)))
    }
}
