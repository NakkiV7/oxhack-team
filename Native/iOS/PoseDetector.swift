import UIKit
#if SPOTTR_EXPERIMENTAL_PRESAGE
import ImageIO
import Vision

final class PoseDetector {
    typealias Observation = [VNHumanBodyPoseObservation.JointName: PosePoint]
    private let observe: (CGImage, CGImagePropertyOrientation) throws -> [Observation]
    private var preferredTurn = 0

    init(observe: ((CGImage, CGImagePropertyOrientation) throws -> [Observation])? = nil) throws {
        self.observe = observe ?? { image, orientation in
            let request = VNDetectHumanBodyPoseRequest()
            try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
            return try (request.results ?? []).map { observation in
                try observation.recognizedPoints(.all).mapValues { point in
                    PosePoint(x: point.location.x, y: point.location.y, confidence: Double(point.confidence))
                }
            }
        }
    }
    func detect(_ image: UIImage, at time: Double) throws -> PoseFrame {
        let upright = image.imageOrientation == .up ? image : UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cgImage = upright.cgImage else { throw CocoaError(.coderInvalidValue) }
        let turns = [preferredTurn] + [0, 1, 3].filter { $0 != preferredTurn }
        var best = PoseFrame(time: time, width: image.size.width, height: image.size.height, points: [])
        var bestScore = -Double.infinity
        for turn in turns {
            let orientation: CGImagePropertyOrientation = turn == 1 ? .right : (turn == 3 ? .left : .up)
            let observations = try observe(cgImage, orientation)
            guard observations.count <= 1 else {
                return PoseFrame(time: time, width: image.size.width, height: image.size.height, points: [], observation: .multiplePeople)
            }
            let frame = AppleVisionPoseAdapter.frame(observations: observations, time: time,
                size: image.size, quarterTurns: turn)
            let score = AppleVisionPoseAdapter.trackingScore(frame)
            if score > bestScore { best = frame; bestScore = score; preferredTurn = turn }
            if score >= 0.6 { return frame }
        }
        return best
    }
}

enum AppleVisionPoseAdapter {
    static func frame(observations: [[VNHumanBodyPoseObservation.JointName: PosePoint]],
                      time: Double, size: CGSize, quarterTurns: Int = 0) -> PoseFrame {
        guard observations.count == 1, let observation = observations.first,
              observation.values.contains(where: { $0.confidence > 0 }) else {
            return PoseFrame(time: time, width: size.width, height: size.height, points: [], observation: observations.count > 1 ? .multiplePeople : .notDetected)
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
            let x = point.x, y = 1 - point.y
            let mapped: (Double, Double)
            switch (quarterTurns % 4 + 4) % 4 {
            case 1: mapped = (y, 1 - x)
            case 2: mapped = (1 - x, 1 - y)
            case 3: mapped = (1 - y, x)
            default: mapped = (x, y)
            }
            points[index] = PosePoint(x: mapped.0, y: mapped.1, confidence: point.confidence)
        }
        return PoseFrame(time: time, width: size.width, height: size.height, points: points)
    }

    static func trackingScore(_ frame: PoseFrame) -> Double {
        guard frame.points.count == 33 else { return 0 }
        return (0...1).map { side in
            [11, 13, 15, 23].map { frame.points[$0 + side].confidence }.min() ?? 0
        }.max() ?? 0
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
    private var processingClock = PoseProcessingClock()
    private let landmarker: PoseLandmarker
    init() throws {
        guard let model = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
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
        guard let timestamp = processingClock.milliseconds(for: time) else { throw CocoaError(.coderInvalidValue) }
        let result = try landmarker.detect(videoFrame: MPImage(uiImage: image), timestampInMilliseconds: timestamp)
        let points = result.landmarks.count == 1 ? result.landmarks[0].map {
            PosePoint(x: Double($0.x), y: Double($0.y),
                      confidence: min($0.visibility?.doubleValue ?? 0, $0.presence?.doubleValue ?? 0))
        } : []
        let world: [PoseWorldPoint]? = result.landmarks.count == 1 && result.worldLandmarks.count == 1 && points.count == 33 && result.worldLandmarks[0].count == 33 ? result.worldLandmarks[0].enumerated().map { index, landmark in
            PoseWorldPoint(x: Double(landmark.x), y: Double(landmark.y), z: Double(landmark.z),
                confidence: min(points[index].confidence, landmark.visibility?.doubleValue ?? points[index].confidence))
        } : nil
        let validWorld = world.flatMap { values in
            values.allSatisfy { [$0.x,$0.y,$0.z].allSatisfy { $0.isFinite && abs($0) <= 5 } && $0.confidence.isFinite && (0...1).contains($0.confidence) } ? values : nil
        }
        return PoseFrame(time: time, width: image.size.width, height: image.size.height, points: points, worldPoints: validWorld, observation: result.landmarks.count > 1 ? .multiplePeople : (result.landmarks.count == 1 ? .singlePerson : .notDetected))
    }
}

#endif
