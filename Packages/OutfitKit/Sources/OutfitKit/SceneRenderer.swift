#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

public extension Affine2D {
    var cgAffineTransform: CGAffineTransform {
        CGAffineTransform(a: CGFloat(a), b: CGFloat(b), c: CGFloat(c), d: CGFloat(d), tx: CGFloat(tx), ty: CGFloat(ty))
    }
}

public extension SRGBColor {
    var cgColor: CGColor {
        CGColor(colorSpace: ColorSpaces.sRGB, components: [CGFloat(r), CGFloat(g), CGFloat(b), 1]) ?? CGColor(gray: 0.5, alpha: 1)
    }

    func cgColor(alpha: Double) -> CGColor {
        CGColor(colorSpace: ColorSpaces.sRGB, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(alpha)]) ?? CGColor(gray: 0.5, alpha: alpha)
    }
}

public extension Array where Element == PathElement {
    /// Converts to a `CGPath`, mapping every point through `transform`.
    func cgPath(transform: Affine2D = .identity) -> CGPath {
        let path = CGMutablePath()
        for element in self {
            switch element {
            case let .move(p): path.move(to: transform.apply(p))
            case let .line(p): path.addLine(to: transform.apply(p))
            case let .cubic(c1, c2, p): path.addCurve(to: transform.apply(p), control1: transform.apply(c1), control2: transform.apply(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// Colours for drawing the avatar.
public struct AvatarStyle: Equatable, Sendable {
    public var skin: SRGBColor
    public var baseLayer: SRGBColor
    public var floorShadow: Bool

    public static let baseLayerColor = SRGBColor(hex: "#3A3542")!

    public init(skin: SRGBColor, baseLayer: SRGBColor = AvatarStyle.baseLayerColor, floorShadow: Bool = true) {
        self.skin = skin
        self.baseLayer = baseLayer
        self.floorShadow = floorShadow
    }
}

/// Draws an `OutfitScene` with Core Graphics (thumbnails, sharing, tests).
/// The interactive canvas in the app draws the same scene with SwiftUI.
public enum SceneRenderer {
    public static func render(
        scene: OutfitScene,
        images: [SceneLayer.Content: CGImage],
        size: CGSize,
        bodyRect: CGRect? = nil,
        background: SRGBColor? = nil,
        style: AvatarStyle,
        padding: Double = 0.04
    ) -> CGImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: ColorSpaces.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Work in a y-down coordinate system like UIKit/SwiftUI.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        let rect = bodyRect ?? framingRect(for: scene)
        let mapping = CanvasMapping(bodyRect: rect, canvasSize: CGSize(width: w, height: h), padding: padding)
        draw(scene: scene, images: images, in: ctx, mapping: mapping, style: style)
        return ctx.makeImage()
    }

    /// Standard framing, widened if layers stick out (e.g. a bag).
    public static func framingRect(for scene: OutfitScene) -> CGRect {
        let standard = CanvasMapping.standardBodyRect(for: scene.avatar)
        let union = standard.union(scene.bounds)
        // Keep it centred on the body.
        let half = max(abs(Double(union.minX)), abs(Double(union.maxX)))
        return CGRect(x: -half, y: Double(union.minY), width: 2 * half, height: Double(union.height))
    }

    /// Draws into a context whose user space is y-down, in canvas pixels.
    public static func draw(scene: OutfitScene, images: [SceneLayer.Content: CGImage], in ctx: CGContext, mapping: CanvasMapping, style: AvatarStyle) {
        let avatar = scene.avatar
        let toCanvas = mapping.transform

        if style.floorShadow {
            let center = mapping.toCanvas(CGPoint(x: 0, y: avatar.floorY))
            let shadowWidth = 0.34 * mapping.scale, shadowHeight = 0.028 * mapping.scale
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.10))
            ctx.fillEllipse(in: CGRect(x: Double(center.x) - shadowWidth / 2, y: Double(center.y) - shadowHeight / 2,
                                       width: shadowWidth, height: shadowHeight))
        }

        ctx.saveGState()
        if !scene.showsLegs {
            let clip = AvatarShape.torsoClipRect(for: avatar)
            ctx.clip(to: toCanvas.boundingBox(of: clip))
        }
        ctx.setFillColor(style.skin.cgColor)
        for part in AvatarShape.parts(for: scene) {
            ctx.addPath(part.elements.cgPath(transform: toCanvas))
            ctx.fillPath()
        }
        ctx.setFillColor(style.baseLayer.cgColor)
        for part in AvatarShape.baseLayer(for: scene) {
            ctx.addPath(part.elements.cgPath(transform: toCanvas))
            ctx.fillPath()
        }
        ctx.restoreGState()

        for layer in scene.layers {
            guard let image = images[layer.content] else { continue }
            ctx.saveGState()
            ctx.concatenate(layer.transform.concatenating(toCanvas).cgAffineTransform)
            // Undo the y-down flip locally so the bitmap is drawn upright.
            ctx.translateBy(x: 0, y: layer.imageSize.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: layer.imageSize))
            ctx.restoreGState()
        }
    }
}
#endif
