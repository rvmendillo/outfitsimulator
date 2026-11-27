import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Silhouette family used for the avatar body. Only widths differ; vertical
/// proportions come from stature.
public enum BodyShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case feminine
    case masculine
    case neutral

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .feminine: return "Feminine"
        case .masculine: return "Masculine"
        case .neutral: return "Neutral"
        }
    }
}

/// The user's body settings. Everything else about the avatar is derived.
public struct BodyProfile: Codable, Equatable, Sendable {
    public var heightCM: Double
    public var shape: BodyShape
    /// Width multiplier for torso and limbs (slim < 1 < broad).
    public var build: Double
    /// Overrides the skin tone sampled from the face photo.
    public var skinToneOverride: RGBColor?
    public var showArms: Bool
    /// Neutral base layer (tank + briefs) drawn under clothes.
    public var showBaseLayer: Bool

    public static let heightRange: ClosedRange<Double> = 120...220
    public static let buildRange: ClosedRange<Double> = 0.85...1.25
    public static let defaultSkinTone = RGBColor(hex: "#D9A784")!

    public init(
        heightCM: Double = 170,
        shape: BodyShape = .neutral,
        build: Double = 1.0,
        skinToneOverride: RGBColor? = nil,
        showArms: Bool = true,
        showBaseLayer: Bool = true
    ) {
        self.heightCM = heightCM
        self.shape = shape
        self.build = build
        self.skinToneOverride = skinToneOverride
        self.showArms = showArms
        self.showBaseLayer = showBaseLayer
    }

    /// A copy with every value forced into its valid range.
    public var sanitized: BodyProfile {
        var copy = self
        copy.heightCM = heightCM.isFinite ? clamp(heightCM, Self.heightRange.lowerBound, Self.heightRange.upperBound) : 170
        copy.build = build.isFinite ? clamp(build, Self.buildRange.lowerBound, Self.buildRange.upperBound) : 1
        return copy
    }
}

/// Anthropometric reference data.
///
/// Vertical landmarks follow the classic Drillis & Contini segment proportions
/// (as tabulated in Winter, *Biomechanics and Motor Control of Human Movement*),
/// expressed here as distance from the top of the head in units of stature.
/// Head height scales allometrically with stature, so shorter people have
/// proportionally larger heads (fewer "heads tall") and taller people smaller.
public enum Anthropometry {
    /// Reference stature for the standard proportions (cm).
    public static let referenceStatureCM = 175.0
    /// Vertex-to-menton head height at the reference stature (cm), = 0.130 × 175.
    public static let referenceHeadHeightCM = 22.75
    /// Allometric exponent: head height grows slower than stature.
    public static let headAllometryExponent = 0.4

    /// Standard landmark depths (from the top of the head, fraction of stature).
    public enum Standard {
        public static let chin = 0.130
        public static let neckBase = 0.165
        public static let shoulder = 0.182
        public static let armpit = 0.245
        public static let chest = 0.280
        public static let waist = 0.375
        public static let trouserWaist = 0.405
        public static let hip = 0.470
        public static let crotch = 0.525
        public static let knee = 0.715
        public static let calf = 0.800
        public static let ankle = 0.961
        public static let upperArmLength = 0.186
        public static let forearmLength = 0.146
        public static let handLength = 0.108
    }

    /// Eyes sit at the vertical midpoint of the head (vertex to chin).
    public static let eyeLineFraction = 0.5
    /// Interpupillary distance as a fraction of head height (63 mm / 227 mm).
    public static let interpupillaryToHeadHeight = 0.2775
    /// Head breadth as a fraction of head height.
    public static let headBreadthToHeadHeight = 0.66

    public static func headHeightCM(forStatureCM stature: Double) -> Double {
        referenceHeadHeightCM * pow(stature / referenceStatureCM, headAllometryExponent)
    }

    /// Head height as a fraction of stature.
    public static func headRatio(forStatureCM stature: Double) -> Double {
        headHeightCM(forStatureCM: stature) / stature
    }

    /// How many head heights fit in the stature ("heads tall").
    public static func headsTall(forStatureCM stature: Double) -> Double {
        1 / headRatio(forStatureCM: stature)
    }

    /// Half-widths (fraction of stature) per body shape, before `build`.
    struct Widths {
        var neck: Double
        var shoulder: Double
        var chest: Double
        var waist: Double
        var hip: Double
        var thigh: Double
        var knee: Double
        var calf: Double
        var ankle: Double
        var upperArm: Double
        var forearm: Double
        var wrist: Double
        var hand: Double
    }

    static func widths(for shape: BodyShape) -> Widths {
        switch shape {
        case .masculine:
            return Widths(neck: 0.034, shoulder: 0.1325, chest: 0.095, waist: 0.083, hip: 0.095,
                          thigh: 0.047, knee: 0.028, calf: 0.031, ankle: 0.018,
                          upperArm: 0.024, forearm: 0.021, wrist: 0.015, hand: 0.02)
        case .feminine:
            return Widths(neck: 0.029, shoulder: 0.1225, chest: 0.088, waist: 0.078, hip: 0.106,
                          thigh: 0.05, knee: 0.027, calf: 0.03, ankle: 0.016,
                          upperArm: 0.021, forearm: 0.019, wrist: 0.013, hand: 0.018)
        case .neutral:
            return Widths(neck: 0.0315, shoulder: 0.1275, chest: 0.0915, waist: 0.0805, hip: 0.1005,
                          thigh: 0.0485, knee: 0.0275, calf: 0.0305, ankle: 0.017,
                          upperArm: 0.0225, forearm: 0.02, wrist: 0.014, hand: 0.019)
        }
    }
}

/// The avatar's geometry in *body space*: x = 0 is the body's centre line
/// (positive to the viewer's right), y = 0 is the top of the head and y = 1
/// the floor. One unit equals the user's stature, so every proportion here is
/// relative to their real height.
public struct AvatarModel: Equatable, Sendable {
    public let profile: BodyProfile

    // Vertical landmarks (depth from the top of the head).
    public let headHeight: Double
    public let eyeY: Double
    public let chinY: Double
    public let neckBaseY: Double
    public let shoulderY: Double
    public let armpitY: Double
    public let chestY: Double
    public let waistY: Double
    public let trouserWaistY: Double
    public let hipY: Double
    public let crotchY: Double
    public let kneeY: Double
    public let calfY: Double
    public let ankleY: Double
    public let floorY: Double = 1

    // Half-widths.
    public let headHalfWidth: Double
    public let neckHalfWidth: Double
    public let shoulderHalfWidth: Double
    public let chestHalfWidth: Double
    public let waistHalfWidth: Double
    public let hipHalfWidth: Double
    public let thighHalfWidth: Double
    public let kneeHalfWidth: Double
    public let calfHalfWidth: Double
    public let ankleHalfWidth: Double
    public let footHalfWidth: Double
    public let upperArmHalfWidth: Double
    public let forearmHalfWidth: Double
    public let wristHalfWidth: Double
    public let handHalfWidth: Double

    /// x of each leg's axis (the right leg is at +legX).
    public let kneeX: Double
    public let ankleX: Double
    public let interpupillaryDistance: Double

    // Right arm joints (viewer's right, +x). The left arm mirrors them.
    public let shoulderJoint: CGPoint
    public let elbow: CGPoint
    public let wrist: CGPoint
    public let fingertip: CGPoint

    public init(profile rawProfile: BodyProfile) {
        let profile = rawProfile.sanitized
        self.profile = profile

        let r = Anthropometry.headRatio(forStatureCM: profile.heightCM)
        headHeight = r
        eyeY = r * Anthropometry.eyeLineFraction
        chinY = r

        // Below the chin the standard proportions are rescaled so that the chin
        // moves with the head ratio while the floor stays at 1.
        let k = (1 - r) / (1 - Anthropometry.Standard.chin)
        func remap(_ standardY: Double) -> Double {
            r + (standardY - Anthropometry.Standard.chin) * k
        }
        neckBaseY = remap(Anthropometry.Standard.neckBase)
        shoulderY = remap(Anthropometry.Standard.shoulder)
        armpitY = remap(Anthropometry.Standard.armpit)
        chestY = remap(Anthropometry.Standard.chest)
        waistY = remap(Anthropometry.Standard.waist)
        trouserWaistY = remap(Anthropometry.Standard.trouserWaist)
        hipY = remap(Anthropometry.Standard.hip)
        crotchY = remap(Anthropometry.Standard.crotch)
        kneeY = remap(Anthropometry.Standard.knee)
        calfY = remap(Anthropometry.Standard.calf)
        ankleY = remap(Anthropometry.Standard.ankle)

        let w = Anthropometry.widths(for: profile.shape)
        let build = profile.build
        // Bone widths (shoulders, head) change less with build than soft tissue.
        let boneBuild = 1 + (build - 1) * 0.4
        headHalfWidth = r * Anthropometry.headBreadthToHeadHeight / 2
        neckHalfWidth = w.neck * (1 + (build - 1) * 0.6)
        shoulderHalfWidth = w.shoulder * boneBuild
        chestHalfWidth = w.chest * build
        waistHalfWidth = w.waist * build
        hipHalfWidth = w.hip * build
        thighHalfWidth = w.thigh * build
        kneeHalfWidth = w.knee * (1 + (build - 1) * 0.7)
        calfHalfWidth = w.calf * build
        ankleHalfWidth = w.ankle * boneBuild
        footHalfWidth = 0.03 * boneBuild
        upperArmHalfWidth = w.upperArm * build
        forearmHalfWidth = w.forearm * build
        wristHalfWidth = w.wrist * boneBuild
        handHalfWidth = w.hand * boneBuild

        kneeX = max(0.045, hipHalfWidth - thighHalfWidth) * 0.96
        ankleX = kneeX + 0.003
        interpupillaryDistance = r * Anthropometry.interpupillaryToHeadHeight

        // Arms hang in a relaxed A-pose.
        let upperArmAngle = 9.0 * Double.pi / 180
        let forearmAngle = 12.0 * Double.pi / 180
        let shoulderJointPoint = CGPoint(x: shoulderHalfWidth - upperArmHalfWidth, y: shoulderY + 0.012)
        let elbowPoint = shoulderJointPoint + CGPoint(x: sin(upperArmAngle), y: cos(upperArmAngle)) * (Anthropometry.Standard.upperArmLength * k)
        let wristPoint = elbowPoint + CGPoint(x: sin(forearmAngle), y: cos(forearmAngle)) * (Anthropometry.Standard.forearmLength * k)
        let tipPoint = wristPoint + CGPoint(x: sin(forearmAngle), y: cos(forearmAngle)) * (Anthropometry.Standard.handLength * k)
        shoulderJoint = shoulderJointPoint
        elbow = elbowPoint
        wrist = wristPoint
        fingertip = tipPoint
    }

    // MARK: Derived landmarks

    public var headsTall: Double { 1 / headHeight }

    /// Pupils (image-left first).
    public var eyeLeft: CGPoint { CGPoint(x: -interpupillaryDistance / 2, y: eyeY) }
    public var eyeRight: CGPoint { CGPoint(x: interpupillaryDistance / 2, y: eyeY) }
    public var chin: CGPoint { CGPoint(x: 0, y: chinY) }

    /// Outer feet edges, used to place shoes.
    public var feetOuterHalfSpan: Double { ankleX + footHalfWidth + 0.006 }

    /// Torso half-width at a given depth (between the neck base and the crotch),
    /// interpolated through the body's key widths.
    public func torsoHalfWidth(atY y: Double) -> Double {
        let profilePoints: [(y: Double, w: Double)] = [
            (neckBaseY, neckHalfWidth * 1.08),
            (shoulderY, shoulderHalfWidth),
            (armpitY, chestHalfWidth),
            (chestY, chestHalfWidth),
            (waistY, waistHalfWidth),
            (hipY, hipHalfWidth),
            (crotchY, hipHalfWidth * 0.96),
        ]
        if y <= profilePoints[0].y { return profilePoints[0].w }
        for i in 1..<profilePoints.count {
            let p0 = profilePoints[i - 1], p1 = profilePoints[i]
            if y <= p1.y {
                let t = (y - p0.y) / max(p1.y - p0.y, 1e-9)
                return lerp(p0.w, p1.w, t)
            }
        }
        return profilePoints[profilePoints.count - 1].w
    }

    /// Body-space height of the avatar in centimetres per unit (for display).
    public var centimetresPerUnit: Double { profile.heightCM }
}
