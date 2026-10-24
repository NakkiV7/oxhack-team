import UIKit
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
