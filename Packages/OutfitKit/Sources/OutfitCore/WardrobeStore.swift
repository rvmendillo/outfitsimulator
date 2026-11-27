import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum StoreError: Error, Equatable, LocalizedError {
    case invalidFileName(String)
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidFileName(name): return "Invalid file name: \(name)"
        case let .unsupportedSchema(version): return "This library was created by a newer version of the app (schema \(version))."
        }
    }
}

/// File-backed persistence: `library.json` plus image blobs in `files/`.
///
/// Not thread-safe; use from one actor (the app uses it on the main actor and
/// does image work elsewhere).
public final class WardrobeStore {
    public static let libraryFileName = "library.json"
    public static let filesDirectoryName = "files"

    public let rootURL: URL
    public private(set) var library: Library
    /// Set when an unreadable library was moved aside during load.
    public private(set) var recoveredFromCorruption = false

    private let fileManager = FileManager.default

    public var filesURL: URL { rootURL.appendingPathComponent(Self.filesDirectoryName, isDirectory: true) }
    public var libraryURL: URL { rootURL.appendingPathComponent(Self.libraryFileName) }

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appendingPathComponent(Self.filesDirectoryName, isDirectory: true),
                                        withIntermediateDirectories: true)
        let url = rootURL.appendingPathComponent(Self.libraryFileName)
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            do {
                let decoded = try Self.decoder.decode(Library.self, from: data)
                if decoded.schemaVersion > Library.currentSchemaVersion {
                    throw StoreError.unsupportedSchema(decoded.schemaVersion)
                }
                library = decoded
            } catch let error as StoreError {
                throw error
            } catch {
                // Keep the unreadable file for support/debugging and start fresh.
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = rootURL.appendingPathComponent("library.corrupt-\(stamp).json")
                try? fileManager.moveItem(at: url, to: backup)
                library = Library()
                recoveredFromCorruption = true
            }
        } else {
            library = Library()
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Default (reference-date seconds as Double) round-trips exactly; ISO 8601
        // would drop sub-second precision and make reloaded data compare unequal.
        e.dateEncodingStrategy = .deferredToDate
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }()

    /// Atomically writes `library.json`.
    public func save() throws {
        let data = try Self.encoder.encode(library)
        try data.write(to: libraryURL, options: .atomic)
    }

    // MARK: Blobs

    /// Only simple file names are accepted (no paths), so callers cannot write
    /// outside the store.
    public static func isValidFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 200, name != ".", name != ".." else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) } && !name.hasPrefix(".")
    }

    public func blobURL(_ name: String) -> URL {
        filesURL.appendingPathComponent(name)
    }

    public func writeBlob(_ data: Data, named name: String) throws {
        guard Self.isValidFileName(name) else { throw StoreError.invalidFileName(name) }
        try data.write(to: blobURL(name), options: .atomic)
    }

    public func readBlob(named name: String) -> Data? {
        guard Self.isValidFileName(name) else { return nil }
        return try? Data(contentsOf: blobURL(name))
    }

    public func blobExists(_ name: String) -> Bool {
        Self.isValidFileName(name) && fileManager.fileExists(atPath: blobURL(name).path)
    }

    public func deleteBlob(named name: String) {
        guard Self.isValidFileName(name) else { return }
        try? fileManager.removeItem(at: blobURL(name))
    }

    /// Unique file name such as `garment-<uuid>-image.png`.
    public static func fileName(prefix: String, id: UUID, suffix: String, ext: String) -> String {
        "\(prefix)-\(id.uuidString.lowercased())-\(suffix).\(ext)"
    }

    // MARK: Garments

    public func upsertGarment(_ garment: Garment) throws {
        if let i = library.garments.firstIndex(where: { $0.id == garment.id }) {
            library.garments[i] = garment
        } else {
            library.garments.append(garment)
        }
        try save()
    }

    /// Deletes a garment, removes it from every outfit and deletes its files.
    public func deleteGarment(id: UUID) throws {
        guard let garment = library.garment(id) else { return }
        library.garments.removeAll { $0.id == id }
        for i in library.outfits.indices where library.outfits[i].contains(id) {
            library.outfits[i].remove(id)
            library.outfits[i].updatedAt = Date()
        }
        try save()
        for file in garment.files { deleteBlob(named: file) }
    }

    // MARK: Outfits

    public func upsertOutfit(_ outfit: Outfit) throws {
        var copy = outfit
        // Never persist references to garments that no longer exist.
        let known = Set(library.garments.map(\.id))
        copy.items.removeAll { !known.contains($0.garmentID) }
        if let i = library.outfits.firstIndex(where: { $0.id == copy.id }) {
            library.outfits[i] = copy
        } else {
            library.outfits.append(copy)
        }
        try save()
    }

    public func deleteOutfit(id: UUID) throws {
        guard let outfit = library.outfits.first(where: { $0.id == id }) else { return }
        library.outfits.removeAll { $0.id == id }
        try save()
        if let thumb = outfit.thumbnailFile { deleteBlob(named: thumb) }
    }

    // MARK: Profile

    public func updateProfile(_ profile: UserProfile) throws {
        let oldFace = library.profile.face?.imageFile
        library.profile = profile
        try save()
        if let oldFace, oldFace != profile.face?.imageFile {
            deleteBlob(named: oldFace)
        }
    }

    // MARK: Maintenance

    /// Removes files in `files/` that nothing references. Returns their names.
    @discardableResult
    public func removeUnreferencedBlobs() -> [String] {
        let referenced = library.referencedFiles
        let names = (try? fileManager.contentsOfDirectory(atPath: filesURL.path)) ?? []
        var removed: [String] = []
        for name in names where !referenced.contains(name) {
            try? fileManager.removeItem(at: blobURL(name))
            removed.append(name)
        }
        return removed.sorted()
    }

    /// Deletes everything and starts with an empty library.
    public func eraseAll() throws {
        try? fileManager.removeItem(at: filesURL)
        try fileManager.createDirectory(at: filesURL, withIntermediateDirectories: true)
        library = Library()
        try save()
    }
}
