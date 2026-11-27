import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Estimates a garment's fit guides from its cut-out mask (and, for photos of
/// a person wearing it, the detected body joints).
public enum AnchorEstimator {
    /// Vision's shoulder joints sit inside the silhouette; the shoulder seam is
    /// roughly 14% of the joint distance further out on each side.
    public static let shoulderJointToSeamExpansion = 0.14
    /// Full-length trousers/skirts are at least this many times longer than wide.
    public static let fullLengthAspectRatio = 2.0

    /// - Parameters:
    ///   - mask: alpha of the cut-out (same size as the cut-out image).
    ///   - pose: joints in the same pixel coordinates as `mask`, if known.
    public static func estimate(
        category: GarmentCategory,
        mask: AlphaMask,
        pose: PoseJoints? = nil,
        threshold: UInt8 = AlphaMask.defaultThreshold
    ) -> GarmentAnchors {
        guard !mask.isEmpty, let box = mask.boundingBox(threshold: threshold) else {
            return .fallback(for: category)
        }
        let result: GarmentAnchors
        switch category {
        case .top, .outerwear, .dress:
            result = upperBody(category: category, mask: mask, box: box, pose: pose, threshold: threshold)
        case .bottom:
            result = bottom(mask: mask, box: box, pose: pose, threshold: threshold)
        case .shoes:
            result = shoes(mask: mask, threshold: threshold) ?? bandAnchors(mask: mask, box: box, level: .sole, yFraction: 1.0, useMax: true, threshold: threshold)
        case .hat:
            result = bandAnchors(mask: mask, box: box, level: .brim, band: 0.88...1.0, yFraction: 0.97, useMax: true, threshold: threshold)
        case .eyewear:
            result = bandAnchors(mask: mask, box: box, level: .eyes, band: 0.2...0.8, yFraction: 0.5, useMax: true, threshold: threshold)
        case .bag:
            result = boxAnchors(mask: mask, box: box, level: .handle, yFraction: 0)
        case .scarf:
            result = bandAnchors(mask: mask, box: box, level: .neck, band: 0...0.15, yFraction: 0.05, useMax: false, threshold: threshold)
        case .belt:
            result = boxAnchors(mask: mask, box: box, level: .waist, yFraction: 0.5)
        case .accessory:
            result = boxAnchors(mask: mask, box: box, level: .center, yFraction: 0.5)
        }
        return result.normalized
    }

    // MARK: - Upper body

    static func upperBody(category: GarmentCategory, mask: AlphaMask, box: PixelRect, pose: PoseJoints?, threshold: UInt8) -> GarmentAnchors {
        let w = Double(mask.width), h = Double(mask.height)
        let boxHeight = Double(box.height)
        let hemY = Double(box.maxY + 1) / h

        if let pose, let rawL = pose.shoulderL, let rawR = pose.shoulderR {
            let (pl, pr) = PoseJoints.ordered(rawL, rawR)
            if let l0 = pl, let r0 = pr {
                let span = r0 - l0
                let l = l0 - span * shoulderJointToSeamExpansion
                let r = r0 + span * shoulderJointToSeamExpansion
                let width = l.distance(to: r)
                let margin = Double(box.width) * 0.05
                let plausible = width >= Double(box.width) * 0.25 &&
                    Double(l.x) >= Double(box.minX) - margin && Double(r.x) <= Double(box.maxX + 1) + margin
                if plausible {
                    return GarmentAnchors(
                        left: CGPoint(x: Double(l.x) / w, y: Double(l.y) / h),
                        right: CGPoint(x: Double(r.x) / w, y: Double(r.y) / h),
                        hemY: hemY, fitsLength: false, level: .shoulders, source: .pose
                    )
                }
            }
        }

        let shoulderFraction: Double
        let torsoBand: ClosedRange<Double>
        let torsoFactor: Double
        switch category {
        case .dress:
            shoulderFraction = 0.05
            torsoBand = 0.20...0.30
            torsoFactor = 0.95
        case .outerwear:
            shoulderFraction = 0.08
            torsoBand = 0.40...0.60
            torsoFactor = 0.87
        default:
            shoulderFraction = 0.08
            torsoBand = 0.45...0.65
            torsoFactor = 0.87
        }

        // Candidate A: the shoulder band, only from rows that are mostly filled
        // (straps of a camisole are not shoulders).
        var shoulderWidths: [Double] = []
        let shoulderRows = rows(in: 0.06...0.13, of: box)
        for y in shoulderRows {
            guard let extent = mask.rowExtent(y, threshold: threshold) else { continue }
            if Double(extent.span) >= Double(box.width) * 0.25 && extent.fill >= 0.75 {
                shoulderWidths.append(Double(extent.span))
            }
        }
        let candidateA = shoulderWidths.count >= max(1, shoulderRows.count / 3) ? median(shoulderWidths) : nil

        // Candidate B: the torso width (the run that contains the centre line,
        // so sleeves hanging away from the body are ignored).
        var torsoWidths: [Double] = []
        var torsoCenters: [Double] = []
        let centerX = box.centerX + 0.5
        for y in rows(in: torsoBand, of: box) {
            let runs = mask.runs(inRow: y, threshold: threshold)
            guard !runs.isEmpty else { continue }
            let run = runs.min { a, b in
                distance(of: centerX, to: a) < distance(of: centerX, to: b)
            }!
            torsoWidths.append(Double(run.count))
            torsoCenters.append(Double(run.lowerBound + run.upperBound + 1) / 2)
        }
        let candidateB = median(torsoWidths).map { $0 * torsoFactor }

        var width: Double
        switch (candidateA, candidateB) {
        case let (a?, b?): width = min(a, b)
        case let (a?, nil): width = a
        case let (nil, b?): width = b
        case (nil, nil): width = Double(box.width) * 0.76
        }
        width = clamp(width, Double(box.width) * 0.3, Double(box.width))
        let cx = median(torsoCenters) ?? centerX
        let y = Double(box.minY) + shoulderFraction * boxHeight
        return GarmentAnchors(
            left: CGPoint(x: (cx - width / 2) / w, y: y / h),
            right: CGPoint(x: (cx + width / 2) / w, y: y / h),
            hemY: hemY, fitsLength: false, level: .shoulders, source: .shape
        )
    }

    // MARK: - Bottoms

    static func bottom(mask: AlphaMask, box: PixelRect, pose: PoseJoints?, threshold: UInt8) -> GarmentAnchors {
        let w = Double(mask.width), h = Double(mask.height)
        let boxHeight = Double(box.height)
        let hemPixel = Double(box.maxY + 1)

        var level = AnchorLevel.waist
        var lineY = Double(box.minY) + max(1, 0.02 * boxHeight)
        var band = rows(in: 0...0.04, of: box)
        var source = AnchorSource.shape

        if let pose, let hipL = pose.hipL, let hipR = pose.hipR {
            let hipY = (Double(hipL.y) + Double(hipR.y)) / 2
            // Use the hip line when the garment clearly spans it.
            if hipY > Double(box.minY) + 0.03 * boxHeight && hipY < Double(box.minY) + 0.45 * boxHeight {
                level = .hips
                lineY = hipY
                let half = max(1, Int(0.02 * boxHeight))
                let center = Int(hipY.rounded())
                band = Array(max(box.minY, center - half)...min(box.maxY, center + half))
                source = .pose
            }
        }

        var extents: [AlphaMask.RowExtent] = []
        for y in band {
            if let e = mask.rowExtent(y, threshold: threshold) { extents.append(e) }
        }
        let left: Double, right: Double
        if extents.isEmpty {
            left = Double(box.minX)
            right = Double(box.maxX + 1)
        } else {
            left = median(extents.map { Double($0.minX) })!
            right = median(extents.map { Double($0.maxX + 1) })!
        }
        let lineWidth = max(right - left, 1)

        var fitsLength: Bool
        if let pose, let ankleL = pose.ankleL, let ankleR = pose.ankleR {
            let ankleY = (Double(ankleL.y) + Double(ankleR.y)) / 2
            if let kneeL = pose.kneeL, let kneeR = pose.kneeR {
                let kneeY = (Double(kneeL.y) + Double(kneeR.y)) / 2
                fitsLength = hemPixel >= ankleY - 0.35 * max(ankleY - kneeY, 1)
            } else {
                fitsLength = hemPixel >= ankleY - 0.08 * boxHeight
            }
        } else {
            fitsLength = (hemPixel - lineY) / lineWidth >= fullLengthAspectRatio
        }
        if hemPixel - lineY < 2 { fitsLength = false }

        return GarmentAnchors(
            left: CGPoint(x: left / w, y: lineY / h),
            right: CGPoint(x: right / w, y: lineY / h),
            hemY: hemPixel / h, fitsLength: fitsLength, level: level, source: source
        )
    }

    // MARK: - Shoes

    static func shoes(mask: AlphaMask, threshold: UInt8) -> GarmentAnchors? {
        let (_, components) = mask.connectedComponents(threshold: threshold)
        guard let largest = components.first else { return nil }
        let kept = components.prefix(2).filter { Double($0.pixelCount) >= Double(largest.pixelCount) * 0.15 }
        guard var bounds = kept.first?.bounds else { return nil }
        for c in kept.dropFirst() { bounds = bounds.union(c.bounds) }
        let w = Double(mask.width), h = Double(mask.height)
        let y = Double(bounds.maxY + 1) / h
        return GarmentAnchors(
            left: CGPoint(x: Double(bounds.minX) / w, y: y),
            right: CGPoint(x: Double(bounds.maxX + 1) / w, y: y),
            hemY: y, fitsLength: false, level: .sole, source: .shape
        )
    }

    // MARK: - Generic

    static func bandAnchors(mask: AlphaMask, box: PixelRect, level: AnchorLevel, band: ClosedRange<Double> = 0...1, yFraction: Double, useMax: Bool, threshold: UInt8) -> GarmentAnchors {
        let w = Double(mask.width), h = Double(mask.height)
        var extents: [AlphaMask.RowExtent] = []
        for y in rows(in: band, of: box) {
            if let e = mask.rowExtent(y, threshold: threshold) { extents.append(e) }
        }
        var left = Double(box.minX), right = Double(box.maxX + 1)
        if !extents.isEmpty {
            if useMax {
                left = Double(extents.map(\.minX).min()!)
                right = Double(extents.map(\.maxX).max()! + 1)
            } else {
                left = median(extents.map { Double($0.minX) })!
                right = median(extents.map { Double($0.maxX + 1) })!
            }
        }
        let y = (Double(box.minY) + yFraction * Double(box.height)) / h
        return GarmentAnchors(left: CGPoint(x: left / w, y: y), right: CGPoint(x: right / w, y: y),
                              hemY: Double(box.maxY + 1) / h, fitsLength: false, level: level, source: .shape)
    }

    static func boxAnchors(mask: AlphaMask, box: PixelRect, level: AnchorLevel, yFraction: Double) -> GarmentAnchors {
        let w = Double(mask.width), h = Double(mask.height)
        let y = (Double(box.minY) + yFraction * Double(box.height)) / h
        return GarmentAnchors(left: CGPoint(x: Double(box.minX) / w, y: y),
                              right: CGPoint(x: Double(box.maxX + 1) / w, y: y),
                              hemY: Double(box.maxY + 1) / h, fitsLength: false, level: level, source: .shape)
    }

    // MARK: - Helpers

    /// Row indices covering a fractional band of the box (always at least one row).
    static func rows(in band: ClosedRange<Double>, of box: PixelRect) -> [Int] {
        let h = Double(box.height)
        let start = box.minY + Int((band.lowerBound * h).rounded(.down))
        let end = box.minY + Int((band.upperBound * h).rounded(.down))
        let lo = clamp(start, box.minY, box.maxY)
        let hi = clamp(max(end, lo), box.minY, box.maxY)
        return Array(lo...hi)
    }

    static func distance(of x: Double, to run: ClosedRange<Int>) -> Double {
        let lo = Double(run.lowerBound), hi = Double(run.upperBound + 1)
        if x < lo { return lo - x }
        if x > hi { return x - hi }
        return 0
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
