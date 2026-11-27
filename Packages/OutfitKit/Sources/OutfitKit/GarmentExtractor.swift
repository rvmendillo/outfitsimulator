#if canImport(Vision) && canImport(CoreML)
import CoreGraphics
import Foundation

/// A piece separated from a photo, ready to be reviewed and saved.
public struct ExtractedPiece: Identifiable, @unchecked Sendable {
    public enum Origin: Equatable, Sendable {
        /// Found by the clothing parser on a photo of a person.
        case parsed
        /// A separate object found by subject lifting or background keying.
        case object
    }

    public let id = UUID()
    public var category: GarmentCategory
    public var name: String
    /// Opaque crop of the original photo around the piece.
    public var source: RGBABitmap
    /// Soft mask over `source`.
    public var mask: AlphaMask
    public var anchors: GarmentAnchors
    public var dominantColor: RGBColor
    public var palette: [RGBColor]
    /// Share of the photo the piece covers (0...1).
    public var areaFraction: Double
    public var origin: Origin
    /// Where `source` was cropped from, in the processed photo's pixels.
    public var cropRect: PixelRect

    /// Rebuilds the RGBA cut-out from `source` and `mask`.
    public func cutout() -> RGBABitmap {
        CutoutComposer.compose(source: source, mask: mask)
    }
}

public struct ExtractionResult: @unchecked Sendable {
    public enum Kind: Equatable, Sendable {
        case wornOutfit
        case separateItems
        case nothingFound
    }

    public var kind: Kind
    public var pieces: [ExtractedPiece]
    public var pose: PoseJoints?
}

/// Separates garments from a photo.
///
/// * Photos of a person: the clothing parser labels each pixel (top, trousers,
///   shoes, ...); edges are refined with the person matte and fit guides come
///   from the detected body pose.
/// * Flat-lays / product photos: each foreground object (Vision subject
///   lifting, or background keying as a fallback) becomes a piece, labelled by
///   the parser's majority vote when possible.
public final class GarmentExtractor: @unchecked Sendable {
    public let parser: ClothingParser?
    /// Longest side used for processing and stored cut-outs.
    public var workingMaxSide = 1600

    public init(parser: ClothingParser?) {
        self.parser = parser
    }

    struct Group {
        var category: GarmentCategory
        var labels: Set<ParserLabel>
        var minArea: Double
        var maxComponents: Int
        var refineWithMatte: Bool
        var name: String
    }

    static let groups: [Group] = [
        Group(category: .top, labels: [.upperClothes], minArea: 0.004, maxComponents: 3, refineWithMatte: true, name: "Top"),
        Group(category: .dress, labels: [.dress], minArea: 0.004, maxComponents: 2, refineWithMatte: true, name: "Dress"),
        Group(category: .bottom, labels: [.pants], minArea: 0.004, maxComponents: 2, refineWithMatte: true, name: "Trousers"),
        Group(category: .bottom, labels: [.skirt], minArea: 0.004, maxComponents: 2, refineWithMatte: true, name: "Skirt"),
        Group(category: .shoes, labels: [.leftShoe, .rightShoe], minArea: 0.0012, maxComponents: 2, refineWithMatte: true, name: "Shoes"),
        Group(category: .hat, labels: [.hat], minArea: 0.0008, maxComponents: 1, refineWithMatte: true, name: "Hat"),
        Group(category: .eyewear, labels: [.sunglasses], minArea: 0.0002, maxComponents: 1, refineWithMatte: false, name: "Sunglasses"),
        Group(category: .bag, labels: [.bag], minArea: 0.002, maxComponents: 1, refineWithMatte: false, name: "Bag"),
        Group(category: .scarf, labels: [.scarf], minArea: 0.002, maxComponents: 1, refineWithMatte: true, name: "Scarf"),
        Group(category: .belt, labels: [.belt], minArea: 0.0008, maxComponents: 1, refineWithMatte: true, name: "Belt"),
    ]

    public func extract(from input: CGImage) throws -> ExtractionResult {
        let image = ImageCodec.downscaled(input, maxSide: workingMaxSide)
        guard let bitmap = RGBABitmap(cgImage: image) else { throw ImageError.contextFailed }

        let labelMap = try parser?.parse(image)
        let bodyFraction = labelMap?.fraction(of: Set(ParserLabel.allCases.filter(\.isBodyPart))) ?? 0
        let garmentFraction = labelMap?.fraction(of: Set(ParserLabel.allCases.filter { $0.garmentCategory != nil })) ?? 0

        if let labelMap, bodyFraction >= 0.003, garmentFraction >= 0.004 {
            let pieces = try extractWorn(image: image, bitmap: bitmap, labelMap: labelMap)
            if !pieces.pieces.isEmpty { return pieces }
        }
        let objects = extractObjects(image: image, bitmap: bitmap, labelMap: labelMap)
        return ExtractionResult(kind: objects.isEmpty ? .nothingFound : .separateItems, pieces: objects, pose: nil)
    }

    // MARK: Worn outfits

    func extractWorn(image: CGImage, bitmap: RGBABitmap, labelMap: LabelMap) throws -> ExtractionResult {
        let w = image.width, h = image.height
        let matte = try? PersonSegmenter.matte(for: image)
        let pose = try? PoseDetector.detect(in: image)
        var pieces: [ExtractedPiece] = []
        for group in Self.groups {
            guard labelMap.fraction(of: group.labels) >= group.minArea else { continue }
            var mask = labelMap.mask(for: group.labels, width: w, height: h)
            if group.refineWithMatte, let matte {
                let refined = mask.multiplied(by: matte)
                // Only trust the matte when it keeps most of the garment.
                if Double(refined.setCount()) >= 0.6 * Double(mask.setCount()) {
                    mask = refined
                }
            }
            mask = mask
                .keepingLargestComponents(maxCount: group.maxComponents, minRelativeArea: 0.08)
                .fillingHoles(maxHoleFraction: 0.02)
            guard let piece = makePiece(bitmap: bitmap, mask: mask, category: group.category, baseName: group.name,
                                        pose: pose, origin: .parsed) else { continue }
            pieces.append(piece)
        }
        return ExtractionResult(kind: .wornOutfit, pieces: pieces, pose: pose)
    }

    // MARK: Separate items

    func extractObjects(image: CGImage, bitmap: RGBABitmap, labelMap: LabelMap?) -> [ExtractedPiece] {
        var masks: [AlphaMask] = []
        if let instances = try? SubjectSegmenter.instanceMasks(for: image), !instances.isEmpty {
            masks = instances
        } else if let keyed = BackgroundKeyer.foregroundMask(bitmap) {
            masks = BackgroundKeyer.split(keyed)
        }
        let minArea = 0.004 * Double(image.width * image.height)
        var pieces: [ExtractedPiece] = []
        var shoeMasks: [AlphaMask] = []
        let garmentLabels = Set(ParserLabel.allCases.filter { $0.garmentCategory != nil })
        // An instance can contain several disconnected objects; split them.
        let objectMasks = masks.flatMap { BackgroundKeyer.split($0, minAreaFraction: 0.004) }
        for raw in objectMasks {
            let mask = raw.fillingHoles(maxHoleFraction: 0.02)
            guard Double(mask.setCount()) >= minArea else { continue }
            // Trust the parser's vote only when it clearly covers the object.
            var label: ParserLabel?
            if let vote = labelMap?.dominantLabel(in: mask, among: garmentLabels), vote.coverage >= 0.3 {
                label = vote.label
            }
            let category = label?.garmentCategory ?? Self.guessCategory(for: mask)
            if category == .shoes {
                shoeMasks.append(mask)
                continue
            }
            let name: String
            switch label {
            case .pants?: name = "Trousers"
            case .skirt?: name = "Skirt"
            case .sunglasses?: name = "Sunglasses"
            default: name = category.displayName
            }
            if let piece = makePiece(bitmap: bitmap, mask: mask, category: category, baseName: name, pose: nil, origin: .object) {
                pieces.append(piece)
            }
        }
        // A pair of shoes photographed together becomes one piece.
        if !shoeMasks.isEmpty {
            var pairs: [AlphaMask] = []
            var remaining = shoeMasks
            while !remaining.isEmpty {
                var current = remaining.removeFirst()
                if let partnerIndex = remaining.firstIndex(where: { Self.areSimilarSize(current, $0) }) {
                    current = current.union(remaining.remove(at: partnerIndex))
                }
                pairs.append(current)
            }
            for mask in pairs {
                if let piece = makePiece(bitmap: bitmap, mask: mask, category: .shoes, baseName: "Shoes", pose: nil, origin: .object) {
                    pieces.append(piece)
                }
            }
        }
        return pieces.sorted { lhs, rhs in
            let li = GarmentCategory.closetOrder.firstIndex(of: lhs.category) ?? 0
            let ri = GarmentCategory.closetOrder.firstIndex(of: rhs.category) ?? 0
            return li != ri ? li < ri : lhs.areaFraction > rhs.areaFraction
        }
    }

    static func areSimilarSize(_ a: AlphaMask, _ b: AlphaMask) -> Bool {
        let ca = Double(a.setCount()), cb = Double(b.setCount())
        guard ca > 0, cb > 0 else { return false }
        return min(ca, cb) / max(ca, cb) > 0.5
    }

    /// Without the parser, guess from the outline: long → bottom, wide and
    /// short → shoes, otherwise a top.
    static func guessCategory(for mask: AlphaMask) -> GarmentCategory {
        guard let box = mask.boundingBox() else { return .top }
        let aspect = Double(box.height) / Double(max(box.width, 1))
        if aspect > 1.9 { return .bottom }
        if aspect < 0.55 { return .shoes }
        return .top
    }

    // MARK: Piece construction

    func makePiece(bitmap: RGBABitmap, mask fullMask: AlphaMask, category: GarmentCategory, baseName: String, pose: PoseJoints?, origin: ExtractedPiece.Origin) -> ExtractedPiece? {
        guard let box = fullMask.boundingBox(threshold: 100) else { return nil }
        let padding = max(4, Int(Double(max(box.width, box.height)) * 0.03))
        let crop = box.expanded(by: padding, clampedToWidth: bitmap.width, height: bitmap.height)
        let source = bitmap.cropped(to: crop)
        let mask = fullMask.cropped(to: crop)
        guard source.width > 2, source.height > 2 else { return nil }
        let localPose = pose?.translated(by: CGPoint(x: crop.minX, y: crop.minY))
        let anchors = AnchorEstimator.estimate(category: category, mask: mask, pose: localPose)
        let cutout = CutoutComposer.compose(source: source, mask: mask)
        let swatches = ColorPalette.dominantColors(samples: CutoutComposer.colorSamples(cutout), k: 3)
        let dominant = swatches.first?.color ?? RGBColor(r: 0.5, g: 0.5, b: 0.5)
        let colorName = ColorNaming.name(for: dominant)
        return ExtractedPiece(
            category: category,
            name: "\(colorName) \(baseName)",
            source: source,
            mask: mask,
            anchors: anchors,
            dominantColor: dominant,
            palette: swatches.map(\.color),
            areaFraction: Double(fullMask.setCount()) / Double(max(1, bitmap.width * bitmap.height)),
            origin: origin,
            cropRect: crop
        )
    }
}
#endif
