#if canImport(Vision)
import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Body joints via `VNDetectHumanBodyPoseRequest`.
public enum PoseDetector {
    /// Joints of the most prominent person, in image pixel coordinates
    /// (top-left origin). Left/right are image-left/right.
    public static func detect(in image: CGImage, minimumConfidence: Float = 0.25) throws -> PoseJoints? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observations = request.results, !observations.isEmpty else { return nil }

        let w = Double(image.width), h = Double(image.height)
        var best: (joints: PoseJoints, spread: Double)?
        for observation in observations {
            guard let points = try? observation.recognizedPoints(.all) else { continue }
            func point(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                guard let p = points[name], p.confidence >= minimumConfidence else { return nil }
                return CGPoint(x: Double(p.location.x) * w, y: (1 - Double(p.location.y)) * h)
            }
            let (shoulderL, shoulderR) = PoseJoints.ordered(point(.leftShoulder), point(.rightShoulder))
            let (elbowL, elbowR) = PoseJoints.ordered(point(.leftElbow), point(.rightElbow))
            let (wristL, wristR) = PoseJoints.ordered(point(.leftWrist), point(.rightWrist))
            let (hipL, hipR) = PoseJoints.ordered(point(.leftHip), point(.rightHip))
            let (kneeL, kneeR) = PoseJoints.ordered(point(.leftKnee), point(.rightKnee))
            let (ankleL, ankleR) = PoseJoints.ordered(point(.leftAnkle), point(.rightAnkle))
            let joints = PoseJoints(neck: point(.neck), shoulderL: shoulderL, shoulderR: shoulderR,
                                    elbowL: elbowL, elbowR: elbowR, wristL: wristL, wristR: wristR,
                                    hipL: hipL, hipR: hipR, kneeL: kneeL, kneeR: kneeR, ankleL: ankleL, ankleR: ankleR)
            let all = [joints.neck, shoulderL, shoulderR, hipL, hipR, kneeL, kneeR, ankleL, ankleR].compactMap { $0 }
            guard all.count >= 2 else { continue }
            let ys = all.map { Double($0.y) }
            let xs = all.map { Double($0.x) }
            let spread = (ys.max()! - ys.min()!) + (xs.max()! - xs.min()!)
            if best == nil || spread > best!.spread {
                best = (joints, spread)
            }
        }
        return best?.joints
    }
}

/// Face position and landmarks via `VNDetectFaceLandmarksRequest`.
public struct FaceLandmarks: Equatable, Sendable {
    /// Face box in image pixels (top-left origin).
    public var boundingBox: CGRect
    public var eyeLeft: CGPoint
    public var eyeRight: CGPoint
    public var chin: CGPoint
    public var faceContour: [CGPoint]
    public var outerLips: [CGPoint]
    /// Radians, when Vision provides them.
    public var yaw: Double?
    public var roll: Double?
    public var pitch: Double?
    public var faceCount: Int

    public var eyeMidpoint: CGPoint { .midpoint(eyeLeft, eyeRight) }
    public var interpupillaryDistance: Double { eyeLeft.distance(to: eyeRight) }
    public var eyeToChin: Double { eyeMidpoint.distance(to: chin) }

    public func translated(by origin: CGPoint) -> FaceLandmarks {
        var copy = self
        copy.boundingBox = boundingBox.offsetBy(dx: -origin.x, dy: -origin.y)
        copy.eyeLeft = eyeLeft - origin
        copy.eyeRight = eyeRight - origin
        copy.chin = chin - origin
        copy.faceContour = faceContour.map { $0 - origin }
        copy.outerLips = outerLips.map { $0 - origin }
        return copy
    }
}

public enum FaceAnalyzer {
    /// Landmarks of the largest face, or nil when no face is found.
    public static func detect(in image: CGImage) throws -> FaceLandmarks? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard let faces = request.results, !faces.isEmpty else { return nil }
        guard let face = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            return nil
        }
        let size = CGSize(width: image.width, height: image.height)
        let h = Double(image.height)
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: Double(p.x), y: h - Double(p.y)) }
        func region(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let r, r.pointCount > 0 else { return [] }
            return r.pointsInImage(imageSize: size).map(flip)
        }
        func centroid(_ points: [CGPoint]) -> CGPoint? {
            guard !points.isEmpty else { return nil }
            let sx = points.reduce(0.0) { $0 + Double($1.x) }, sy = points.reduce(0.0) { $0 + Double($1.y) }
            return CGPoint(x: sx / Double(points.count), y: sy / Double(points.count))
        }

        let landmarks = face.landmarks
        let box = face.boundingBox
        let pixelBox = CGRect(x: Double(box.minX) * size.width, y: (1 - Double(box.maxY)) * size.height,
                              width: Double(box.width) * size.width, height: Double(box.height) * size.height)

        // Eyes: prefer the pupil, but only if it lies within its eye region.
        func eye(pupil: VNFaceLandmarkRegion2D?, region eyeRegion: VNFaceLandmarkRegion2D?) -> CGPoint? {
            let pupilPoint = centroid(region(pupil))
            let outline = region(eyeRegion)
            guard let center = centroid(outline) else { return pupilPoint }
            guard let pupilPoint else { return center }
            let xs = outline.map { Double($0.x) }, ys = outline.map { Double($0.y) }
            let eyeWidth = xs.max()! - xs.min()!, eyeHeight = ys.max()! - ys.min()!
            let bounds = CGRect(x: xs.min()! - 0.5 * eyeWidth, y: ys.min()! - eyeHeight - 2,
                                width: 2 * eyeWidth, height: 3 * eyeHeight + 4)
            return bounds.contains(pupilPoint) ? pupilPoint : center
        }
        let (eyeL, eyeR) = Self.plausibleEyes(eye(pupil: landmarks?.leftPupil, region: landmarks?.leftEye),
                                              eye(pupil: landmarks?.rightPupil, region: landmarks?.rightEye),
                                              faceBox: pixelBox)

        let contour = region(landmarks?.faceContour)
        let lips = region(landmarks?.outerLips)
        let chin = Self.plausibleChin(eyeLeft: eyeL, eyeRight: eyeR, contour: contour, lips: lips, faceBox: pixelBox)

        return FaceLandmarks(
            boundingBox: pixelBox,
            eyeLeft: eyeL, eyeRight: eyeR, chin: chin,
            faceContour: contour, outerLips: lips,
            yaw: face.yaw?.doubleValue, roll: face.roll?.doubleValue, pitch: face.pitch?.doubleValue,
            faceCount: faces.count
        )
    }

    /// Eye-to-chin height over pupil distance for real adult faces.
    static let plausibleChinRatio: ClosedRange<Double> = 1.25...2.7
    /// Pupil distance over face-box width (front-facing ~0.4, three-quarter ~0.3).
    static let plausibleEyeSpacing: ClosedRange<Double> = 0.18...0.62

    /// Validates detected pupils against the face box; when they are missing or
    /// implausible, uses the typical eye positions inside a Vision face box.
    static func plausibleEyes(_ a: CGPoint?, _ b: CGPoint?, faceBox: CGRect) -> (CGPoint, CGPoint) {
        let fallback = (CGPoint(x: faceBox.minX + 0.3 * faceBox.width, y: faceBox.minY + 0.3 * faceBox.height),
                        CGPoint(x: faceBox.minX + 0.7 * faceBox.width, y: faceBox.minY + 0.3 * faceBox.height))
        guard let a, let b, faceBox.width > 1 else { return fallback }
        let (l, r) = a.x <= b.x ? (a, b) : (b, a)
        let spacing = l.distance(to: r) / Double(faceBox.width)
        let tilt = abs(atan2(Double(r.y - l.y), Double(r.x - l.x))) * 180 / .pi
        let box = faceBox.insetBy(dx: -0.1 * faceBox.width, dy: -0.1 * faceBox.height)
        let upperHalf = Double(faceBox.minY) + 0.6 * Double(faceBox.height)
        guard plausibleEyeSpacing.contains(spacing), tilt <= 40,
              box.contains(l), box.contains(r), Double(l.y) < upperHalf, Double(r.y) < upperHalf else {
            return fallback
        }
        return (l, r)
    }

    /// The chin (menton), validated against facial anatomy. Candidates, in
    /// order: middle of the jaw contour, its lowest point, bottom of the face box, and an estimate
    /// from the mouth; the first that is below the mouth, inside the (slightly
    /// enlarged) face box and at a plausible distance from the eyes wins.
    static func plausibleChin(eyeLeft: CGPoint, eyeRight: CGPoint, contour: [CGPoint], lips: [CGPoint], faceBox: CGRect) -> CGPoint {
        let eyeMid = CGPoint.midpoint(eyeLeft, eyeRight)
        let ipd = max(eyeLeft.distance(to: eyeRight), 1)
        let v = eyeRight - eyeLeft
        // Unit vector perpendicular to the eye line, pointing down the face.
        var down = CGPoint(x: -Double(v.y) / ipd, y: Double(v.x) / ipd)
        if down.y < 0 { down = down * -1 }
        func heightBelowEyes(_ p: CGPoint) -> Double {
            let d = p - eyeMid
            return Double(d.x) * Double(down.x) + Double(d.y) * Double(down.y)
        }
        let lowestLip = lips.map(heightBelowEyes).max()
        let box = faceBox.insetBy(dx: -0.25 * faceBox.width, dy: -0.25 * faceBox.height)
        func isPlausible(_ p: CGPoint) -> Bool {
            let h = heightBelowEyes(p)
            if let lowestLip, h <= lowestLip { return false }
            return box.contains(p) && plausibleChinRatio.contains(h / ipd)
        }
        var candidates: [CGPoint] = []
        // Vision's jaw contour runs ear to ear with the chin in the middle.
        if contour.count >= 5 { candidates.append(contour[contour.count / 2]) }
        if let lowest = contour.max(by: { heightBelowEyes($0) < heightBelowEyes($1) }) { candidates.append(lowest) }
        candidates.append(CGPoint(x: faceBox.midX, y: faceBox.maxY))
        if !lips.isEmpty {
            // The mouth sits ~58% of the way from the eyes to the chin.
            let mouth = CGPoint(x: lips.map { Double($0.x) }.reduce(0, +) / Double(lips.count),
                                y: lips.map { Double($0.y) }.reduce(0, +) / Double(lips.count))
            candidates.append(eyeMid + (mouth - eyeMid) / 0.58)
        }
        if let chin = candidates.first(where: isPlausible) { return chin }
        // Last resort: the average face (eye-to-chin = 1.8 x pupil distance).
        return eyeMid + down * (1.8 * ipd)
    }
}

/// Person matte via `VNGeneratePersonSegmentationRequest`.
public enum PersonSegmenter {
    /// Soft person mask at the image's size, or nil if no person is found.
    public static func matte(for image: CGImage) throws -> AlphaMask? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard let buffer = request.results?.first?.pixelBuffer, let mask = AlphaMask(pixelBuffer: buffer) else { return nil }
        let scaled = mask.resized(width: image.width, height: image.height)
        return scaled.coverage(threshold: 128) > 0.002 ? scaled : nil
    }
}

/// Foreground subjects ("lift subject") via `VNGenerateForegroundInstanceMaskRequest`.
public enum SubjectSegmenter {
    /// One soft mask per foreground instance, each at the image's size.
    public static func instanceMasks(for image: CGImage) throws -> [AlphaMask] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first else { return [] }
        var masks: [AlphaMask] = []
        for index in result.allInstances {
            let buffer = try result.generateScaledMaskForImage(forInstances: IndexSet(integer: index), from: handler)
            guard var mask = AlphaMask(pixelBuffer: buffer) else { continue }
            if mask.width != image.width || mask.height != image.height {
                mask = mask.resized(width: image.width, height: image.height)
            }
            masks.append(mask)
        }
        return masks
    }
}
#endif
