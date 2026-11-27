import Combine
import OutfitKit
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case closet, studio, outfits, me
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// Launch configuration (UI tests pass `-uiTesting` to start from a clean,
/// temporary library).
struct LaunchOptions {
    var isUITesting: Bool

    static var current: LaunchOptions {
        LaunchOptions(isUITesting: ProcessInfo.processInfo.arguments.contains("-uiTesting"))
    }
}

/// App-wide state: the persisted library, the Studio draft and image caches.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library: Library
    /// The outfit being edited in the Studio.
    @Published var studio: Outfit
    /// True when `studio` differs from what is saved.
    @Published private(set) var studioHasChanges = false
    @Published var selectedTab: AppTab = .closet
    @Published var alert: AppAlert?

    let store: WardrobeStore
    let engine = ProcessingEngine()
    let images = ImageCache()
    let launch: LaunchOptions

    init(store: WardrobeStore, launch: LaunchOptions) {
        self.store = store
        self.launch = launch
        library = store.library
        studio = Outfit(name: "New outfit")
        if store.recoveredFromCorruption {
            alert = AppAlert(title: "Library restored",
                             message: "Your saved data could not be read, so a fresh library was started. The old file was kept for recovery.")
        }
        // Warm up the clothing parser in the background.
        Task.detached(priority: .utility) { [engine] in _ = await engine.hasParser() }
    }

    static func makeDefault() -> AppModel {
        let launch = LaunchOptions.current
        let fm = FileManager.default
        let root: URL
        if launch.isUITesting {
            root = fm.temporaryDirectory.appendingPathComponent("OutfitSimUITests-\(UUID().uuidString)", isDirectory: true)
        } else {
            let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
            root = support.appendingPathComponent("OutfitSim", isDirectory: true)
        }
        do {
            return AppModel(store: try WardrobeStore(rootURL: root), launch: launch)
        } catch {
            // Fall back to a temporary library rather than crashing.
            let temp = fm.temporaryDirectory.appendingPathComponent("OutfitSim-\(UUID().uuidString)", isDirectory: true)
            let model = AppModel(store: try! WardrobeStore(rootURL: temp), launch: launch)
            model.alert = AppAlert(title: "Storage unavailable", message: error.localizedDescription)
            return model
        }
    }

    // MARK: Derived state

    var profile: UserProfile { library.profile }
    var avatar: AvatarModel { AvatarModel(profile: library.profile.body) }
    var skinTone: SRGBColor { library.profile.effectiveSkinTone }
    var avatarStyle: AvatarStyle { AvatarStyle(skin: skinTone) }
    var garments: [Garment] { library.garments }
    var outfits: [Outfit] { library.outfits.sorted { $0.updatedAt > $1.updatedAt } }

    func garment(_ id: UUID) -> Garment? { library.garment(id) }

    func garments(in category: GarmentCategory?) -> [Garment] {
        let list = category.map { c in library.garments.filter { $0.category == c } } ?? library.garments
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    func categoriesInCloset() -> [GarmentCategory] {
        let present = Set(library.garments.map(\.category))
        return GarmentCategory.closetOrder.filter(present.contains)
    }

    // MARK: Persistence helper

    private func perform(_ title: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            alert = AppAlert(title: title, message: error.localizedDescription)
        }
        library = store.library
    }

    // MARK: Garments

    /// Saves reviewed pieces to the closet. Returns the new garments.
    @discardableResult
    func addPieces(_ pieces: [ReviewPiece]) async -> [Garment] {
        var added: [Garment] = []
        for piece in pieces where piece.include {
            do {
                let encoded = try await engine.encodePiece(source: piece.source, mask: piece.mask)
                let id = UUID()
                let image = WardrobeStore.fileName(prefix: "garment", id: id, suffix: "cutout", ext: "png")
                let source = WardrobeStore.fileName(prefix: "garment", id: id, suffix: "source", ext: "jpg")
                let mask = WardrobeStore.fileName(prefix: "garment", id: id, suffix: "mask", ext: "png")
                let thumb = WardrobeStore.fileName(prefix: "garment", id: id, suffix: "thumb", ext: "png")
                try store.writeBlob(encoded.cutoutPNG, named: image)
                try store.writeBlob(encoded.sourceJPEG, named: source)
                try store.writeBlob(encoded.maskPNG, named: mask)
                try store.writeBlob(encoded.thumbnailPNG, named: thumb)
                let name = piece.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let garment = Garment(id: id, name: name.isEmpty ? piece.category.displayName : name, category: piece.category,
                                      imageFile: image, sourceFile: source, maskFile: mask, thumbnailFile: thumb,
                                      imageSize: encoded.size, anchors: piece.anchors.normalized,
                                      dominantColor: piece.dominantColor, palette: piece.palette)
                try store.upsertGarment(garment)
                added.append(garment)
            } catch {
                alert = AppAlert(title: "Couldn't save a piece", message: error.localizedDescription)
            }
        }
        library = store.library
        return added
    }

    func updateGarment(_ garment: Garment) {
        perform("Couldn't save changes") { try store.upsertGarment(garment) }
    }

    /// Replaces a garment's mask (cut-out editor) and regenerates its images.
    func updateGarmentMask(_ id: UUID, source: RGBABitmap, mask: AlphaMask, anchors: GarmentAnchors) async {
        guard var garment = library.garment(id) else { return }
        do {
            let encoded = try await engine.encodePiece(source: source, mask: mask)
            try store.writeBlob(encoded.cutoutPNG, named: garment.imageFile)
            if let maskFile = garment.maskFile { try store.writeBlob(encoded.maskPNG, named: maskFile) }
            if let thumb = garment.thumbnailFile { try store.writeBlob(encoded.thumbnailPNG, named: thumb) }
            garment.files.forEach(images.invalidate)
            garment.imageSize = encoded.size
            garment.anchors = anchors.normalized
            try store.upsertGarment(garment)
        } catch {
            alert = AppAlert(title: "Couldn't save the cut-out", message: error.localizedDescription)
        }
        library = store.library
    }

    /// Changes a garment's category and re-measures its fit guides for it
    /// (unless the user placed them by hand).
    func changeCategory(of id: UUID, to category: GarmentCategory) {
        guard var garment = library.garment(id), garment.category != category else { return }
        garment.category = category
        if garment.anchors.source != .user {
            var mask: AlphaMask?
            if let maskFile = garment.maskFile, let data = store.readBlob(named: maskFile), let cg = ImageCodec.decode(data: data) {
                mask = AlphaMask(grayscaleImage: cg)
            } else if let cg = uiImage(garment.imageFile)?.cgImage {
                mask = RGBABitmap(cgImage: cg)?.alphaMask
            }
            garment.anchors = mask.map { AnchorEstimator.estimate(category: category, mask: $0) } ?? .fallback(for: category)
        }
        // Wearing it may now clash with another piece of the same category.
        if studio.contains(id) {
            studio.remove(id)
            studio.add(garment) { [library] in $0 == id ? category : library.garment($0)?.category }
        }
        perform("Couldn't save changes") { try store.upsertGarment(garment) }
    }

    func deleteGarment(_ id: UUID) {
        if let garment = library.garment(id) { garment.files.forEach(images.invalidate) }
        perform("Couldn't delete") { try store.deleteGarment(id: id) }
        studio.remove(id)
    }

    // MARK: Studio

    func toggleInStudio(_ garment: Garment) {
        if studio.contains(garment.id) {
            studio.remove(garment.id)
        } else {
            studio.add(garment) { [library] in library.garment($0)?.category }
        }
        studioHasChanges = true
    }

    func adjustment(for garmentID: UUID) -> ItemAdjustment {
        studio.items.first { $0.garmentID == garmentID }?.adjustment ?? .identity
    }

    func setAdjustment(_ adjustment: ItemAdjustment, for garmentID: UUID) {
        guard let i = studio.items.firstIndex(where: { $0.garmentID == garmentID }) else { return }
        studio.items[i].adjustment = adjustment.sanitized
        studioHasChanges = true
    }

    func moveLayer(_ garmentID: UUID, direction: Int) {
        let scene = studioScene()
        guard let z = SceneBuilder.reorderedZ(for: garmentID, direction: direction, in: scene),
              let i = studio.items.firstIndex(where: { $0.garmentID == garmentID }) else { return }
        studio.items[i].zOverride = z
        studioHasChanges = true
    }

    func removeFromStudio(_ garmentID: UUID) {
        studio.remove(garmentID)
        studioHasChanges = true
    }

    func setTuckedIn(_ tucked: Bool) {
        studio.tuckedIn = tucked
        studioHasChanges = true
    }

    func newStudio() {
        studio = Outfit(name: "New outfit")
        studioHasChanges = false
    }

    func openInStudio(_ outfit: Outfit) {
        studio = outfit
        studioHasChanges = false
        selectedTab = .studio
    }

    func applyToStudio(garmentIDs: [UUID], name: String? = nil) {
        var outfit = Outfit(name: name ?? "New outfit")
        for id in garmentIDs {
            if let g = library.garment(id) { outfit.add(g) { [library] in library.garment($0)?.category } }
        }
        studio = outfit
        studioHasChanges = true
    }

    /// Saves the Studio outfit (new or existing) under `name`.
    func saveStudio(name: String) {
        var outfit = studio
        outfit.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Outfit" : name
        outfit.updatedAt = Date()
        perform("Couldn't save the outfit") { try store.upsertOutfit(outfit) }
        studio = outfit
        studioHasChanges = false
    }

    var studioIsSaved: Bool { library.outfits.contains { $0.id == studio.id } }

    func saveSuggestion(_ suggestion: OutfitSuggestion, name: String) {
        var outfit = Outfit(name: name)
        for id in suggestion.garmentIDs {
            if let g = library.garment(id) { outfit.add(g) { [library] in library.garment($0)?.category } }
        }
        perform("Couldn't save the outfit") { try store.upsertOutfit(outfit) }
    }

    func duplicateOutfit(_ outfit: Outfit) {
        var copy = outfit
        copy.id = UUID()
        copy.name = outfit.name + " copy"
        copy.thumbnailFile = nil
        copy.createdAt = Date()
        copy.updatedAt = Date()
        perform("Couldn't duplicate") { try store.upsertOutfit(copy) }
    }

    func renameOutfit(_ outfit: Outfit, to name: String) {
        var copy = outfit
        copy.name = name
        copy.updatedAt = Date()
        perform("Couldn't rename") { try store.upsertOutfit(copy) }
        if studio.id == outfit.id { studio.name = name }
    }

    func deleteOutfit(_ outfit: Outfit) {
        perform("Couldn't delete") { try store.deleteOutfit(id: outfit.id) }
        if studio.id == outfit.id { studioHasChanges = true }
    }

    func generateOutfits(count: Int, locked: Set<UUID>, includeOuterwear: Bool, includeAccessories: Bool, seed: UInt64) -> GeneratorResult {
        let existing = Set(library.outfits.map(\.signature))
        let options = GeneratorOptions(count: count, locked: locked, excludedSignatures: existing,
                                       includeOuterwear: includeOuterwear, includeAccessories: includeAccessories, seed: seed)
        return OutfitGenerator.generate(from: library.garments.map(GarmentSummary.init), options: options)
    }

    // MARK: Profile

    func updateBody(_ body: BodyProfile) {
        var profile = library.profile
        profile.body = body.sanitized
        perform("Couldn't save your profile") { try store.updateProfile(profile) }
    }

    func setUnits(_ units: UnitSystem) {
        var profile = library.profile
        profile.units = units
        perform("Couldn't save your profile") { try store.updateProfile(profile) }
    }

    func setFace(_ head: HeadCutout, adjustment: ItemAdjustment) async {
        do {
            let png = try await engine.encodeHead(head)
            let file = WardrobeStore.fileName(prefix: "face", id: UUID(), suffix: "head", ext: "png")
            try store.writeBlob(png, named: file)
            var profile = library.profile
            profile.face = FaceAsset(imageFile: file, imageSize: head.size, eyeLeft: head.eyeLeft, eyeRight: head.eyeRight,
                                     chin: head.chin, skinTone: head.skinTone, adjustment: adjustment,
                                     yawDegrees: head.yawDegrees, rollDegrees: head.rollDegrees, pitchDegrees: head.pitchDegrees)
            if let old = library.profile.face?.imageFile { images.invalidate(old) }
            try store.updateProfile(profile)
        } catch {
            alert = AppAlert(title: "Couldn't save your face photo", message: error.localizedDescription)
        }
        library = store.library
    }

    func updateFaceAdjustment(_ adjustment: ItemAdjustment) {
        guard var face = library.profile.face else { return }
        face.adjustment = adjustment.sanitized
        var profile = library.profile
        profile.face = face
        perform("Couldn't save your profile") { try store.updateProfile(profile) }
    }

    func removeFace() {
        if let old = library.profile.face?.imageFile { images.invalidate(old) }
        var profile = library.profile
        profile.face = nil
        perform("Couldn't save your profile") { try store.updateProfile(profile) }
    }

    func completeOnboarding() {
        var profile = library.profile
        profile.hasCompletedOnboarding = true
        perform("Couldn't save your profile") { try store.updateProfile(profile) }
    }

    func eraseAll() {
        images.removeAll()
        perform("Couldn't erase") { try store.eraseAll() }
        newStudio()
    }

    // MARK: Images

    func uiImage(_ file: String?) -> UIImage? {
        guard let file else { return nil }
        return images.image(named: file, store: store)
    }

    func thumbnail(for garment: Garment) -> UIImage? {
        uiImage(garment.thumbnailFile) ?? uiImage(garment.imageFile)
    }

    /// Scene for an outfit on the user's avatar.
    func scene(for outfit: Outfit, profile: UserProfile? = nil) -> OutfitScene {
        let p = profile ?? library.profile
        return SceneBuilder.build(avatar: AvatarModel(profile: p.body), outfit: outfit, garments: library.garmentsByID,
                                  face: p.face, skinTone: p.effectiveSkinTone)
    }

    func studioScene() -> OutfitScene { scene(for: studio) }

    /// Images keyed by scene layer.
    func layerImages(for scene: OutfitScene, profile: UserProfile? = nil) -> [SceneLayer.Content: UIImage] {
        var result: [SceneLayer.Content: UIImage] = [:]
        for layer in scene.layers {
            switch layer.content {
            case let .garment(id):
                if let g = library.garment(id), let image = uiImage(g.imageFile) { result[layer.content] = image }
            case .face:
                if let face = (profile ?? library.profile).face, let image = uiImage(face.imageFile) { result[.face] = image }
            }
        }
        return result
    }

    /// Alpha mask (downsampled) for hit-testing a layer.
    func hitMask(for content: SceneLayer.Content) -> AlphaMask? {
        switch content {
        case let .garment(id):
            guard let g = library.garment(id) else { return nil }
            return images.hitMask(named: g.imageFile, store: store)
        case .face:
            guard let face = library.profile.face else { return nil }
            return images.hitMask(named: face.imageFile, store: store)
        }
    }

    /// Full-quality image of an outfit for sharing.
    func renderImage(for outfit: Outfit, size: CGSize = CGSize(width: 1080, height: 1620)) -> UIImage? {
        let scene = scene(for: outfit)
        var cgImages: [SceneLayer.Content: CGImage] = [:]
        for (key, image) in layerImages(for: scene) {
            if let cg = image.cgImage { cgImages[key] = cg }
        }
        guard let cg = SceneRenderer.render(scene: scene, images: cgImages, size: size,
                                            background: SRGBColor(hex: "#F7F3EE"), style: avatarStyle) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Decoded images and hit-test masks, cached by file name.
final class ImageCache {
    private let images = NSCache<NSString, UIImage>()
    private var masks: [String: AlphaMask] = [:]

    init() {
        images.countLimit = 300
    }

    func image(named name: String, store: WardrobeStore) -> UIImage? {
        if let cached = images.object(forKey: name as NSString) { return cached }
        guard let data = store.readBlob(named: name), let cg = ImageCodec.decode(data: data) else { return nil }
        let image = UIImage(cgImage: cg)
        images.setObject(image, forKey: name as NSString)
        return image
    }

    func hitMask(named name: String, store: WardrobeStore) -> AlphaMask? {
        if let cached = masks[name] { return cached }
        guard let image = image(named: name, store: store)?.cgImage else { return nil }
        let small = ImageCodec.downscaled(image, maxSide: 160)
        guard let bitmap = RGBABitmap(cgImage: small) else { return nil }
        let mask = bitmap.alphaMask
        masks[name] = mask
        return mask
    }

    func invalidate(_ name: String) {
        images.removeObject(forKey: name as NSString)
        masks[name] = nil
    }

    func removeAll() {
        images.removeAllObjects()
        masks.removeAll()
    }
}
