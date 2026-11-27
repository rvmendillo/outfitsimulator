#if canImport(Vision)
import CoreGraphics
import Foundation
import XCTest
@testable import OutfitKit

/// Prints what Vision and the parser report for the face fixture, so results
/// can be compared between macOS and the iOS Simulator in CI logs.
final class DiagnosticsTests: XCTestCase {
    func testPrintFaceDiagnostics() async throws {
        let image = try Fixtures.image("face_portrait.jpg")
        let working = ImageCodec.downscaled(image, maxSide: 1600)
        func f(_ p: CGPoint) -> String { String(format: "(%.0f,%.0f)", Double(p.x), Double(p.y)) }
        if let face = try FaceAnalyzer.detect(in: working) {
            print("DIAG image \(working.width)x\(working.height)")
            print("DIAG bbox \(face.boundingBox) eyeL \(f(face.eyeLeft)) eyeR \(f(face.eyeRight)) chin \(f(face.chin))")
            print("DIAG contour[\(face.faceContour.count)] \(face.faceContour.map(f).joined(separator: " "))")
            print("DIAG lips[\(face.outerLips.count)] \(face.outerLips.map(f).joined(separator: " "))")
            print("DIAG yaw \(face.yaw.map { $0 * 180 / .pi } ?? .nan) roll \(face.roll.map { $0 * 180 / .pi } ?? .nan) pitch \(face.pitch.map { $0 * 180 / .pi } ?? .nan) faces \(face.faceCount)")
        } else {
            print("DIAG no face")
        }
        if let parser = try? await TestModel.parser() {
            let map = try parser.parse(working)
            let fractions = ParserLabel.allCases.map { "\($0)=\(String(format: "%.4f", map.fraction(of: [$0])))" }
            print("DIAG labels \(fractions.joined(separator: " "))")
        }
        let head = try HeadExtractor(parser: try? await TestModel.parser()).extract(from: image)
        print("DIAG head \(head.image.width)x\(head.image.height) eyeL \(f(head.eyeLeft)) eyeR \(f(head.eyeRight)) chin \(f(head.chin)) warnings \(head.warnings)")
    }
}
#endif
