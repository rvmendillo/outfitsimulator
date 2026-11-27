import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

final class ModelTests: XCTestCase {
    func testOutfitAddReplacesExclusiveCategory() {
        let top1 = makeGarment(category: .top), top2 = makeGarment(category: .top)
        let ring = makeGarment(category: .accessory), necklace = makeGarment(category: .accessory)
        let all = Dictionary(uniqueKeysWithValues: [top1, top2, ring, necklace].map { ($0.id, $0) })
        var outfit = Outfit(name: "x")
        let lookup: (UUID) -> GarmentCategory? = { all[$0]?.category }
        outfit.add(top1, categoryOf: lookup)
        outfit.add(ring, categoryOf: lookup)
        outfit.add(top2, categoryOf: lookup)
        outfit.add(necklace, categoryOf: lookup)
        outfit.add(necklace, categoryOf: lookup) // duplicate ignored
        XCTAssertEqual(outfit.garmentIDs, [ring.id, top2.id, necklace.id])
        outfit.remove(ring.id)
        XCTAssertFalse(outfit.contains(ring.id))
    }

    func testAnchorsNormalization() {
        let a = GarmentAnchors(left: CGPoint(x: 1.4, y: -0.2), right: CGPoint(x: 0.2, y: 0.5), hemY: 3, fitsLength: true, level: .waist, source: .user)
        let n = a.normalized
        XCTAssertEqual(n.left, CGPoint(x: 0.2, y: 0.5))
        XCTAssertEqual(n.right, CGPoint(x: 1, y: 0))
        XCTAssertEqual(n.hemY, 1)
        let nan = GarmentAnchors(left: CGPoint(x: Double.nan, y: 0), right: CGPoint(x: 1, y: 0), hemY: .nan, fitsLength: false, level: .waist, source: .user).normalized
        XCTAssertEqual(nan.left.x, 0.5)
        XCTAssertEqual(nan.hemY, 1)
    }

    func testFallbackAnchorsAreSensible() {
        for category in GarmentCategory.allCases {
            let a = GarmentAnchors.fallback(for: category)
            XCTAssertLessThan(a.left.x, a.right.x)
            XCTAssertEqual(a.level, category.defaultAnchorLevel)
        }
    }

    func testPoseOrderingAndTranslation() {
        let (l, r) = PoseJoints.ordered(CGPoint(x: 10, y: 0), CGPoint(x: 2, y: 0))
        XCTAssertEqual(l, CGPoint(x: 2, y: 0))
        XCTAssertEqual(r, CGPoint(x: 10, y: 0))
        let (a, b) = PoseJoints.ordered(nil, CGPoint(x: 1, y: 1))
        XCTAssertNil(a)
        XCTAssertEqual(b, CGPoint(x: 1, y: 1))
        let pose = PoseJoints(neck: CGPoint(x: 50, y: 60), hipL: CGPoint(x: 40, y: 200))
        let moved = pose.translated(by: CGPoint(x: 10, y: 20))
        XCTAssertEqual(moved.neck, CGPoint(x: 40, y: 40))
        XCTAssertEqual(moved.hipL, CGPoint(x: 30, y: 180))
        XCTAssertNil(moved.ankleR)
    }

    func testJSONRoundTrip() throws {
        var g = makeGarment(category: .shoes, color: SRGBColor(hex: "#6B4428")!)
        g.sourceFile = "src.jpg"
        g.maskFile = "mask.png"
        let library = Library(garments: [g], outfits: [Outfit(name: "o", items: [OutfitItem(garmentID: g.id)])], profile: UserProfile(hasCompletedOnboarding: true))
        let data = try WardrobeStore.encoder.encode(library)
        let decoded = try WardrobeStore.decoder.decode(Library.self, from: data)
        XCTAssertEqual(decoded, library)
        XCTAssertEqual(Set(decoded.referencedFiles), Set([g.imageFile, "src.jpg", "mask.png"]))
    }

    func testSkinTonePriority() {
        var profile = UserProfile()
        XCTAssertEqual(profile.effectiveSkinTone, BodyProfile.defaultSkinTone)
        profile.face = FaceAsset(imageFile: "f.png", imageSize: CGSize(width: 1, height: 1), eyeLeft: .zero, eyeRight: .zero, chin: .zero, skinTone: .black)
        XCTAssertEqual(profile.effectiveSkinTone, .black)
        profile.body.skinToneOverride = .white
        XCTAssertEqual(profile.effectiveSkinTone, .white)
    }

    func testHeightFormatting() {
        XCTAssertEqual(HeightFormatter.string(fromCentimetres: 170, units: .metric), "170 cm")
        XCTAssertEqual(HeightFormatter.string(fromCentimetres: 170, units: .imperial), "5′ 7″")
        let (feet, inches) = HeightFormatter.feetAndInches(fromCentimetres: 182.88)
        XCTAssertEqual(feet, 6)
        XCTAssertEqual(inches, 0)
        XCTAssertEqual(HeightFormatter.centimetres(feet: 5, inches: 10), 177.8, accuracy: 1e-9)
    }

    func testCategoryMetadataIsComplete() {
        XCTAssertEqual(Set(GarmentCategory.closetOrder), Set(GarmentCategory.allCases))
        XCTAssertEqual(Set(GarmentCategory.allCases.map(\.baseZ)).count, GarmentCategory.allCases.count, "distinct z per category")
        for c in GarmentCategory.allCases {
            XCTAssertFalse(c.displayName.isEmpty)
            XCTAssertFalse(c.symbolName.isEmpty)
            XCTAssertNotEqual(c.baseZ, SceneZ.head)
        }
        XCTAssertLessThan(SceneZ.tuckedTop, GarmentCategory.bottom.baseZ)
        XCTAssertGreaterThan(SceneZ.head, GarmentCategory.outerwear.baseZ)
        XCTAssertLessThan(SceneZ.head, GarmentCategory.hat.baseZ)
    }
}

final class AvatarShapeTests: XCTestCase {
    func testBodyOutlineIsSymmetricAndSpansBody() {
        for shape in BodyShape.allCases {
            let a = AvatarModel(profile: BodyProfile(heightCM: 172, shape: shape))
            let outline = AvatarShape.bodyOutline(a)
            for p in outline {
                XCTAssertTrue(outline.contains { abs(Double($0.x) + Double(p.x)) < 1e-12 && abs(Double($0.y) - Double(p.y)) < 1e-12 }, "mirror of \(p)")
            }
            let ys = outline.map { Double($0.y) }
            XCTAssertEqual(ys.max()!, a.floorY, accuracy: 1e-12)
            XCTAssertLessThan(ys.min()!, a.chinY)
            XCTAssertGreaterThan(ys.min()!, a.eyeY, "neck stays under the head")
            let xs = outline.map { Double($0.x) }
            XCTAssertEqual(xs.max()!, a.shoulderHalfWidth, accuracy: 1e-12)
        }
    }

    func testDressedTorsoIsNarrowerButNeckAndLegsAreNot() {
        let a = AvatarModel(profile: BodyProfile(heightCM: 172))
        let full = AvatarShape.bodyOutline(a)
        let slim = AvatarShape.bodyOutline(a, torsoScale: 0.86)
        XCTAssertEqual(full.count, slim.count)
        XCTAssertEqual(slim.map { Double($0.x) }.max()!, a.shoulderHalfWidth * 0.86, accuracy: 1e-9)
        // Neck (first points) and feet are unchanged.
        XCTAssertEqual(full[0], slim[0])
        XCTAssertEqual(full.map(\.y).max(), slim.map(\.y).max())
        XCTAssertTrue(slim.contains(CGPoint(x: a.ankleX + a.footHalfWidth * 0.7, y: a.floorY)))
    }

    func testArmsHangBesideTheBody() {
        let a = AvatarModel(profile: BodyProfile(heightCM: 172))
        let parts = AvatarShape.parts(for: a, includeHead: true)
        XCTAssertEqual(parts.map(\.kind), [.armLeft, .armRight, .body, .head])
        let right = parts[1].outline
        XCTAssertTrue(right.allSatisfy { $0.x > 0 })
        XCTAssertTrue(right.contains(a.fingertip))
        let left = parts[0].outline
        XCTAssertTrue(left.contains(a.fingertip.mirroredX))

        var noArms = a.profile
        noArms.showArms = false
        let partsWithoutArms = AvatarShape.parts(for: AvatarModel(profile: noArms), includeHead: false)
        XCTAssertEqual(partsWithoutArms.map(\.kind), [.body])
    }

    func testHeadOutlineMatchesHeadHeight() {
        let a = AvatarModel(profile: BodyProfile(heightCM: 160))
        let head = AvatarShape.headOutline(a)
        let ys = head.map { Double($0.y) }
        XCTAssertEqual(ys.min()!, 0, accuracy: 1e-12)
        XCTAssertEqual(ys.max()!, a.headHeight, accuracy: 1e-12)
    }

    func testBaseLayerStaysOnTheTorso() {
        let a = AvatarModel(profile: BodyProfile(heightCM: 172, shape: .feminine))
        for part in AvatarShape.baseLayer(for: a) {
            for p in part.outline {
                XCTAssertLessThanOrEqual(abs(Double(p.x)), a.shoulderHalfWidth)
                XCTAssertGreaterThan(Double(p.y), a.neckBaseY)
                XCTAssertLessThan(Double(p.y), a.kneeY)
            }
        }
    }

    func testSmoothPathStructure() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let elements = PathBuilder.smoothClosed(pts)
        XCTAssertEqual(elements.count, pts.count + 2)
        XCTAssertEqual(elements.first, .move(pts[0]))
        XCTAssertEqual(elements.last, .close)
        // Curves pass through every input point.
        let ends = elements.compactMap { e -> CGPoint? in
            if case let .cubic(_, _, p) = e { return p }
            return nil
        }
        XCTAssertEqual(ends, [pts[1], pts[2], pts[3], pts[0]])
        XCTAssertEqual(PathBuilder.polygon(pts).count, 5) // move + 3 lines + close
        XCTAssertTrue(PathBuilder.smoothClosed([]).isEmpty)
    }

    func testCatmullRomControlPointsOnStraightLine() {
        let (c1, c2) = PathBuilder.controlPoints(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 3, y: 0))
        XCTAssertPointEqual(c1, CGPoint(x: 4.0 / 3, y: 0), accuracy: 1e-12)
        XCTAssertPointEqual(c2, CGPoint(x: 5.0 / 3, y: 0), accuracy: 1e-12)
    }

    func testPathBoundsAndTransform() {
        let elements = PathBuilder.polygon([CGPoint(x: -1, y: 2), CGPoint(x: 3, y: 2), CGPoint(x: 3, y: 5)])
        XCTAssertEqual(PathBuilder.bounds(of: elements), CGRect(x: -1, y: 2, width: 4, height: 3))
        let moved = PathBuilder.transformed(elements, by: .translation(1, 1))
        XCTAssertEqual(PathBuilder.bounds(of: moved), CGRect(x: 0, y: 3, width: 4, height: 3))
    }
}
