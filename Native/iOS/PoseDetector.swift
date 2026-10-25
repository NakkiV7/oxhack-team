import UIKit
#if SPOTTR_EXPERIMENTAL_PRESAGE
import ImageIO
import Vision

final class PoseDetector {
    init() throws {}
    func detect(_ image: UIImage, at time: Double) throws -> PoseFrame {
        guard let cgImage = image.cgImage else { throw CocoaError(.coderInvalidValue) }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage,
            orientation: AppleVisionPoseAdapter.orientation(for: image.imageOrientation), options: [:])
        try handler.perform([request])
        let observations = try (request.results ?? []).map { observation in
            try observation.recognizedPoints(.all).mapValues { point in
                PosePoint(x: point.location.x, y: point.location.y, confidence: Double(point.confidence))
            }
        }
        return AppleVisionPoseAdapter.frame(observations: observations, time: time, size: image.size)
    }
}

enum AppleVisionPoseAdapter {
    static func frame(observations: [[VNHumanBodyPoseObservation.JointName: PosePoint]],
                      time: Double, size: CGSize) -> PoseFrame {
        guard observations.count == 1, let observation = observations.first,
              observation.values.contains(where: { $0.confidence > 0 }) else {
            return PoseFrame(time: time, width: size.width, height: size.height, points: [])
        }
        var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
        let joints: [(Int, VNHumanBodyPoseObservation.JointName)] = [
            (0, .nose), (2, .leftEye), (5, .rightEye), (7, .leftEar), (8, .rightEar),
            (11, .leftShoulder), (12, .rightShoulder), (13, .leftElbow), (14, .rightElbow),
            (15, .leftWrist), (16, .rightWrist), (23, .leftHip), (24, .rightHip),
            (25, .leftKnee), (26, .rightKnee), (27, .leftAnkle), (28, .rightAnkle)
        ]
        for (index, joint) in joints {
            guard let point = observation[joint] else { continue }
            points[index] = PosePoint(x: point.x, y: 1 - point.y, confidence: point.confidence)
        }
        return PoseFrame(time: time, width: size.width, height: size.height, points: points)
    }

    static func orientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
#else
import MediaPipeTasksVision

final class PoseDetector {
    private let landmarker: PoseLandmarker
    init() throws {
        guard let model = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = model
        options.runningMode = .video
        options.numPoses = 2
        options.minPoseDetectionConfidence = 0.6
        options.minPosePresenceConfidence = 0.6
        options.minTrackingConfidence = 0.6
        landmarker = try PoseLandmarker(options: options)
    }
    func detect(_ image: UIImage, at time: Double) throws -> PoseFrame {
        let result = try landmarker.detect(videoFrame: MPImage(uiImage: image), timestampInMilliseconds: Int(time * 1000))
        let points = result.landmarks.count == 1 ? result.landmarks[0].map {
            PosePoint(x: Double($0.x), y: Double($0.y),
                      confidence: min($0.visibility?.doubleValue ?? 0, $0.presence?.doubleValue ?? 0))
        } : []
        return PoseFrame(time: time, width: image.size.width, height: image.size.height, points: points)
    }
}

#endif
