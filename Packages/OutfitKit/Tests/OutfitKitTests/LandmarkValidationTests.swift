#if canImport(Vision)
import CoreGraphics
import Foundation
import XCTest
@testable import OutfitKit

/// Landmark validation using real values recorded from Vision on macOS (good)
/// and on the iOS Simulator (corrupted) for the same portrait.
final class LandmarkValidationTests: XCTestCase {
    let macBox = CGRect(x: 178.3, y: 205.0, width: 251.1, height: 251.1)
    let simBox = CGRect(x: 179.0, y: 206.6, width: 248.1, height: 248.1)

    func testGoodEyesAreKept() {
        let (l, r) = FaceAnalyzer.plausibleEyes(CGPoint(x: 339, y: 266), CGPoint(x: 261, y: 280), faceBox: macBox)
        XCTAssertEqual(l, CGPoint(x: 261, y: 280))
        XCTAssertEqual(r, CGPoint(x: 339, y: 266))
    }

    func testCorruptedEyesFallBackToFaceBoxGeometry() {
        let (l, r) = FaceAnalyzer.plausibleEyes(CGPoint(x: 322, y: 310), CGPoint(x: 332, y: 304), faceBox: simBox)
        XCTAssertEqual(Double(l.x), Double(simBox.minX) + 0.3 * Double(simBox.width), accuracy: 1e-9)
        XCTAssertEqual(Double(r.x), Double(simBox.minX) + 0.7 * Double(simBox.width), accuracy: 1e-9)
        XCTAssertEqual(Double(l.y), Double(r.y), accuracy: 1e-9)
        let missing = FaceAnalyzer.plausibleEyes(nil, CGPoint(x: 1, y: 1), faceBox: simBox)
        XCTAssertEqual(missing.0, l)
    }

    func testGoodChinIsKept() {
        let contour = [(452, 267), (452, 301), (450, 336), (442, 370), (423, 399), (395, 421), (364, 437), (331, 448), (296, 452),
                       (278, 440), (267, 420), (257, 400), (249, 379), (243, 357), (238, 334), (239, 311), (244, 289)]
            .map { CGPoint(x: $0.0, y: $0.1) }
        let lips = [(264, 382), (290, 367), (336, 380), (303, 400), (285, 405)].map { CGPoint(x: $0.0, y: $0.1) }
        let chin = FaceAnalyzer.plausibleChin(eyeLeft: CGPoint(x: 261, y: 280), eyeRight: CGPoint(x: 339, y: 266),
                                              contour: contour, lips: lips, faceBox: macBox)
        XCTAssertEqual(chin, CGPoint(x: 296, y: 452))
    }

    func testCorruptedChinFallsBackToFaceBoxBottom() {
        let (l, r) = FaceAnalyzer.plausibleEyes(CGPoint(x: 322, y: 310), CGPoint(x: 332, y: 304), faceBox: simBox)
        let contour = [(354, 281), (357, 287), (360, 294), (364, 303), (367, 311), (368, 319), (369, 329), (372, 340), (369, 351),
                       (357, 351), (347, 346), (336, 340), (327, 335), (318, 328), (311, 319), (306, 310), (303, 301)]
            .map { CGPoint(x: $0.0, y: $0.1) }
        let lips = [(357, 329), (363, 325), (372, 314), (371, 325), (353, 328)].map { CGPoint(x: $0.0, y: $0.1) }
        let chin = FaceAnalyzer.plausibleChin(eyeLeft: l, eyeRight: r, contour: contour, lips: lips, faceBox: simBox)
        XCTAssertEqual(Double(chin.y), Double(simBox.maxY), accuracy: 1e-9)
        XCTAssertEqual(Double(chin.x), Double(simBox.midX), accuracy: 1e-9)
    }

    func testChinNeverAboveTheMouth() {
        // A contour that ends at the mouth must be rejected.
        let eyes = (CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 100))
        let lips = [CGPoint(x: 120, y: 170), CGPoint(x: 140, y: 175)]
        let box = CGRect(x: 60, y: 60, width: 140, height: 160)
        let chin = FaceAnalyzer.plausibleChin(eyeLeft: eyes.0, eyeRight: eyes.1, contour: [CGPoint(x: 130, y: 172)], lips: lips, faceBox: box)
        XCTAssertGreaterThan(chin.y, 175)
    }
}
#endif
