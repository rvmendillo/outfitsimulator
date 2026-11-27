import Foundation
import XCTest
@testable import OutfitCore

final class FittingTests: XCTestCase {
    let avatar = AvatarModel(profile: BodyProfile(heightCM: 170, shape: .neutral))

    private func anchors(_ l: CGPoint, _ r: CGPoint, hemY: Double = 1, fitsLength: Bool = false, level: AnchorLevel) -> GarmentAnchors {
        GarmentAnchors(left: l, right: r, hemY: hemY, fitsLength: fitsLength, level: level, source: .user)
    }

    func testTopShouldersLandOnAvatarShoulders() {
        let size = CGSize(width: 400, height: 500)
        let a = anchors(CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.8, y: 0.1), level: .shoulders)
        let fit = GarmentFitter.autoFit(anchors: a, imageSize: size, category: .top, avatar: avatar)
        let target = GarmentFitter.target(for: .top, level: .shoulders, avatar: avatar)
        XCTAssertPointEqual(fit.apply(CGPoint(x: 80, y: 50)), target.left, accuracy: 1e-9)
        XCTAssertPointEqual(fit.apply(CGPoint(x: 320, y: 50)), target.right, accuracy: 1e-9)
        XCTAssertEqual(Double(target.left.y), avatar.shoulderY, accuracy: 1e-12)
        XCTAssertEqual(target.width, 2 * avatar.shoulderHalfWidth, accuracy: 1e-12)
        // Uniform scale: the garment is not distorted.
        XCTAssertEqual(fit.a, fit.d, accuracy: 1e-12)
    }

    func testOuterwearSitsSlightlyWiderThanTops() {
        let top = GarmentFitter.target(for: .top, level: .shoulders, avatar: avatar)
        let coat = GarmentFitter.target(for: .outerwear, level: .shoulders, avatar: avatar)
        XCTAssertGreaterThan(coat.width, top.width)
        XCTAssertLessThan(coat.width, top.width * 1.1)
    }

    func testFullLengthTrousersEndAtTheAnkle() throws {
        // Waist 160 px wide at y = 10, hem at y = 600 (aspect > 2 → full length).
        let size = CGSize(width: 200, height: 600)
        let a = anchors(CGPoint(x: 0.1, y: 10.0 / 600), CGPoint(x: 0.9, y: 10.0 / 600), hemY: 1, fitsLength: true, level: .waist)
        let fit = GarmentFitter.autoFit(anchors: a, imageSize: size, category: .bottom, avatar: avatar)
        let target = GarmentFitter.target(for: .bottom, level: .waist, avatar: avatar)
        let hem = fit.apply(CGPoint(x: 100, y: 600))
        XCTAssertEqual(Double(hem.y), try XCTUnwrap(target.hemY), accuracy: 1e-9)
        XCTAssertEqual(Double(hem.y), avatar.ankleY + 0.008, accuracy: 1e-9)
        let waistMid = fit.apply(CGPoint(x: 100, y: 10))
        XCTAssertPointEqual(waistMid, target.midpoint, accuracy: 1e-9)
        let anisotropy = fit.a / fit.d
        XCTAssertLessThanOrEqual(anisotropy, GarmentFitter.maxAnisotropy + 1e-9)
        XCTAssertGreaterThanOrEqual(anisotropy, 1 / GarmentFitter.maxAnisotropy - 1e-9)
    }

    func testExtremeAspectIsClampedNotStretched() {
        // Very skinny and long garment: width would need a huge horizontal stretch.
        let size = CGSize(width: 50, height: 1000)
        let a = anchors(CGPoint(x: 0.2, y: 0.01), CGPoint(x: 0.8, y: 0.01), hemY: 1, fitsLength: true, level: .waist)
        let fit = GarmentFitter.autoFit(anchors: a, imageSize: size, category: .bottom, avatar: avatar)
        XCTAssertEqual(fit.a / fit.d, GarmentFitter.maxAnisotropy, accuracy: 1e-9)
    }

    func testShortsScaleUniformlyByWaist() {
        let size = CGSize(width: 300, height: 260)
        let a = anchors(CGPoint(x: 0.05, y: 0.02), CGPoint(x: 0.95, y: 0.02), hemY: 1, fitsLength: false, level: .waist)
        let fit = GarmentFitter.autoFit(anchors: a, imageSize: size, category: .bottom, avatar: avatar)
        XCTAssertEqual(fit.a, fit.d, accuracy: 1e-12)
        let target = GarmentFitter.target(for: .bottom, level: .waist, avatar: avatar)
        XCTAssertEqual(Double(fit.apply(CGPoint(x: 285, y: 5.2)).x), Double(target.right.x), accuracy: 1e-9)
    }

    func testTiltedWidthLineIsLevelled() {
        let size = CGSize(width: 400, height: 400)
        // 10° tilt.
        let angle = 10.0 * Double.pi / 180
        let center = CGPoint(x: 200, y: 100)
        let half = CGPoint(x: cos(angle) * 120, y: sin(angle) * 120)
        let l = center - half, r = center + half
        let a = anchors(CGPoint(x: Double(l.x) / 400, y: Double(l.y) / 400), CGPoint(x: Double(r.x) / 400, y: Double(r.y) / 400), level: .shoulders)
        let fit = GarmentFitter.autoFit(anchors: a, imageSize: size, category: .top, avatar: avatar)
        let target = GarmentFitter.target(for: .top, level: .shoulders, avatar: avatar)
        XCTAssertPointEqual(fit.apply(l), target.left, accuracy: 1e-9)
        XCTAssertPointEqual(fit.apply(r), target.right, accuracy: 1e-9)
    }

    func testLargeTiltIsOnlyPartiallyCorrected() {
        let size = CGSize(width: 400, height: 400)
        let a = anchors(CGPoint(x: 0.25, y: 0.2), CGPoint(x: 0.75, y: 0.7), level: .shoulders) // 45°
        let fit = GarmentFitter.autoFit(anchors: a, imageSize: size, category: .top, avatar: avatar)
        XCTAssertEqual(abs(fit.rotationAngle), GarmentFitter.maxLevelingAngle, accuracy: 1e-9)
    }

    func testShoesStandOnTheFloor() {
        let size = CGSize(width: 300, height: 120)
        let a = anchors(CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), level: .sole)
        let fit = GarmentFitter.autoFit(anchors: a, imageSize: size, category: .shoes, avatar: avatar)
        XCTAssertEqual(Double(fit.apply(CGPoint(x: 150, y: 120)).y), avatar.floorY, accuracy: 1e-9)
        XCTAssertEqual(Double(fit.apply(CGPoint(x: 0, y: 120)).x), -avatar.feetOuterHalfSpan, accuracy: 1e-9)
    }

    func testHatAndEyewearFollowHeadLandmarks() {
        let hat = GarmentFitter.target(for: .hat, level: .brim, avatar: avatar)
        XCTAssertLessThan(Double(hat.left.y), avatar.eyeY)
        XCTAssertGreaterThan(hat.width, 2 * avatar.headHalfWidth)
        let glasses = GarmentFitter.target(for: .eyewear, level: .eyes, avatar: avatar)
        XCTAssertEqual(Double(glasses.midpoint.y), avatar.eyeY, accuracy: 1e-12)
        XCTAssertGreaterThan(glasses.width, avatar.interpupillaryDistance)
    }

    func testBagHangsFromTheHand() {
        let bag = GarmentFitter.target(for: .bag, level: .handle, avatar: avatar)
        XCTAssertEqual(Double(bag.midpoint.x), Double(avatar.wrist.x), accuracy: 0.03)
        XCTAssertEqual(Double(bag.midpoint.y), Double(avatar.wrist.y), accuracy: 0.03)
    }

    func testAdjustmentPivotsAroundAnchor() {
        let garment = makeGarment(category: .top, anchors: anchors(CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.8, y: 0.1), level: .shoulders))
        let pivot = GarmentFitter.pivot(for: garment.anchors, category: .top, avatar: avatar)
        let base = GarmentFitter.placement(for: garment, adjustment: .identity, avatar: avatar)
        let anchorPixel = CGPoint(x: 200, y: 50)
        XCTAssertPointEqual(base.apply(anchorPixel), pivot, accuracy: 1e-9)

        // Scaling and rotating keep the anchor in place.
        let scaled = GarmentFitter.placement(for: garment, adjustment: ItemAdjustment(scale: 1.5, rotation: 0.2), avatar: avatar)
        XCTAssertPointEqual(scaled.apply(anchorPixel), pivot, accuracy: 1e-9)
        XCTAssertEqual(scaled.meanScale, base.meanScale * 1.5, accuracy: 1e-9)

        // Offsets move it by exactly the offset.
        let moved = GarmentFitter.placement(for: garment, adjustment: ItemAdjustment(offset: CGPoint(x: 0.01, y: -0.02)), avatar: avatar)
        XCTAssertPointEqual(moved.apply(anchorPixel), pivot + CGPoint(x: 0.01, y: -0.02), accuracy: 1e-9)
    }

    func testAdjustmentScaleIsClamped() {
        let adj = ItemAdjustment(scale: 100).sanitized
        XCTAssertEqual(adj.scale, ItemAdjustment.scaleRange.upperBound)
        XCTAssertEqual(ItemAdjustment(offset: CGPoint(x: Double.nan, y: 0), scale: .nan, rotation: .infinity).sanitized, .identity)
    }

    // MARK: Face alignment (proportions)

    /// A synthetic face whose landmarks have exactly the avatar's proportions.
    private func idealFace(pixelsPerUnit: Double, roll: Double = 0, origin: CGPoint = CGPoint(x: 300, y: 260), for avatar: AvatarModel) -> FaceAsset {
        let rot = Affine2D.rotation(roll)
        func px(_ body: CGPoint) -> CGPoint {
            // Body-space offset from the eye midpoint, scaled and rotated into pixels.
            let mid = CGPoint.midpoint(avatar.eyeLeft, avatar.eyeRight)
            return origin + rot.applyVector((body - mid) * pixelsPerUnit)
        }
        return FaceAsset(imageFile: "face.png", imageSize: CGSize(width: 600, height: 800),
                         eyeLeft: px(avatar.eyeLeft), eyeRight: px(avatar.eyeRight), chin: px(avatar.chin),
                         skinTone: BodyProfile.defaultSkinTone)
    }

    func testIdealFaceMapsExactlyOntoAvatar() throws {
        let face = idealFace(pixelsPerUnit: 2500, for: avatar)
        let fit = try XCTUnwrap(FaceFitter.autoFit(face: face, avatar: avatar))
        XCTAssertPointEqual(fit.apply(face.eyeLeft), avatar.eyeLeft, accuracy: 1e-9)
        XCTAssertPointEqual(fit.apply(face.eyeRight), avatar.eyeRight, accuracy: 1e-9)
        XCTAssertPointEqual(fit.apply(face.chin), avatar.chin, accuracy: 1e-9)
        XCTAssertEqual(fit.meanScale, 1 / 2500, accuracy: 1e-12)
    }

    func testTiltedFaceIsLevelled() throws {
        let roll = 12.0 * Double.pi / 180
        let face = idealFace(pixelsPerUnit: 1800, roll: roll, for: avatar)
        let fit = try XCTUnwrap(FaceFitter.autoFit(face: face, avatar: avatar))
        let l = fit.apply(face.eyeLeft), r = fit.apply(face.eyeRight)
        XCTAssertEqual(Double(l.y), Double(r.y), accuracy: 1e-9)
        XCTAssertEqual(fit.rotationAngle, -roll, accuracy: 1e-9)
    }

    func testExtremeRollIsClamped() throws {
        let face = idealFace(pixelsPerUnit: 1800, roll: 1.2, for: avatar)
        let fit = try XCTUnwrap(FaceFitter.autoFit(face: face, avatar: avatar))
        XCTAssertEqual(abs(fit.rotationAngle), FaceFitter.maxRoll, accuracy: 1e-9)
        // The chin still lands exactly on the neck and the head keeps its size.
        XCTAssertPointEqual(fit.apply(face.chin), avatar.chin, accuracy: 1e-9)
        XCTAssertEqual(fit.meanScale, 1 / 1800, accuracy: 1e-12)
    }

    func testHeadIsOneHeadHeightForEveryStature() throws {
        // The core proportion guarantee: whatever the photo's resolution, the
        // placed head is exactly the anthropometric head height for the user's
        // stature (e.g. 1/7.7 of a 175 cm body).
        for height in [150.0, 165, 175, 190] {
            let a = AvatarModel(profile: BodyProfile(heightCM: height))
            for ppu in [600.0, 2400, 9000] {
                let face = idealFace(pixelsPerUnit: ppu, for: a)
                let placement = try XCTUnwrap(FaceFitter.placement(face: face, avatar: a))
                let headHeight = FaceFitter.impliedHeadHeight(face: face, placement: placement)
                XCTAssertEqual(headHeight, a.headHeight, accuracy: a.headHeight * 1e-6)
                XCTAssertEqual(headHeight * height, Anthropometry.headHeightCM(forStatureCM: height), accuracy: 0.01)
            }
        }
    }

    func testFaceWithDifferentShapeStaysCloseAndUndistorted() throws {
        // A longer-than-average face: chin 15% further from the eyes.
        var face = idealFace(pixelsPerUnit: 2000, for: avatar)
        let mid = CGPoint.midpoint(face.eyeLeft, face.eyeRight)
        face.chin = mid + (face.chin - mid) * 1.15
        let fit = try XCTUnwrap(FaceFitter.autoFit(face: face, avatar: avatar))
        XCTAssertEqual(fit.a, fit.d, accuracy: 1e-12, "uniform scale only")
        // Landmarks land within a few millimetres of the targets.
        let tolerance = 0.012 // ~2 cm at 170 cm
        XCTAssertPointEqual(fit.apply(face.chin), avatar.chin, accuracy: tolerance)
        XCTAssertPointEqual(fit.apply(face.eyeLeft), avatar.eyeLeft, accuracy: tolerance)
    }

    func testFaceAdjustmentScalesAroundEyes() throws {
        var face = idealFace(pixelsPerUnit: 2000, for: avatar)
        face.adjustment = ItemAdjustment(scale: 1.1)
        let placement = try XCTUnwrap(FaceFitter.placement(face: face, avatar: avatar))
        let eyeMid = placement.apply(.midpoint(face.eyeLeft, face.eyeRight))
        XCTAssertPointEqual(eyeMid, FaceFitter.pivot(avatar: avatar), accuracy: 1e-9)
        XCTAssertEqual(FaceFitter.impliedHeadHeight(face: face, placement: placement), avatar.headHeight * 1.1, accuracy: 1e-9)
    }

    func testDegenerateFaceReturnsNil() {
        let p = CGPoint(x: 10, y: 10)
        let face = FaceAsset(imageFile: "f.png", imageSize: CGSize(width: 10, height: 10), eyeLeft: p, eyeRight: p, chin: p, skinTone: .white)
        XCTAssertNil(FaceFitter.autoFit(face: face, avatar: avatar))
    }

    func testGarmentAndFaceShareTheSameScaleRelationship() throws {
        // A person photographed at one scale: their shoulders (from the same
        // photo) and face should come out consistent with the avatar's proportions.
        let ppu = 1500.0
        let face = idealFace(pixelsPerUnit: ppu, for: avatar)
        let facePlacement = try XCTUnwrap(FaceFitter.placement(face: face, avatar: avatar))
        let shoulderWidthPx = 2 * avatar.shoulderHalfWidth * ppu
        let size = CGSize(width: shoulderWidthPx * 1.4, height: shoulderWidthPx * 1.6)
        let l = (size.width - shoulderWidthPx) / 2
        let a = anchors(CGPoint(x: l / size.width, y: 0.1), CGPoint(x: (l + shoulderWidthPx) / size.width, y: 0.1), level: .shoulders)
        let topPlacement = GarmentFitter.autoFit(anchors: a, imageSize: size, category: .top, avatar: avatar)
        XCTAssertEqual(topPlacement.meanScale, facePlacement.meanScale, accuracy: 1e-9)
    }
}
