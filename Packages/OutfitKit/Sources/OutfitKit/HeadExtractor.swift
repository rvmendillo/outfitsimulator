#if canImport(Vision) && canImport(CoreML)
import CoreGraphics
import Foundation

public enum HeadWarning: Equatable, Sendable {
    /// Head turned sideways (degrees).
    case turned(Double)
    /// Head tilted up or down (degrees).
    case tiltedUpDown(Double)
    /// The face is small in the photo, so the cut-out will look soft.
    case lowResolution
    /// More than one face; the largest was used.
    case multipleFaces

    public var message: String {
        switch self {
        case let .turned(deg):
            return "Your head is turned about \(Int(deg.rounded()))°. A straight-on photo lines up best."
        case let .tiltedUpDown(deg):
            return "Your head is tilted about \(Int(deg.rounded()))°. Look straight at the camera for the best fit."
        case .lowResolution:
            return "The face is small in this photo. Use a closer photo for a sharper result."
        case .multipleFaces:
            return "Several faces were found; the largest one was used."
        }
    }
}

public enum HeadExtractionError: Error, LocalizedError, Equatable {
    case noFace
    case segmentationFailed

    public var errorDescription: String? {
        switch self {
        case .noFace: return "No face was found. Try a well-lit, front-facing photo."
        case .segmentationFailed: return "The head could not be separated from the background. Try a photo with a plainer background."
        }
    }
}

/// The user's head, cut out, with the landmarks used to align it.
public struct HeadCutout: @unchecked Sendable {
    public var image: RGBABitmap
    public var eyeLeft: CGPoint
    public var eyeRight: CGPoint
    public var chin: CGPoint
    public var skinTone: RGBColor
    public var yawDegrees: Double?
    public var rollDegrees: Double?
    public var pitchDegrees: Double?
    public var warnings: [HeadWarning]

    public var size: CGSize { CGSize(width: image.width, height: image.height) }
}

/// Cuts the head (face, hair, and a short neck stub that blends into the
/// avatar's neck) out of a selfie.
public final class HeadExtractor: @unchecked Sendable {
    public let parser: ClothingParser?
    public var workingMaxSide = 1600
    public static let turnedWarningDegrees = 20.0
    public static let tiltWarningDegrees = 20.0

    public init(parser: ClothingParser?) {
        self.parser = parser
    }

    public func extract(from input: CGImage) throws -> HeadCutout {
        let image = ImageCodec.downscaled(input, maxSide: workingMaxSide)
        guard let bitmap = RGBABitmap(cgImage: image) else { throw ImageError.contextFailed }
        guard let face = try FaceAnalyzer.detect(in: image) else { throw HeadExtractionError.noFace }
        let w = image.width, h = image.height

        let eyeMid = face.eyeMidpoint
        let eyeToChin = max(face.eyeToChin, 4)
        let headHeight = 2 * eyeToChin / (2 * Anthropometry.eyeLineFraction)
        let labelMap = try? parser?.parse(image)
        let matte = try? PersonSegmenter.matte(for: image)

        // Skin tone first: it also filters the neck stub.
        let faceLabelMask: AlphaMask? = labelMap.map { $0.mask(for: [.face], width: w, height: h) }
        let skinTone = Self.sampleSkin(bitmap: bitmap, face: face, faceMask: faceLabelMask) ?? BodyProfile.defaultSkinTone

        // Region that can contain the head (generous, for long hair).
        let roi = CGRect(x: Double(eyeMid.x) - 1.5 * headHeight, y: Double(eyeMid.y) - 1.1 * headHeight,
                         width: 3 * headHeight, height: 2.9 * headHeight)
        let neckFadeStart = Double(face.chin.y) + 0.05 * headHeight
        let neckFadeEnd = Double(face.chin.y) + 0.28 * headHeight

        var head: AlphaMask
        var usedParser = false
        if let labelMap {
            let parsed = labelMap.mask(for: [.hair, .face, .hat, .sunglasses], width: w, height: h)
            // Trust the parser only if it found the detected face.
            if Self.overlap(of: parsed, with: face.boundingBox) >= 0.35 {
                head = parsed
                usedParser = true
            } else {
                head = AlphaMask(width: w, height: h)
            }
        } else {
            head = AlphaMask(width: w, height: h)
        }
        if !usedParser {
            guard let matte else { throw HeadExtractionError.segmentationFailed }
            head = matte
        }

        // Clip: inside the ROI; below the chin only hair survives (when parsed)
        // and the neck stub fades out.
        let hairMask: AlphaMask? = usedParser ? labelMap?.mask(for: [.hair], width: w, height: h) : nil
        for y in 0..<h {
            let fy = Double(y) + 0.5
            for x in 0..<w {
                let i = y * w + x
                let fx = Double(x) + 0.5
                if !roi.contains(CGPoint(x: fx, y: fy)) {
                    head.values[i] = 0
                    continue
                }
                if fy > neckFadeStart {
                    let isHair = (hairMask?.values[i] ?? 0) >= 128
                    if !isHair { head.values[i] = 0 }
                }
            }
        }

        // Neck stub: skin-coloured pixels just under the chin, fading out.
        let neckHalfWidth = 0.24 * headHeight
        let stubTop = max(0, Int(Double(face.chin.y) - 0.1 * headHeight))
        let stubBottom = min(h - 1, Int(neckFadeEnd.rounded(.up)))
        let skinLab = skinTone.lab
        if stubTop <= stubBottom {
            for y in stubTop...stubBottom {
                let fy = Double(y) + 0.5
                let fade = fy <= neckFadeStart ? 1.0 : max(0, 1 - (fy - neckFadeStart) / max(neckFadeEnd - neckFadeStart, 1))
                let minX = max(0, Int(Double(face.chin.x) - neckHalfWidth)), maxX = min(w - 1, Int(Double(face.chin.x) + neckHalfWidth))
                guard minX <= maxX else { continue }
                for x in minX...maxX {
                    guard let c = bitmap.color(x: x, y: y) else { continue }
                    let d = c.lab.distance(to: skinLab)
                    let skinWeight = max(0, min(1, 1 - (d - 16) / 22))
                    var a = fade * skinWeight
                    if let matte { a *= Double(matte[x, y]) / 255 }
                    let i = y * w + x
                    head.values[i] = max(head.values[i], UInt8(max(0, min(255, (a * 255).rounded()))))
                }
            }
        }

        // Crisp outer edges from the person matte (hair strands, ears).
        if usedParser, let matte {
            let refined = head.multiplied(by: matte)
            if Double(refined.setCount()) >= 0.6 * Double(head.setCount()) {
                head = refined
            }
        }
        head = head.keepingLargestComponents(maxCount: 2, minRelativeArea: 0.05).fillingHoles(maxHoleFraction: 0.03)
        guard let box = head.boundingBox(threshold: 60), box.width > 8, box.height > 8 else {
            throw HeadExtractionError.segmentationFailed
        }
        // The face itself must be inside the cut-out.
        guard head[clampInt(Int(eyeMid.x), 0, w - 1), clampInt(Int(eyeMid.y), 0, h - 1)] >= 128 else {
            throw HeadExtractionError.segmentationFailed
        }

        let pad = max(4, Int(Double(max(box.width, box.height)) * 0.04))
        let crop = box.expanded(by: pad, clampedToWidth: w, height: h)
        let origin = CGPoint(x: crop.minX, y: crop.minY)
        let cutout = CutoutComposer.compose(source: bitmap.cropped(to: crop), mask: head.cropped(to: crop))

        var warnings: [HeadWarning] = []
        let yaw = face.yaw.map { abs($0) * 180 / .pi }
        let pitch = face.pitch.map { abs($0) * 180 / .pi }
        if let yaw, yaw > Self.turnedWarningDegrees { warnings.append(.turned(yaw)) }
        if let pitch, pitch > Self.tiltWarningDegrees { warnings.append(.tiltedUpDown(pitch)) }
        if face.interpupillaryDistance < 40 { warnings.append(.lowResolution) }
        if face.faceCount > 1 { warnings.append(.multipleFaces) }

        return HeadCutout(
            image: cutout,
            eyeLeft: face.eyeLeft - origin,
            eyeRight: face.eyeRight - origin,
            chin: face.chin - origin,
            skinTone: skinTone,
            yawDegrees: face.yaw.map { $0 * 180 / .pi },
            rollDegrees: face.roll.map { $0 * 180 / .pi },
            pitchDegrees: face.pitch.map { $0 * 180 / .pi },
            warnings: warnings
        )
    }

    /// Fraction of `rect` covered by `mask`.
    static func overlap(of mask: AlphaMask, with rect: CGRect) -> Double {
        let minX = max(0, Int(rect.minX)), maxX = min(mask.width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY)), maxY = min(mask.height - 1, Int(rect.maxY))
        guard minX < maxX, minY < maxY else { return 0 }
        var set = 0, total = 0
        for y in stride(from: minY, through: maxY, by: 2) {
            for x in stride(from: minX, through: maxX, by: 2) {
                total += 1
                if mask[x, y] >= 128 { set += 1 }
            }
        }
        return total > 0 ? Double(set) / Double(total) : 0
    }

    /// Median colour of the cheeks (below the eyes, beside the nose).
    static func sampleSkin(bitmap: RGBABitmap, face: FaceLandmarks, faceMask: AlphaMask?) -> RGBColor? {
        let ipd = max(face.interpupillaryDistance, 6)
        let cheekY = Double(face.eyeMidpoint.y) + 0.42 * face.eyeToChin
        let radius = 0.2 * ipd
        var samples: [RGBColor] = []
        for eye in [face.eyeLeft, face.eyeRight] {
            let cx = Double(eye.x)
            let minX = max(0, Int(cx - radius)), maxX = min(bitmap.width - 1, Int(cx + radius))
            let minY = max(0, Int(cheekY - radius)), maxY = min(bitmap.height - 1, Int(cheekY + radius))
            guard minX <= maxX, minY <= maxY else { continue }
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = Double(x) - cx, dy = Double(y) - cheekY
                    guard dx * dx + dy * dy <= radius * radius else { continue }
                    if let faceMask, faceMask[x, y] < 128 { continue }
                    if let c = bitmap.color(x: x, y: y) { samples.append(c) }
                }
            }
        }
        guard samples.count >= 8 else { return nil }
        // Drop the darkest and brightest quarter (shadows, highlights).
        let sorted = samples.sorted { $0.relativeLuminance < $1.relativeLuminance }
        let trimmed = Array(sorted[(sorted.count / 4)..<(sorted.count * 3 / 4)])
        return ColorPalette.medianColor(trimmed.isEmpty ? sorted : trimmed)
    }
}

@inline(__always)
func clampInt(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
#endif
