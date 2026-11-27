import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Point arithmetic

public extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: CGPoint, rhs: Double) -> CGPoint {
        CGPoint(x: Double(lhs.x) * rhs, y: Double(lhs.y) * rhs)
    }

    static func / (lhs: CGPoint, rhs: Double) -> CGPoint {
        CGPoint(x: Double(lhs.x) / rhs, y: Double(lhs.y) / rhs)
    }

    /// Euclidean length of the point treated as a vector.
    var length: Double {
        let dx = Double(x), dy = Double(y)
        return (dx * dx + dy * dy).squareRoot()
    }

    func distance(to other: CGPoint) -> Double {
        (self - other).length
    }

    /// The same point mirrored across the vertical axis (x = 0).
    var mirroredX: CGPoint {
        CGPoint(x: -x, y: y)
    }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (Double(a.x) + Double(b.x)) / 2, y: (Double(a.y) + Double(b.y)) / 2)
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: Double(a.x) + (Double(b.x) - Double(a.x)) * t,
                y: Double(a.y) + (Double(b.y) - Double(a.y)) * t)
    }

    /// Returns true when both coordinates are finite numbers.
    var isFinite: Bool {
        Double(x).isFinite && Double(y).isFinite
    }
}

@inlinable
public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

@inlinable
public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

// MARK: - Affine transform

/// A 2D affine transform with the same conventions as `CGAffineTransform`:
/// `x' = a*x + c*y + tx`, `y' = b*x + d*y + ty`.
///
/// It lives in OutfitCore (instead of using `CGAffineTransform`) so that the
/// fitting maths can be unit tested on every platform.
public struct Affine2D: Equatable, Codable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = Affine2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ dx: Double, _ dy: Double) -> Affine2D {
        Affine2D(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)
    }

    public static func translation(_ v: CGPoint) -> Affine2D {
        translation(Double(v.x), Double(v.y))
    }

    public static func scale(_ sx: Double, _ sy: Double) -> Affine2D {
        Affine2D(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    public static func scale(_ s: Double) -> Affine2D {
        scale(s, s)
    }

    /// Rotation by `angle` radians. With y pointing down (screen space) a positive
    /// angle turns clockwise on screen, exactly like `CGAffineTransform(rotationAngle:)`.
    public static func rotation(_ angle: Double) -> Affine2D {
        let cosA = cos(angle), sinA = sin(angle)
        return Affine2D(a: cosA, b: sinA, c: -sinA, d: cosA, tx: 0, ty: 0)
    }

    /// Returns the transform that applies `self` first and then `t`
    /// (same semantics as `CGAffineTransform.concatenating`).
    public func concatenating(_ t: Affine2D) -> Affine2D {
        Affine2D(
            a: a * t.a + b * t.c,
            b: a * t.b + b * t.d,
            c: c * t.a + d * t.c,
            d: c * t.b + d * t.d,
            tx: tx * t.a + ty * t.c + t.tx,
            ty: tx * t.b + ty * t.d + t.ty
        )
    }

    public func apply(_ p: CGPoint) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        return CGPoint(x: a * x + c * y + tx, y: b * x + d * y + ty)
    }

    /// Applies the linear part only (no translation).
    public func applyVector(_ v: CGPoint) -> CGPoint {
        let x = Double(v.x), y = Double(v.y)
        return CGPoint(x: a * x + c * y, y: b * x + d * y)
    }

    public var determinant: Double { a * d - b * c }

    public var isInvertible: Bool {
        abs(determinant) > 1e-12 && [a, b, c, d, tx, ty].allSatisfy(\.isFinite)
    }

    public func inverted() -> Affine2D? {
        let det = determinant
        guard abs(det) > 1e-12 else { return nil }
        let ia = d / det
        let ib = -b / det
        let ic = -c / det
        let id = a / det
        return Affine2D(
            a: ia, b: ib, c: ic, d: id,
            tx: -(tx * ia + ty * ic),
            ty: -(tx * ib + ty * id)
        )
    }

    /// Geometric mean of the axis scale factors.
    public var meanScale: Double { abs(determinant).squareRoot() }

    /// Rotation component (radians) assuming no shear.
    public var rotationAngle: Double { atan2(b, a) }

    /// Axis-aligned bounding box of a transformed rectangle.
    public func boundingBox(of rect: CGRect) -> CGRect {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ].map(apply)
        let xs = corners.map { Double($0.x) }
        let ys = corners.map { Double($0.y) }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func isApproximatelyEqual(to other: Affine2D, tolerance: Double = 1e-9) -> Bool {
        abs(a - other.a) <= tolerance && abs(b - other.b) <= tolerance &&
            abs(c - other.c) <= tolerance && abs(d - other.d) <= tolerance &&
            abs(tx - other.tx) <= tolerance && abs(ty - other.ty) <= tolerance
    }
}

// MARK: - Point set fitting

public enum PointFit {
    /// Weighted least-squares similarity transform (uniform scale + rotation +
    /// translation) that maps `source[i]` as closely as possible onto `target[i]`.
    ///
    /// - Parameters:
    ///   - allowRotation: when false the result has no rotation (scale + translation only).
    /// - Returns: nil when fewer than two points are given, the counts differ,
    ///   or the source points are degenerate (all identical).
    public static func similarity(
        from source: [CGPoint],
        to target: [CGPoint],
        weights: [Double]? = nil,
        allowRotation: Bool = true
    ) -> Affine2D? {
        let n = source.count
        guard n >= 2, target.count == n else { return nil }
        let w = weights ?? Array(repeating: 1.0, count: n)
        guard w.count == n, w.allSatisfy({ $0 >= 0 && $0.isFinite }) else { return nil }
        let totalWeight = w.reduce(0, +)
        guard totalWeight > 0 else { return nil }

        var csx = 0.0, csy = 0.0, ctx = 0.0, cty = 0.0
        for i in 0..<n {
            csx += w[i] * Double(source[i].x)
            csy += w[i] * Double(source[i].y)
            ctx += w[i] * Double(target[i].x)
            cty += w[i] * Double(target[i].y)
        }
        csx /= totalWeight; csy /= totalWeight
        ctx /= totalWeight; cty /= totalWeight

        var numReal = 0.0, numImag = 0.0, denominator = 0.0
        for i in 0..<n {
            let zx = Double(source[i].x) - csx, zy = Double(source[i].y) - csy
            let ux = Double(target[i].x) - ctx, uy = Double(target[i].y) - cty
            // u * conj(z)
            numReal += w[i] * (ux * zx + uy * zy)
            numImag += w[i] * (uy * zx - ux * zy)
            denominator += w[i] * (zx * zx + zy * zy)
        }
        guard denominator > 1e-12 else { return nil }
        let ar = numReal / denominator
        let ai = allowRotation ? numImag / denominator : 0
        let bx = ctx - (ar * csx - ai * csy)
        let by = cty - (ai * csx + ar * csy)
        let result = Affine2D(a: ar, b: ai, c: -ai, d: ar, tx: bx, ty: by)
        return result.isInvertible ? result : nil
    }

    /// Root-mean-square residual of `transform` mapping `source` onto `target`.
    public static func rmsError(_ transform: Affine2D, source: [CGPoint], target: [CGPoint]) -> Double {
        guard !source.isEmpty, source.count == target.count else { return .infinity }
        var sum = 0.0
        for (s, t) in zip(source, target) {
            let p = transform.apply(s)
            let dx = Double(p.x) - Double(t.x), dy = Double(p.y) - Double(t.y)
            sum += dx * dx + dy * dy
        }
        return (sum / Double(source.count)).squareRoot()
    }
}

// MARK: - Integer rectangles (pixel space)

public struct PixelRect: Equatable, Codable, Sendable {
    public var minX: Int
    public var minY: Int
    public var maxX: Int // inclusive
    public var maxY: Int // inclusive

    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Int { maxX - minX + 1 }
    public var height: Int { maxY - minY + 1 }
    public var area: Int { width * height }
    public var centerX: Double { Double(minX + maxX) / 2 }
    public var centerY: Double { Double(minY + maxY) / 2 }

    public var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }

    public func union(_ other: PixelRect) -> PixelRect {
        PixelRect(minX: Swift.min(minX, other.minX), minY: Swift.min(minY, other.minY),
                  maxX: Swift.max(maxX, other.maxX), maxY: Swift.max(maxY, other.maxY))
    }

    /// Expands the rectangle by `margin` pixels on every side, clamped to `bounds`.
    public func expanded(by margin: Int, clampedToWidth width: Int, height: Int) -> PixelRect {
        PixelRect(minX: Swift.max(0, minX - margin), minY: Swift.max(0, minY - margin),
                  maxX: Swift.min(width - 1, maxX + margin), maxY: Swift.min(height - 1, maxY + margin))
    }
}
