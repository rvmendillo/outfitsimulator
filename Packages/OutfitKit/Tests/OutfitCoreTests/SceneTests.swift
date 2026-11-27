import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

final class SceneTests: XCTestCase {
    let avatar = AvatarModel(profile: BodyProfile(heightCM: 168, shape: .feminine))

    private func face() -> FaceAsset {
        FaceAsset(imageFile: "face.png", imageSize: CGSize(width: 400, height: 500),
                  eyeLeft: CGPoint(x: 160, y: 200), eyeRight: CGPoint(x: 240, y: 200), chin: CGPoint(x: 200, y: 345),
                  skinTone: BodyProfile.defaultSkinTone)
    }

    func testLayersAreSortedByCategory() {
        let top = makeGarment(category: .top), bottom = makeGarment(category: .bottom)
        let shoes = makeGarment(category: .shoes), coat = makeGarment(category: .outerwear)
        let hat = makeGarment(category: .hat)
        let outfit = Outfit(name: "Test", items: [hat, coat, top, shoes, bottom].map { OutfitItem(garmentID: $0.id) })
        let garments = Dictionary(uniqueKeysWithValues: [top, bottom, shoes, coat, hat].map { ($0.id, $0) })
        let scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: garments, face: face(), skinTone: .white)
        let order = scene.layers.map { layer -> String in
            switch layer.content {
            case .face: return "face"
            case let .garment(id): return garments[id]!.category.rawValue
            }
        }
        XCTAssertEqual(order, ["shoes", "bottom", "top", "outerwear", "face", "hat"])
        XCTAssertFalse(scene.drawsAvatarHead)
    }

    func testTuckedTopGoesUnderBottoms() {
        let top = makeGarment(category: .top), bottom = makeGarment(category: .bottom), belt = makeGarment(category: .belt)
        var outfit = Outfit(name: "Tucked", items: [top, bottom, belt].map { OutfitItem(garmentID: $0.id) })
        outfit.tuckedIn = true
        let garments = Dictionary(uniqueKeysWithValues: [top, bottom, belt].map { ($0.id, $0) })
        let scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: garments, face: nil, skinTone: .white)
        XCTAssertEqual(scene.layers.map(\.content), [.garment(top.id), .garment(bottom.id), .garment(belt.id)])
        XCTAssertTrue(scene.drawsAvatarHead)
    }

    func testMissingAndInvalidGarmentsAreSkipped() {
        let ok = makeGarment(category: .top)
        let broken = makeGarment(category: .bottom, size: .zero)
        let outfit = Outfit(name: "x", items: [OutfitItem(garmentID: ok.id), OutfitItem(garmentID: broken.id), OutfitItem(garmentID: UUID())])
        let scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: [ok.id: ok, broken.id: broken], face: nil, skinTone: .white)
        XCTAssertEqual(scene.layers.count, 1)
    }

    func testZOverrideAndReordering() throws {
        let top = makeGarment(category: .top), coat = makeGarment(category: .outerwear), bottom = makeGarment(category: .bottom)
        let garments = Dictionary(uniqueKeysWithValues: [top, coat, bottom].map { ($0.id, $0) })
        var outfit = Outfit(name: "x", items: [top, coat, bottom].map { OutfitItem(garmentID: $0.id) })
        var scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: garments, face: nil, skinTone: .white)
        XCTAssertNil(SceneBuilder.reorderedZ(for: coat.id, direction: 1, in: scene), "already in front")
        XCTAssertNil(SceneBuilder.reorderedZ(for: bottom.id, direction: -1, in: scene), "already at the back")

        // Move the coat back one step: it must land between bottom and top.
        let z = try XCTUnwrap(SceneBuilder.reorderedZ(for: coat.id, direction: -1, in: scene))
        let i = try XCTUnwrap(outfit.items.firstIndex { $0.garmentID == coat.id })
        outfit.items[i].zOverride = z
        scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: garments, face: nil, skinTone: .white)
        XCTAssertEqual(scene.layers.map(\.content), [.garment(bottom.id), .garment(coat.id), .garment(top.id)])
    }

    func testHitTestFindsTopmostOpaqueLayer() {
        let top = makeGarment(category: .top), coat = makeGarment(category: .outerwear)
        let garments = Dictionary(uniqueKeysWithValues: [top, coat].map { ($0.id, $0) })
        let outfit = Outfit(name: "x", items: [top, coat].map { OutfitItem(garmentID: $0.id) })
        let scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: garments, face: nil, skinTone: .white)
        let chest = CGPoint(x: 0, y: avatar.chestY)
        XCTAssertEqual(scene.hitTest(chest)?.content, .garment(coat.id))
        // If the coat is transparent there, the top is hit instead.
        let hit = scene.hitTest(chest) { layer, _ in layer.content == .garment(coat.id) ? 0 : 1 }
        XCTAssertEqual(hit?.content, .garment(top.id))
        XCTAssertNil(scene.hitTest(CGPoint(x: 5, y: 5)))
    }

    func testArmsAndLegsHideUnderGarmentsThatReplaceThem() {
        let shorts = makeGarment(category: .bottom)
        var jeansAnchors = GarmentAnchors.fallback(for: .bottom)
        jeansAnchors.fitsLength = true
        let jeans = makeGarment(category: .bottom, anchors: jeansAnchors)
        let top = makeGarment(category: .top), hat = makeGarment(category: .hat)
        let garments = Dictionary(uniqueKeysWithValues: [shorts, jeans, top, hat].map { ($0.id, $0) })
        func scene(_ items: [Garment]) -> OutfitScene {
            SceneBuilder.build(avatar: avatar, outfit: Outfit(name: "x", items: items.map { OutfitItem(garmentID: $0.id) }),
                               garments: garments, face: nil, skinTone: .white)
        }
        XCTAssertTrue(scene([]).showsArms)
        XCTAssertTrue(scene([]).showsLegs)
        XCTAssertTrue(scene([hat, shorts]).showsArms)
        XCTAssertTrue(scene([hat, shorts]).showsLegs, "shorts show legs")
        XCTAssertFalse(scene([top]).showsArms, "sleeves replace arms")
        XCTAssertFalse(scene([jeans]).showsLegs, "full-length trousers replace legs")
        let parts = AvatarShape.parts(for: scene([top])).map(\.kind)
        XCTAssertFalse(parts.contains(.armLeft))
        XCTAssertTrue(parts.contains(.body))
        var noArms = avatar.profile
        noArms.showArms = false
        let s = SceneBuilder.build(avatar: AvatarModel(profile: noArms), outfit: Outfit(name: "x"), garments: [:], face: nil, skinTone: .white)
        XCTAssertFalse(s.showsArms, "setting respected")
        // Base layer and full torso only where nothing covers them.
        XCTAssertTrue(scene([]).showsBaseTop && scene([]).showsBaseBottom)
        XCTAssertEqual(scene([]).torsoScale, 1)
        XCTAssertFalse(scene([top]).showsBaseTop)
        XCTAssertTrue(scene([top]).showsBaseBottom)
        XCTAssertFalse(scene([shorts]).showsBaseBottom)
        XCTAssertEqual(scene([top]).torsoScale, SceneBuilder.dressedTorsoScale)
        XCTAssertEqual(scene([hat]).torsoScale, 1, "accessories alone do not slim the torso")
        XCTAssertEqual(AvatarShape.baseLayer(for: scene([top])).map(\.kind), [.baseBottom])
        XCTAssertTrue(AvatarShape.baseLayer(for: scene([top, shorts])).isEmpty)
        let clip = AvatarShape.torsoClipRect(for: avatar)
        XCTAssertTrue(clip.contains(CGPoint(x: 0, y: avatar.hipY)))
        XCTAssertFalse(clip.contains(CGPoint(x: 0, y: avatar.kneeY)))
    }

    func testCanvasMappingFitsAndRoundTrips() {
        let rect = CanvasMapping.standardBodyRect(for: avatar)
        let mapping = CanvasMapping(bodyRect: rect, canvasSize: CGSize(width: 390, height: 600), padding: 0.05)
        let topLeft = mapping.toCanvas(CGPoint(x: rect.minX, y: rect.minY))
        let bottomRight = mapping.toCanvas(CGPoint(x: rect.maxX, y: rect.maxY))
        XCTAssertGreaterThanOrEqual(Double(topLeft.x), -1e-9)
        XCTAssertGreaterThanOrEqual(Double(topLeft.y), 600 * 0.05 - 1e-9)
        XCTAssertLessThanOrEqual(Double(bottomRight.x), 390 + 1e-9)
        XCTAssertLessThanOrEqual(Double(bottomRight.y), 600 * 0.95 + 1e-9)
        // Centred horizontally.
        XCTAssertEqual(Double(mapping.toCanvas(.zero).x), 195, accuracy: 1e-9)
        let p = CGPoint(x: 0.1, y: 0.7)
        XCTAssertPointEqual(mapping.toBody(mapping.toCanvas(p)), p, accuracy: 1e-12)
        XCTAssertPointEqual(mapping.transform.apply(p), mapping.toCanvas(p), accuracy: 1e-12)
    }

    func testSceneBoundsIncludeLayers() {
        var anchors = GarmentAnchors.fallback(for: .bag)
        anchors.left = CGPoint(x: 0.4, y: 0)
        anchors.right = CGPoint(x: 0.6, y: 0)
        let bag = makeGarment(category: .bag, anchors: anchors)
        let outfit = Outfit(name: "x", items: [OutfitItem(garmentID: bag.id, adjustment: ItemAdjustment(offset: CGPoint(x: 0.5, y: 0)))])
        let scene = SceneBuilder.build(avatar: avatar, outfit: outfit, garments: [bag.id: bag], face: nil, skinTone: .white)
        XCTAssertGreaterThan(Double(scene.bounds.maxX), 0.5)
    }
}
