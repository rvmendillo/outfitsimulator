#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageError: Error, LocalizedError, Equatable {
    case unreadable
    case encodingFailed
    case contextFailed
    case emptyImage

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "The image could not be read."
        case .encodingFailed: return "The image could not be saved."
        case .contextFailed: return "Not enough memory to process the image."
        case .emptyImage: return "The image is empty."
        }
    }
}

enum ColorSpaces {
    static let sRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let gray: CGColorSpace = CGColorSpaceCreateDeviceGray()
}

/// 8-bit RGBA pixels with premultiplied alpha in sRGB, row 0 = top row.
public struct RGBABitmap: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "bitmap size mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (0, 0, 0, 0)) {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        var i = 0
        while i < px.count {
            px[i] = fill.r; px[i + 1] = fill.g; px[i + 2] = fill.b; px[i + 3] = fill.a
            i += 4
        }
        self.init(width: width, height: height, pixels: px)
    }

    /// Draws `cgImage` into an sRGB RGBA buffer (any source format is converted).
    public init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: ColorSpaces.sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, pixels: px)
    }

    public func makeCGImage() -> CGImage? {
        guard width > 0, height > 0,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: ColorSpaces.sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    @inline(__always)
    public func alpha(x: Int, y: Int) -> UInt8 {
        pixels[(y * width + x) * 4 + 3]
    }

    /// Un-premultiplied colour of a pixel (nil when fully transparent).
    public func color(x: Int, y: Int) -> RGBColor? {
        let i = (y * width + x) * 4
        let a = Double(pixels[i + 3])
        guard a > 0 else { return nil }
        return RGBColor(r: Double(pixels[i]) / a, g: Double(pixels[i + 1]) / a, b: Double(pixels[i + 2]) / a)
    }

    public func cropped(to rect: PixelRect) -> RGBABitmap {
        let minX = max(0, rect.minX), minY = max(0, rect.minY)
        let maxX = min(width - 1, rect.maxX), maxY = min(height - 1, rect.maxY)
        guard maxX >= minX, maxY >= minY else { return RGBABitmap(width: 0, height: 0, pixels: []) }
        let w = maxX - minX + 1, h = maxY - minY + 1
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let src = ((minY + y) * width + minX) * 4
            let dst = y * w * 4
            for i in 0..<(w * 4) { out[dst + i] = pixels[src + i] }
        }
        return RGBABitmap(width: w, height: h, pixels: out)
    }

    /// Alpha channel as a mask.
    public var alphaMask: AlphaMask {
        var values = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) { values[i] = pixels[i * 4 + 3] }
        return AlphaMask(width: width, height: height, values: values)
    }

    /// Bilinear resize via Core Graphics.
    public func resized(width newWidth: Int, height newHeight: Int) -> RGBABitmap? {
        guard let image = makeCGImage() else { return nil }
        return ImageCodec.resized(image, width: newWidth, height: newHeight).flatMap(RGBABitmap.init(cgImage:))
    }
}

public extension AlphaMask {
    /// Reads an 8-bit grayscale (or any) image's luminance as mask values.
    init?(grayscaleImage image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var values = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = values.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: ColorSpaces.gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, values: values)
    }

    func makeGrayscaleCGImage() -> CGImage? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(values) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: ColorSpaces.gray, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Reads a one-component pixel buffer (8-bit or 32-bit float, as produced by Vision).
    init?(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let w = CVPixelBufferGetWidth(pixelBuffer), h = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        var values = [UInt8](repeating: 0, count: w * h)
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<h {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<w { values[y * w + x] = row[x] }
            }
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<h {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in 0..<w {
                    let v = row[x].isFinite ? row[x] : 0
                    values[y * w + x] = UInt8(max(0, min(255, (v * 255).rounded())))
                }
            }
        default:
            return nil
        }
        self.init(width: w, height: h, values: values)
    }
}

public enum ImageCodec {
    /// Decodes and applies the EXIF orientation, downscaling so the longest
    /// side is at most `maxPixelSize`.
    public static func loadUpright(data: Data, maxPixelSize: Int = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return uprightImage(from: source, maxPixelSize: maxPixelSize)
    }

    public static func loadUpright(url: URL, maxPixelSize: Int = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return uprightImage(from: source, maxPixelSize: maxPixelSize)
    }

    static func uprightImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Decodes without resizing (for PNGs the app wrote itself).
    public static func decode(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    public static func pngData(_ image: CGImage) -> Data? {
        encode(image, type: UTType.png, properties: nil)
    }

    public static func jpegData(_ image: CGImage, quality: Double = 0.9) -> Data? {
        encode(image, type: UTType.jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    }

    static func encode(_ image: CGImage, type: UTType, properties: CFDictionary?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// High-quality resize into an sRGB RGBA image.
    public static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: ColorSpaces.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Scales down (never up) so the longest side is at most `maxSide`.
    public static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide, maxSide > 0 else { return image }
        let s = Double(maxSide) / Double(longest)
        let w = max(1, Int((Double(image.width) * s).rounded()))
        let h = max(1, Int((Double(image.height) * s).rounded()))
        return resized(image, width: w, height: h) ?? image
    }
}

/// Combines source pixels with a mask into a cut-out.
public enum CutoutComposer {
    /// Multiplies `source` (premultiplied RGBA) by `mask`. Sizes must match.
    public static func compose(source: RGBABitmap, mask: AlphaMask) -> RGBABitmap {
        precondition(source.width == mask.width && source.height == mask.height, "size mismatch")
        var out = source.pixels
        for i in 0..<(mask.width * mask.height) {
            let m = UInt32(mask.values[i])
            if m == 255 { continue }
            let p = i * 4
            out[p] = UInt8((UInt32(out[p]) * m + 127) / 255)
            out[p + 1] = UInt8((UInt32(out[p + 1]) * m + 127) / 255)
            out[p + 2] = UInt8((UInt32(out[p + 2]) * m + 127) / 255)
            out[p + 3] = UInt8((UInt32(out[p + 3]) * m + 127) / 255)
        }
        return RGBABitmap(width: source.width, height: source.height, pixels: out)
    }

    /// Colour samples from the clearly opaque part of a cut-out (for palettes).
    public static func colorSamples(_ bitmap: RGBABitmap, maxSamples: Int = 4000, minimumAlpha: UInt8 = 220) -> [RGBColor] {
        let total = bitmap.width * bitmap.height
        guard total > 0 else { return [] }
        var opaque = 0
        for i in 0..<total where bitmap.pixels[i * 4 + 3] >= minimumAlpha { opaque += 1 }
        guard opaque > 0 else { return [] }
        let step = max(1, opaque / maxSamples)
        var samples: [RGBColor] = []
        samples.reserveCapacity(min(opaque, maxSamples + 1))
        var seen = 0
        for i in 0..<total where bitmap.pixels[i * 4 + 3] >= minimumAlpha {
            if seen % step == 0, let c = bitmap.color(x: i % bitmap.width, y: i / bitmap.width) {
                samples.append(c)
            }
            seen += 1
        }
        return samples
    }
}
#endif
