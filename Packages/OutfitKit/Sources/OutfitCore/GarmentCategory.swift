import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The kinds of pieces the app understands. The raw values are persisted.
public enum GarmentCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case top
    case outerwear
    case dress
    case bottom
    case shoes
    case hat
    case eyewear
    case bag
    case scarf
    case belt
    case accessory

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .top: return "Top"
        case .outerwear: return "Outerwear"
        case .dress: return "Dress"
        case .bottom: return "Bottom"
        case .shoes: return "Shoes"
        case .hat: return "Hat"
        case .eyewear: return "Eyewear"
        case .bag: return "Bag"
        case .scarf: return "Scarf"
        case .belt: return "Belt"
        case .accessory: return "Accessory"
        }
    }

    public var pluralName: String {
        switch self {
        case .top: return "Tops"
        case .outerwear: return "Outerwear"
        case .dress: return "Dresses"
        case .bottom: return "Bottoms"
        case .shoes: return "Shoes"
        case .hat: return "Hats"
        case .eyewear: return "Eyewear"
        case .bag: return "Bags"
        case .scarf: return "Scarves"
        case .belt: return "Belts"
        case .accessory: return "Accessories"
        }
    }

    /// SF Symbol used across the UI.
    public var symbolName: String {
        switch self {
        case .top: return "tshirt"
        case .outerwear: return "jacket"
        case .dress: return "figure.stand.dress"
        case .bottom: return "rectangle.portrait.split.2x1"
        case .shoes: return "shoe"
        case .hat: return "hat.widebrim"
        case .eyewear: return "eyeglasses"
        case .bag: return "handbag"
        case .scarf: return "wind"
        case .belt: return "minus.rectangle"
        case .accessory: return "sparkles"
        }
    }

    /// Symbol to use when `symbolName` is unavailable on the running OS.
    public static let fallbackSymbolName = "tag"

    /// Default stacking order on the avatar (higher draws on top). The face/head
    /// layer sits at `SceneZ.head`.
    public var baseZ: Double {
        switch self {
        case .shoes: return 10
        case .bottom: return 20
        case .belt: return 22
        case .dress: return 26
        case .top: return 30
        case .outerwear: return 40
        case .scarf: return 45
        case .eyewear: return 55
        case .hat: return 60
        case .accessory: return 65
        case .bag: return 70
        }
    }

    /// Only one item of an exclusive category can be worn at a time; adding a
    /// new one replaces the old one.
    public var isExclusive: Bool {
        self != .accessory
    }

    /// How the garment's primary width line is interpreted when there is no
    /// better information.
    public var defaultAnchorLevel: AnchorLevel {
        switch self {
        case .top, .outerwear, .dress: return .shoulders
        case .bottom: return .waist
        case .shoes: return .sole
        case .hat: return .brim
        case .eyewear: return .eyes
        case .bag: return .handle
        case .scarf: return .neck
        case .belt: return .waist
        case .accessory: return .center
        }
    }

    /// Categories shown in the closet filter, in display order.
    public static let closetOrder: [GarmentCategory] = [
        .top, .bottom, .dress, .outerwear, .shoes, .bag, .hat, .eyewear, .scarf, .belt, .accessory,
    ]

    /// Categories that form the core of an outfit.
    public var isCore: Bool {
        switch self {
        case .top, .bottom, .dress: return true
        default: return false
        }
    }

    /// Relative visual weight used when scoring colour harmony.
    public var colorWeight: Double {
        switch self {
        case .top, .bottom: return 1.0
        case .dress: return 1.4
        case .outerwear: return 1.1
        case .shoes: return 0.45
        case .bag: return 0.35
        case .hat, .scarf: return 0.3
        case .belt, .eyewear, .accessory: return 0.15
        }
    }
}

/// Z positions of non-garment layers.
public enum SceneZ {
    public static let head: Double = 50
    /// Where a tucked-in top is drawn (below bottoms and belts).
    public static let tuckedTop: Double = 15
}

/// What the garment's width line is aligned to on the body.
public enum AnchorLevel: String, Codable, CaseIterable, Sendable {
    case shoulders
    case waist
    case hips
    case sole
    case brim
    case eyes
    case handle
    case neck
    case center

    public var displayName: String {
        switch self {
        case .shoulders: return "Shoulders"
        case .waist: return "Waist"
        case .hips: return "Hips"
        case .sole: return "Soles"
        case .brim: return "Brim"
        case .eyes: return "Eye line"
        case .handle: return "Handle"
        case .neck: return "Neck"
        case .center: return "Center"
        }
    }

    /// Short instruction shown in the fit-guide editor.
    public var guideHint: String {
        switch self {
        case .shoulders: return "Drag the dots to the shoulder seams."
        case .waist: return "Drag the dots to the waistband corners."
        case .hips: return "Drag the dots to the widest point of the hips."
        case .sole: return "Drag the dots to the outer edges of the soles."
        case .brim: return "Drag the dots to the edges of the brim."
        case .eyes: return "Drag the dots to the outer edges of the frames."
        case .handle: return "Drag the dots to the edges of the bag."
        case .neck: return "Drag the dots to the edges of the scarf at the neck."
        case .center: return "Drag the dots across the piece's width."
        }
    }
}
