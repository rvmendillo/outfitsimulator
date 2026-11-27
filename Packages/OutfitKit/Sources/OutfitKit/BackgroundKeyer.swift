#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

/// Separates objects from a plain, roughly uniform background (typical
/// flat-lay or product photos). Used when Vision's subject lifting is
/// unavailable, e.g. in the simulator.
public enum BackgroundKeyer {
    /// Working resolution for keying (the result is upsampled).
    static let workingMaxSide = 640

    /// Foreground mask at the bitmap's size, or nil when the border is not a
    /// uniform background.
    public static func foregroundMask(_ bitmap: RGBABitmap) -> AlphaMask? {
        guard bitmap.width >= 8, bitmap.height >= 8 else { return nil }
        let longest = max(bitmap.width, bitmap.height)
        let small: RGBABitmap
        if longest > workingMaxSide {
            let s = Double(workingMaxSide) / Double(longest)
            guard let r = bitmap.resized(width: max(8, Int(Double(bitmap.width) * s)), height: max(8, Int(Double(bitmap.height) * s))) else {
                return nil
            }
            small = r
        } else {
            small = bitmap
        }
        let w = small.width, h = small.height

        // Sample the border.
        let band = max(2, min(w, h) / 40)
        var borderLabs: [LabColor] = []
        var borderColors: [SRGBColor] = []
        let step = max(1, (2 * (w + h) * band) / 3000)
        var counter = 0
        for y in 0..<h {
            for x in 0..<w where x < band || y < band || x >= w - band || y >= h - band {
                counter += 1
                if counter % step != 0 { continue }
                if let c = small.color(x: x, y: y) {
                    borderColors.append(c)
                    borderLabs.append(c.lab)
                }
            }
        }
        guard let background = ColorPalette.medianColor(borderColors) else { return nil }
        let bgLab = background.lab
        let distances = borderLabs.map { $0.distance(to: bgLab) }.sorted()
        let mad = distances[distances.count / 2]
        let p90 = distances[min(distances.count - 1, Int(Double(distances.count) * 0.9))]
        // A busy border means there is no plain background to key out.
        guard mad < 10, p90 < 28 else { return nil }
        let threshold = max(14, 3 * p90 + 4)

        var values = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                guard let c = small.color(x: x, y: y) else { continue }
                let d = c.lab.distance(to: bgLab)
                let a = (d - threshold * 0.6) / (threshold * 0.8)
                values[y * w + x] = UInt8(max(0, min(255, (a * 255).rounded())))
            }
        }
        var mask = AlphaMask(width: w, height: h, values: values)
        mask = mask.fillingHoles(maxHoleFraction: 0.02)
        let minArea = Double(w * h) * 0.004
        let (_, components) = mask.connectedComponents()
        let keepCount = components.filter { Double($0.pixelCount) >= minArea }.count
        guard keepCount > 0 else { return nil }
        mask = mask.keepingLargestComponents(maxCount: keepCount, minRelativeArea: 0)
        if mask.width != bitmap.width || mask.height != bitmap.height {
            mask = mask.resized(width: bitmap.width, height: bitmap.height)
        }
        return mask
    }

    /// Splits a mask into one mask per large connected component.
    public static func split(_ mask: AlphaMask, minAreaFraction: Double = 0.004, maxCount: Int = 8) -> [AlphaMask] {
        let (labels, components) = mask.connectedComponents()
        let minArea = Double(mask.width * mask.height) * minAreaFraction
        var result: [AlphaMask] = []
        for component in components.prefix(maxCount) where Double(component.pixelCount) >= minArea {
            var single = AlphaMask(width: mask.width, height: mask.height)
            let b = component.bounds.expanded(by: 2, clampedToWidth: mask.width, height: mask.height)
            for y in b.minY...b.maxY {
                for x in b.minX...b.maxX {
                    let i = y * mask.width + x
                    if labels[i] == component.label {
                        single.values[i] = mask.values[i]
                    } else if labels[i] == 0 && mask.values[i] > 0 {
                        single.values[i] = mask.values[i] // soft fringe
                    }
                }
            }
            result.append(single)
        }
        return result
    }
}
#endif
