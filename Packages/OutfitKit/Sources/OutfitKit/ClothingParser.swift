#if canImport(CoreML) && canImport(Vision)
import CoreGraphics
import CoreML
import Foundation
import Vision

/// Classes predicted by the SegFormer clothing parser (ATR label set).
public enum ParserLabel: Int, CaseIterable, Sendable {
    case background = 0
    case hat
    case hair
    case sunglasses
    case upperClothes
    case skirt
    case pants
    case dress
    case belt
    case leftShoe
    case rightShoe
    case face
    case leftLeg
    case rightLeg
    case leftArm
    case rightArm
    case bag
    case scarf

    public var garmentCategory: GarmentCategory? {
        switch self {
        case .hat: return .hat
        case .sunglasses: return .eyewear
        case .upperClothes: return .top
        case .skirt, .pants: return .bottom
        case .dress: return .dress
        case .belt: return .belt
        case .leftShoe, .rightShoe: return .shoes
        case .bag: return .bag
        case .scarf: return .scarf
        case .background, .hair, .face, .leftLeg, .rightLeg, .leftArm, .rightArm: return nil
        }
    }

    /// Exposed skin / body parts (used to recognise photos of a person).
    public var isBodyPart: Bool {
        switch self {
        case .face, .hair, .leftLeg, .rightLeg, .leftArm, .rightArm: return true
        default: return false
        }
    }
}

/// Per-pixel class indices at the parser's resolution.
public struct LabelMap: Sendable {
    public let width: Int
    public let height: Int
    public let labels: [UInt8]

    public init(width: Int, height: Int, labels: [UInt8]) {
        precondition(labels.count == width * height, "label map size mismatch")
        self.width = width
        self.height = height
        self.labels = labels
    }

    public func fraction(of set: Set<ParserLabel>) -> Double {
        guard !labels.isEmpty else { return 0 }
        let raw = Set(set.map { UInt8($0.rawValue) })
        var count = 0
        for l in labels where raw.contains(l) { count += 1 }
        return Double(count) / Double(labels.count)
    }

    /// Binary mask (0/255) at label resolution.
    public func mask(for set: Set<ParserLabel>) -> AlphaMask {
        let raw = Set(set.map { UInt8($0.rawValue) })
        return AlphaMask(width: width, height: height, values: labels.map { raw.contains($0) ? 255 : 0 })
    }

    /// Soft mask upsampled to an image size.
    public func mask(for set: Set<ParserLabel>, width outWidth: Int, height outHeight: Int) -> AlphaMask {
        mask(for: set).resized(width: outWidth, height: outHeight)
    }

    /// The most frequent label from `candidates` inside `region` (a mask in
    /// image coordinates of any size) and the share of the region it covers,
    /// or nil if none occur.
    public func dominantLabel(in region: AlphaMask, among candidates: Set<ParserLabel>) -> (label: ParserLabel, coverage: Double)? {
        guard region.width > 0, region.height > 0 else { return nil }
        var counts = [Int](repeating: 0, count: ParserLabel.allCases.count)
        var total = 0
        let step = max(1, Int((Double(region.width * region.height) / 40_000).squareRoot()))
        var y = 0
        while y < region.height {
            var x = 0
            while x < region.width {
                if region[x, y] >= 128 {
                    total += 1
                    let lx = min(width - 1, x * width / region.width)
                    let ly = min(height - 1, y * height / region.height)
                    let l = Int(labels[ly * width + lx])
                    if l < counts.count { counts[l] += 1 }
                }
                x += step
            }
            y += step
        }
        var best: ParserLabel?
        var bestCount = 0
        for label in candidates.sorted(by: { $0.rawValue < $1.rawValue }) where counts[label.rawValue] > bestCount {
            bestCount = counts[label.rawValue]
            best = label
        }
        guard let best, total > 0 else { return nil }
        return (best, Double(bestCount) / Double(total))
    }
}

public enum ClothingParserError: Error, LocalizedError {
    case modelNotFound
    case noOutput
    case unexpectedOutput(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound: return "The clothing recognition model is missing from this build."
        case .noOutput: return "The clothing recognition model returned no result."
        case let .unexpectedOutput(detail): return "Unexpected model output: \(detail)"
        }
    }
}

/// Runs the bundled Core ML clothing parser.
public final class ClothingParser: @unchecked Sendable {
    public static let inputSize = 512
    /// Name of the model resource (compiled by Xcode to `<name>.mlmodelc`).
    public static let modelName = "ClothingParserModel"

    private let model: VNCoreMLModel

    public init(compiledModelURL: URL) throws {
        let configuration = MLModelConfiguration()
        #if targetEnvironment(simulator)
        configuration.computeUnits = .cpuOnly
        #else
        configuration.computeUnits = .all
        #endif
        let mlModel = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
        model = try VNCoreMLModel(for: mlModel)
    }

    /// The compiled model shipped inside `bundle`, if present.
    public static func bundledModelURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: modelName, withExtension: "mlmodelc")
    }

    /// Compiles an `.mlpackage` (used by tests and development tools).
    public static func compileModel(at packageURL: URL) async throws -> URL {
        try await MLModel.compileModel(at: packageURL)
    }

    public func parse(_ image: CGImage) throws -> LabelMap {
        let request = VNCoreMLRequest(model: model)
        VisionCompute.configure(request)
        // The model was trained on images squashed to 512x512, so do the same.
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
              let array = observation.featureValue.multiArrayValue else {
            throw ClothingParserError.noOutput
        }
        return try Self.labelMap(from: array)
    }

    static func labelMap(from array: MLMultiArray) throws -> LabelMap {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard shape.count >= 2, strides.count == shape.count else {
            throw ClothingParserError.unexpectedOutput("shape \(shape)")
        }
        let h = shape[shape.count - 2], w = shape[shape.count - 1]
        let sy = strides[strides.count - 2], sx = strides[strides.count - 1]
        guard w > 0, h > 0 else { throw ClothingParserError.unexpectedOutput("empty") }
        let maxLabel = Int32(ParserLabel.allCases.count - 1)
        var labels = [UInt8](repeating: 0, count: w * h)

        switch array.dataType {
        case .int32:
            array.withUnsafeBytes { raw in
                for y in 0..<h {
                    for x in 0..<w {
                        let v = raw.load(fromByteOffset: (y * sy + x * sx) * MemoryLayout<Int32>.stride, as: Int32.self)
                        labels[y * w + x] = UInt8(max(0, min(maxLabel, v)))
                    }
                }
            }
        case .float32:
            array.withUnsafeBytes { raw in
                for y in 0..<h {
                    for x in 0..<w {
                        let v = raw.load(fromByteOffset: (y * sy + x * sx) * MemoryLayout<Float>.stride, as: Float.self)
                        labels[y * w + x] = UInt8(max(0, min(Float(maxLabel), v.rounded())))
                    }
                }
            }
        default:
            // Rare formats: slower, but correct.
            let leading = [NSNumber](repeating: 0, count: shape.count - 2)
            for y in 0..<h {
                for x in 0..<w {
                    let v = array[leading + [NSNumber(value: y), NSNumber(value: x)]].int32Value
                    labels[y * w + x] = UInt8(max(0, min(maxLabel, v)))
                }
            }
        }
        return LabelMap(width: w, height: h, labels: labels)
    }
}
#endif
