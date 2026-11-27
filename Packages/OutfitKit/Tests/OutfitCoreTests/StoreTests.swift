import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OutfitCore

final class StoreTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OutfitStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRoundTripPersistsEverything() throws {
        let store = try WardrobeStore(rootURL: root)
        var garment = makeGarment(category: .top, color: SRGBColor(hex: "#1F2A44")!)
        garment.palette = [SRGBColor(hex: "#1F2A44")!, .white]
        garment.notes = "Linen"
        try store.writeBlob(Data([1, 2, 3]), named: garment.imageFile)
        try store.upsertGarment(garment)
        var outfit = Outfit(name: "Monday", items: [OutfitItem(garmentID: garment.id, adjustment: ItemAdjustment(offset: CGPoint(x: 0.01, y: 0.02), scale: 1.1, rotation: 0.05), zOverride: 33)])
        outfit.tuckedIn = true
        try store.upsertOutfit(outfit)
        var profile = UserProfile(body: BodyProfile(heightCM: 181, shape: .masculine, build: 1.1), units: .imperial, hasCompletedOnboarding: true)
        profile.face = FaceAsset(imageFile: "face-1.png", imageSize: CGSize(width: 300, height: 400), eyeLeft: CGPoint(x: 100, y: 150),
                                 eyeRight: CGPoint(x: 180, y: 150), chin: CGPoint(x: 140, y: 290), skinTone: SRGBColor(hex: "#C8946E")!,
                                 yawDegrees: 4, rollDegrees: -2, pitchDegrees: 1)
        try store.updateProfile(profile)

        let reopened = try WardrobeStore(rootURL: root)
        XCTAssertEqual(reopened.library, store.library)
        XCTAssertEqual(reopened.readBlob(named: garment.imageFile), Data([1, 2, 3]))
        XCTAssertFalse(reopened.recoveredFromCorruption)
    }

    func testDeletingGarmentCleansOutfitsAndFiles() throws {
        let store = try WardrobeStore(rootURL: root)
        let a = makeGarment(category: .top), b = makeGarment(category: .bottom)
        for g in [a, b] {
            try store.writeBlob(Data([9]), named: g.imageFile)
            try store.upsertGarment(g)
        }
        try store.upsertOutfit(Outfit(name: "o", items: [OutfitItem(garmentID: a.id), OutfitItem(garmentID: b.id)]))
        try store.deleteGarment(id: a.id)
        XCTAssertNil(store.library.garment(a.id))
        XCTAssertEqual(store.library.outfits[0].garmentIDs, [b.id])
        XCTAssertFalse(store.blobExists(a.imageFile))
        XCTAssertTrue(store.blobExists(b.imageFile))
        // Deleting an unknown id is harmless.
        XCTAssertNoThrow(try store.deleteGarment(id: UUID()))
    }

    func testOutfitsNeverReferenceUnknownGarments() throws {
        let store = try WardrobeStore(rootURL: root)
        let g = makeGarment(category: .top)
        try store.upsertGarment(g)
        try store.upsertOutfit(Outfit(name: "o", items: [OutfitItem(garmentID: g.id), OutfitItem(garmentID: UUID())]))
        XCTAssertEqual(store.library.outfits[0].garmentIDs, [g.id])
    }

    func testUpsertReplacesExisting() throws {
        let store = try WardrobeStore(rootURL: root)
        var g = makeGarment(category: .top)
        try store.upsertGarment(g)
        g.name = "Renamed"
        try store.upsertGarment(g)
        XCTAssertEqual(store.library.garments.count, 1)
        XCTAssertEqual(store.library.garments[0].name, "Renamed")
    }

    func testFileNamesAreValidated() throws {
        let store = try WardrobeStore(rootURL: root)
        for bad in ["", "../escape.png", "a/b.png", "/etc/passwd", ".hidden", "..", "spa ce.png"] {
            XCTAssertThrowsError(try store.writeBlob(Data([1]), named: bad), bad)
            XCTAssertNil(store.readBlob(named: bad))
        }
        let name = WardrobeStore.fileName(prefix: "garment", id: UUID(), suffix: "image", ext: "png")
        XCTAssertTrue(WardrobeStore.isValidFileName(name))
        XCTAssertNoThrow(try store.writeBlob(Data([1]), named: name))
    }

    func testCorruptLibraryIsMovedAsideAndReset() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: root.appendingPathComponent(WardrobeStore.libraryFileName))
        let store = try WardrobeStore(rootURL: root)
        XCTAssertTrue(store.recoveredFromCorruption)
        XCTAssertEqual(store.library, Library())
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("library.corrupt-") })
    }

    func testNewerSchemaIsRejected() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var library = Library()
        library.schemaVersion = Library.currentSchemaVersion + 1
        try WardrobeStore.encoder.encode(library).write(to: root.appendingPathComponent(WardrobeStore.libraryFileName))
        XCTAssertThrowsError(try WardrobeStore(rootURL: root)) { error in
            XCTAssertEqual(error as? StoreError, .unsupportedSchema(Library.currentSchemaVersion + 1))
        }
    }

    func testRemovesOnlyUnreferencedBlobs() throws {
        let store = try WardrobeStore(rootURL: root)
        let g = makeGarment(category: .top)
        try store.writeBlob(Data([1]), named: g.imageFile)
        try store.upsertGarment(g)
        try store.writeBlob(Data([2]), named: "orphan-1.png")
        XCTAssertEqual(store.removeUnreferencedBlobs(), ["orphan-1.png"])
        XCTAssertTrue(store.blobExists(g.imageFile))
    }

    func testProfileUpdateDeletesReplacedFace() throws {
        let store = try WardrobeStore(rootURL: root)
        try store.writeBlob(Data([1]), named: "face-a.png")
        var profile = UserProfile()
        profile.face = FaceAsset(imageFile: "face-a.png", imageSize: CGSize(width: 1, height: 1), eyeLeft: .zero, eyeRight: CGPoint(x: 1, y: 0), chin: CGPoint(x: 0, y: 1), skinTone: .white)
        try store.updateProfile(profile)
        try store.writeBlob(Data([2]), named: "face-b.png")
        profile.face?.imageFile = "face-b.png"
        try store.updateProfile(profile)
        XCTAssertFalse(store.blobExists("face-a.png"))
        XCTAssertTrue(store.blobExists("face-b.png"))
        profile.face = nil
        try store.updateProfile(profile)
        XCTAssertFalse(store.blobExists("face-b.png"))
    }

    func testEraseAll() throws {
        let store = try WardrobeStore(rootURL: root)
        let g = makeGarment(category: .top)
        try store.writeBlob(Data([1]), named: g.imageFile)
        try store.upsertGarment(g)
        try store.eraseAll()
        XCTAssertEqual(store.library, Library())
        XCTAssertFalse(store.blobExists(g.imageFile))
        XCTAssertEqual(try WardrobeStore(rootURL: root).library, Library())
    }
}
