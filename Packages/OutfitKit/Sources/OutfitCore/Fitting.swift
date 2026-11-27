import Foundation

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
            return symmetric(avatar.headHalfWidth * 1.18, avatar.headHeight * 0.28)
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

        return Affine2D.translation(-Double(mid.x), -Double(mid.y))
            .concatenating(.rotation(-angle))
            .concatenating(.scale(sx, sy))
            .concatenating(.translation(target.midpoint))
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
public enum FaceFitter {
    /// Relative weights of left eye, right eye and chin in the fit.
    public static let weights: [Double] = [1, 1, 1.2]
    /// Rotation correction is limited so a bad landmark cannot spin the head.
    public static let maxRoll = Double.pi / 6

    /// Similarity transform (uniform scale, roll correction, translation)
    /// mapping the cut-out's pupils and chin onto the avatar's. Uniform scale
    /// keeps the face undistorted; least squares spreads any difference in face
    /// shape evenly between eyes and chin.
    public static func autoFit(face: FaceAsset, avatar: AvatarModel) -> Affine2D? {
        var eyeL = face.eyeLeft, eyeR = face.eyeRight
        if eyeL.x > eyeR.x { swap(&eyeL, &eyeR) }
        let source = [eyeL, eyeR, face.chin]
        guard source.allSatisfy(\.isFinite) else { return nil }
        let target = [avatar.eyeLeft, avatar.eyeRight, avatar.chin]
        guard var transform = PointFit.similarity(from: source, to: target, weights: weights, allowRotation: true) else {
            return nil
        }
        let roll = transform.rotationAngle
        if abs(roll) > maxRoll {
            // Keep the fitted scale (head size) but limit the rotation, and pin
            // the chin to the avatar's chin so the neck still connects.
            let linear = Affine2D.rotation(clamp(roll, -maxRoll, maxRoll)).concatenating(.scale(transform.meanScale))
            let mappedChin = linear.apply(face.chin)
            transform = linear.concatenating(.translation(avatar.chin - mappedChin))
        }
        return transform
    }

    /// Pivot for manual face adjustments: the midpoint between the avatar's eyes.
    public static func pivot(avatar: AvatarModel) -> CGPoint {
        .midpoint(avatar.eyeLeft, avatar.eyeRight)
    }

    public static func placement(face: FaceAsset, avatar: AvatarModel) -> Affine2D? {
        guard let fit = autoFit(face: face, avatar: avatar) else { return nil }
        return GarmentFitter.apply(face.adjustment, to: fit, pivot: pivot(avatar: avatar))
    }

    /// Head height in body units implied by a placement, using the canonical
    /// eye-line-at-mid-head rule (eye→chin distance is half the head height).
    public static func impliedHeadHeight(face: FaceAsset, placement: Affine2D) -> Double {
        let eyeMid = placement.apply(.midpoint(face.eyeLeft, face.eyeRight))
        let chin = placement.apply(face.chin)
        return eyeMid.distance(to: chin) / Anthropometry.eyeLineFraction
    }
}
