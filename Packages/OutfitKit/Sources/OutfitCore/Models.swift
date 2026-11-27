import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where a garment's anchors came from.
public enum AnchorSource: String, Codable, Sendable {
    /// Derived from body-pose joints detected in the source photo.
    case pose
    /// Estimated from the cut-out's shape.
    case shape
    /// Placed by the user in the fit-guide editor.
    case user
}

/// Fit guides for a garment cut-out, in normalised image coordinates
/// (0...1, origin top-left).
///
/// The *width line* (`left` → `right`) is aligned with the body landmark named
/// by `level` (e.g. the shoulder seams with the avatar's shoulders). When
/// `fitsLength` is true the hem (`hemY`) is also aligned with the body (e.g.
/// full-length trousers end at the ankle).
public struct GarmentAnchors: Codable, Equatable, Sendable {
    public var left: CGPoint
    public var right: CGPoint
    public var hemY: Double
    public var fitsLength: Bool
    public var level: AnchorLevel
    public var source: AnchorSource

    public init(left: CGPoint, right: CGPoint, hemY: Double, fitsLength: Bool, level: AnchorLevel, source: AnchorSource) {
        self.left = left
        self.right = right
        self.hemY = hemY
        self.fitsLength = fitsLength
        self.level = level
        self.source = source
    }

    /// A copy with points clamped into the unit square and ordered left → right.
    public var normalized: GarmentAnchors {
        var copy = self
        func unit(_ p: CGPoint) -> CGPoint {
            CGPoint(x: clamp(Double(p.x).isFinite ? Double(p.x) : 0.5, 0, 1),
                    y: clamp(Double(p.y).isFinite ? Double(p.y) : 0.5, 0, 1))
        }
        var l = unit(left), r = unit(right)
        if l.x > r.x { swap(&l, &r) }
        copy.left = l
        copy.right = r
        copy.hemY = clamp(hemY.isFinite ? hemY : 1, 0, 1)
        return copy
    }

    /// Reasonable anchors spanning the whole image, used as a last resort.
    public static func fallback(for category: GarmentCategory) -> GarmentAnchors {
        let level = category.defaultAnchorLevel
        let y: Double
        switch level {
        case .shoulders: y = 0.08
        case .waist, .hips, .handle, .neck: y = 0.03
        case .sole, .brim: y = 0.97
        case .eyes, .center: y = 0.5
        }
        let inset = level == .shoulders ? 0.12 : 0.02
        return GarmentAnchors(left: CGPoint(x: inset, y: y), right: CGPoint(x: 1 - inset, y: y),
                              hemY: 1, fitsLength: false, level: level, source: .shape)
    }
}

/// Manual tweak applied on top of the automatic fit, in body units, around the
/// garment's anchor point.
public struct ItemAdjustment: Codable, Equatable, Sendable {
    public var offset: CGPoint
    public var scale: Double
    public var rotation: Double

    public init(offset: CGPoint = .zero, scale: Double = 1, rotation: Double = 0) {
        self.offset = offset
        self.scale = scale
        self.rotation = rotation
    }

    public static let identity = ItemAdjustment()
    public static let scaleRange: ClosedRange<Double> = 0.25...4

    public var isIdentity: Bool {
        abs(Double(offset.x)) < 1e-9 && abs(Double(offset.y)) < 1e-9 && abs(scale - 1) < 1e-9 && abs(rotation) < 1e-9
    }

    /// A copy with the scale clamped and non-finite values reset.
    public var sanitized: ItemAdjustment {
        var copy = self
        if !offset.isFinite { copy.offset = .zero }
        copy.scale = scale.isFinite ? clamp(scale, Self.scaleRange.lowerBound, Self.scaleRange.upperBound) : 1
        copy.rotation = rotation.isFinite ? rotation : 0
        return copy
    }
}

/// Body joints in image pixel coordinates. "L"/"R" are image-left/right (the
/// subject's right side appears on the image's left for a front-facing photo).
public struct PoseJoints: Codable, Equatable, Sendable {
    public var neck: CGPoint?
    public var shoulderL: CGPoint?
    public var shoulderR: CGPoint?
    public var elbowL: CGPoint?
    public var elbowR: CGPoint?
    public var wristL: CGPoint?
    public var wristR: CGPoint?
    public var hipL: CGPoint?
    public var hipR: CGPoint?
    public var kneeL: CGPoint?
    public var kneeR: CGPoint?
    public var ankleL: CGPoint?
    public var ankleR: CGPoint?

    public init(
        neck: CGPoint? = nil,
        shoulderL: CGPoint? = nil, shoulderR: CGPoint? = nil,
        elbowL: CGPoint? = nil, elbowR: CGPoint? = nil,
        wristL: CGPoint? = nil, wristR: CGPoint? = nil,
        hipL: CGPoint? = nil, hipR: CGPoint? = nil,
        kneeL: CGPoint? = nil, kneeR: CGPoint? = nil,
        ankleL: CGPoint? = nil, ankleR: CGPoint? = nil
    ) {
        self.neck = neck
        self.shoulderL = shoulderL
        self.shoulderR = shoulderR
        self.elbowL = elbowL
        self.elbowR = elbowR
        self.wristL = wristL
        self.wristR = wristR
        self.hipL = hipL
        self.hipR = hipR
        self.kneeL = kneeL
        self.kneeR = kneeR
        self.ankleL = ankleL
        self.ankleR = ankleR
    }

    /// Builds joints from a pair of points whose left/right labels may be
    /// unreliable: the point with the smaller x becomes "L".
    public static func ordered(_ a: CGPoint?, _ b: CGPoint?) -> (CGPoint?, CGPoint?) {
        guard let a, let b else { return (a, b) }
        return a.x <= b.x ? (a, b) : (b, a)
    }

    /// The same joints expressed in a cropped image whose origin is `origin`.
    public func translated(by origin: CGPoint) -> PoseJoints {
        func t(_ p: CGPoint?) -> CGPoint? { p.map { $0 - origin } }
        return PoseJoints(neck: t(neck), shoulderL: t(shoulderL), shoulderR: t(shoulderR),
                          elbowL: t(elbowL), elbowR: t(elbowR), wristL: t(wristL), wristR: t(wristR),
                          hipL: t(hipL), hipR: t(hipR), kneeL: t(kneeL), kneeR: t(kneeR),
                          ankleL: t(ankleL), ankleR: t(ankleR))
    }

    public var hasShoulders: Bool { shoulderL != nil && shoulderR != nil }
    public var hasHips: Bool { hipL != nil && hipR != nil }
}

/// A single cut-out piece of clothing in the closet.
public struct Garment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var category: GarmentCategory
    /// RGBA cut-out (PNG) — what is drawn on the avatar.
    public var imageFile: String
    /// Original pixels behind the cut-out (JPEG), used by the restore brush.
    public var sourceFile: String?
    /// 8-bit mask (PNG) matching the cut-out.
    public var maskFile: String?
    /// Small preview (PNG).
    public var thumbnailFile: String?
    /// Cut-out size in pixels.
    public var imageSize: CGSize
    public var anchors: GarmentAnchors
    public var dominantColor: RGBColor
    public var palette: [RGBColor]
    public var favorite: Bool
    public var notes: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        category: GarmentCategory,
        imageFile: String,
        sourceFile: String? = nil,
        maskFile: String? = nil,
        thumbnailFile: String? = nil,
        imageSize: CGSize,
        anchors: GarmentAnchors,
        dominantColor: RGBColor,
        palette: [RGBColor] = [],
        favorite: Bool = false,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.imageFile = imageFile
        self.sourceFile = sourceFile
        self.maskFile = maskFile
        self.thumbnailFile = thumbnailFile
        self.imageSize = imageSize
        self.anchors = anchors
        self.dominantColor = dominantColor
        self.palette = palette
        self.favorite = favorite
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Every file this garment owns.
    public var files: [String] {
        [imageFile, sourceFile, maskFile, thumbnailFile].compactMap { $0 }
    }

    public var colorName: String { ColorNaming.name(for: dominantColor) }
}

/// A garment placed in an outfit.
public struct OutfitItem: Codable, Equatable, Identifiable, Sendable {
    public var garmentID: UUID
    public var adjustment: ItemAdjustment
    /// Explicit stacking position; nil uses the category default.
    public var zOverride: Double?

    public var id: UUID { garmentID }

    public init(garmentID: UUID, adjustment: ItemAdjustment = .identity, zOverride: Double? = nil) {
        self.garmentID = garmentID
        self.adjustment = adjustment
        self.zOverride = zOverride
    }
}

public struct Outfit: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [OutfitItem]
    public var tuckedIn: Bool
    public var thumbnailFile: String?
    public var favorite: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        items: [OutfitItem] = [],
        tuckedIn: Bool = false,
        thumbnailFile: String? = nil,
        favorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.tuckedIn = tuckedIn
        self.thumbnailFile = thumbnailFile
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var garmentIDs: [UUID] { items.map(\.garmentID) }

    public func contains(_ garmentID: UUID) -> Bool {
        items.contains { $0.garmentID == garmentID }
    }

    /// Adds a garment, replacing any item of the same exclusive category
    /// (looked up through `categoryOf`). Adding a garment that is already worn
    /// is a no-op.
    public mutating func add(_ garment: Garment, categoryOf: (UUID) -> GarmentCategory?) {
        guard !contains(garment.id) else { return }
        if garment.category.isExclusive {
            items.removeAll { categoryOf($0.garmentID) == garment.category }
        }
        items.append(OutfitItem(garmentID: garment.id))
    }

    public mutating func remove(_ garmentID: UUID) {
        items.removeAll { $0.garmentID == garmentID }
    }

    /// Order-independent identity of the garments in the outfit.
    public var signature: [UUID] {
        garmentIDs.sorted { $0.uuidString < $1.uuidString }
    }
}

/// The user's head cut-out and where its landmarks are.
public struct FaceAsset: Codable, Equatable, Sendable {
    /// RGBA head cut-out (PNG).
    public var imageFile: String
    public var imageSize: CGSize
    /// Pupils and chin (menton) in cut-out pixel coordinates.
    public var eyeLeft: CGPoint
    public var eyeRight: CGPoint
    public var chin: CGPoint
    public var skinTone: RGBColor
    /// Fine-tuning applied after automatic alignment.
    public var adjustment: ItemAdjustment
    /// Head pose of the source photo in degrees, for user feedback.
    public var yawDegrees: Double?
    public var rollDegrees: Double?
    public var pitchDegrees: Double?

    public init(
        imageFile: String,
        imageSize: CGSize,
        eyeLeft: CGPoint,
        eyeRight: CGPoint,
        chin: CGPoint,
        skinTone: RGBColor,
        adjustment: ItemAdjustment = .identity,
        yawDegrees: Double? = nil,
        rollDegrees: Double? = nil,
        pitchDegrees: Double? = nil
    ) {
        self.imageFile = imageFile
        self.imageSize = imageSize
        self.eyeLeft = eyeLeft
        self.eyeRight = eyeRight
        self.chin = chin
        self.skinTone = skinTone
        self.adjustment = adjustment
        self.yawDegrees = yawDegrees
        self.rollDegrees = rollDegrees
        self.pitchDegrees = pitchDegrees
    }
}

public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial
}

public struct UserProfile: Codable, Equatable, Sendable {
    public var body: BodyProfile
    public var face: FaceAsset?
    public var units: UnitSystem
    public var hasCompletedOnboarding: Bool

    public init(body: BodyProfile = BodyProfile(), face: FaceAsset? = nil, units: UnitSystem = .metric, hasCompletedOnboarding: Bool = false) {
        self.body = body
        self.face = face
        self.units = units
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// Skin tone used for the avatar body.
    public var effectiveSkinTone: RGBColor {
        body.skinToneOverride ?? face?.skinTone ?? BodyProfile.defaultSkinTone
    }
}

/// Everything the app persists (besides image files).
public struct Library: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var garments: [Garment]
    public var outfits: [Outfit]
    public var profile: UserProfile

    public init(schemaVersion: Int = Library.currentSchemaVersion, garments: [Garment] = [], outfits: [Outfit] = [], profile: UserProfile = UserProfile()) {
        self.schemaVersion = schemaVersion
        self.garments = garments
        self.outfits = outfits
        self.profile = profile
    }

    public func garment(_ id: UUID) -> Garment? {
        garments.first { $0.id == id }
    }

    public var garmentsByID: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// All files referenced by the library.
    public var referencedFiles: Set<String> {
        var files = Set(garments.flatMap(\.files))
        files.formUnion(outfits.compactMap(\.thumbnailFile))
        if let face = profile.face { files.insert(face.imageFile) }
        return files
    }
}
