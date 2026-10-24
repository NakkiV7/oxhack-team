import AVFoundation
import UIKit

enum VisionState {
    case idle, camera, video, finished, unavailable, denied, failed(String)
    var message: String {
        switch self {
        case .idle: return "Set your iPhone to the side. Keep your full body in view."
        case .camera: return "Camera"
        case .video: return "Video analysis"
        case .finished: return "Video complete"
        case .unavailable: return "Camera unavailable"
        case .denied: return "Allow camera access in Settings, or import a video."
        case .failed(let message): return message
        }
    }
}

final class VisionWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let capture = AVCaptureSession()
    var onFrame: ((PoseFrame, UIImage, UUID) -> Void)?
    var onState: ((VisionState, UUID) -> Void)?
    private let queue = DispatchQueue(label: "spottr.vision", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var detector: PoseDetector?
    private var token: UUID?
    private var lastFrame = -Double.infinity
    private var generator: AVAssetImageGenerator?
    private var videoTime = 0.0
    private var videoDuration = 0.0
    private var videoURL: URL?
    private var scoped = false
    private let requestAccess: (@escaping (Bool) -> Void) -> Void
    private let cameraAvailable: () -> Bool
    private let intentLock = NSLock()
    private var intent: UUID?

    private func setIntent(_ value: UUID?) {
        intentLock.lock(); defer { intentLock.unlock() }; intent = value
    }
    private func hasIntent(_ value: UUID) -> Bool {
        intentLock.lock(); defer { intentLock.unlock() }; return intent == value
    }

    init(cameraAvailable: @escaping () -> Bool = { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil },
         requestAccess: @escaping (@escaping (Bool) -> Void) -> Void = { AVCaptureDevice.requestAccess(for: .video, completionHandler: $0) }) {
        self.cameraAvailable = cameraAvailable
        self.requestAccess = requestAccess
        super.init()
    }

    func camera(token: UUID) {
        setIntent(token)
        guard cameraAvailable() else { onState?(.unavailable, token); return }
        requestAccess { [weak self] granted in
            guard let self else { return }
            self.queue.async {
                guard self.hasIntent(token) else { return }
                self.closeVideo(); self.token = token
                guard granted else { self.onState?(.denied, token); return }
                self.startCamera(token: token)
            }
        }
    }

    private func startCamera(token: UUID) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            onState?(.unavailable, token); return
        }
        do {
            detector = try PoseDetector(); lastFrame = -.infinity
            if capture.inputs.isEmpty {
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                capture.beginConfiguration(); capture.sessionPreset = .vga640x480
                guard capture.canAddInput(input), capture.canAddOutput(output) else {
                    capture.commitConfiguration(); onState?(.unavailable, token); return
                }
                capture.addInput(input); capture.addOutput(output)
                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    connection.automaticallyAdjustsVideoMirroring = false
                    if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
                }
                capture.commitConfiguration()
            }
            guard hasIntent(token) else { return }
            capture.startRunning(); onState?(.camera, token)
        } catch { onState?(.failed("Couldn’t start pose tracking. Try again."), token) }
    }

    func video(url: URL, token: UUID) {
        setIntent(token)
        queue.async {
            guard self.hasIntent(token) else { return }
            self.capture.stopRunning(); self.closeVideo(); self.token = token
            self.videoURL = url; self.scoped = url.startAccessingSecurityScopedResource()
            let asset = AVURLAsset(url: url)
            Task {
                do {
                    let duration = try await asset.load(.duration).seconds
                    self.queue.async { self.prepareVideo(asset: asset, duration: duration, token: token) }
                } catch {
                    self.queue.async {
                        guard self.hasIntent(token) else { return }
                        self.onState?(.failed("Couldn’t open this video."), token); self.closeVideo()
                    }
                }
            }
        }
    }

    private func prepareVideo(asset: AVAsset, duration: Double, token: UUID) {
        guard hasIntent(token) else { return }
        guard duration.isFinite, duration > 0, duration <= 600 else {
            onState?(.failed("Choose a video under 10 minutes."), token); closeVideo(); return
        }
        videoDuration = duration
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        self.generator = generator; videoTime = 0
        beginVideo(token: token)
    }

    private func beginVideo(token: UUID) {
        do {
            detector = try PoseDetector(); onState?(.video, token); stepVideo(token: token)
        } catch { onState?(.failed("Couldn’t load pose tracking."), token) }
    }

    private func stepVideo(token: UUID) {
        guard self.token == token, hasIntent(token), let generator else { return }
        guard videoTime < videoDuration else { onState?(.finished, token); return }
        let time = videoTime
        generator.generateCGImageAsynchronously(for: CMTime(seconds: time, preferredTimescale: 600)) { image, _, error in
            self.queue.async {
                guard self.token == token, self.hasIntent(token) else { return }
                guard let image, error == nil else {
                    self.onState?(.failed("Couldn’t read this video. Try another clip."), token); return
                }
                do {
                    try self.process(UIImage(cgImage: image), at: time, token: token)
                    self.videoTime += 0.1
                    self.queue.asyncAfter(deadline: .now() + 0.1) { self.stepVideo(token: token) }
                } catch { self.onState?(.failed("Couldn’t analyse this video."), token) }
            }
        }
    }

    func pause() { setIntent(nil); queue.async { self.token = nil; self.capture.stopRunning() } }
    func resume(token: UUID, source: InputSource) {
        setIntent(token)
        queue.async {
            guard self.hasIntent(token) else { return }
            self.token = token
            if source == .video {
                if self.generator != nil { self.beginVideo(token: token); return }
                if let url = self.videoURL { self.video(url: url, token: token); return }
                self.onState?(.failed("Choose a video to continue this set."), token); return
            }
            self.startCamera(token: token)
        }
    }
    func stop() {
        setIntent(nil)
        queue.async { self.token = nil; self.capture.stopRunning(); self.closeVideo(); self.detector = nil }
    }
    private func closeVideo() {
        generator?.cancelAllCGImageGeneration(); generator = nil
        if scoped { videoURL?.stopAccessingSecurityScopedResource() }
        videoURL = nil; scoped = false
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let token, hasIntent(token), let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - lastFrame >= 0.1 else { return }
        lastFrame = time
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        do { try process(UIImage(cgImage: cgImage), at: time, token: token) }
        catch { onState?(.failed("Pose tracking stopped. Try the camera again."), token) }
    }
    private func process(_ image: UIImage, at time: Double, token: UUID) throws {
        guard let detector else { return }
        let frame = try detector.detect(image, at: time)
        onFrame?(frame, image, token)
    }
}
