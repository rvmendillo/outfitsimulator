#if canImport(Vision)
import CoreGraphics
import Foundation
import XCTest
@testable import OutfitKit

/// End-to-end checks on real photos (macOS, Vision + Core ML).
final class PipelineTests: XCTestCase {
    // MARK: Parser

    func testParserLabelsAPersonsOutfit() async throws {
        let parser = try await TestModel.parser()
        let image = try Fixtures.image("outfit_front.jpg")
        let map = try parser.parse(image)
        XCTAssertEqual(map.width, ClothingParser.inputSize)
        XCTAssertEqual(map.height, ClothingParser.inputSize)
        for label in [ParserLabel.upperClothes, .pants, .face, .hair, .hat] {
            XCTAssertGreaterThan(map.fraction(of: [label]), 0.001, "\(label) found")
        }
        XCTAssertGreaterThan(map.fraction(of: [.leftShoe, .rightShoe]), 0.002)
        // Spatial sanity: hat above face above top above trousers above shoes.
        func centroidY(_ labels: Set<ParserLabel>) throws -> Double {
            let mask = map.mask(for: labels)
            var sum = 0.0, n = 0.0
            for y in 0..<mask.height { for x in 0..<mask.width where mask[x, y] > 0 { sum += Double(y); n += 1 } }
            return try XCTUnwrap(n > 0 ? sum / n : nil)
        }
        let groups: [[ParserLabel]] = [[.hat], [.face], [.upperClothes], [.pants], [.leftShoe, .rightShoe]]
        let order = try groups.map { try centroidY(Set($0)) }
        XCTAssertEqual(order, order.sorted(), "top-to-bottom order \(order)")
    }

    // MARK: Worn outfit

    func testExtractsGarmentsFromAPhotoOfAPerson() async throws {
        let parser = try await TestModel.parser()
        let extractor = GarmentExtractor(parser: parser)
        let image = try Fixtures.image("outfit_front.jpg")
        let result = try extractor.extract(from: image)
        XCTAssertEqual(result.kind, .wornOutfit)
        let categories = Set(result.pieces.map(\.category))
        for expected in [GarmentCategory.top, .bottom, .shoes, .hat] {
            XCTAssertTrue(categories.contains(expected), "found \(expected) in \(categories)")
        }
        let top = try XCTUnwrap(result.pieces.first { $0.category == .top })
        let bottom = try XCTUnwrap(result.pieces.first { $0.category == .bottom })
        let shoes = try XCTUnwrap(result.pieces.first { $0.category == .shoes })
        XCTAssertLessThan(top.cropRect.centerY, bottom.cropRect.centerY)
        XCTAssertLessThan(bottom.cropRect.centerY, shoes.cropRect.centerY)
        XCTAssertEqual(bottom.anchors.fitsLength, true, "full-length jeans reach the ankles")
        XCTAssertEqual(shoes.anchors.level, .sole)
        if result.pose?.hasShoulders == true {
            XCTAssertEqual(top.anchors.source, .pose)
        }
        for piece in result.pieces {
            XCTAssertEqual(piece.source.width, piece.mask.width)
            XCTAssertEqual(piece.source.height, piece.mask.height)
            XCTAssertGreaterThan(piece.mask.coverage(), 0.1, "\(piece.category) mask not empty")
            XCTAssertFalse(piece.name.isEmpty)
            let cut = piece.cutout()
            Artifacts.save(cut.makeCGImage(), "worn-\(piece.category.rawValue)-\(piece.name.replacingOccurrences(of: " ", with: "_")).png")
        }
        // Jeans are denim/blue, the jacket camel/brown.
        XCTAssertTrue(["Denim", "Blue", "Sky Blue", "Navy", "Gray", "Light Gray", "Stone"].contains(bottom.dominantColor.name), bottom.dominantColor.name)
    }

    func testWornAccessoriesKeepRealisticSizes() async throws {
        let parser = try await TestModel.parser()
        let result = try GarmentExtractor(parser: parser).extract(from: try Fixtures.image("outfit_front.jpg"))
        let avatar = AvatarModel(profile: BodyProfile(heightCM: 175))
        for piece in result.pieces {
            let cut = piece.cutout()
            let size = CGSize(width: cut.width, height: cut.height)
            let fit = GarmentFitter.autoFit(anchors: piece.anchors, imageSize: size, category: piece.category, avatar: avatar)
            let box = fit.boundingBox(of: CGRect(origin: .zero, size: size))
            let limits = GarmentFitter.maximumSize(for: piece.category)
            XCTAssertLessThanOrEqual(Double(box.width), limits.width + 1e-9, "\(piece.category) width")
            XCTAssertLessThanOrEqual(Double(box.height), limits.height + 1e-9, "\(piece.category) height")
            switch piece.category {
            case .hat:
                // A beanie is roughly head-sized: 0.7-1.9 head widths across.
                let headWidth = 2 * avatar.headHalfWidth
                XCTAssertGreaterThan(Double(box.width), 0.7 * headWidth, "hat too small")
                XCTAssertLessThan(Double(box.width), 1.9 * headWidth, "hat too big")
                XCTAssertLessThan(Double(box.minY), avatar.eyeY, "hat sits on the head")
                XCTAssertEqual(Double(box.midX), 0, accuracy: 0.08)
            case .shoes:
                XCTAssertEqual(Double(box.maxY), avatar.floorY, accuracy: 0.03, "shoes on the floor")
                XCTAssertLessThan(Double(box.width), 0.3)
            case .top:
                XCTAssertLessThan(Double(box.minY), avatar.shoulderY)
                XCTAssertGreaterThan(Double(box.maxY), avatar.waistY)
            case .bottom:
                XCTAssertEqual(Double(box.maxY), avatar.ankleY, accuracy: 0.05, "jeans reach the ankles")
            default:
                break
            }
        }
    }

    func testSideOnPhotoStillYieldsCoreGarments() async throws {
        let parser = try await TestModel.parser()
        let result = try GarmentExtractor(parser: parser).extract(from: try Fixtures.image("outfit_side.jpg"))
        let categories = Set(result.pieces.map(\.category))
        XCTAssertTrue(categories.isSuperset(of: [.top, .bottom, .shoes]), "\(categories)")
    }

    // MARK: Flat-lay

    func testSeparatesItemsLaidOutOnAPlainBackground() throws {
        let navy = SRGBColor(hex: "#1F2A44")!, tan = SRGBColor(hex: "#C9A06A")!
        let image = makeBitmap(width: 900, height: 700, background: SRGBColor(hex: "#F4F2EE")!) { ctx in
            // T-shirt
            ctx.setFillColor(navy.cgColor)
            let shirt = CGMutablePath()
            shirt.addLines(between: [CGPoint(x: 120, y: 120), CGPoint(x: 330, y: 120), CGPoint(x: 410, y: 190), CGPoint(x: 370, y: 240),
                                     CGPoint(x: 330, y: 215), CGPoint(x: 330, y: 470), CGPoint(x: 120, y: 470), CGPoint(x: 120, y: 215),
                                     CGPoint(x: 80, y: 240), CGPoint(x: 40, y: 190)])
            shirt.closeSubpath()
            ctx.addPath(shirt)
            ctx.fillPath()
            // Trousers
            ctx.setFillColor(tan.cgColor)
            let trousers = CGMutablePath()
            trousers.addLines(between: [CGPoint(x: 560, y: 60), CGPoint(x: 760, y: 60), CGPoint(x: 790, y: 640), CGPoint(x: 690, y: 640),
                                        CGPoint(x: 660, y: 230), CGPoint(x: 630, y: 640), CGPoint(x: 530, y: 640)])
            trousers.closeSubpath()
            ctx.addPath(trousers)
            ctx.fillPath()
        }
        // Without the parser the category comes from the outline (deterministic).
        let result = try GarmentExtractor(parser: nil).extract(from: image)
        XCTAssertEqual(result.kind, .separateItems)
        XCTAssertEqual(result.pieces.count, 2, "\(result.pieces.map(\.category))")
        let byX = result.pieces.sorted { $0.cropRect.minX < $1.cropRect.minX }
        XCTAssertEqual(Double(byX[0].cropRect.centerX), 225, accuracy: 30)
        XCTAssertEqual(Double(byX[1].cropRect.centerX), 660, accuracy: 30)
        XCTAssertEqual(byX[0].category, .top)
        XCTAssertEqual(byX[1].category, .bottom, "tall piece is a bottom")
        XCTAssertTrue(byX[1].anchors.fitsLength)
        XCTAssertEqual(byX[0].dominantColor.name, "Navy")
    }

    func testEmptyPhotoFindsNothing() throws {
        let image = makeBitmap(width: 300, height: 300, background: SRGBColor(hex: "#EEEEEE")!) { _ in }
        let result = try GarmentExtractor(parser: nil).extract(from: image)
        XCTAssertEqual(result.kind, .nothingFound)
        XCTAssertTrue(result.pieces.isEmpty)
    }

    // MARK: Face

    func testFindsFaceLandmarks() throws {
        let image = try Fixtures.image("face_portrait.jpg")
        let face = try XCTUnwrap(try FaceAnalyzer.detect(in: image))
        XCTAssertLessThan(face.eyeLeft.x, face.eyeRight.x)
        XCTAssertLessThan(face.eyeMidpoint.y, face.chin.y)
        XCTAssertTrue(face.boundingBox.contains(face.eyeLeft))
        // Proportion sanity for a real face: eye-to-chin is 1.4-2.6x the pupil distance.
        let ratio = face.eyeToChin / face.interpupillaryDistance
        XCTAssertGreaterThan(ratio, 1.3)
        XCTAssertLessThan(ratio, 2.8)
    }

    func testNoFaceThrows() throws {
        let image = makeBitmap(width: 400, height: 400, background: SRGBColor(hex: "#C0C0C0")!) { _ in }
        XCTAssertThrowsError(try HeadExtractor(parser: nil).extract(from: image)) { error in
            XCTAssertEqual(error as? HeadExtractionError, .noFace)
        }
    }

    func testHeadCutoutAlignsWithAvatarProportions() async throws {
        let parser = try? await TestModel.parser()
        let head = try HeadExtractor(parser: parser).extract(from: try Fixtures.image("face_portrait.jpg"))
        Artifacts.save(head.image.makeCGImage(), "head-cutout.png")
        let size = head.size
        for p in [head.eyeLeft, head.eyeRight, head.chin] {
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(p), "landmark \(p) inside cut-out \(size)")
        }
        // Skin tone is a plausible skin colour (warm: r > g > b, not too dark/bright).
        let skin = head.skinTone
        XCTAssertGreaterThan(skin.r, skin.g)
        XCTAssertGreaterThan(skin.g, skin.b)
        XCTAssertTrue((25...92).contains(skin.lab.l), "L* \(skin.lab.l)")
        // The pupils are opaque, the corners transparent.
        XCTAssertGreaterThan(head.image.alpha(x: Int(head.eyeLeft.x), y: Int(head.eyeLeft.y)), 200)
        XCTAssertEqual(head.image.alpha(x: 0, y: 0), 0)

        for height in [152.0, 170, 192] {
            let avatar = AvatarModel(profile: BodyProfile(heightCM: height))
            let asset = FaceAsset(imageFile: "face.png", imageSize: size, eyeLeft: head.eyeLeft, eyeRight: head.eyeRight,
                                  chin: head.chin, skinTone: head.skinTone, yawDegrees: head.yawDegrees,
                                  rollDegrees: head.rollDegrees, pitchDegrees: head.pitchDegrees)
            let placement = try XCTUnwrap(FaceFitter.placement(face: asset, avatar: avatar))
            // Eyes level and the head one anthropometric head-height tall.
            let l = placement.apply(head.eyeLeft), r = placement.apply(head.eyeRight)
            XCTAssertEqual(atan2(Double(r.y - l.y), Double(r.x - l.x)) * 180 / .pi, 0, accuracy: 1)
            let implied = FaceFitter.impliedHeadHeight(face: asset, placement: placement)
            XCTAssertEqual(implied / avatar.headHeight, 1, accuracy: 0.03, "head height ratio at \(height) cm")
            // Chin sits on the avatar's neck.
            XCTAssertEqual(Double(placement.apply(head.chin).y), avatar.chinY, accuracy: avatar.headHeight * 0.08)
            XCTAssertEqual(Double(placement.apply(head.chin).x), 0, accuracy: avatar.headHeight * 0.08)
            // Hair reaches above the eyes by roughly half a head (top of the cut-out).
            let top = placement.boundingBox(of: CGRect(origin: .zero, size: size)).minY
            XCTAssertLessThan(Double(top), avatar.eyeY - avatar.headHeight * 0.35)
        }
    }

    // MARK: Composite (visual check)

    func testCompositeOutfitOnAvatar() async throws {
        let parser = try await TestModel.parser()
        let pieces = try GarmentExtractor(parser: parser).extract(from: try Fixtures.image("outfit_front.jpg")).pieces
        let head = try HeadExtractor(parser: parser).extract(from: try Fixtures.image("face_portrait.jpg"))
        var garments: [UUID: Garment] = [:]
        var images: [SceneLayer.Content: CGImage] = [:]
        var outfit = Outfit(name: "Test")
        for piece in pieces {
            let cut = piece.cutout()
            let g = Garment(name: piece.name, category: piece.category, imageFile: "\(piece.id).png",
                            imageSize: CGSize(width: cut.width, height: cut.height), anchors: piece.anchors, dominantColor: piece.dominantColor)
            garments[g.id] = g
            images[.garment(g.id)] = cut.makeCGImage()
            outfit.add(g) { garments[$0]?.category }
        }
        let face = FaceAsset(imageFile: "face.png", imageSize: head.size, eyeLeft: head.eyeLeft, eyeRight: head.eyeRight, chin: head.chin, skinTone: head.skinTone)
        images[.face] = head.image.makeCGImage()
        for (shape, height) in [(BodyShape.feminine, 165.0), (.masculine, 183.0)] {
            let avatar = AvatarModel(profile: BodyProfile(heightCM: height, shape: shape))
            let scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: garments, face: face, skinTone: head.skinTone)
            XCTAssertFalse(scene.drawsAvatarHead)
            XCTAssertEqual(scene.layers.count, outfit.items.count + 1)
            let image = SceneRenderer.render(scene: scene, images: images, size: CGSize(width: 600, height: 1000),
                                             background: SRGBColor(hex: "#F7F3EE")!, style: AvatarStyle(skin: head.skinTone))
            XCTAssertNotNil(image)
            Artifacts.save(image, "composite-\(shape.rawValue)-\(Int(height)).png")
        }
    }
}

private extension SRGBColor {
    var name: String { ColorNaming.name(for: self) }
}
#endif
