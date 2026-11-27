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

        let eye1 = centroid(region(landmarks?.leftPupil)) ?? centroid(region(landmarks?.leftEye))
        let eye2 = centroid(region(landmarks?.rightPupil)) ?? centroid(region(landmarks?.rightEye))
        guard let e1 = eye1, let e2 = eye2 else { return nil }
        let (eyeL, eyeR) = PoseJoints.ordered(e1, e2)

        let contour = region(landmarks?.faceContour)
        let lips = region(landmarks?.outerLips)
        var chin = contour.max { $0.y < $1.y } ?? CGPoint(x: pixelBox.midX, y: pixelBox.maxY)
        // The chin is never above the mouth; fall back to the box bottom if the
        // contour is clearly truncated.
        if let lowestLip = lips.map({ Double($0.y) }).max(), Double(chin.y) < lowestLip {
            chin = CGPoint(x: Double(chin.x), y: Double(pixelBox.maxY))
        }

        return FaceLandmarks(
            boundingBox: pixelBox,
            eyeLeft: eyeL!, eyeRight: eyeR!, chin: chin,
            faceContour: contour, outerLips: lips,
            yaw: face.yaw?.doubleValue, roll: face.roll?.doubleValue, pitch: face.pitch?.doubleValue,
            faceCount: faces.count
        )
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
