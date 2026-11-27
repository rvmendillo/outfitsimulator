import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where a garment's width line (and optionally hem) must land on the avatar.
public struct FitTarget: Equatable, Sendable {
    public var left: CGPoint
    public var right: CGPoint
    /// Body-space depth the hem should reach when the garment fits by length.
    public var hemY: Double?

    public init(left: CGPoint, right: CGPoint, hemY: Double? = nil) {
        self.left = left
        self.right = right
        self.hemY = hemY
    }

    public var midpoint: CGPoint { .midpoint(left, right) }
    public var width: Double { Double(right.x - left.x) }
}

/// Places garment cut-outs on the avatar so that their real-world proportions
/// line up with the body (shoulders on shoulders, waistband on the waist, hems
/// at the ankles, soles on the floor).
public enum GarmentFitter {
    /// Largest allowed ratio between horizontal and vertical scale when a garment
    /// is fitted by both width and length. Keeps garments from looking stretched.
    public static let maxAnisotropy = 1.15
    /// Width lines tilted by more than this are not fully levelled.
    public static let maxLevelingAngle = Double.pi / 12

    /// Looser than the body so flat-lay garments (which show half the
    /// circumference) do not look shrink-wrapped.
    public static let bottomEase = 1.10

    public static func target(for category: GarmentCategory, level: AnchorLevel, avatar: AvatarModel) -> FitTarget {
        func symmetric(_ halfWidth: Double, _ y: Double, hemY: Double? = nil) -> FitTarget {
            FitTarget(left: CGPoint(x: -halfWidth, y: y), right: CGPoint(x: halfWidth, y: y), hemY: hemY)
        }
        let ankleHem = avatar.ankleY + 0.008
        switch level {
        case .shoulders:
            let factor: Double
            switch category {
            case .outerwear: factor = 1.06
            default: factor = 1.0
            }
            return symmetric(avatar.shoulderHalfWidth * factor, avatar.shoulderY)
        case .waist:
            let y = avatar.trouserWaistY
            let ease = category == .belt ? 1.04 : bottomEase
            return symmetric(avatar.torsoHalfWidth(atY: y) * ease, y, hemY: ankleHem)
        case .hips:
            return symmetric(avatar.hipHalfWidth * 1.06, avatar.hipY, hemY: ankleHem)
        case .sole:
            return symmetric(avatar.feetOuterHalfSpan, avatar.floorY)
        case .brim:
            return symmetric(avatar.headHalfWidth * 1.35, avatar.headHeight * 0.28)
        case .eyes:
            return symmetric(avatar.headHalfWidth * 1.02, avatar.eyeY)
        case .handle:
            let center = Double(avatar.wrist.x) + 0.012
            let halfWidth = 0.07
            let y = Double(avatar.wrist.y) - 0.01
            return FitTarget(left: CGPoint(x: center - halfWidth, y: y), right: CGPoint(x: center + halfWidth, y: y))
        case .neck:
            return symmetric(avatar.neckHalfWidth * 2.4, avatar.chinY + 0.025)
        case .center:
            return symmetric(0.03, avatar.chestY)
        }
    }

    /// Automatic placement: maps cut-out *pixel* coordinates to body space.
    public static func autoFit(anchors rawAnchors: GarmentAnchors, imageSize: CGSize, category: GarmentCategory, avatar: AvatarModel) -> Affine2D {
        let anchors = rawAnchors.normalized
        let width = max(Double(imageSize.width), 1)
        let height = max(Double(imageSize.height), 1)
        let target = target(for: category, level: anchors.level, avatar: avatar)

        let left = CGPoint(x: Double(anchors.left.x) * width, y: Double(anchors.left.y) * height)
        let right = CGPoint(x: Double(anchors.right.x) * width, y: Double(anchors.right.y) * height)
        let mid = CGPoint.midpoint(left, right)

        var angle = atan2(Double(right.y - left.y), Double(right.x - left.x))
        angle = clamp(angle, -maxLevelingAngle, maxLevelingAngle)

        let sourceWidth = max(left.distance(to: right), 1)
        let targetWidth = max(target.width, 1e-6)
        let widthScale = targetWidth / sourceWidth
        var sx = widthScale
        var sy = widthScale

        if anchors.fitsLength, let hemTarget = target.hemY {
            let sourceLength = anchors.hemY * height - Double(mid.y)
            let targetLength = hemTarget - Double(target.midpoint.y)
            if sourceLength > 1, targetLength > 0 {
                let lengthScale = targetLength / sourceLength
                sy = lengthScale
                sx = clamp(widthScale, lengthScale / maxAnisotropy, lengthScale * maxAnisotropy)
            }
        }

        // Accessories cut from a photo of a person keep their size relative to
        // that person (a hat relative to the head, shoes to the body).
        if var s = referenceScale(anchors: anchors, category: category, avatar: avatar) {
            if category == .hat || category == .eyewear {
                // Head measurements in outfit photos (sunglasses, beards, turned
                // heads) can be off; let them adjust the anthropometric default
                // by at most -25%/+50%.
                s = clamp(s, widthScale * 0.75, widthScale * 1.5)
            }
            sx = s
            sy = s
        }

        // Plausibility: never let a bad measurement blow a piece up.
        let limits = maximumSize(for: category)
        let shrink = min(1, limits.width / max(sx * width, 1e-9), limits.height / max(sy * height, 1e-9))
        sx *= shrink
        sy *= shrink

        return Affine2D.translation(-Double(mid.x), -Double(mid.y))
            .concatenating(.rotation(-angle))
            .concatenating(.scale(sx, sy))
            .concatenating(.translation(target.midpoint))
    }

    /// Uniform scale from the source photo's person, when known.
    static func referenceScale(anchors: GarmentAnchors, category: GarmentCategory, avatar: AvatarModel) -> Double? {
        switch category {
        case .hat, .eyewear:
            guard let head = anchors.sourceHeadHeight else { return nil }
            return avatar.headHeight / head
        case .shoes, .bag, .belt, .scarf, .accessory:
            guard let shoulders = anchors.sourceShoulderWidth else { return nil }
            return 2 * avatar.shoulderHalfWidth / shoulders
        case .top, .outerwear, .dress, .bottom:
            return nil
        }
    }

    /// Largest plausible size (width, height) of a piece, in units of stature.
    public static func maximumSize(for category: GarmentCategory) -> (width: Double, height: Double) {
        switch category {
        case .top: return (1.1, 0.6)
        case .outerwear: return (1.1, 0.85)
        case .dress: return (1.1, 0.95)
        case .bottom: return (0.7, 0.72)
        case .shoes: return (0.45, 0.22)
        case .hat: return (0.28, 0.24)
        case .eyewear: return (0.14, 0.08)
        case .bag: return (0.4, 0.5)
        case .scarf: return (0.5, 0.6)
        case .belt: return (0.4, 0.1)
        case .accessory: return (0.3, 0.3)
        }
    }

    /// The body-space point a garment's manual adjustment pivots around.
    public static func pivot(for anchors: GarmentAnchors, category: GarmentCategory, avatar: AvatarModel) -> CGPoint {
        target(for: category, level: anchors.normalized.level, avatar: avatar).midpoint
    }

    /// Applies a manual adjustment (scale/rotate about `pivot`, then offset).
    public static func apply(_ adjustment: ItemAdjustment, to transform: Affine2D, pivot: CGPoint) -> Affine2D {
        let adj = adjustment.sanitized
        if adj.isIdentity { return transform }
        return transform
            .concatenating(.translation(-Double(pivot.x), -Double(pivot.y)))
            .concatenating(.scale(adj.scale))
            .concatenating(.rotation(adj.rotation))
            .concatenating(.translation(pivot + adj.offset))
    }

    /// Final transform for a garment in an outfit.
    public static func placement(for garment: Garment, adjustment: ItemAdjustment, avatar: AvatarModel) -> Affine2D {
        let fit = autoFit(anchors: garment.anchors, imageSize: garment.imageSize, category: garment.category, avatar: avatar)
        let pivot = pivot(for: garment.anchors, category: garment.category, avatar: avatar)
        return apply(adjustment, to: fit, pivot: pivot)
    }
}

/// Aligns the user's head cut-out with the avatar.
///
/// * Rotation levels the eye line exactly (corrects head roll).
/// * Scale makes the eye-to-chin height (measured perpendicular to the eye
///   line, so it is insensitive to roll and to turning the head) equal half
///   the avatar's head height — the canonical "eyes at mid-head" rule — and,
///   for front-facing photos, also takes the interpupillary distance into
///   account. Scale is uniform, so the face is never distorted.
/// * Translation pins the chin onto the avatar's chin so the neck connects.
public enum FaceFitter {
    /// Weight of the eye-to-chin height versus the pupil distance when
    /// estimating scale (geometric weighting).
    public static let verticalWeight = 0.65
    /// Above this head turn the pupil distance is foreshortened, so only the
    /// eye-to-chin height is used.
    public static let yawLimitForIPD = 12.0
    /// Rotation correction is limited so a bad landmark cannot spin the head.
    public static let maxRoll = Double.pi / 6

    public static func autoFit(face: FaceAsset, avatar: AvatarModel) -> Affine2D? {
        var eyeL = face.eyeLeft, eyeR = face.eyeRight
        if eyeL.x > eyeR.x { swap(&eyeL, &eyeR) }
        let chin = face.chin
        guard eyeL.isFinite, eyeR.isFinite, chin.isFinite else { return nil }

        let eyeVector = eyeR - eyeL
        let ipd = eyeVector.length
        guard ipd > 1e-6 else { return nil }
        let tilt = atan2(Double(eyeVector.y), Double(eyeVector.x))
        let eyeMid = CGPoint.midpoint(eyeL, eyeR)
        // Distance from the eye line to the chin, perpendicular to the eye line.
        let down = CGPoint(x: -Double(eyeVector.y) / ipd, y: Double(eyeVector.x) / ipd)
        let toChin = chin - eyeMid
        let eyeToChin = Double(toChin.x) * Double(down.x) + Double(toChin.y) * Double(down.y)
        guard eyeToChin > 1e-6 else { return nil }

        let verticalScale = (avatar.chinY - avatar.eyeY) / eyeToChin
        let horizontalScale = avatar.interpupillaryDistance / ipd
        // Foreshortening only ever shrinks a measured distance. A pupil distance
        // that is small for the face (head turned) must not enlarge the head, so
        // it is used only when it argues for a smaller head (e.g. the eye-to-chin
        // height was foreshortened by looking up or down).
        let turned = abs(face.yawDegrees ?? 0) > yawLimitForIPD
        let w = (turned || horizontalScale >= verticalScale) ? 1.0 : verticalWeight
        let scale = exp(w * log(verticalScale) + (1 - w) * log(horizontalScale))
        guard scale.isFinite, scale > 0 else { return nil }

        let rotation = clamp(-tilt, -maxRoll, maxRoll)
        let linear = Affine2D.rotation(rotation).concatenating(.scale(scale))
        let transform = linear.concatenating(.translation(avatar.chin - linear.apply(chin)))
        return transform.isInvertible ? transform : nil
    }

    /// Pivot for manual face adjustments: the midpoint between the avatar's eyes.
    public static func pivot(avatar: AvatarModel) -> CGPoint {
        .midpoint(avatar.eyeLeft, avatar.eyeRight)
    }

    public static func placement(face: FaceAsset, avatar: AvatarModel) -> Affine2D? {
        guard let fit = autoFit(face: face, avatar: avatar) else { return nil }
        return GarmentFitter.apply(face.adjustment, to: fit, pivot: pivot(avatar: avatar))
    }

    /// Head height in body units implied by a placement: twice the eye-to-chin
    /// height measured perpendicular to the placed eye line.
    public static func impliedHeadHeight(face: FaceAsset, placement: Affine2D) -> Double {
        let l = placement.apply(face.eyeLeft), r = placement.apply(face.eyeRight)
        let chin = placement.apply(face.chin)
        let v = r - l
        let len = max(v.length, 1e-12)
        let sign: Double = v.x >= 0 ? 1 : -1
        let down = CGPoint(x: -Double(v.y) / len * sign, y: Double(v.x) / len * sign)
        let toChin = chin - CGPoint.midpoint(l, r)
        let height = Double(toChin.x) * Double(down.x) + Double(toChin.y) * Double(down.y)
        return height / Anthropometry.eyeLineFraction
    }
}
