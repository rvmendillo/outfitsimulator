import Foundation
import XCTest
@testable import OutfitCore

final class GeometryTests: XCTestCase {
    func testConcatenationAppliesInOrder() {
        let t1 = Affine2D.scale(2, 3)
        let t2 = Affine2D.translation(5, -1)
        let t3 = Affine2D.rotation(0.3)
        let p = CGPoint(x: 1.5, y: -2)
        let combined = t1.concatenating(t2).concatenating(t3)
        XCTAssertPointEqual(combined.apply(p), t3.apply(t2.apply(t1.apply(p))), accuracy: 1e-12)
    }

    func testInverseRoundTrip() throws {
        let t = Affine2D.rotation(1.1).concatenating(.scale(3, 0.5)).concatenating(.translation(10, 20))
        let inv = try XCTUnwrap(t.inverted())
        let p = CGPoint(x: -4, y: 7.25)
        XCTAssertPointEqual(inv.apply(t.apply(p)), p, accuracy: 1e-9)
        XCTAssertTrue(t.concatenating(inv).isApproximatelyEqual(to: .identity, tolerance: 1e-9))
    }

    func testSingularTransformHasNoInverse() {
        XCTAssertNil(Affine2D.scale(0, 1).inverted())
        XCTAssertFalse(Affine2D.scale(0, 1).isInvertible)
    }

    func testRotationMatchesCoreGraphicsConvention() {
        // CGAffineTransform(rotationAngle: .pi/2) maps (1, 0) to (0, 1).
        let p = Affine2D.rotation(.pi / 2).apply(CGPoint(x: 1, y: 0))
        XCTAssertPointEqual(p, CGPoint(x: 0, y: 1), accuracy: 1e-12)
    }

    func testBoundingBoxOfRotatedSquare() {
        let t = Affine2D.rotation(.pi / 4)
        let box = t.boundingBox(of: CGRect(x: -1, y: -1, width: 2, height: 2))
        XCTAssertEqual(Double(box.width), 2 * 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(Double(box.midX), 0, accuracy: 1e-9)
    }

    func testSimilarityFitRecoversKnownTransform() throws {
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<50 {
            let angle = (rng.nextUnit() - 0.5) * 2
            let scale = 0.1 + rng.nextUnit() * 5
            let truth = Affine2D.rotation(angle).concatenating(.scale(scale)).concatenating(.translation(rng.nextUnit() * 100 - 50, rng.nextUnit() * 100 - 50))
            let source = (0..<5).map { _ in CGPoint(x: rng.nextUnit() * 400, y: rng.nextUnit() * 400) }
            let target = source.map(truth.apply)
            let fit = try XCTUnwrap(PointFit.similarity(from: source, to: target))
            XCTAssertTrue(fit.isApproximatelyEqual(to: truth, tolerance: 1e-6), "\(fit) vs \(truth)")
            XCTAssertLessThan(PointFit.rmsError(fit, source: source, target: target), 1e-6)
        }
    }

    func testSimilarityWithoutRotationHasNoRotation() throws {
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 5, y: 8)]
        let truth = Affine2D.rotation(0.4).concatenating(.scale(2))
        let fit = try XCTUnwrap(PointFit.similarity(from: source, to: source.map(truth.apply), allowRotation: false))
        XCTAssertEqual(fit.b, 0)
        XCTAssertEqual(fit.c, 0)
        XCTAssertGreaterThan(fit.a, 0)
    }

    func testSimilarityRejectsDegenerateInput() {
        XCTAssertNil(PointFit.similarity(from: [CGPoint(x: 1, y: 1)], to: [CGPoint(x: 2, y: 2)]))
        XCTAssertNil(PointFit.similarity(from: [CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 1)], to: [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 3)]))
        XCTAssertNil(PointFit.similarity(from: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)], to: [CGPoint(x: 0, y: 0)]))
        XCTAssertNil(PointFit.similarity(from: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)], to: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)], weights: [0, 0]))
    }

    func testWeightsPullTowardHeavierPoints() throws {
        // Inconsistent targets: the heavily weighted pair should be matched closely.
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10)]
        let target = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 14)]
        let fit = try XCTUnwrap(PointFit.similarity(from: source, to: target, weights: [100, 100, 1]))
        XCTAssertPointEqual(fit.apply(source[1]), target[1], accuracy: 0.2)
    }

    func testPixelRectHelpers() {
        let r = PixelRect(minX: 2, minY: 3, maxX: 11, maxY: 7)
        XCTAssertEqual(r.width, 10)
        XCTAssertEqual(r.height, 5)
        XCTAssertEqual(r.area, 50)
        XCTAssertEqual(r.union(PixelRect(minX: 0, minY: 5, maxX: 4, maxY: 20)), PixelRect(minX: 0, minY: 3, maxX: 11, maxY: 20))
        XCTAssertEqual(r.expanded(by: 5, clampedToWidth: 14, height: 9), PixelRect(minX: 0, minY: 0, maxX: 13, maxY: 8))
    }

    func testSeededGeneratorIsDeterministicAndUniform() {
        var a = SeededGenerator(seed: 7), b = SeededGenerator(seed: 7)
        let xs = (0..<1000).map { _ in a.nextUnit() }
        let ys = (0..<1000).map { _ in b.nextUnit() }
        XCTAssertEqual(xs, ys)
        XCTAssertTrue(xs.allSatisfy { $0 >= 0 && $0 < 1 })
        let mean = xs.reduce(0, +) / Double(xs.count)
        XCTAssertEqual(mean, 0.5, accuracy: 0.05)
    }
}
