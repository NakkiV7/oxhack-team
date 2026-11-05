import XCTest
@testable import Spottr

final class PoseDetectorTests: XCTestCase {
    func testNativeDetectorDistinguishesExplicitMultiplePeopleFromMissingPose() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pose", withExtension: "jpg"))
        let original = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let crop = try XCTUnwrap(original.cgImage?.cropping(to: CGRect(x: 220, y: 200, width: 560, height: 460)))
        let source = UIImage(cgImage: crop)
        let image = UIGraphicsImageRenderer(size: CGSize(width: source.size.width * 2, height: source.size.height)).image { _ in
            source.draw(at: .zero); source.draw(at: CGPoint(x: source.size.width, y: 0))
        }
        let result = try PoseDetector().detect(image, at: 0)
        XCTAssertEqual(result.observation, .multiplePeople)
        XCTAssertTrue(result.points.isEmpty)
    }

    #if !SPOTTR_EXPERIMENTAL_PRESAGE
    func testFullPoseModelUsedByThePushupPrototypeIsBundledForOfflineTracking() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "pose_landmarker_full", withExtension: "task"))
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 9_000_000)
    }
    #endif

    func testBundledMediaPipeFindsHumanAndRejectsBlankImage() throws {
        let detector = try PoseDetector()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pose", withExtension: "jpg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let result = try detector.detect(image, at: 0)
        XCTAssertEqual(result.points.count, 33)
        #if !SPOTTR_EXPERIMENTAL_PRESAGE
        XCTAssertEqual(result.worldPoints?.count, 33)
        XCTAssertTrue(result.worldPoints?.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && (0...1).contains($0.confidence) } == true)
        #endif
        XCTAssertGreaterThan(result.points.filter { $0.confidence > 0.6 }.count, 10)
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 640)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 480, height: 640))
        }
        XCTAssertTrue(try detector.detect(blank, at: 1).points.isEmpty)
    }
}

@MainActor
final class TrackingContinuityFlowTests: XCTestCase {
    func testSquatKeepsItsObservedBodySideWhenJointsBrieflyDisappear() async throws {
        for oppositeSideVisible in [false, true] {
            let vision = VisionWorker(cameraAvailable: { false }, requestAccess: { _ in })
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
            let store = TrainingStore(historyURL: url, vision: vision)
            store.selectedExercise = .squat; store.start(); store.hasInput = true
            defer { store.cancelCoaching(); vision.stop() }
            for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90)] {
                try await deliver(pose(time, angle, sides: [1]), to: store)
            }
            try await deliver(pose(1.0, 90, sides: oppositeSideVisible ? [0] : []), to: store)
            try await deliver(pose(1.2, 90, sides: []), to: store)
            try await deliver(pose(1.4, 90, sides: [0, 1]), to: store)
            try await deliver(pose(1.8, 170, sides: [0, 1]), to: store)
            try await deliver(pose(2.0, 170, sides: [0, 1]), to: store)
            XCTAssertEqual(store.session.counter.reps, 1, "A short joint dropout must not switch legs and discard observed squat depth")
        }
    }

    func testInvisibleSquatBottomCannotCreateACountedRep() async throws {
        let vision = VisionWorker(cameraAvailable: { false }, requestAccess: { _ in })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url, vision: vision)
        store.selectedExercise = .squat; store.start(); store.hasInput = true
        defer { store.cancelCoaching(); vision.stop() }
        for (time, angle, visible) in [(0.0, 170.0, true), (0.2, 170, true), (0.6, 90, false),
                                       (0.8, 90, false), (1.2, 170, true), (1.4, 170, true)] {
            try await deliver(pose(time, angle, sides: visible ? [1] : []), to: store)
        }
        XCTAssertEqual(store.session.counter.reps, 0)
    }

    private func deliver(_ frame: PoseFrame, to store: TrainingStore) async throws {
        store.vision.onFrame?(frame, UIImage(), store.session.generation)
        for _ in 0..<100 {
            if store.frame?.time == frame.time { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("The current-generation camera frame was not delivered")
    }

    private func pose(_ time: Double, _ angle: Double, sides: Set<Int>) -> PoseFrame {
        var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
        for side in sides {
            let x = 0.4 + Double(side) * 0.1
            points[11 + side] = .init(x: x, y: 0.05, confidence: 1)
            points[23 + side] = .init(x: x, y: 0.25, confidence: 1)
            points[25 + side] = .init(x: x, y: 0.5, confidence: 1)
            points[27 + side] = .init(x: x + sin(angle * .pi / 180) * 0.25,
                                    y: 0.5 - cos(angle * .pi / 180) * 0.25, confidence: 1)
        }
        return .init(time: time, width: 640, height: 640, points: points)
    }
}

#if !SPOTTR_EXPERIMENTAL_PRESAGE
import AVFoundation
import CoreImage
import CryptoKit

/// Opt-in private footage QA. Normal app tests never access source media.
final class PublicVideoValidationTests: XCTestCase {
    func testFrozenPublicVideosThroughNativeDetector() throws {
        guard let path = ProcessInfo.processInfo.environment["SPOTTR_PUBLIC_VIDEO_CONFIG"] else { throw XCTSkip("Opt-in private public-video validation requires SPOTTR_PUBLIC_VIDEO_CONFIG; normal regression suites do not establish video accuracy") }
        let configURL = URL(fileURLWithPath: path)
        let config = try JSONDecoder().decode(VideoReplayConfig.self, from: Data(contentsOf: configURL))
        XCTAssertTrue(["development", "heldOut"].contains(config.split))
        XCTAssertTrue((5...30).contains(config.fps))
        let root = URL(fileURLWithPath: config.root)
        let annotationData = try Data(contentsOf: root.appendingPathComponent("codex-visual-annotations-locked.json"))
        XCTAssertEqual(videoSHA(annotationData), "25263ee96b8b3ba12f1a8b10297752060a1865d8a800fdc9149e2f17e84d1cb9")
        let references = try JSONDecoder().decode(VideoReferences.self, from: annotationData)
        var sources = try ["source-manifest-frozen.json", "supplemental-source-manifest-frozen.json"].flatMap {
            try JSONDecoder().decode(VideoSources.self, from: Data(contentsOf: root.appendingPathComponent($0))).clips
        }
        XCTAssertEqual(sources.count, 24)
        XCTAssertEqual(sources.filter { $0.split == "heldOut" }.count, 8)
        XCTAssertEqual(references.trials.count, 33)
        var allTrials = references.trials
        if config.includeSupplement == true {
            guard config.split == "development" else { throw CocoaError(.coderInvalidValue) }
            let data = try Data(contentsOf: root.appendingPathComponent("post-baseline-development-annotations-locked.json"))
            XCTAssertEqual(videoSHA(data), "14ccea11bb3e62e7eb834d999798883c16adfd1ae1bc109dc9b5f8babab8b761")
            let extra = try JSONDecoder().decode(VideoReferences.self, from: data).trials
            XCTAssertEqual(extra.count, 8)
            XCTAssertTrue(extra.allSatisfy { $0.split == "development" })
            allTrials += extra
            sources += try JSONDecoder().decode(VideoSources.self, from: Data(contentsOf: root.appendingPathComponent("post-baseline-development-sources-frozen.json"))).clips
            XCTAssertEqual(sources.count, 28)
        }
        let trials = allTrials.filter { $0.split == config.split && (config.trialIDs == nil || config.trialIDs!.contains($0.id)) }
        XCTAssertFalse(trials.isEmpty)
        guard !trials.isEmpty else { throw CocoaError(.coderInvalidValue) }
        let output = URL(fileURLWithPath: config.output)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = try XCTUnwrap(Bundle.main.url(forResource: "pose_landmarker_full", withExtension: "task"))
        var results: [[String: Any]] = []
        for trial in trials {
            let source = try XCTUnwrap(sources.first { $0.clipName == trial.clip })
            XCTAssertEqual(source.split, trial.split)
            XCTAssertEqual(source.sha256, trial.sourceSHA256)
            XCTAssertEqual(videoSHA(try Data(contentsOf: URL(fileURLWithPath: source.file))), source.sha256)
            let result = try replay(trial, source: source, config: config, output: output)
            results.append(result)
            try videoWrite(["mode": "nativeEndToEnd", "modelSHA256": videoSHA(try Data(contentsOf: model)),
                "sdk": "MediaPipeTasksVision 1.1.1", "config": String(decoding: Data(contentsOf: configURL), as: UTF8.self),
                "annotationSHA256": videoSHA(annotationData), "results": results], to: output.appendingPathComponent("results.json"))
            print("PUBLIC_VIDEO_RESULT \(trial.id) \(trial.clip) \(result["quantity"]!) frames=\(result["frames"]!)")
        }
        XCTAssertEqual(results.count, trials.count)
        XCTAssertGreaterThan(results.compactMap { $0["frames"] as? Int }.reduce(0,+), 0)
    }

    private func replay(_ trial: VideoTrial, source: VideoSource, config: VideoReplayConfig, output: URL) throws -> [String: Any] {
        let exercise = try XCTUnwrap(Exercise(rawValue: trial.exercise))
        if let window = config.sensitivityWindow {
            XCTAssertEqual(window.originalTrialID, trial.id); XCTAssertEqual(window.sourceSHA256, source.sha256)
            XCTAssertGreaterThan(window.endSeconds, window.startSeconds)
            XCTAssertGreaterThanOrEqual(window.startSeconds, trial.startSeconds); XCTAssertLessThanOrEqual(window.endSeconds, trial.endSeconds)
        }
        let startSeconds = config.sensitivityWindow?.startSeconds ?? trial.startSeconds
        let endSeconds = config.sensitivityWindow?.endSeconds ?? trial.endSeconds
        let asset = AVURLAsset(url: URL(fileURLWithPath: source.file))
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: startSeconds, preferredTimescale: 600000),
            end: CMTime(seconds: endSeconds, preferredTimescale: 600000))
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        defer { reader.cancelReading() }
        let detector = try PoseDetector()
        let context = CIContext(options: [.cacheIntermediates: false])
        let traceURL = output.appendingPathComponent("\(trial.id)-trace.jsonl")
        guard !FileManager.default.fileExists(atPath: traceURL.path) else { throw CocoaError(.fileWriteFileExists) }
        FileManager.default.createFile(atPath: traceURL.path, contents: nil)
        let trace = try FileHandle(forWritingTo: traceURL)
        defer { try? trace.close() }
        var counter = RepCounter(exercise: exercise)
        var hold = PoseHoldCounter(exercise: exercise)
        var preferredSide: Int?
        var frames = 0, poses = 0, measurements = 0
        var nextTime = startSeconds
        var firstPTS: Double?, lastPTS: Double?, firstEarnedPTS: Double?
        var events: [[String: Any]] = []
        var provenanceCounts: [String: Int] = [:]
        while reader.status == .reading {
            let decoded = try autoreleasepool { () throws -> Bool in
                guard let buffer = readerOutput.copyNextSampleBuffer() else { return false }
                let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                guard pts >= nextTime - 0.000001, pts < endSeconds else { return true }
                if config.sampling == "minimumInterval" { nextTime = pts + 1/config.fps }
                else { nextTime += (floor(max(0, pts-nextTime) * config.fps) + 1) / config.fps }
                guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { throw CocoaError(.coderInvalidValue) }
                let transformed = CIImage(cvPixelBuffer: pixels).transformed(by: track.preferredTransform)
                let normalized = transformed.transformed(by: CGAffineTransform(translationX: -transformed.extent.minX, y: -transformed.extent.minY))
                let scale = min(1, min(Double(config.inputWidth ?? 640) / normalized.extent.width, Double(config.inputHeight ?? 640) / normalized.extent.height))
                let bounded = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let cgImage = try XCTUnwrap(context.createCGImage(bounded, from: bounded.extent))
                let frame = try detector.detect(UIImage(cgImage: cgImage), at: pts)
                let heldSide = counter.continuitySide(at: frame.time)
                let sample = PoseGeometry.measure(frame, exercise: exercise, preferredSide: heldSide ?? preferredSide, allowSideFallback: heldSide == nil)
                preferredSide = sample?.side ?? preferredSide
                let before = counter.reps, secondsBefore = hold.observedSeconds
                let input = sample ?? MovementSample(time: pts, angle: .nan, confidence: 0)
                let cue = exercise.isTimed ? hold.consume(input) : counter.consume(input)
                frames += 1; poses += frame.points.count == 33 ? 1 : 0; measurements += sample?.angle.isFinite == true ? 1 : 0
                firstPTS = firstPTS ?? pts; lastPTS = pts
                if counter.reps > before || hold.observedSeconds > secondsBefore { firstEarnedPTS = firstEarnedPTS ?? pts }
                if counter.reps > before {
                    var event: [String: Any] = ["pts": pts, "increment": counter.reps-before, "total": counter.reps]
                    event["duration"] = counter.lastRepDuration
                    if let phases = counter.lastRepPhases { event["phases"] = ["lowering": phases.lowering, "rising": phases.rising, "minimumAngle": phases.minimumAngle] }
                    events.append(event)
                }
                var row: [String: Any] = ["observation": frame.observation.rawValue, "pts": pts, "width": frame.width, "height": frame.height,
                    "points": frame.points.map { [$0.x,$0.y,$0.confidence] },
                    "world": frame.worldPoints?.map { [$0.x,$0.y,$0.z,$0.confidence] } ?? [],
                    "quantity": exercise.isTimed ? hold.observedSeconds : Double(counter.reps), "cue": String(describing: cue)]
                if let sample, sample.angle.isFinite {
                    provenanceCounts[sample.provenance.rawValue, default: 0] += 1
                    row["sample"] = ["angle": sample.angle, "side": sample.side, "confidence": sample.confidence,
                        "provenance": sample.provenance.rawValue, "qualification": String(describing: sample.holdQualification),
                        "secondaryAngle": sample.secondary?.angle as Any? ?? NSNull(), "secondarySide": sample.secondary?.side as Any? ?? NSNull()]
                }
                try trace.write(contentsOf: JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]))
                try trace.write(contentsOf: Data([10]))
                guard frames <= 1800 else { throw CocoaError(.coderInvalidValue) }
                return true
            }
            if !decoded { break }
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        XCTAssertGreaterThan(frames, 0)
        let quantity = exercise.isTimed ? hold.observedSeconds : Double(counter.reps)
        let reference = config.sensitivityWindow?.referenceQuantity ?? trial.referenceQuantity
        var result: [String: Any] = ["id": trial.id, "clip": trial.clip, "exercise": trial.exercise, "split": trial.split,
            "windowStartSeconds": startSeconds, "windowEndSeconds": endSeconds, "isPostBaselineSensitivity": config.sensitivityWindow != nil,
            "sourceSHA256": source.sha256, "frames": frames, "poseFrames": poses, "measurementFrames": measurements,
            "poseCoverage": Double(poses)/Double(max(1,frames)), "measurementCoverage": Double(measurements)/Double(max(1,frames)),
            "quantity": quantity, "referenceQuantity": reference, "unit": trial.referenceUnit,
            "missedQuantity": max(0,reference-quantity), "extraQuantity": max(0,quantity-reference),
            "events": events, "completedLimbCycles": counter.completedLimbCycles, "provenanceFrames": provenanceCounts,
            "preferredTransform": [track.preferredTransform.a,track.preferredTransform.b,track.preferredTransform.c,track.preferredTransform.d,track.preferredTransform.tx,track.preferredTransform.ty],
            "traceSHA256": videoSHA(try Data(contentsOf: traceURL))]
        result["expectedAutomaticQuantity"] = trial.expectedAutomaticQuantity
        result["firstPTS"] = firstPTS; result["lastPTS"] = lastPTS; result["firstEarnedPTS"] = firstEarnedPTS
        return result
    }
}

private struct VideoSensitivity: Decodable {
    let originalTrialID: String; let sourceSHA256: String
    let startSeconds: Double; let endSeconds: Double; let referenceQuantity: Double
}
private struct VideoReplayConfig: Decodable {
    let sensitivityWindow: VideoSensitivity?
    let root: String
    let output: String
    let split: String
    let fps: Double
    let trialIDs: [String]?
    let includeSupplement: Bool?
    let inputWidth: Int?
    let inputHeight: Int?
    let sampling: String?
}
private struct VideoSources: Decodable { let clips: [VideoSource] }
private struct VideoSource: Decodable { let clipName: String; let file: String; let sha256: String; let split: String }
private struct VideoReferences: Decodable { let trials: [VideoTrial] }
private struct VideoTrial: Decodable {
    let id: String; let clip: String; let exercise: String; let split: String; let sourceSHA256: String
    let startSeconds: Double; let endSeconds: Double; let referenceQuantity: Double; let referenceUnit: String
    let expectedAutomaticQuantity: Double?
}
private func videoSHA(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func videoWrite(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted,.sortedKeys]).write(to: url, options: .atomic)
}
#endif
