import Foundation

/// An 8-bit single-channel mask (0 = transparent, 255 = opaque), row-major,
/// origin top-left. Used for segmentation results, cut-out alpha and brushes.
public struct AlphaMask: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var values: [UInt8]

    public static let defaultThreshold: UInt8 = 128

    public init(width: Int, height: Int, values: [UInt8]) {
        precondition(width >= 0 && height >= 0, "negative mask size")
        precondition(values.count == width * height, "mask size mismatch")
        self.width = width
        self.height = height
        self.values = values
    }

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.init(width: width, height: height, values: [UInt8](repeating: fill, count: max(0, width * height)))
    }

    public var isEmpty: Bool { width == 0 || height == 0 }

    @inline(__always)
    public subscript(x: Int, y: Int) -> UInt8 {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }

    @inline(__always)
    public func isSet(_ x: Int, _ y: Int, threshold: UInt8 = AlphaMask.defaultThreshold) -> Bool {
        values[y * width + x] >= threshold
    }

    // MARK: Measurements

    public func setCount(threshold: UInt8 = AlphaMask.defaultThreshold) -> Int {
        var count = 0
        for v in values where v >= threshold { count += 1 }
        return count
    }

    /// Fraction of pixels at or above the threshold.
    public func coverage(threshold: UInt8 = AlphaMask.defaultThreshold) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(setCount(threshold: threshold)) / Double(values.count)
    }

    public func boundingBox(threshold: UInt8 = AlphaMask.defaultThreshold) -> PixelRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            var rowHasPixels = false
            for x in 0..<width where values[row + x] >= threshold {
                rowHasPixels = true
                if x < minX { minX = x }
                if x > maxX { maxX = x }
            }
            if rowHasPixels {
                if y < minY { minY = y }
                maxY = y
            }
        }
        guard maxX >= 0 else { return nil }
        return PixelRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    public struct RowExtent: Equatable, Sendable {
        public var minX: Int
        public var maxX: Int
        /// Number of set pixels in the row.
        public var count: Int
        /// Width in pixels from the left edge of `minX` to the right edge of `maxX`.
        public var span: Int { maxX - minX + 1 }
        public var fill: Double { span > 0 ? Double(count) / Double(span) : 0 }
        public var center: Double { Double(minX + maxX + 1) / 2 }
    }

    public func rowExtent(_ y: Int, threshold: UInt8 = AlphaMask.defaultThreshold) -> RowExtent? {
        guard y >= 0, y < height else { return nil }
        var minX = -1, maxX = -1, count = 0
        let row = y * width
        for x in 0..<width where values[row + x] >= threshold {
            if minX < 0 { minX = x }
            maxX = x
            count += 1
        }
        guard minX >= 0 else { return nil }
        return RowExtent(minX: minX, maxX: maxX, count: count)
    }

    /// Contiguous runs of set pixels in a row (inclusive ranges).
    public func runs(inRow y: Int, threshold: UInt8 = AlphaMask.defaultThreshold) -> [ClosedRange<Int>] {
        guard y >= 0, y < height else { return [] }
        var result: [ClosedRange<Int>] = []
        var start = -1
        let row = y * width
        for x in 0..<width {
            let set = values[row + x] >= threshold
            if set && start < 0 { start = x }
            if !set && start >= 0 {
                result.append(start...(x - 1))
                start = -1
            }
        }
        if start >= 0 { result.append(start...(width - 1)) }
        return result
    }

    // MARK: Connected components

    public struct Component: Equatable, Sendable {
        public var label: Int32
        public var pixelCount: Int
        public var bounds: PixelRect
        public var touchesBorder: Bool
    }

    /// 8-connected components of set pixels. Labels start at 1 (0 = unset).
    /// Components are returned sorted by size, largest first.
    public func connectedComponents(threshold: UInt8 = AlphaMask.defaultThreshold, connectivity8: Bool = true) -> (labels: [Int32], components: [Component]) {
        var labels = [Int32](repeating: 0, count: values.count)
        var components: [Component] = []
        var stack: [Int] = []
        var nextLabel: Int32 = 1
        for start in 0..<values.count where values[start] >= threshold && labels[start] == 0 {
            let label = nextLabel
            nextLabel += 1
            labels[start] = label
            stack.append(start)
            var count = 0
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            var border = false
            while let index = stack.popLast() {
                count += 1
                let x = index % width, y = index / width
                minX = Swift.min(minX, x); maxX = Swift.max(maxX, x)
                minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 { border = true }
                for dy in -1...1 {
                    let ny = y + dy
                    if ny < 0 || ny >= height { continue }
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        if !connectivity8 && dx != 0 && dy != 0 { continue }
                        let nx = x + dx
                        if nx < 0 || nx >= width { continue }
                        let n = ny * width + nx
                        if labels[n] == 0 && values[n] >= threshold {
                            labels[n] = label
                            stack.append(n)
                        }
                    }
                }
            }
            components.append(Component(label: label, pixelCount: count,
                                        bounds: PixelRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY),
                                        touchesBorder: border))
        }
        components.sort { $0.pixelCount > $1.pixelCount }
        return (labels, components)
    }

    /// Keeps only the largest components: at most `maxCount`, each at least
    /// `minRelativeArea` of the largest one. Soft alpha values of kept pixels
    /// (and of their unset fringe) are preserved.
    public func keepingLargestComponents(maxCount: Int = 1, minRelativeArea: Double = 0.05, threshold: UInt8 = AlphaMask.defaultThreshold) -> AlphaMask {
        let (labels, components) = connectedComponents(threshold: threshold)
        guard let largest = components.first else { return AlphaMask(width: width, height: height) }
        let minArea = Double(largest.pixelCount) * minRelativeArea
        let kept = Set(components.prefix(maxCount).filter { Double($0.pixelCount) >= minArea }.map(\.label))
        var result = AlphaMask(width: width, height: height)
        // Pixels below threshold (soft fringe) are kept if they neighbour a kept pixel.
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let label = labels[i]
                if label != 0 {
                    if kept.contains(label) { result.values[i] = values[i] }
                } else if values[i] > 0 {
                    var nearKept = false
                    search: for dy in -1...1 {
                        let ny = y + dy
                        if ny < 0 || ny >= height { continue }
                        for dx in -1...1 {
                            let nx = x + dx
                            if nx < 0 || nx >= width { continue }
                            let l = labels[ny * width + nx]
                            if l != 0 && kept.contains(l) {
                                nearKept = true
                                break search
                            }
                        }
                    }
                    if nearKept { result.values[i] = values[i] }
                }
            }
        }
        return result
    }

    /// Fills enclosed holes smaller than `maxHoleFraction` of the set area.
    public func fillingHoles(maxHoleFraction: Double = 0.02, threshold: UInt8 = AlphaMask.defaultThreshold) -> AlphaMask {
        let setArea = setCount(threshold: threshold)
        guard setArea > 0 else { return self }
        // Components of the *unset* pixels (4-connected so diagonal gaps do not leak).
        let inverted = AlphaMask(width: width, height: height, values: values.map { $0 >= threshold ? 0 : 255 })
        let (labels, components) = inverted.connectedComponents(threshold: 128, connectivity8: false)
        let maxHole = Double(setArea) * maxHoleFraction
        let holes = Set(components.filter { !$0.touchesBorder && Double($0.pixelCount) <= maxHole }.map(\.label))
        guard !holes.isEmpty else { return self }
        var result = self
        for i in 0..<values.count where holes.contains(labels[i]) {
            result.values[i] = 255
        }
        return result
    }

    // MARK: Transformations

    public func cropped(to rect: PixelRect) -> AlphaMask {
        let minX = Swift.max(0, rect.minX), minY = Swift.max(0, rect.minY)
        let maxX = Swift.min(width - 1, rect.maxX), maxY = Swift.min(height - 1, rect.maxY)
        guard maxX >= minX, maxY >= minY else { return AlphaMask(width: 0, height: 0) }
        let w = maxX - minX + 1, h = maxY - minY + 1
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let src = (minY + y) * width + minX
            for x in 0..<w { out[y * w + x] = values[src + x] }
        }
        return AlphaMask(width: w, height: h, values: out)
    }

    /// Bilinear resampling (pixel centres aligned, like `align_corners=False`).
    public func resized(width newWidth: Int, height newHeight: Int) -> AlphaMask {
        guard newWidth > 0, newHeight > 0, width > 0, height > 0 else {
            return AlphaMask(width: Swift.max(newWidth, 0), height: Swift.max(newHeight, 0))
        }
        if newWidth == width && newHeight == height { return self }
        var out = [UInt8](repeating: 0, count: newWidth * newHeight)
        let sx = Double(width) / Double(newWidth), sy = Double(height) / Double(newHeight)
        for y in 0..<newHeight {
            let fy = clamp((Double(y) + 0.5) * sy - 0.5, 0, Double(height - 1))
            let y0 = Int(fy), y1 = Swift.min(y0 + 1, height - 1)
            let ty = fy - Double(y0)
            for x in 0..<newWidth {
                let fx = clamp((Double(x) + 0.5) * sx - 0.5, 0, Double(width - 1))
                let x0 = Int(fx), x1 = Swift.min(x0 + 1, width - 1)
                let tx = fx - Double(x0)
                let v00 = Double(values[y0 * width + x0]), v10 = Double(values[y0 * width + x1])
                let v01 = Double(values[y1 * width + x0]), v11 = Double(values[y1 * width + x1])
                let top = v00 + (v10 - v00) * tx
                let bottom = v01 + (v11 - v01) * tx
                out[y * newWidth + x] = UInt8(clamp((top + (bottom - top) * ty).rounded(), 0, 255))
            }
        }
        return AlphaMask(width: newWidth, height: newHeight, values: out)
    }

    /// Separable box blur, used to feather edges.
    public func blurred(radius: Int) -> AlphaMask {
        guard radius > 0, width > 0, height > 0 else { return self }
        var temp = [Double](repeating: 0, count: values.count)
        var out = [UInt8](repeating: 0, count: values.count)
        for y in 0..<height {
            let row = y * width
            var sum = 0.0
            var count = 0
            for x in 0...Swift.min(radius, width - 1) {
                sum += Double(values[row + x]); count += 1
            }
            for x in 0..<width {
                temp[row + x] = sum / Double(count)
                let add = x + radius + 1, remove = x - radius
                if add < width { sum += Double(values[row + add]); count += 1 }
                if remove >= 0 { sum -= Double(values[row + remove]); count -= 1 }
            }
        }
        for x in 0..<width {
            var sum = 0.0
            var count = 0
            for y in 0...Swift.min(radius, height - 1) {
                sum += temp[y * width + x]; count += 1
            }
            for y in 0..<height {
                out[y * width + x] = UInt8(clamp((sum / Double(count)).rounded(), 0, 255))
                let add = y + radius + 1, remove = y - radius
                if add < height { sum += temp[add * width + x]; count += 1 }
                if remove >= 0 { sum -= temp[remove * width + x]; count -= 1 }
            }
        }
        return AlphaMask(width: width, height: height, values: out)
    }

    public func thresholded(_ threshold: UInt8 = AlphaMask.defaultThreshold) -> AlphaMask {
        AlphaMask(width: width, height: height, values: values.map { $0 >= threshold ? 255 : 0 })
    }

    /// Per-pixel product (both masks must be the same size).
    public func multiplied(by other: AlphaMask) -> AlphaMask {
        precondition(other.width == width && other.height == height, "mask size mismatch")
        var out = values
        for i in 0..<out.count {
            out[i] = UInt8((UInt16(values[i]) * UInt16(other.values[i]) + 127) / 255)
        }
        return AlphaMask(width: width, height: height, values: out)
    }

    public func union(_ other: AlphaMask) -> AlphaMask {
        precondition(other.width == width && other.height == height, "mask size mismatch")
        var out = values
        for i in 0..<out.count { out[i] = Swift.max(values[i], other.values[i]) }
        return AlphaMask(width: width, height: height, values: out)
    }

    public func subtracting(_ other: AlphaMask) -> AlphaMask {
        precondition(other.width == width && other.height == height, "mask size mismatch")
        var out = values
        for i in 0..<out.count {
            out[i] = UInt8((UInt16(values[i]) * UInt16(255 - other.values[i]) + 127) / 255)
        }
        return AlphaMask(width: width, height: height, values: out)
    }

    /// Morphological dilation (square structuring element) of the binary mask.
    public func dilated(radius: Int, threshold: UInt8 = AlphaMask.defaultThreshold) -> AlphaMask {
        guard radius > 0 else { return self }
        // Max filter, separable.
        var temp = [UInt8](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var m: UInt8 = 0
                for xx in Swift.max(0, x - radius)...Swift.min(width - 1, x + radius) {
                    m = Swift.max(m, values[y * width + xx])
                }
                temp[y * width + x] = m
            }
        }
        var out = temp
        for y in 0..<height {
            for x in 0..<width {
                var m: UInt8 = 0
                for yy in Swift.max(0, y - radius)...Swift.min(height - 1, y + radius) {
                    m = Swift.max(m, temp[yy * width + x])
                }
                out[y * width + x] = m
            }
        }
        return AlphaMask(width: width, height: height, values: out)
    }
}

// MARK: - Drawing (brushes and test shapes)

public extension AlphaMask {
    enum BrushMode: String, Codable, Sendable {
        case erase
        case restore
    }

    /// Paints a soft round dab. `hardness` 0...1 controls the falloff.
    mutating func paintDab(center: CGPoint, radius: Double, mode: BrushMode, hardness: Double = 0.7, strength: Double = 1) {
        guard radius > 0, width > 0, height > 0 else { return }
        let cx = Double(center.x), cy = Double(center.y)
        let minX = Swift.max(0, Int((cx - radius).rounded(.down)))
        let maxX = Swift.min(width - 1, Int((cx + radius).rounded(.up)))
        let minY = Swift.max(0, Int((cy - radius).rounded(.down)))
        let maxY = Swift.min(height - 1, Int((cy + radius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }
        let inner = radius * clamp(hardness, 0, 1)
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                let d = (dx * dx + dy * dy).squareRoot()
                if d > radius { continue }
                var a = d <= inner ? 1.0 : 1 - (d - inner) / max(radius - inner, 1e-6)
                a = clamp(a * strength, 0, 1)
                let i = y * width + x
                let current = Double(values[i])
                switch mode {
                case .erase:
                    values[i] = UInt8(clamp((current * (1 - a)).rounded(), 0, 255))
                case .restore:
                    values[i] = UInt8(clamp(Swift.max(current, 255 * a).rounded(), 0, 255))
                }
            }
        }
    }

    /// Paints dabs along a segment so fast strokes have no gaps.
    mutating func paintStroke(from start: CGPoint, to end: CGPoint, radius: Double, mode: BrushMode, hardness: Double = 0.7) {
        let distance = start.distance(to: end)
        let step = Swift.max(radius * 0.3, 0.5)
        let steps = Swift.max(1, Int((distance / step).rounded(.up)))
        for i in 0...steps {
            paintDab(center: .lerp(start, end, Double(i) / Double(steps)), radius: radius, mode: mode, hardness: hardness)
        }
    }

    mutating func fillRect(_ rect: PixelRect, value: UInt8 = 255) {
        let minX = Swift.max(0, rect.minX), maxX = Swift.min(width - 1, rect.maxX)
        let minY = Swift.max(0, rect.minY), maxY = Swift.min(height - 1, rect.maxY)
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY...maxY {
            for x in minX...maxX { values[y * width + x] = value }
        }
    }

    /// Even-odd scanline fill of a polygon (pixel centres inside are set).
    mutating func fillPolygon(_ points: [CGPoint], value: UInt8 = 255) {
        guard points.count >= 3, height > 0 else { return }
        for y in 0..<height {
            let sy = Double(y) + 0.5
            var xs: [Double] = []
            for i in 0..<points.count {
                let p1 = points[i], p2 = points[(i + 1) % points.count]
                let y1 = Double(p1.y), y2 = Double(p2.y)
                if (y1 <= sy && y2 > sy) || (y2 <= sy && y1 > sy) {
                    let t = (sy - y1) / (y2 - y1)
                    xs.append(Double(p1.x) + t * (Double(p2.x) - Double(p1.x)))
                }
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                let startX = Swift.max(0, Int((xs[i] - 0.5).rounded(.up)))
                let endX = Swift.min(width - 1, Int((xs[i + 1] - 0.5).rounded(.down)))
                if startX <= endX {
                    for x in startX...endX { values[y * width + x] = value }
                }
                i += 2
            }
        }
    }

    mutating func fillEllipse(center: CGPoint, radiusX: Double, radiusY: Double, value: UInt8 = 255) {
        guard radiusX > 0, radiusY > 0, height > 0, width > 0 else { return }
        let cx = Double(center.x), cy = Double(center.y)
        let minY = Swift.max(0, Int(cy - radiusY)), maxY = Swift.min(height - 1, Int(cy + radiusY))
        guard minY <= maxY else { return }
        for y in minY...maxY {
            let dy = (Double(y) + 0.5 - cy) / radiusY
            if abs(dy) > 1 { continue }
            let half = radiusX * (1 - dy * dy).squareRoot()
            let startX = Swift.max(0, Int((cx - half - 0.5).rounded(.up)))
            let endX = Swift.min(width - 1, Int((cx + half - 0.5).rounded(.down)))
            if startX <= endX {
                for x in startX...endX { values[y * width + x] = value }
            }
        }
    }
}
