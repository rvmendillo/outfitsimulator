#if canImport(Vision)
import CoreGraphics
import Foundation
import XCTest
@testable import OutfitKit

enum Fixtures {
    static func url(_ name: String) throws -> URL {
        let parts = name.split(separator: ".")
        return try XCTUnwrap(Bundle.module.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: "Fixtures"),
                             "missing fixture \(name)")
    }

    static func image(_ name: String, maxSide: Int = 2048) throws -> CGImage {
        try XCTUnwrap(ImageCodec.loadUpright(url: url(name), maxPixelSize: maxSide), "unreadable fixture \(name)")
    }
}

enum TestModel {
    static var cached: ClothingParser?

    static var repoRoot: URL {
        // .../Packages/OutfitKit/Tests/OutfitKitTests/Support.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The clothing parser compiled from `Models/build`, or nil when the model
    /// has not been generated (tests that need it are skipped, unless
    /// REQUIRE_PARSER_MODEL=1 makes that a failure, as on CI).
    static func parser() async throws -> ClothingParser {
        if let cached { return cached }
        let env = ProcessInfo.processInfo.environment
        let url = env["OUTFIT_PARSER_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? repoRoot.appendingPathComponent("Models/build/ClothingParserModel.mlpackage")
        guard FileManager.default.fileExists(atPath: url.path) else {
            if env["REQUIRE_PARSER_MODEL"] == "1" {
                XCTFail("Parser model missing at \(url.path)")
            }
            throw XCTSkip("Parser model not generated (run Models/convert_clothing_parser.py)")
        }
        let compiled = try await ClothingParser.compileModel(at: url)
        let parser = try ClothingParser(compiledModelURL: compiled)
        cached = parser
        return parser
    }
}

enum Artifacts {
    /// Directory for visual-check images (set OUTFIT_ARTIFACTS_DIR).
    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["OUTFIT_ARTIFACTS_DIR"] else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ image: CGImage?, _ name: String) {
        guard let image, let dir = directory, let data = ImageCodec.pngData(image) else { return }
        try? data.write(to: dir.appendingPathComponent(name))
    }
}

extension RGBABitmap {
    /// Un-premultiplied colour, or nil when transparent.
    func rgb(_ x: Int, _ y: Int) -> RGBColor? { color(x: x, y: y) }
}

func makeBitmap(width: Int, height: Int, background: RGBColor, draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // y-down drawing for the callers.
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}
#endif
