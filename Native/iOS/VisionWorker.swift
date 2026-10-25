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

protocol VisionCameraDriving: AnyObject {
    var capture: AVCaptureSession { get }
    func start(worker: VisionWorker, queue: DispatchQueue, captureID: UUID) throws
    func stop()
}

final class VisionWorker: NSObject, @unchecked Sendable {
    var capture: AVCaptureSession { cameraDriver.capture }
    var onFrame: ((PoseFrame, UIImage, UUID) -> Void)?
    var onState: ((VisionState, UUID) -> Void)?
    var onPreviewState: ((VisionState, UUID) -> Void)?
    /// At most one retained sample. Receiver must call done after processing or dropping it.
    var onSample: ((CMSampleBuffer, UUID, @escaping () -> Void) -> Void)?
    private let queue = DispatchQueue(label: "spottr.vision", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let cameraDriver: any VisionCameraDriving
    private let makePoseProcessor: () throws -> (UIImage, Double) throws -> PoseFrame
    private var processPose: ((UIImage, Double) throws -> PoseFrame)?
    private enum CameraMode: Equatable { case pose, preview }
    private var cameraMode: CameraMode = .pose
    private var sampleInFlight: UUID?
    private var captureID: UUID?
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
         requestAccess: @escaping (@escaping (Bool) -> Void) -> Void = { AVCaptureDevice.requestAccess(for: .video, completionHandler: $0) },
         cameraDriver: (any VisionCameraDriving)? = nil,
         makePoseProcessor: @escaping () throws -> (UIImage, Double) throws -> PoseFrame = {
             let detector = try PoseDetector()
             return { image, time in try detector.detect(image, at: time) }
         }) {
        self.cameraAvailable = cameraAvailable
        self.requestAccess = requestAccess
        self.cameraDriver = cameraDriver ?? FrontCameraDriver()
        self.makePoseProcessor = makePoseProcessor
        super.init()
    }

    func camera(token: UUID) { openCamera(token: token, mode: .pose) }
    func frontPreview(token: UUID) { openCamera(token: token, mode: .preview) }

    private func openCamera(token: UUID, mode: CameraMode) {
        setIntent(token)
        guard cameraAvailable() else { report(.unavailable, token: token, mode: mode); return }
        requestAccess { [weak self] granted in
            guard let self else { return }
            self.queue.async {
                guard self.hasIntent(token) else { return }
                self.closeVideo(); self.token = token; self.cameraMode = mode
                guard granted else { self.report(.denied, token: token, mode: mode); return }
                self.startCamera(token: token, mode: mode)
            }
        }
    }

    private func startCamera(token: UUID, mode: CameraMode) {
        do {
            processPose = mode == .pose ? try makePoseProcessor() : nil
            lastFrame = -.infinity
            guard hasIntent(token) else { return }
            let captureID = UUID()
            self.captureID = captureID
            try cameraDriver.start(worker: self, queue: queue, captureID: captureID)
            report(.camera, token: token, mode: mode)
        } catch {
            captureID = nil
            report(.failed(mode == .pose ? "Couldn’t start pose tracking. Try again." : "Couldn’t start the front camera. Try again."), token: token, mode: mode)
        }
    }

    private func report(_ state: VisionState, token: UUID, mode: CameraMode) {
        guard hasIntent(token) else { return }
        if mode == .preview { onPreviewState?(state, token) }
        else { onState?(state, token) }
    }

    func video(url: URL, token: UUID) {
        setIntent(token)
        queue.async {
            guard self.hasIntent(token) else { return }
            self.captureID = nil; self.cameraDriver.stop(); self.closeVideo(); self.token = token
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
            processPose = try makePoseProcessor(); onState?(.video, token); stepVideo(token: token)
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

    func pause() { setIntent(nil); queue.async { self.token = nil; self.captureID = nil; self.cameraDriver.stop() } }
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
            self.startCamera(token: token, mode: self.cameraMode)
        }
    }
    func stop() {
        setIntent(nil)
        queue.async { self.token = nil; self.captureID = nil; self.cameraDriver.stop(); self.closeVideo(); self.processPose = nil; self.cameraMode = .pose }
    }
    private func closeVideo() {
        generator?.cancelAllCGImageGeneration(); generator = nil
        if scoped { videoURL?.stopAccessingSecurityScopedResource() }
        videoURL = nil; scoped = false
    }
    /// Entry used by the per-start capture delegate on its serial queue.
    func receiveCameraSample(_ sampleBuffer: CMSampleBuffer, captureID: UUID) {
        guard self.captureID == captureID, let token, hasIntent(token),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let onSample, sampleInFlight == nil {
            let sampleID = UUID()
            sampleInFlight = sampleID
            onSample(sampleBuffer, token) { [weak self] in
                self?.queue.async { [weak self] in
                    guard let self, sampleInFlight == sampleID else { return }
                    sampleInFlight = nil
                }
            }
        }
        guard cameraMode == .pose, hasIntent(token) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - lastFrame >= 0.1 else { return }
        lastFrame = time
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        do { try process(UIImage(cgImage: cgImage), at: time, token: token) }
        catch { onState?(.failed("Pose tracking stopped. Try the camera again."), token) }
    }
    private func process(_ image: UIImage, at time: Double, token: UUID) throws {
        guard let processPose, hasIntent(token) else { return }
        let frame = try processPose(image, time)
        guard hasIntent(token) else { return }
        onFrame?(frame, image, token)
    }
}

private final class FrontCameraDriver: VisionCameraDriving {
    let capture = AVCaptureSession()
    private var output: AVCaptureVideoDataOutput?
    private var receiver: FrontCameraFrameDelegate?
    func start(worker: VisionWorker, queue: DispatchQueue, captureID: UUID) throws {
        if capture.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                throw CameraError.unavailable
            }
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            capture.beginConfiguration(); capture.sessionPreset = .vga640x480
            defer { capture.commitConfiguration() }
            guard capture.canAddInput(input), capture.canAddOutput(output) else { throw CameraError.unavailable }
            capture.addInput(input); capture.addOutput(output)
            self.output = output
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                connection.automaticallyAdjustsVideoMirroring = false
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
            }
        }
        let receiver = FrontCameraFrameDelegate(worker: worker, captureID: captureID)
        self.receiver = receiver
        output?.setSampleBufferDelegate(receiver, queue: queue)
        capture.startRunning()
    }
    func stop() { capture.stopRunning() }
    private enum CameraError: Error { case unavailable }
}


private final class FrontCameraFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var worker: VisionWorker?
    private let captureID: UUID
    init(worker: VisionWorker, captureID: UUID) { self.worker = worker; self.captureID = captureID }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        worker?.receiveCameraSample(sampleBuffer, captureID: captureID)
    }
}
