import Foundation
import CryptoKit
import Testing
@testable import SpottrCore

/// Replays previously frozen native landmarks; this is explicitly not detector validation.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SPOTTR_CACHED_POSE_CONFIG"] != nil, "Opt-in cached native poses; not detector acceptance")) func optInFrozenNativePoseReplay() throws {
    guard let configPath = ProcessInfo.processInfo.environment["SPOTTR_CACHED_POSE_CONFIG"] else { return }
    let config = try JSONDecoder().decode(CachedReplayConfig.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
    let input = URL(fileURLWithPath: config.input)
    let trials = try JSONDecoder().decode(CachedTrials.self, from: Data(contentsOf: input.appendingPathComponent("results.json"))).results
    if let fps = config.fps { try #require((5...15).contains(fps)) }
    if let every = config.dropoutEvery { try #require(every >= 2) }
    #expect(!trials.isEmpty)
    var results: [[String: Any]] = []
    for trial in trials {
        let id = trial.id
        if let selected = config.trialIDs, !selected.contains(id) { continue }
        let exercise = try #require(Exercise(rawValue: trial.exercise))
        let traceData = try Data(contentsOf: input.appendingPathComponent("\(id)-trace.jsonl"))
        try #require(replaySHA(traceData) == trial.traceSHA256)
        let rows = String(decoding: traceData, as: UTF8.self).split(separator: "\n")
        var counter = RepCounter(exercise: exercise), hold = PoseHoldCounter(exercise: exercise)
        var limbCounters = [RepCounter(exercise:exercise),RepCounter(exercise:exercise)]
        var preferred: Int?, firstEarned: Double?
        var events: [[String: Any]] = [], limbEvents: [[String: Any]] = []
        var measurementCount = 0, processed = 0
        var nextPTS = -Double.infinity
        for (index,line) in rows.enumerated() {
            let row = try JSONDecoder().decode(CachedPose.self, from: Data(line.utf8))
            try #require((row.points.count == 33 || row.points.isEmpty) && row.points.allSatisfy { $0.count == 3 })
            try #require((row.world.count == 33 || row.world.isEmpty) && row.world.allSatisfy { $0.count == 4 })
            if let fps = config.fps {
                if !nextPTS.isFinite { nextPTS = row.pts }
                if row.pts < nextPTS - 0.000001 { continue }
                nextPTS += (floor(max(0,row.pts-nextPTS)*fps)+1)/fps
            }
            let drop = config.dropoutEvery.map { index % $0 == 0 } ?? false
            var points = row.points.map { PosePoint(x: config.mirror == true ? 1-$0[0] : $0[0], y: $0[1], confidence: drop ? 0 : $0[2]) }
            var world = row.world.map { PoseWorldPoint(x: config.mirror == true ? -$0[0] : $0[0], y: $0[1], z: $0[2], confidence: drop ? 0 : $0[3]) }
            if config.mirror == true && points.count == 33 {
                for left in stride(from: 11, through: 31, by: 2) { points.swapAt(left,left+1) }
                if world.count == 33 { for left in stride(from: 11, through: 31, by: 2) { world.swapAt(left,left+1) } }
            }
            let frame = PoseFrame(time: row.pts, width: row.width, height: row.height, points: points, worldPoints: world.isEmpty || config.imageOnly == true ? nil : world, observation: row.observation.flatMap(PoseObservation.init(rawValue:)))
            let held = counter.continuitySide(at: row.pts)
            let sample = PoseGeometry.measure(frame, exercise: exercise, preferredSide: held ?? preferred, allowSideFallback: held == nil)
            preferred = sample?.side ?? preferred
            let before = counter.reps, seconds = hold.observedSeconds
            let input = sample ?? MovementSample(time: row.pts, angle: .nan, confidence: 0)
            if exercise.isTimed { _ = hold.consume(input) } else { _ = counter.consume(input) }
            if exercise.tracksAlternatingLimbs {
                for side in 0...1 {
                    let limb: MovementSample
                    if let sample, sample.side == side {
                        limb = .init(time:row.pts,angle:sample.angle,confidence:sample.confidence,side:side,
                            aligned:sample.aligned,bodyAngle:sample.bodyAngle,provenance:sample.provenance)
                    } else if let other = sample?.secondary, other.side == side {
                        limb = .init(time:row.pts,angle:other.angle,confidence:other.confidence,side:side,
                            aligned:other.aligned,bodyAngle:other.bodyAngle,provenance:other.provenance)
                    } else { limb = .init(time:row.pts,angle:.nan,confidence:0,side:side) }
                    let before = limbCounters[side].reps
                    _ = limbCounters[side].consume(limb)
                    if limbCounters[side].reps > before {
                        var event: [String: Any] = ["side":side,"pts":row.pts]
                        event["duration"] = limbCounters[side].lastRepDuration
                        limbEvents.append(event)
                    }
                }
            }
            if counter.reps > before || hold.observedSeconds > seconds { firstEarned = firstEarned ?? row.pts }
            if counter.reps > before { events.append(["pts": row.pts, "increment": counter.reps-before]) }
            measurementCount += sample?.angle.isFinite == true ? 1 : 0; processed += 1
        }
        let quantity = exercise.isTimed ? hold.observedSeconds : Double(counter.reps)
        var result: [String: Any] = ["id": id, "exercise": exercise.rawValue, "quantity": quantity,
            "frames": processed, "measurementFrames": measurementCount, "events": events, "limbEvents": limbEvents, "completedLimbCycles":counter.completedLimbCycles, "traceSHA256":trial.traceSHA256]
        result["firstEarnedPTS"] = firstEarned
        results.append(result)
    }
    #expect(!results.isEmpty)
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let files = ["Shared/Core/RepCounter.swift","Shared/Core/PoseHoldCounter.swift","Shared/Core/MovementProfiles.swift","Shared/Core/PoseGeometry.swift"]
    let code = try Dictionary(uniqueKeysWithValues: files.map { ($0,try replaySHA(Data(contentsOf:root.appendingPathComponent($0)))) })
    let output: [String: Any] = ["mode": "cachedCoreOnly", "input": config.input, "results": results, "sourceCodeSHA256":code,
        "config":String(decoding:try Data(contentsOf:URL(fileURLWithPath:configPath)),as:UTF8.self)]
    try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: config.output))
}
private struct CachedReplayConfig: Decodable {
    let input: String; let output: String; let trialIDs: [String]?
    let mirror: Bool?; let fps: Double?; let dropoutEvery: Int?; let imageOnly: Bool?
}
private struct CachedPose: Decodable {
    let observation: String?
    let pts: Double; let width: Double; let height: Double
    let points: [[Double]]; let world: [[Double]]
}

private struct CachedTrials: Decodable { let results: [CachedTrial] }
private struct CachedTrial: Decodable { let id: String; let exercise: String; let traceSHA256: String }
private func replaySHA(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
