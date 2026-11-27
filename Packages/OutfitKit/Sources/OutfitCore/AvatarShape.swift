import Foundation

/// Platform-neutral path description, converted to `CGPath`/SwiftUI `Path` by
/// the rendering layer.
public enum PathElement: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint) // control1, control2, end
    case close

    /// All coordinates referenced by the element.
    public var points: [CGPoint] {
        switch self {
        case let .move(p), let .line(p): return [p]
        case let .cubic(c1, c2, p): return [c1, c2, p]
        case .close: return []
        }
    }
}

public enum PathBuilder {
    /// Closed centripetal Catmull–Rom spline through `points`, as cubic Béziers.
    /// Centripetal parameterisation never overshoots or forms cusps, which keeps
    /// the body outline clean at tight turns (feet, crotch, hands).
    public static func smoothClosed(_ points: [CGPoint]) -> [PathElement] {
        let n = points.count
        guard n >= 3 else { return polygon(points) }
        var elements: [PathElement] = [.move(points[0])]
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            let (c1, c2) = controlPoints(p0, p1, p2, p3)
            elements.append(.cubic(c1, c2, p2))
        }
        elements.append(.close)
        return elements
    }

    public static func polygon(_ points: [CGPoint]) -> [PathElement] {
        guard let first = points.first else { return [] }
        return [.move(first)] + points.dropFirst().map { .line($0) } + [.close]
    }

    /// Bézier control points of the centripetal Catmull–Rom segment p1 → p2.
    static func controlPoints(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> (CGPoint, CGPoint) {
        let eps = 1e-9
        let d1 = max(p0.distance(to: p1), eps)
        let d2 = max(p1.distance(to: p2), eps)
        let d3 = max(p2.distance(to: p3), eps)
        let s1 = d1.squareRoot(), s2 = d2.squareRoot(), s3 = d3.squareRoot()

        let c1Num = p2 * d1 - p0 * d2 + p1 * (2 * d1 + 3 * s1 * s2 + d2)
        let c1 = c1Num / (3 * s1 * (s1 + s2))
        let c2Num = p1 * d3 - p3 * d2 + p2 * (2 * d3 + 3 * s3 * s2 + d2)
        let c2 = c2Num / (3 * s3 * (s3 + s2))
        return (c1, c2)
    }

    /// Bounding box of all points referenced by the elements (control points
    /// included, so it is a conservative bound).
    public static func bounds(of elements: [PathElement]) -> CGRect {
        let pts = elements.flatMap(\.points)
        guard let first = pts.first else { return .zero }
        var minX = Double(first.x), maxX = Double(first.x), minY = Double(first.y), maxY = Double(first.y)
        for p in pts {
            minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
            minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public static func transformed(_ elements: [PathElement], by t: Affine2D) -> [PathElement] {
        elements.map { element in
            switch element {
            case let .move(p): return .move(t.apply(p))
            case let .line(p): return .line(t.apply(p))
            case let .cubic(c1, c2, p): return .cubic(t.apply(c1), t.apply(c2), t.apply(p))
            case .close: return .close
            }
        }
    }
}

/// A filled region of the avatar.
public struct AvatarPart: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case armLeft, armRight, body, head, baseTop, baseBottom
    }

    public var kind: Kind
    /// Outline anchor points (before smoothing), useful for tests and hit areas.
    public var outline: [CGPoint]
    public var elements: [PathElement]
}

/// Builds the avatar silhouette from an `AvatarModel`, in body space.
public enum AvatarShape {
    /// Parts in back-to-front order.
    public static func parts(for avatar: AvatarModel, includeHead: Bool) -> [AvatarPart] {
        var result: [AvatarPart] = []
        if avatar.profile.showArms {
            let right = armOutline(avatar)
            let left = right.reversed().map(\.mirroredX)
            result.append(AvatarPart(kind: .armLeft, outline: left, elements: PathBuilder.smoothClosed(left)))
            result.append(AvatarPart(kind: .armRight, outline: right, elements: PathBuilder.smoothClosed(right)))
        }
        let body = bodyOutline(avatar)
        result.append(AvatarPart(kind: .body, outline: body, elements: PathBuilder.smoothClosed(body)))
        if includeHead {
            let head = headOutline(avatar)
            result.append(AvatarPart(kind: .head, outline: head, elements: PathBuilder.smoothClosed(head)))
        }
        return result
    }

    /// Neutral base layer (tank + briefs) so the avatar never looks undressed.
    public static func baseLayer(for avatar: AvatarModel) -> [AvatarPart] {
        let top = baseTopOutline(avatar)
        let bottom = baseBottomOutline(avatar)
        return [
            AvatarPart(kind: .baseBottom, outline: bottom, elements: PathBuilder.smoothClosed(bottom)),
            AvatarPart(kind: .baseTop, outline: top, elements: PathBuilder.smoothClosed(top)),
        ]
    }

    /// Torso + legs outline, clockwise starting at the right side of the neck.
    public static func bodyOutline(_ a: AvatarModel) -> [CGPoint] {
        let neckTop = a.chinY - 0.025
        var right: [CGPoint] = [
            CGPoint(x: a.neckHalfWidth * 0.94, y: neckTop),
            CGPoint(x: a.neckHalfWidth, y: a.chinY + 0.012),
            CGPoint(x: a.neckHalfWidth * 1.1, y: a.neckBaseY - 0.004),
            CGPoint(x: a.neckHalfWidth + (a.shoulderHalfWidth - a.neckHalfWidth) * 0.45, y: a.neckBaseY + 0.010),
            CGPoint(x: a.shoulderHalfWidth - 0.016, y: a.shoulderY - 0.002),
            CGPoint(x: a.shoulderHalfWidth, y: a.shoulderY + 0.022),
            CGPoint(x: a.shoulderHalfWidth - 0.01, y: a.armpitY - 0.014),
            CGPoint(x: a.chestHalfWidth, y: a.armpitY + 0.006),
            CGPoint(x: a.chestHalfWidth, y: a.chestY),
            CGPoint(x: a.waistHalfWidth, y: a.waistY),
            CGPoint(x: a.torsoHalfWidth(atY: (a.waistY + a.hipY) / 2), y: (a.waistY + a.hipY) / 2),
            CGPoint(x: a.hipHalfWidth, y: a.hipY),
            CGPoint(x: a.hipHalfWidth * 0.97, y: a.crotchY + 0.03),
            CGPoint(x: a.kneeX + a.kneeHalfWidth + 0.012, y: (a.crotchY + a.kneeY) / 2 + 0.02),
            CGPoint(x: a.kneeX + a.kneeHalfWidth, y: a.kneeY),
            CGPoint(x: a.ankleX + a.calfHalfWidth, y: a.calfY),
            CGPoint(x: a.ankleX + a.ankleHalfWidth, y: a.ankleY),
            CGPoint(x: a.ankleX + a.footHalfWidth, y: a.floorY - 0.012),
            CGPoint(x: a.ankleX + a.footHalfWidth * 0.7, y: a.floorY),
            CGPoint(x: a.ankleX - a.footHalfWidth * 0.7, y: a.floorY),
            CGPoint(x: a.ankleX - a.footHalfWidth * 0.95, y: a.floorY - 0.012),
            CGPoint(x: a.ankleX - a.ankleHalfWidth, y: a.ankleY),
            CGPoint(x: a.ankleX - a.calfHalfWidth * 0.85, y: a.calfY),
            CGPoint(x: a.kneeX - a.kneeHalfWidth, y: a.kneeY),
            CGPoint(x: max(0.012, a.kneeX - a.thighHalfWidth * 0.8), y: a.crotchY + 0.07),
        ]
        // Keep the inner leg edges from crossing the centre line.
        right = right.map { CGPoint(x: max(Double($0.x), 0.004), y: Double($0.y)) }
        let crotch = CGPoint(x: 0, y: a.crotchY)
        let left = right.reversed().map(\.mirroredX)
        return right + [crotch] + left
    }

    /// Right arm (viewer's right), as an outline around the arm's axis.
    public static func armOutline(_ a: AvatarModel) -> [CGPoint] {
        let hand = CGPoint.lerp(a.wrist, a.fingertip, 0.45)
        // The arm starts just below the shoulder joint so its rounded top stays
        // hidden under the torso's shoulder line (no "shoulder pad" bumps).
        let top = a.shoulderJoint + CGPoint(x: 0, y: 0.006)
        let axis: [CGPoint] = [top, a.elbow, a.wrist, hand, a.fingertip]
        let halfWidths: [Double] = [a.upperArmHalfWidth, a.forearmHalfWidth, a.wristHalfWidth, a.handHalfWidth, 0]
        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        for i in 0..<(axis.count - 1) {
            let prev = axis[max(0, i - 1)]
            let next = axis[i + 1]
            let dir = next - prev
            let len = max(dir.length, 1e-9)
            let normal = CGPoint(x: Double(dir.y) / len, y: -Double(dir.x) / len) // points away from the body for the right arm
            let outward = Double(normal.x) >= 0 ? normal : normal * -1
            outer.append(axis[i] + outward * halfWidths[i])
            inner.append(axis[i] - outward * halfWidths[i])
        }
        let tip = a.fingertip
        let cap = a.shoulderJoint
        return [cap] + outer + [tip] + inner.reversed()
    }

    public static func headOutline(_ a: AvatarModel) -> [CGPoint] {
        let center = CGPoint(x: 0, y: a.headHeight / 2)
        let halfHeight = a.headHeight / 2
        let halfWidth = a.headHalfWidth * 1.06
        var points: [CGPoint] = []
        for step in 0..<12 {
            let theta = Double(step) * Double.pi / 6
            let s = sin(theta), c = cos(theta)
            // Narrow toward the chin (c < 0 is the lower half).
            let narrowing = c < 0 ? 1 + 0.24 * c : 1
            points.append(CGPoint(x: Double(center.x) + halfWidth * s * narrowing,
                                  y: Double(center.y) - halfHeight * c))
        }
        return points
    }

    static func baseTopOutline(_ a: AvatarModel) -> [CGPoint] {
        // A fitted tank: narrow straps, scoop neck, curved armholes, hem just
        // above the briefs.
        let strapInner = a.neckHalfWidth * 1.35
        let strapWidth = a.neckHalfWidth * 0.7
        let hemY = a.trouserWaistY - 0.004
        let right: [CGPoint] = [
            CGPoint(x: strapInner, y: a.neckBaseY + 0.006),
            CGPoint(x: strapInner + strapWidth, y: a.neckBaseY + 0.01),
            CGPoint(x: a.chestHalfWidth * 0.86, y: a.armpitY - 0.022),
            CGPoint(x: a.chestHalfWidth * 0.985, y: a.armpitY + 0.012),
            CGPoint(x: a.chestHalfWidth * 0.99, y: a.chestY),
            CGPoint(x: a.waistHalfWidth * 0.995, y: a.waistY),
            CGPoint(x: a.torsoHalfWidth(atY: hemY) * 0.995, y: hemY),
        ]
        let neckline = CGPoint(x: 0, y: a.shoulderY + 0.035)
        let hemCenter = CGPoint(x: 0, y: hemY + 0.003)
        return [neckline] + right + [hemCenter] + right.reversed().map(\.mirroredX)
    }

    static func baseBottomOutline(_ a: AvatarModel) -> [CGPoint] {
        let topY = a.trouserWaistY + 0.012
        let right: [CGPoint] = [
            CGPoint(x: a.torsoHalfWidth(atY: topY) * 0.99, y: topY),
            CGPoint(x: a.hipHalfWidth * 0.995, y: a.hipY),
            CGPoint(x: a.hipHalfWidth * 0.97, y: a.crotchY + 0.022),
            CGPoint(x: a.kneeX, y: a.crotchY + 0.034),
            CGPoint(x: max(0.014, a.kneeX - a.thighHalfWidth * 0.75), y: a.crotchY + 0.03),
        ]
        let topCenter = CGPoint(x: 0, y: topY)
        let crotch = CGPoint(x: 0, y: a.crotchY + 0.006)
        return [topCenter] + right + [crotch] + right.reversed().map(\.mirroredX)
    }
}
