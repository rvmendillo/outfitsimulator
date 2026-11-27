import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One image drawn on top of the avatar.
public struct SceneLayer: Equatable, Identifiable, Sendable {
    public enum Content: Equatable, Hashable, Sendable {
        case garment(UUID)
        case face
    }

    public var content: Content
    /// Maps image pixel coordinates to body space.
    public var transform: Affine2D
    public var imageSize: CGSize
    public var zIndex: Double
    public var category: GarmentCategory?

    public var id: String {
        switch content {
        case let .garment(id): return "garment-\(id.uuidString)"
        case .face: return "face"
        }
    }

    /// Body-space bounding box of the layer's image.
    public var bounds: CGRect {
        transform.boundingBox(of: CGRect(origin: .zero, size: imageSize))
    }

    /// Converts a body-space point to the layer's image pixel coordinates.
    public func imagePoint(forBodyPoint point: CGPoint) -> CGPoint? {
        transform.inverted()?.apply(point)
    }
}

/// Everything needed to draw an outfit on the avatar, back to front.
public struct OutfitScene: Equatable, Sendable {
    public var avatar: AvatarModel
    public var layers: [SceneLayer]
    /// True when no face photo is used, so the avatar's own head is drawn.
    public var drawsAvatarHead: Bool
    public var skinTone: RGBColor

    /// Union of the avatar and every layer, in body space.
    public var bounds: CGRect {
        var rect = CGRect(x: -0.3, y: 0, width: 0.6, height: 1)
        for layer in layers {
            rect = rect.union(layer.bounds)
        }
        return rect
    }

    /// Topmost layer under `point`. `alpha` reports the opacity (0...1) of a
    /// layer's image at a pixel; pass nil to hit-test bounding boxes only.
    public func hitTest(_ point: CGPoint, alpha: ((SceneLayer, CGPoint) -> Double)? = nil, minimumAlpha: Double = 0.1) -> SceneLayer? {
        for layer in layers.reversed() {
            guard let p = layer.imagePoint(forBodyPoint: point) else { continue }
            guard p.x >= 0, p.y >= 0, p.x < layer.imageSize.width, p.y < layer.imageSize.height else { continue }
            if let alpha {
                if alpha(layer, p) >= minimumAlpha { return layer }
            } else {
                return layer
            }
        }
        return nil
    }
}

public enum SceneBuilder {
    /// Stacking position for an item.
    public static func zIndex(for item: OutfitItem, category: GarmentCategory, tuckedIn: Bool) -> Double {
        if let z = item.zOverride { return z }
        if tuckedIn && category == .top { return SceneZ.tuckedTop }
        return category.baseZ
    }

    public static func build(avatar: AvatarModel, outfit: Outfit, garments: [UUID: Garment], face: FaceAsset?, skinTone: RGBColor) -> OutfitScene {
        var layers: [SceneLayer] = []
        for (index, item) in outfit.items.enumerated() {
            guard let garment = garments[item.garmentID] else { continue }
            guard garment.imageSize.width > 0, garment.imageSize.height > 0 else { continue }
            let transform = GarmentFitter.placement(for: garment, adjustment: item.adjustment, avatar: avatar)
            guard transform.isInvertible else { continue }
            // A tiny index term keeps the order stable for equal z values.
            let z = zIndex(for: item, category: garment.category, tuckedIn: outfit.tuckedIn) + Double(index) * 1e-4
            layers.append(SceneLayer(content: .garment(garment.id), transform: transform,
                                     imageSize: garment.imageSize, zIndex: z, category: garment.category))
        }
        var drawsAvatarHead = true
        if let face, face.imageSize.width > 0, face.imageSize.height > 0,
           let transform = FaceFitter.placement(face: face, avatar: avatar), transform.isInvertible {
            layers.append(SceneLayer(content: .face, transform: transform, imageSize: face.imageSize,
                                     zIndex: SceneZ.head, category: nil))
            drawsAvatarHead = false
        }
        layers.sort { $0.zIndex < $1.zIndex }
        return OutfitScene(avatar: avatar, layers: layers, drawsAvatarHead: drawsAvatarHead, skinTone: skinTone)
    }

    /// z value that moves `garmentID` one step forward (+1) or backward (-1)
    /// past its neighbour in the current scene, or nil if it is already at the end.
    public static func reorderedZ(for garmentID: UUID, direction: Int, in scene: OutfitScene) -> Double? {
        let garmentLayers = scene.layers.filter {
            if case .garment = $0.content { return true }
            return false
        }
        guard let index = garmentLayers.firstIndex(where: { $0.content == .garment(garmentID) }) else { return nil }
        let neighbourIndex = index + (direction >= 0 ? 1 : -1)
        guard garmentLayers.indices.contains(neighbourIndex) else { return nil }
        let neighbour = garmentLayers[neighbourIndex]
        // Land just beyond the neighbour, but not past the next one.
        let beyondIndex = neighbourIndex + (direction >= 0 ? 1 : -1)
        if garmentLayers.indices.contains(beyondIndex) {
            return (neighbour.zIndex + garmentLayers[beyondIndex].zIndex) / 2
        }
        return neighbour.zIndex + (direction >= 0 ? 1 : -1)
    }
}

/// Maps body space to a view/canvas of a given size (aspect-fit with padding).
public struct CanvasMapping: Equatable, Sendable {
    public var scale: Double
    public var offset: CGPoint

    /// Fits `bodyRect` into `canvasSize`, centred, leaving `padding` (fraction
    /// of the canvas) around it.
    public init(bodyRect: CGRect, canvasSize: CGSize, padding: Double = 0.04) {
        let w = max(Double(canvasSize.width), 1), h = max(Double(canvasSize.height), 1)
        let availableW = w * (1 - 2 * padding), availableH = h * (1 - 2 * padding)
        let bw = max(Double(bodyRect.width), 1e-6), bh = max(Double(bodyRect.height), 1e-6)
        scale = min(availableW / bw, availableH / bh)
        let usedW = bw * scale, usedH = bh * scale
        offset = CGPoint(x: (w - usedW) / 2 - Double(bodyRect.minX) * scale,
                         y: (h - usedH) / 2 - Double(bodyRect.minY) * scale)
    }

    public init(scale: Double, offset: CGPoint) {
        self.scale = scale
        self.offset = offset
    }

    public var transform: Affine2D {
        Affine2D.scale(scale).concatenating(.translation(offset))
    }

    public func toCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: Double(p.x) * scale + Double(offset.x), y: Double(p.y) * scale + Double(offset.y))
    }

    public func toBody(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (Double(p.x) - Double(offset.x)) / scale, y: (Double(p.y) - Double(offset.y)) / scale)
    }

    /// The standard framing for the avatar: whole body with a little headroom.
    public static func standardBodyRect(for avatar: AvatarModel) -> CGRect {
        CGRect(x: -0.32, y: -0.04, width: 0.64, height: 1.08)
    }
}
