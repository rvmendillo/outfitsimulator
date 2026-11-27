#if canImport(Vision)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OutfitKit

final class ImagingTests: XCTestCase {
    let red = RGBColor(r: 1, g: 0, b: 0)
    let blue = RGBColor(r: 0, g: 0, b: 1)

    func testExifOrientationIsApplied() throws {
        // Stored 40x20: left half red, right half blue. Orientation 6 means
        // "rotate 90° clockwise to display", so upright it is 20x40 with red on top.
        let stored = makeBitmap(width: 40, height: 20, background: blue) { ctx in
            ctx.setFillColor(self.red.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, stored, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let upright = try XCTUnwrap(ImageCodec.loadUpright(data: data as Data))
        XCTAssertEqual(upright.width, 20)
        XCTAssertEqual(upright.height, 40)
        let bitmap = try XCTUnwrap(RGBABitmap(cgImage: upright))
        let top = try XCTUnwrap(bitmap.rgb(10, 5)), bottom = try XCTUnwrap(bitmap.rgb(10, 35))
        XCTAssertGreaterThan(top.r, 0.8)
        XCTAssertLessThan(top.b, 0.2)
        XCTAssertGreaterThan(bottom.b, 0.8)
    }

    func testDownscaleOnLoadAndHelpers() throws {
        let big = makeBitmap(width: 3000, height: 1500, background: red) { _ in }
        let png = try XCTUnwrap(ImageCodec.pngData(big))
        let loaded = try XCTUnwrap(ImageCodec.loadUpright(data: png, maxPixelSize: 1000))
        XCTAssertEqual(max(loaded.width, loaded.height), 1000)
        let down = ImageCodec.downscaled(big, maxSide: 600)
        XCTAssertEqual(down.width, 600)
        XCTAssertEqual(down.height, 300)
        XCTAssertTrue(ImageCodec.downscaled(down, maxSide: 4000) === down, "never upscales")
        XCTAssertNil(ImageCodec.loadUpright(data: Data([1, 2, 3])))
    }

    func testPNGRoundTripPreservesAlpha() throws {
        var bitmap = RGBABitmap(width: 4, height: 1, fill: (0, 0, 0, 0))
        // Premultiplied: 50% red.
        bitmap.pixels[0] = 128; bitmap.pixels[3] = 128
        bitmap.pixels[4] = 0; bitmap.pixels[5] = 255; bitmap.pixels[6] = 0; bitmap.pixels[7] = 255
        let image = try XCTUnwrap(bitmap.makeCGImage())
        let decoded = try XCTUnwrap(ImageCodec.decode(data: try XCTUnwrap(ImageCodec.pngData(image))))
        let back = try XCTUnwrap(RGBABitmap(cgImage: decoded))
        XCTAssertEqual(back.alpha(x: 0, y: 0), 128)
        XCTAssertEqual(Double(back.rgb(0, 0)?.r ?? 0), 1, accuracy: 0.02)
        XCTAssertEqual(back.alpha(x: 2, y: 0), 0)
        XCTAssertNil(back.rgb(2, 0))
        XCTAssertNotNil(ImageCodec.jpegData(image))
    }

    func testMaskImageConversions() throws {
        var mask = AlphaMask(width: 10, height: 6)
        mask.fillRect(PixelRect(minX: 2, minY: 1, maxX: 6, maxY: 4), value: 200)
        let image = try XCTUnwrap(mask.makeGrayscaleCGImage())
        let back = try XCTUnwrap(AlphaMask(grayscaleImage: image))
        XCTAssertEqual(back, mask)
        let png = try XCTUnwrap(ImageCodec.pngData(image))
        XCTAssertEqual(AlphaMask(grayscaleImage: try XCTUnwrap(ImageCodec.decode(data: png))), mask)
    }

    func testPixelBufferMaskConversion() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 8, 4, kCVPixelFormatType_OneComponent32Float, nil, &buffer)
        let pb = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pb, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pb))
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<4 {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<8 { row[x] = x < 4 ? 1 : 0.5 }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        let mask = try XCTUnwrap(AlphaMask(pixelBuffer: pb))
        XCTAssertEqual(mask.width, 8)
        XCTAssertEqual(mask[0, 0], 255)
        XCTAssertEqual(mask[7, 3], 128)
    }

    func testCutoutCompositionAndCropping() throws {
        let source = RGBABitmap(width: 4, height: 4, fill: (200, 100, 50, 255))
        var mask = AlphaMask(width: 4, height: 4)
        mask[1, 1] = 255
        mask[2, 1] = 51
        let cut = CutoutComposer.compose(source: source, mask: mask)
        XCTAssertEqual(cut.alpha(x: 1, y: 1), 255)
        XCTAssertEqual(cut.alpha(x: 2, y: 1), 51)
        XCTAssertEqual(cut.alpha(x: 0, y: 0), 0)
        let c = try XCTUnwrap(cut.rgb(2, 1))
        XCTAssertEqual(c.r, 200.0 / 255, accuracy: 0.03, "un-premultiplied colour survives")
        let crop = cut.cropped(to: PixelRect(minX: 1, minY: 1, maxX: 2, maxY: 2))
        XCTAssertEqual(crop.width, 2)
        XCTAssertEqual(crop.alpha(x: 0, y: 0), 255)
        XCTAssertEqual(cut.alphaMask, mask)
        let samples = CutoutComposer.colorSamples(cut)
        XCTAssertEqual(samples.count, 1)
    }

    func testBackgroundKeyerSeparatesObjects() throws {
        let navy = RGBColor(hex: "#1F2A44")!
        let image = makeBitmap(width: 600, height: 400, background: RGBColor(hex: "#F2F0EC")!) { ctx in
            ctx.setFillColor(navy.cgColor)
            ctx.fill(CGRect(x: 60, y: 80, width: 180, height: 240))
            ctx.setFillColor(self.red.cgColor)
            ctx.fillEllipse(in: CGRect(x: 340, y: 120, width: 200, height: 160))
        }
        let bitmap = try XCTUnwrap(RGBABitmap(cgImage: image))
        let mask = try XCTUnwrap(BackgroundKeyer.foregroundMask(bitmap))
        XCTAssertEqual(mask.width, 600)
        let parts = BackgroundKeyer.split(mask)
        XCTAssertEqual(parts.count, 2)
        let boxes = parts.compactMap { $0.boundingBox() }.sorted { $0.minX < $1.minX }
        XCTAssertEqual(Double(boxes[0].minX), 60, accuracy: 4)
        XCTAssertEqual(Double(boxes[0].maxY), 319, accuracy: 4)
        XCTAssertEqual(Double(boxes[1].minX), 340, accuracy: 4)
    }

    func testBackgroundKeyerRejectsBusyBackground() throws {
        // Random noise border: no plain background.
        var rng = SeededGenerator(seed: 4)
        var bitmap = RGBABitmap(width: 120, height: 120, fill: (0, 0, 0, 255))
        for i in 0..<(120 * 120) {
            bitmap.pixels[i * 4] = UInt8(rng.next() % 256)
            bitmap.pixels[i * 4 + 1] = UInt8(rng.next() % 256)
            bitmap.pixels[i * 4 + 2] = UInt8(rng.next() % 256)
        }
        XCTAssertNil(BackgroundKeyer.foregroundMask(bitmap))
    }

    // MARK: Rendering

    /// A garment image whose top half is red and bottom half blue, placed as a
    /// top: the render must show red at the chest and blue lower down, proving
    /// the y-flip and the fit transform are applied correctly.
    func testRendererPlacesGarmentUprightAtTheShoulders() throws {
        let avatar = AvatarModel(profile: BodyProfile(heightCM: 170, shape: .neutral, showBaseLayer: false))
        let garmentImage = makeBitmap(width: 200, height: 260, background: blue) { ctx in
            ctx.setFillColor(self.red.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 130))
        }
        let anchors = GarmentAnchors(left: CGPoint(x: 0, y: 0), right: CGPoint(x: 1, y: 0), hemY: 1, fitsLength: false, level: .shoulders, source: .user)
        let garment = Garment(name: "Test", category: .top, imageFile: "t.png", imageSize: CGSize(width: 200, height: 260), anchors: anchors, dominantColor: red)
        let outfit = Outfit(name: "o", items: [OutfitItem(garmentID: garment.id)])
        let skin = RGBColor(hex: "#D9A784")!
        let scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: [garment.id: garment], face: nil, skinTone: skin)
        let size = CGSize(width: 400, height: 640)
        let bodyRect = CanvasMapping.standardBodyRect(for: avatar)
        let rendered = try XCTUnwrap(SceneRenderer.render(scene: scene, images: [.garment(garment.id): garmentImage], size: size,
                                                          bodyRect: bodyRect, background: .white, style: AvatarStyle(skin: skin, floorShadow: false)))
        Artifacts.save(rendered, "render-orientation.png")
        let bitmap = try XCTUnwrap(RGBABitmap(cgImage: rendered))
        let mapping = CanvasMapping(bodyRect: bodyRect, canvasSize: size, padding: 0.04)
        func sample(_ body: CGPoint) throws -> RGBColor {
            let p = mapping.toCanvas(body)
            return try XCTUnwrap(bitmap.rgb(Int(p.x), Int(p.y)))
        }
        // The garment spans the shoulders, so just under the shoulder line is red...
        let chest = try sample(CGPoint(x: 0, y: avatar.shoulderY + 0.02))
        XCTAssertGreaterThan(chest.r, 0.8)
        XCTAssertLessThan(chest.b, 0.2)
        // ...and its lower half (blue) is further down.
        let garmentHeight = 260 * (2 * avatar.shoulderHalfWidth / 200)
        let lower = try sample(CGPoint(x: 0, y: avatar.shoulderY + garmentHeight * 0.8))
        XCTAssertGreaterThan(lower.b, 0.8)
        // Legs are skin, the corner is background.
        let knee = try sample(CGPoint(x: avatar.kneeX, y: avatar.kneeY))
        XCTAssertLessThan(knee.lab.distance(to: skin.lab), 2)
        XCTAssertLessThan(try XCTUnwrap(bitmap.rgb(2, 2)).lab.distance(to: RGBColor.white.lab), 1)
        // The avatar's own head is drawn (no face photo).
        let headCenter = try sample(CGPoint(x: 0, y: avatar.headHeight / 2))
        XCTAssertLessThan(headCenter.lab.distance(to: skin.lab), 2)
    }

    func testFramingIncludesProtrudingLayers() {
        let avatar = AvatarModel(profile: BodyProfile())
        var anchors = GarmentAnchors.fallback(for: .bag)
        anchors.level = .handle
        let bag = Garment(name: "Bag", category: .bag, imageFile: "b.png", imageSize: CGSize(width: 100, height: 100), anchors: anchors, dominantColor: red)
        let outfit = Outfit(name: "o", items: [OutfitItem(garmentID: bag.id, adjustment: ItemAdjustment(offset: CGPoint(x: 0.4, y: 0)))])
        let scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: [bag.id: bag], face: nil, skinTone: red)
        let rect = SceneRenderer.framingRect(for: scene)
        XCTAssertGreaterThan(Double(rect.maxX), 0.5)
        XCTAssertEqual(Double(rect.minX), -Double(rect.maxX), accuracy: 1e-9, "centred on the body")
    }
}
#endif
