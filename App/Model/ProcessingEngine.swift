import CoreGraphics
import Foundation
import OutfitKit

/// Runs the heavy image work (segmentation, head extraction, encoding) off the
/// main thread, one job at a time.
actor ProcessingEngine {
    private var parser: ClothingParser?
    private var didLoadParser = false
    private(set) var parserError: String?

    /// Loads the bundled clothing parser once.
    func loadParser() -> ClothingParser? {
        if !didLoadParser {
            didLoadParser = true
            if let url = ClothingParser.bundledModelURL() {
                do {
                    parser = try ClothingParser(compiledModelURL: url)
                } catch {
                    parserError = error.localizedDescription
                }
            } else {
                parserError = ClothingParserError.modelNotFound.localizedDescription
            }
        }
        return parser
    }

    func hasParser() -> Bool { loadParser() != nil }

    func extractGarments(from data: Data) throws -> ExtractionResult {
        guard let image = ImageCodec.loadUpright(data: data, maxPixelSize: 2048) else { throw ImageError.unreadable }
        return try GarmentExtractor(parser: loadParser()).extract(from: image)
    }

    func extractHead(from data: Data) throws -> HeadCutout {
        guard let image = ImageCodec.loadUpright(data: data, maxPixelSize: 2048) else { throw ImageError.unreadable }
        return try HeadExtractor(parser: loadParser()).extract(from: image)
    }

    /// Everything needed to store a piece: encoded files and metadata.
    struct EncodedPiece: Sendable {
        var cutoutPNG: Data
        var sourceJPEG: Data
        var maskPNG: Data
        var thumbnailPNG: Data
        var size: CGSize
    }

    static func encode(source: RGBABitmap, mask: AlphaMask) throws -> EncodedPiece {
        let cut = CutoutComposer.compose(source: source, mask: mask)
        guard let cutImage = cut.makeCGImage(), let cutoutPNG = ImageCodec.pngData(cutImage),
              let sourceImage = source.makeCGImage(), let sourceJPEG = ImageCodec.jpegData(sourceImage, quality: 0.9),
              let maskImage = mask.makeGrayscaleCGImage(), let maskPNG = ImageCodec.pngData(maskImage) else {
            throw ImageError.encodingFailed
        }
        let thumb = ImageCodec.downscaled(cutImage, maxSide: 360)
        guard let thumbnailPNG = ImageCodec.pngData(thumb) else { throw ImageError.encodingFailed }
        return EncodedPiece(cutoutPNG: cutoutPNG, sourceJPEG: sourceJPEG, maskPNG: maskPNG, thumbnailPNG: thumbnailPNG,
                            size: CGSize(width: cut.width, height: cut.height))
    }

    func encodePiece(source: RGBABitmap, mask: AlphaMask) throws -> EncodedPiece {
        try Self.encode(source: source, mask: mask)
    }

    func encodeHead(_ head: HeadCutout) throws -> Data {
        guard let image = head.image.makeCGImage(), let png = ImageCodec.pngData(image) else { throw ImageError.encodingFailed }
        return png
    }
}
