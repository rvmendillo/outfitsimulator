import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

final class AnthropometryTests: XCTestCase {
    func testReferenceStatureMatchesDrillisContini() {
        XCTAssertEqual(Anthropometry.headRatio(forStatureCM: 175), 0.130, accuracy: 1e-9)
        XCTAssertEqual(Anthropometry.headsTall(forStatureCM: 175), 7.69, accuracy: 0.01)
    }

    func testHeadsTallGrowsWithStature() {
        var previous = 0.0
        for height in stride(from: 120.0, through: 220.0, by: 5) {
            let heads = Anthropometry.headsTall(forStatureCM: height)
            XCTAssertGreaterThan(heads, previous)
            previous = heads
        }
        // Typical adult range: roughly 7 to 8 heads tall.
        XCTAssertEqual(Anthropometry.headsTall(forStatureCM: 150), 7.0, accuracy: 0.15)
        XCTAssertEqual(Anthropometry.headsTall(forStatureCM: 190), 8.1, accuracy: 0.15)
        // Real head heights stay plausible (~21-24 cm).
        XCTAssertEqual(Anthropometry.headHeightCM(forStatureCM: 150), 21.4, accuracy: 0.3)
        XCTAssertEqual(Anthropometry.headHeightCM(forStatureCM: 190), 23.5, accuracy: 0.3)
    }

    func testLandmarksAreOrderedTopToBottom() {
        for shape in BodyShape.allCases {
            for height in [120.0, 150, 175, 200, 220] {
                let a = AvatarModel(profile: BodyProfile(heightCM: height, shape: shape))
                let ys = [0, a.eyeY, a.chinY, a.neckBaseY, a.shoulderY, a.armpitY, a.chestY, a.waistY,
                          a.trouserWaistY, a.hipY, a.crotchY, a.kneeY, a.calfY, a.ankleY, a.floorY]
                for i in 1..<ys.count {
                    XCTAssertGreaterThan(ys[i], ys[i - 1], "landmark \(i) for \(shape) \(height)")
                }
                XCTAssertEqual(a.floorY, 1)
                XCTAssertEqual(a.eyeY, a.chinY / 2, accuracy: 1e-12)
                XCTAssertEqual(a.headHeight, Anthropometry.headRatio(forStatureCM: height), accuracy: 1e-12)
            }
        }
    }

    func testReferenceLandmarksMatchStandardTable() {
        let a = AvatarModel(profile: BodyProfile(heightCM: 175))
        XCTAssertEqual(a.shoulderY, Anthropometry.Standard.shoulder, accuracy: 1e-9)
        XCTAssertEqual(a.hipY, Anthropometry.Standard.hip, accuracy: 1e-9)
        XCTAssertEqual(a.kneeY, Anthropometry.Standard.knee, accuracy: 1e-9)
        XCTAssertEqual(a.ankleY, Anthropometry.Standard.ankle, accuracy: 1e-9)
    }

    func testRealWorldWidthsArePlausible() {
        let man = AvatarModel(profile: BodyProfile(heightCM: 178, shape: .masculine))
        let woman = AvatarModel(profile: BodyProfile(heightCM: 163, shape: .feminine))
        // Bideltoid breadth ~44-50 cm (men) and ~38-44 cm (women).
        XCTAssertEqual(2 * man.shoulderHalfWidth * 178, 47, accuracy: 3)
        XCTAssertEqual(2 * woman.shoulderHalfWidth * 163, 40, accuracy: 3)
        // Hips are proportionally wider on the feminine silhouette.
        XCTAssertGreaterThan(woman.hipHalfWidth / woman.shoulderHalfWidth, man.hipHalfWidth / man.shoulderHalfWidth)
        // Interpupillary distance ~ 60-66 mm.
        XCTAssertEqual(man.interpupillaryDistance * 178, 6.3, accuracy: 0.3)
    }

    func testArmsHangAtAnatomicalHeights() {
        for shape in BodyShape.allCases {
            let a = AvatarModel(profile: BodyProfile(heightCM: 170, shape: shape))
            XCTAssertEqual(Double(a.elbow.y), a.waistY, accuracy: 0.03, "elbows at waist level")
            XCTAssertEqual(Double(a.wrist.y), a.crotchY, accuracy: 0.03, "wrists at crotch level")
            XCTAssertGreaterThan(Double(a.fingertip.y), a.crotchY + 0.05, "fingertips at mid-thigh")
            XCTAssertLessThan(Double(a.fingertip.y), a.kneeY)
            // Hands clear the hips in the A-pose.
            XCTAssertGreaterThan(Double(a.wrist.x) - a.wristHalfWidth, a.hipHalfWidth)
        }
    }

    func testBuildChangesWidthsNotHeights() {
        let slim = AvatarModel(profile: BodyProfile(heightCM: 170, build: 0.85))
        let broad = AvatarModel(profile: BodyProfile(heightCM: 170, build: 1.25))
        XCTAssertLessThan(slim.waistHalfWidth, broad.waistHalfWidth)
        XCTAssertLessThan(slim.shoulderHalfWidth, broad.shoulderHalfWidth)
        XCTAssertEqual(slim.hipY, broad.hipY)
        XCTAssertEqual(slim.headHalfWidth, broad.headHalfWidth)
    }

    func testProfileIsSanitized() {
        let a = AvatarModel(profile: BodyProfile(heightCM: 999, build: -5))
        XCTAssertEqual(a.profile.heightCM, BodyProfile.heightRange.upperBound)
        XCTAssertEqual(a.profile.build, BodyProfile.buildRange.lowerBound)
        let b = AvatarModel(profile: BodyProfile(heightCM: .nan, build: .infinity))
        XCTAssertEqual(b.profile.heightCM, 170)
        XCTAssertEqual(b.profile.build, 1)
    }

    func testTorsoWidthInterpolation() {
        let a = AvatarModel(profile: BodyProfile(heightCM: 170))
        XCTAssertEqual(a.torsoHalfWidth(atY: a.waistY), a.waistHalfWidth, accuracy: 1e-12)
        XCTAssertEqual(a.torsoHalfWidth(atY: a.hipY), a.hipHalfWidth, accuracy: 1e-12)
        let between = a.torsoHalfWidth(atY: (a.waistY + a.hipY) / 2)
        XCTAssertGreaterThan(between, min(a.waistHalfWidth, a.hipHalfWidth) - 1e-12)
        XCTAssertLessThan(between, max(a.waistHalfWidth, a.hipHalfWidth) + 1e-12)
        XCTAssertEqual(a.torsoHalfWidth(atY: -1), a.neckHalfWidth * 1.08, accuracy: 1e-12)
    }
}
