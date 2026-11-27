import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

/// Writes SVG previews of the avatar when OUTFIT_SVG_DIR is set (manual visual check).
final class SVGPreviewTests: XCTestCase {
    func testWriteAvatarPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["OUTFIT_SVG_DIR"] else {
            throw XCTSkip("Set OUTFIT_SVG_DIR to write previews")
        }
        func pathString(_ elements: [PathElement], _ m: CanvasMapping) -> String {
            elements.map { e -> String in
                switch e {
                case let .move(p): let q = m.toCanvas(p); return "M\(q.x),\(q.y)"
                case let .line(p): let q = m.toCanvas(p); return "L\(q.x),\(q.y)"
                case let .cubic(c1, c2, p):
                    let a = m.toCanvas(c1), b = m.toCanvas(c2), c = m.toCanvas(p)
                    return "C\(a.x),\(a.y) \(b.x),\(b.y) \(c.x),\(c.y)"
                case .close: return "Z"
                }
            }.joined(separator: " ")
        }
        var svg = "<svg xmlns='http://www.w3.org/2000/svg' width='1200' height='700' style='background:#F7F3EE'>"
        let configs: [(BodyShape, Double)] = [(.feminine, 160), (.neutral, 172), (.masculine, 185), (.feminine, 150), (.masculine, 200)]
        for (i, (shape, height)) in configs.enumerated() {
            let avatar = AvatarModel(profile: BodyProfile(heightCM: height, shape: shape))
            // Same pixels-per-cm for all so relative heights are visible.
            let scale = 600.0 / 200.0 * height
            let m = CanvasMapping(scale: scale, offset: CGPoint(x: 120 + Double(i) * 240, y: 680 - scale))
            for part in AvatarShape.parts(for: avatar, includeHead: true) {
                let fill = "#D9A784"
                svg += "<path d='\(pathString(part.elements, m))' fill='\(fill)'/>"
            }
            for part in AvatarShape.baseLayer(for: avatar) {
                svg += "<path d='\(pathString(part.elements, m))' fill='#3A3542'/>"
            }
            // Landmark guides.
            for (y, color) in [(avatar.eyeY, "#2F5FD0"), (avatar.chinY, "#C62828"), (avatar.shoulderY, "#2E8B57"), (avatar.trouserWaistY, "#EF7A1A"), (avatar.ankleY, "#6A3FA0")] {
                let a = m.toCanvas(CGPoint(x: -0.3, y: y)), b = m.toCanvas(CGPoint(x: 0.3, y: y))
                svg += "<line x1='\(a.x)' y1='\(a.y)' x2='\(b.x)' y2='\(b.y)' stroke='\(color)' stroke-width='0.7'/>"
            }
            let label = m.toCanvas(CGPoint(x: -0.25, y: 1.0))
            svg += "<text x='\(label.x)' y='\(Double(label.y) + 14)' font-size='12' font-family='sans-serif'>\(shape.rawValue) \(Int(height))cm \(String(format: "%.2f", avatar.headsTall)) heads</text>"
        }
        svg += "</svg>"
        try svg.write(toFile: dir + "/avatars.svg", atomically: true, encoding: .utf8)
    }
}
