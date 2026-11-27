import OutfitKit
import SwiftUI

/// Horizontal proportion guide drawn across the avatar.
struct ProportionGuide: Identifiable {
    let id = UUID()
    var y: Double
    var label: String
    var color: Color
}

/// Draws an `OutfitScene` (avatar, base layer, garments, head) with SwiftUI's
/// `Canvas`. Uses exactly the same geometry as `SceneRenderer`.
struct OutfitCanvas: View {
    let scene: OutfitScene
    let images: [SceneLayer.Content: UIImage]
    var style: AvatarStyle
    var selection: SceneLayer.Content?
    var bodyRect: CGRect?
    var guides: [ProportionGuide] = []
    var padding: Double = 0.04

    var body: some View {
        Canvas { context, size in
            let mapping = Self.mapping(scene: scene, bodyRect: bodyRect, size: size, padding: padding)
            let toCanvas = mapping.transform
            let avatar = scene.avatar

            if style.floorShadow {
                let c = mapping.toCanvas(CGPoint(x: 0, y: avatar.floorY))
                let w = 0.34 * mapping.scale, h = 0.028 * mapping.scale
                context.fill(Path(ellipseIn: CGRect(x: Double(c.x) - w / 2, y: Double(c.y) - h / 2, width: w, height: h)),
                             with: .color(.black.opacity(0.10)))
            }
            var bodyContext = context
            if !scene.showsLegs {
                bodyContext.clip(to: Path(toCanvas.boundingBox(of: AvatarShape.torsoClipRect(for: avatar))))
            }
            let skin = Color(style.skin)
            for part in AvatarShape.parts(for: scene) {
                bodyContext.fill(Path(part.elements.cgPath(transform: toCanvas)), with: .color(skin))
            }
            if avatar.profile.showBaseLayer {
                let base = Color(style.baseLayer)
                for part in AvatarShape.baseLayer(for: avatar) {
                    bodyContext.fill(Path(part.elements.cgPath(transform: toCanvas)), with: .color(base))
                }
            }
            for layer in scene.layers {
                guard let image = images[layer.content] else { continue }
                var layerContext = context
                layerContext.concatenate(layer.transform.concatenating(toCanvas).cgAffineTransform)
                layerContext.draw(Image(uiImage: image), in: CGRect(origin: .zero, size: layer.imageSize))
            }
            if let selection, let layer = scene.layers.first(where: { $0.content == selection }) {
                let t = layer.transform.concatenating(toCanvas)
                let s = layer.imageSize
                var outline = Path()
                outline.move(to: t.apply(.zero))
                outline.addLine(to: t.apply(CGPoint(x: s.width, y: 0)))
                outline.addLine(to: t.apply(CGPoint(x: s.width, y: s.height)))
                outline.addLine(to: t.apply(CGPoint(x: 0, y: s.height)))
                outline.closeSubpath()
                context.stroke(outline, with: .color(Brand.coral), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            for guide in guides {
                let a = mapping.toCanvas(CGPoint(x: -0.3, y: guide.y)), b = mapping.toCanvas(CGPoint(x: 0.3, y: guide.y))
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                context.stroke(line, with: .color(guide.color.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                context.draw(Text(guide.label).font(.caption2.weight(.semibold)).foregroundColor(guide.color),
                             at: CGPoint(x: Double(b.x) - 4, y: Double(b.y) - 7), anchor: .trailing)
            }
        }
    }

    static func mapping(scene: OutfitScene, bodyRect: CGRect?, size: CGSize, padding: Double = 0.04) -> CanvasMapping {
        CanvasMapping(bodyRect: bodyRect ?? SceneRenderer.framingRect(for: scene), canvasSize: size, padding: padding)
    }
}

/// Non-interactive preview of an outfit (cards, generator, profile).
struct OutfitPreview: View {
    @EnvironmentObject private var model: AppModel
    let outfit: Outfit
    var bodyRect: CGRect?

    var body: some View {
        let scene = model.scene(for: outfit)
        OutfitCanvas(scene: scene, images: model.layerImages(for: scene), style: model.avatarStyle, bodyRect: bodyRect)
    }
}

/// Standard guides showing where the head, shoulders, waist and ankles fall.
enum Guides {
    static func proportion(for avatar: AvatarModel) -> [ProportionGuide] {
        [
            ProportionGuide(y: 0, label: "Top of head", color: Brand.lilac),
            ProportionGuide(y: avatar.eyeY, label: "Eyes", color: Brand.coral),
            ProportionGuide(y: avatar.chinY, label: "Chin", color: Brand.coral),
            ProportionGuide(y: avatar.shoulderY, label: "Shoulders", color: Brand.sage),
            ProportionGuide(y: avatar.trouserWaistY, label: "Waist", color: Brand.sage),
            ProportionGuide(y: avatar.ankleY, label: "Ankles", color: Brand.lilac),
        ]
    }

    static func head(for avatar: AvatarModel) -> [ProportionGuide] {
        [
            ProportionGuide(y: 0, label: "Top of head", color: Brand.lilac),
            ProportionGuide(y: avatar.eyeY, label: "Eye line", color: Brand.coral),
            ProportionGuide(y: avatar.chinY, label: "Chin", color: Brand.coral),
        ]
    }
}
