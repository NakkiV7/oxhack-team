import SwiftUI

struct CoachingEvent: Identifiable, Equatable {
    let id = UUID()
    let sessionID: UUID
    let generation: UUID
    let decision: CoachingDecision
    let issuedAt: Double
    let expiresAt: Double?
}

@MainActor @Observable
final class TrainingStore {
    enum ConfiguredInput: String, CaseIterable {
        case manual, phoneCamera, secondaryCamera
        var source: InputSource { self == .manual ? .manual : .camera }
        var title: String {
            switch self {
            case .manual: return "Manual reps"
            case .phoneCamera: return "iPhone camera"
            case .secondaryCamera: return "Pi side camera"
            }
        }
    }
    var session = TrainingSession()
    private(set) var configured: ConfigurableSession?
    private(set) var configuredInput: ConfiguredInput = .manual
    var sessionPhase: SessionPhase { configured?.phase ?? session.phase }
    var presented = false
    var history: [SessionRecord] = []
    private(set) var historyAvailable = true
    var error: String?
    var visionState: VisionState = .idle
    private(set) var frontPreviewState: VisionState = .idle
    var frame: PoseFrame?
    var image: UIImage?
    var source: InputSource = .camera
    var hasInput = false
    var selectedExercise: Exercise = .squat
    let vision: VisionWorker
    let secondaryVision: SecondaryCameraVisionWorker
    private(set) var usingSecondaryCamera = false
    private let secondaryCameraClient: @MainActor () throws -> SecondaryCameraClient
    let companion = CompanionLink()
    var watchReachable = false
    private(set) var reportedDiscomfort = false
    private let historyStore: HistoryStore
    let rewards: NativeRewardsStore
    private let rewardDefaults: UserDefaults
    private var preferredSide: Int?
    private var coachingPolicy = CoachingPolicy()
    private var activeCoachingEvent: CoachingEvent?
    private var configuredDiscomfortCueSessionID: UUID?
    private var previewRepContext: VoiceCueContext?
    private var previewObservedReps = 0
    private var previewRepTime: Double?
    private(set) var voiceFeedbackEnabled = false
    private var appActive = true
    let remoteVoice: RemoteVoicePlayback?
    let previewMode: Bool
    private let coachingVoice: CoachingVoiceBridge
    private var restGeneration: UUID?
    private var restStartedAt: Double?

    private var feedbackContext: VoiceCueContext {
        if let run = configured { return .init(sessionID: run.id, generation: run.generation, phase: run.phase) }
        return .init(sessionID: session.id, generation: session.generation, phase: session.phase)
    }
    private var trackingExercise: Exercise? { configured?.trackingExercise ?? (configured == nil ? session.exercise : nil) }
    private var acceptsTracking: Bool {
        if let run = configured { return run.source == .camera && run.hasStarted && run.phase == .active && run.trackingExercise != nil }
        return session.phase == .active && source != .manual
    }

    var coachingEvent: CoachingEvent? {
        let context = feedbackContext
        guard let event = activeCoachingEvent,
              event.sessionID == context.sessionID, event.generation == context.generation,
              context.phase == .active || context.phase == .rest ||
                (context.phase == .finished && event.decision.reason == .workoutCompleted) else { return nil }
        return event
    }

    func cancelCoaching() {
        activeCoachingEvent = nil
        coachingVoice.cancel()
    }

    func setVoiceFeedback(_ enabled: Bool) {
        guard voiceFeedbackEnabled != enabled else { return }
        coachingVoice.update(context: feedbackContext, event: coachingEvent, enabled: false, now: now)
        voiceFeedbackEnabled = enabled
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        if !active {
            if requiresForegroundCapture, sessionPhase == .active, configured?.hasStarted != false { pause() }
            else { cancelCoaching() }
        }
    }

    private var requiresForegroundCapture: Bool {
        configured != nil ? configuredInput != .manual : hasInput && source != .manual
    }

    func actualRestElapsed(at time: Double? = nil) -> Double? {
        let time = time ?? now
        guard time.isFinite, session.phase == .rest, restGeneration == session.generation,
              let restStartedAt else { return nil }
        return max(0, time - restStartedAt)
    }

    func coachingTick(at time: Double? = nil, wallTime: Date = Date()) {
        guard appActive else { cancelCoaching(); return }
        let time = time ?? now
        let context = feedbackContext
        defer { coachingVoice.update(context: context, event: coachingEvent, enabled: voiceFeedbackEnabled, now: time) }
        guard time.isFinite else { return }
        let reps = configured?.actualReps ?? session.actualReps ?? 0
        let milestone = consumePreviewRep(context: context, reps: reps, time: time)
        if context.phase == .finished {
            if coachingEvent?.expiresAt.map({ time >= $0 }) == true { cancelCoaching() }
            return
        }
        if configured?.stoppedForDiscomfort == true {
            guard context.phase == .rest, configuredDiscomfortCueSessionID != context.sessionID else { return }
            configuredDiscomfortCueSessionID = context.sessionID
            activeCoachingEvent = CoachingEvent(sessionID: context.sessionID, generation: context.generation,
                decision: .discomfort, issuedAt: time, expiresAt: nil)
            return
        }
        if let run = configured, run.source != .camera || run.trackingExercise == nil || (!run.hasStarted && !run.stoppedForDiscomfort) {
            cancelCoaching(); return
        }
        let cue = configured?.cue ?? session.cue
        let restElapsed = configured == nil ? actualRestElapsed(at: time) : configured?.restElapsed(at: time)
        let stopReason: StopReason?
        if let run = configured {
            stopReason = run.stoppedForDiscomfort ? .discomfort : (run.phase == .rest ? run.completed.last?.reason : nil)
        } else { stopReason = session.phase == .rest ? session.sets.last?.reason : nil }
        if coachingEvent == nil || activeCoachingEvent?.expiresAt.map({ time >= $0 }) == true {
            activeCoachingEvent = nil
        }
        if let event = coachingEvent, event.decision.priority == .form,
           (event.decision.reason == .alignment && cue != .alignment)
            || (event.decision.reason == .tracking && cue != .tracking) {
            activeCoachingEvent = nil
        }
        guard let exercise = trackingExercise else { return }
        let decision = coachingPolicy.evaluate(.init(
            sessionID: context.sessionID, generation: context.generation, phase: context.phase,
            now: time, exercise: exercise, repCount: configured?.actualReps ?? session.actualReps ?? 0,
            lastRepDuration: configured == nil ? session.counter.lastRepDuration : configured?.counter?.lastRepDuration, cue: cue,
            heartRate: recentHeartRate(at: wallTime), wallTime: wallTime,
            restElapsed: restElapsed,
            target: configured?.current.target ?? session.exercise.target,
            stopReason: stopReason, source: configured?.source ?? source,
            encouragementEnabled: !previewMode && voiceFeedbackEnabled && (remoteVoice?.preference == .david || remoteVoice?.preference == .arnold)
        ))
        if let decision {
            activeCoachingEvent = CoachingEvent(sessionID: context.sessionID, generation: context.generation,
                                               decision: decision, issuedAt: time,
                                               expiresAt: decision.priority == .stop ? nil : time + 6)
            return
        }
        guard previewMode, milestone, voiceFeedbackEnabled, remoteVoice?.preference == .arnold,
              context.phase == .active, acceptsTracking, (configured?.source ?? source) == .camera,
              cue == .controlled, stopReason == nil, !reportedDiscomfort,
              coachingEvent?.decision.priority != .stop, coachingEvent?.decision.priority != .form,
              coachingEvent?.decision.reason != .slowerRep else { return }
        activeCoachingEvent = CoachingEvent(sessionID: context.sessionID, generation: context.generation,
            decision: .init(text: "Keep a steady rhythm.", priority: .pacing, reason: .steadyRhythm,
                            facts: ["\(reps) camera reps recorded in this set."], elapsed: nil),
            issuedAt: time, expiresAt: time + 6)
    }

    private func consumePreviewRep(context: VoiceCueContext, reps: Int, time: Double) -> Bool {
        let sameSession = previewRepContext?.sessionID == context.sessionID
        let sameGeneration = sameSession && previewRepContext?.generation == context.generation
        let previous = sameGeneration ? previewObservedReps : (sameSession ? reps : 0)
        let freshTime = !sameGeneration || time >= (previewRepTime ?? -.infinity)
        previewRepContext = context
        previewObservedReps = sameGeneration ? max(previewObservedReps, reps) : reps
        previewRepTime = sameGeneration ? max(previewRepTime ?? time, time) : time
        return freshTime && reps == previous + 1 && reps > 0 && reps.isMultiple(of: 2)
    }

    private func recentHeartRate(at date: Date) -> [SensorReading] {
        let readings = (configured?.telemetry ?? session.telemetry).suffix(120).compactMap(\.heartRate).filter {
            let age = date.timeIntervalSince($0.date)
            return $0.value.isFinite && (1...300).contains($0.value) && age >= -2 && age <= 30
        }
        let distinct = readings.reduce(into: [Date: SensorReading]()) { $0[$1.date] = $1 }
        return Array(distinct.values.sorted { $0.date < $1.date }.suffix(60))
    }

    init(historyURL: URL? = nil, secondaryVision: SecondaryCameraVisionWorker? = nil,
         secondaryCameraClient: (@MainActor () throws -> SecondaryCameraClient)? = nil,
         voicePlayback: VoicePlayback? = nil, vision: VisionWorker? = nil, rewardsStore: NativeRewardsStore? = nil,
         defaults: UserDefaults = .standard, previewMode: Bool = false, previewPlayback: VoicePlayback? = nil) {
        rewardDefaults = defaults
        self.previewMode = previewMode
        self.vision = vision ?? VisionWorker()
        let playback = voicePlayback ?? RemoteVoicePlayback(previewPlayback: previewMode ? (previewPlayback ?? DemoVoicePlayback()) : nil)
        remoteVoice = playback as? RemoteVoicePlayback
        coachingVoice = CoachingVoiceBridge(playback: playback)
        self.secondaryVision = secondaryVision ?? SecondaryCameraVisionWorker()
        self.secondaryCameraClient = secondaryCameraClient ?? {
            if previewMode {
                guard let data = SecondaryCameraSettings.includedPreviewData() else { throw SecondaryCameraError.configuration }
                return try SecondaryCameraSettings.client(previewData: data)
            }
            return try SecondaryCameraSettings.client()
        }
        let root = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let folder = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        historyStore = HistoryStore(url: historyURL ?? folder.appendingPathComponent("history.json"))
        rewards = rewardsStore ?? NativeRewardsStore(url: historyStore.url.deletingLastPathComponent().appendingPathComponent("rewards.json"))
        do { history = try historyStore.load().reversed() }
        catch { historyAvailable = false; self.error = "Couldn’t read your saved sessions." }
        self.vision.onFrame = { [weak self] frame, image, generation in
            Task { @MainActor in
                guard let self, !self.usingSecondaryCamera else { return }
                self.receive(frame, image: image, generation: generation)
            }
        }
        self.vision.onState = { [weak self] state, generation in
            Task { @MainActor in
                guard let self, !self.usingSecondaryCamera, self.acceptsTracking, self.feedbackContext.generation == generation else { return }
                self.visionState = state
                if case .finished = state { self.pause() }
                if case .failed = state { self.pause() }
                if case .denied = state { self.pause() }
                if case .unavailable = state { self.pause() }
            }
        }
        self.vision.onPreviewState = { [weak self] state, generation in
            Task { @MainActor in
                guard let self, self.usingSecondaryCamera, self.acceptsTracking,
                      self.feedbackContext.generation == generation else { return }
                self.frontPreviewState = state
            }
        }
        self.secondaryVision.onFrame = { [weak self] frame, image, generation in
            guard let self, self.usingSecondaryCamera else { return }
            self.receive(frame, image: image, generation: generation)
        }
        self.secondaryVision.onState = { [weak self] state, generation in
            guard let self, self.usingSecondaryCamera, self.acceptsTracking,
                  self.feedbackContext.generation == generation else { return }
            switch state {
            case .idle: break
            case .starting: self.visionState = .idle; self.frame = nil; self.image = nil
            case .tracking: self.visionState = .camera
            case .failed(let message): self.visionState = .failed(message); self.pause()
            }
        }
        companion.onCommand = { [weak self] command in
            Task { @MainActor in self?.command(command) }
        }
        companion.onTelemetry = { [weak self] telemetry in
            Task { @MainActor in
                guard let self else { return }
                if self.configured != nil { self.configured?.receiveTelemetry(telemetry) }
                else { self.session.receiveTelemetry(telemetry) }
            }
        }
        companion.onReachability = { [weak self] reachable in
            Task { @MainActor in self?.watchReachable = reachable; self?.publish() }
        }
        companion.onRequest = { [weak self] in Task { @MainActor in self?.publish() } }
    }

    func publish() {
        if let configured { companion.publish(CompanionSnapshot(session: configured, at: now)) }
        else { companion.publish(CompanionSnapshot(session: session)) }
    }
    private func command(_ command: CompanionCommand) {
        guard command.sessionID == (configured?.id ?? session.id),
              command.generation == (configured?.generation ?? session.generation) else { publish(); return }
        switch command.action {
        case .startSet: beginConfiguredSet()
        case .pause: pause()
        case .resume: resume()
        case .endSet: endSet()
        case .nextSet: next()
        case .finish: finish()
        }
        publish()
    }
    func heartRate(at date: Date) -> String {
        (configured?.telemetry ?? session.telemetry).compactMap(\.heartRate)
            .filter { $0.heartRate(at: date) != nil }.max { $0.date < $1.date }
            .map { "\(Int($0.value.rounded())) bpm" } ?? "—"
    }

    var now: Double { ProcessInfo.processInfo.systemUptime }
    func start() {
        defer { publish() }
        voiceFeedbackEnabled = false
        configured = nil
        configuredInput = .manual
        stopCapture(); session = TrainingSession(firstExercise: selectedExercise)
        coachingPolicy = CoachingPolicy(history: history)
        reportedDiscomfort = false
        session.start(at: now); presented = true; error = nil; clearInput()
    }
    func startPlan(_ plan: CoachSavedPlan, availableSupport: Set<String>) {
        do {
            var run = try ConfigurableSession(plan: plan, availableSupport: availableSupport)
            run.start(at: now)
            stopCapture(); clearInput(); configured = run
            configuredInput = .manual; source = .manual; voiceFeedbackEnabled = false
            coachingPolicy = CoachingPolicy(history: history)
            reportedDiscomfort = false; presented = true; error = nil; publish()
        } catch { self.error = "This plan needs valid exercises and its required support selected in Coach before it can start." }
    }
    @discardableResult func selectConfiguredInput(_ input: ConfiguredInput) -> Bool {
        guard configured?.resetSet(source: input.source, at: now) == true else { return false }
        stopCapture(); clearInput()
        configuredInput = input; source = input.source
        publish(); return true
    }
    func beginConfiguredSet() {
        guard appActive || configuredInput == .manual,
              let run = configured, run.phase == .active, !run.hasStarted else { return }
        configured?.beginSet(at: now)
        startConfiguredCapture(); publish()
    }
    private func startConfiguredCapture() {
        guard appActive, let run = configured, run.source == .camera, run.hasStarted, run.phase == .active else { return }
        hasInput = true; source = .camera; usingSecondaryCamera = configuredInput == .secondaryCamera
        if usingSecondaryCamera { startSecondaryCamera() }
        else { vision.camera(token: run.generation) }
    }
    func setConfiguredReps(_ reps: Int?) { configured?.setReps(reps); publish() }
    @discardableResult func skipConfiguredSet() -> Bool {
        guard configured?.skipSet(at: now) == true else { return false }
        stopCapture(); frame = nil; image = nil; preferredSide = nil
        cancelCoaching(); publish(); return true
    }
    @discardableResult func useOneRepForRemainingConfiguredSets() -> Bool {
        guard configured?.reduceRemainingRepTargetsToOne() == true else { return false }
        cancelCoaching(); publish(); return true
    }
    func stopConfiguredForDiscomfort() {
        guard let run = configured, !run.stoppedForDiscomfort else { return }
        configured?.stopForDiscomfort(at: now)
        stopCapture(); frame = nil; image = nil; cancelCoaching()
        coachingTick(); publish()
    }
    func switchToManualReps() {
        guard configured == nil, session.phase == .active || session.phase == .paused else { return }
        session.restartSet(source: .manual, at: now)
        stopCapture(); clearInput()
        source = .manual
        publish()
    }
    func setManualReps(_ reps: Int?) {
        guard configured == nil else { return }
        session.setManualReps(reps)
        publish()
    }
    func camera() {
        guard configured == nil else { return }
        defer { publish() }
        stopCapture(); session.restartSet(source: .camera, at: now); clearInput()
        source = .camera; hasInput = true; vision.camera(token: session.generation)
    }
    func secondaryCamera() {
        guard configured == nil, session.phase == .active || session.phase == .paused else { return }
        defer { publish() }
        stopCapture()
        session.restartSet(source: .camera, at: now); clearInput()
        usingSecondaryCamera = true; source = .camera; hasInput = true
        startSecondaryCamera()
    }
    private func startSecondaryCamera() {
        guard appActive else { pause(); return }
        do {
            let client = try secondaryCameraClient()
            frontPreviewState = .idle
            vision.frontPreview(token: feedbackContext.generation)
            secondaryVision.start(client: client, generation: feedbackContext.generation)
        }
        catch {
            visionState = .failed("Pair your side camera in Camera settings before starting capture.")
            pause()
        }
    }
    func video(_ url: URL) {
        guard configured == nil else { return }
        defer { publish() }
        stopCapture(); session.restartSet(source: .video, at: now); clearInput()
        source = .video; hasInput = true; vision.video(url: url, token: session.generation)
    }
    private func receive(_ frame: PoseFrame, image: UIImage, generation: UUID) {
        guard acceptsTracking, generation == feedbackContext.generation, let exercise = trackingExercise else { return }
        self.frame = frame; self.image = image
        let sample = PoseGeometry.measure(frame, exercise: exercise, preferredSide: preferredSide)
        preferredSide = sample?.side
        if configured != nil {
            let previousReps = configured?.actualReps, previousCue = configured?.cue
            configured?.consume(sample ?? .init(time: frame.time, angle: .nan, confidence: 0), generation: generation)
            if previousReps != configured?.actualReps || previousCue != configured?.cue { coachingTick(); publish() }
            return
        }
        let previousReps = session.counter.reps, previousCue = session.cue
        session.consume(sample ?? .init(time: frame.time, angle: .nan, confidence: 0), generation: generation)
        if previousReps != session.counter.reps || previousCue != session.cue {
            coachingTick()
            publish()
        }
    }
    func pause() {
        if configured != nil {
            configured?.pause(at: now); vision.pause(); secondaryVision.stop(); frontPreviewState = .idle
            frame = nil; image = nil; preferredSide = nil; cancelCoaching(); publish(); return
        }
        session.pause(at: now); vision.pause(); secondaryVision.stop(); frontPreviewState = .idle; frame = nil; image = nil
        cancelCoaching()
        publish()
    }
    func resume() {
        guard appActive || !requiresForegroundCapture else { return }
        if configured != nil {
            guard configured?.phase == .paused else { return }
            configured?.resume(at: now); startConfiguredCapture(); publish(); return
        }
        guard session.phase == .paused else { return }
        session.resume(at: now)
        if usingSecondaryCamera { startSecondaryCamera() }
        else if hasInput { vision.resume(token: session.generation, source: source) }
        publish()
    }
    func endSet() {
        if let run = configured {
            let quantity = run.current.unit == .reps ? Double(run.actualReps ?? 0) : run.elapsed(at: now)
            guard configured?.endSet(at: now, reason: quantity >= Double(run.current.target) ? .target : .voluntary) == true else { return }
            stopCapture(); frame = nil; image = nil; preferredSide = nil
            cancelCoaching(); publish(); return
        }
        guard session.phase == .active || session.phase == .paused, let reps = session.actualReps else { return }
        let time = now
        session.endSet(at: time, reason: reps >= session.exercise.target ? .target : .voluntary)
        stopCapture(); frame = nil; image = nil; restStartedAt = time
        restGeneration = session.generation
        cancelCoaching()
        publish()
    }
    func feedback(reserve: Int?, reason: StopReason) {
        if configured != nil { configured?.feedback(reserve: reserve, reason: reason); coachingTick(); publish(); return }
        if session.phase == .rest, reason == .discomfort { reportedDiscomfort = true }
        session.feedback(reserve: reserve, reason: reportedDiscomfort ? .discomfort : reason)
        coachingTick()
    }
    func next() {
        if configured != nil {
            guard configured?.phase == .rest, configured?.stoppedForDiscomfort == false else { return }
            configured?.nextSet(at: now)
            stopCapture(); clearInput()
            configuredInput = .manual; source = .manual
            if configured?.phase == .finished { save(); announceCompletion() }
            publish(); return
        }
        guard !reportedDiscomfort, session.phase == .rest else { publish(); return }
        session.nextSet(at: now); clearInput()
        if session.phase == .finished { save(); announceCompletion() }
        publish()
    }
    func finish() {
        guard sessionPhase != .finished else { return }
        if configured != nil {
            configured?.finish(at: now); stopCapture(); clearInput()
            configuredInput = .manual; source = .manual; save(); announceCompletion(); publish(); return
        }
        session.finish(at: now); stopCapture(); frame = nil; image = nil; cancelCoaching(); save(); announceCompletion(); publish()
    }
    private func announceCompletion() {
        guard previewMode, voiceFeedbackEnabled, appActive, remoteVoice?.preference == .arnold,
              !reportedDiscomfort, configured?.stoppedForDiscomfort != true, sessionPhase == .finished else { return }
        let record = configured?.record ?? session.record
        guard record.sets.contains(where: { $0.reps > 0 && $0.source != .video }) ||
                record.loggedSets.contains(where: { ($0.reps > 0 || $0.seconds > 0) && $0.source != .video }) else { return }
        let context = feedbackContext, time = now
        activeCoachingEvent = CoachingEvent(sessionID: context.sessionID, generation: context.generation,
            decision: .init(text: "We'll be back.", priority: .rest, reason: .workoutCompleted, facts: [], elapsed: nil),
            issuedAt: time, expiresAt: time + 6)
        coachingTick(at: time)
    }
    func save() {
        if let configured {
            guard configured.phase == .finished, !configured.completed.isEmpty || !configured.skippedSets.isEmpty else { return }
            persist(configured.record); return
        }
        persist(session.record)
    }
    func persist(_ record: SessionRecord, completedAt: Date = Date()) {
        var before = history
        do {
            if !historyAvailable { before = try historyStore.load() }
            history = try historyStore.save(record).reversed(); historyAvailable = true; error = nil
        } catch { self.error = "Couldn’t save this session. Try again."; return }
        do {
            try rewards.award(record: record, before: before, history: history, completedAt: completedAt)
        } catch { self.error = "Workout saved. Training rewards couldn’t be updated." }
        refreshRewards(at: completedAt)
    }
    func refreshRewards(at date: Date = Date()) {
        guard historyAvailable else { return }
        let week = rewardDefaults.data(forKey: "coach.approvedWeek").flatMap { try? CoachSavedWeek.decode($0) }
        do {
            try rewards.advance(history: history, at: date,
                                plannedRestDays: week?.plannedRestDays(calendar: rewards.ledger.calendar, at: date) ?? [])
        } catch {
            if self.error == nil { self.error = "Training rewards couldn’t be updated. Your saved workouts are unchanged." }
        }
    }
    func exportHistory() throws -> URL {
        var exportDirectory = historyStore.url.appendingPathExtension("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try exportDirectory.setResourceValues(resourceValues)
        let destination = exportDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("spottr-history.json")
        try historyStore.export(to: destination)
        return destination
    }
    func clearHistory() throws {
        guard sessionPhase == .idle || sessionPhase == .finished else { throw DataControlError.workoutInProgress }
        try historyStore.clear()
        history = []
        historyAvailable = true
        error = nil
        let exportDirectory = historyStore.url.appendingPathExtension("exports")
        if FileManager.default.fileExists(atPath: exportDirectory.path) {
            try FileManager.default.removeItem(at: exportDirectory)
        }
        try rewards.reset(at: Date())
    }
    enum DataControlError: LocalizedError {
        case workoutInProgress
        var errorDescription: String? { "Finish your current workout before deleting training history." }
    }
    private func stopCapture() {
        frontPreviewState = .idle
        vision.stop(); secondaryVision.stop()
    }
    private func clearInput() {
        frame = nil; image = nil; preferredSide = nil; hasInput = false; visionState = .idle; source = .camera
        usingSecondaryCamera = false; frontPreviewState = .idle
        cancelCoaching()
    }
}
