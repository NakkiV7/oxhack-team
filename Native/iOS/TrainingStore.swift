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
        case manual, phoneCamera
        var source: InputSource { self == .manual ? .manual : .camera }
        var title: String {
            switch self {
            case .manual: return "Manual reps"
            case .phoneCamera: return "iPhone camera"
            }
        }
    }
    var session = TrainingSession()
    @ObservationIgnored private var configuredStorage: ConfigurableSession?
    private var configuredRevision = 0
    private(set) var configured: ConfigurableSession? {
        get { _ = configuredRevision; return configuredStorage }
        set { configuredStorage = newValue; configuredRevision += 1 }
    }
    var configuredDisplayedSeconds: Int { Int(max(0, configured?.measuredSeconds(at: now) ?? 0)) }
    private(set) var configuredInput: ConfiguredInput = .manual
    var sessionPhase: SessionPhase { configured?.phase ?? session.phase }
    var presented = false { didSet { if oldValue && !presented { cancelCoaching() } } }
    var history: [SessionRecord] = []
    private(set) var historyAvailable = true
    var error: String?
    var visionState: VisionState = .idle
    private(set) var frontPreviewState: VisionState = .idle
    private(set) var restCameraEnabled = false
    var frame: PoseFrame?
    var image: UIImage?
    var source: InputSource = .camera
    var hasInput = false
    @ObservationIgnored weak var launchCoordinator: WorkoutLaunchCoordinator?
    var programme: ProgrammeStore?
    var quests: QuestStore?
    var rewardReminders: RewardReminderStore?
    private(set) var sessionTrainingContext: SessionTrainingContext?
    var selectedExercise: Exercise = .squat { didSet { if oldValue != selectedExercise { launchCoordinator?.cancel() } } }
    let spokenReps: any SpokenRepListening
    let vision: VisionWorker
    let companion = CompanionLink()
    var watchReachable = false
    private(set) var reportedDiscomfort = false
    private let monotonicClock: () -> Double
    private var accountActive = true
    func setAccountActive(_ active: Bool) {
        if !active, sessionPhase == .active { pause() }
        accountActive = active
        programme?.setActive(active)
        quests?.setActive(active)
        rewardReminders?.setActive(active)
        setAppActive(active)
    }
    let accountScope: AccountDataScope?
    var dataFolder: URL { historyStore.url.deletingLastPathComponent() }
    private let historyStore: HistoryStore
    private let watchInbox: WatchTelemetryInbox
    private var timelineSessionID: UUID?
    private var phaseTimeline: [WorkoutPhaseMark] = []
    private var finishedWallTime: Date?
    private(set) var archiveDataWarning: String?
    let rewards: NativeRewardsStore
    private let rewardDefaults: UserDefaults
    private let persistsVoicePreferences: Bool
    private var preferredSide: Int?
    private var coachingPolicy = CoachingPolicy()
    private var activeCoachingEvent: CoachingEvent?
    private var configuredDiscomfortCueSessionID: UUID?
    private var previewRepContext: VoiceCueContext?
    private var previewObservedReps = 0
    private var previewRepTime: Double?
    private(set) var voiceFeedbackEnabled = false
    /// Spoken rep counts and lines from bundled Arnold or Goggins clips, under the same Voice feedback switch.
    var repVoice: RepVoicePlayer { didSet { coachingVoice.repVoice = repVoice } }
    private struct SpokenSet: Hashable { let sessionID: UUID; let index: Int }
    private var startedRepSets: Set<SpokenSet> = []
    private var pendingRepClosing: (set: SpokenSet, issuedAt: Double)?
    private var repVoiceState: (set: SpokenSet, phase: SessionPhase, reps: Int)?
    private var appActive = true
    let remoteVoice: RemoteVoicePlayback?
    let previewMode: Bool
    private let coachingVoice: CoachingVoiceBridge
    private var restGeneration: UUID?
    private var restStartedAt: Double?
    private var trackingLoss: (sessionID: UUID, generation: UUID, since: Double)?
    private var trackingContext: VoiceCueContext?
    private var lastTrackingPromptAt: Double?
    private var handledTrackingCompletion: UUID?

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
        pendingRepClosing = nil
        activeCoachingEvent = nil
        trackingLoss = nil; trackingContext = nil; lastTrackingPromptAt = nil; handledTrackingCompletion = nil
        coachingVoice.cancel()
        repVoice.cancel()
    }

    private func transitionCoaching(continuingCamera: Bool = false) {
        activeCoachingEvent = nil
        trackingLoss = nil; trackingContext = nil; lastTrackingPromptAt = nil; handledTrackingCompletion = nil
        if continuingCamera { coachingVoice.continueTracking(to: feedbackContext) }
        else { coachingVoice.transition(to: feedbackContext) }
    }

    func setVoiceFeedback(_ enabled: Bool) {
        guard voiceFeedbackEnabled != enabled else { return }
        coachingVoice.update(context: feedbackContext, event: coachingEvent, enabled: false, now: now)
        activeCoachingEvent = nil
        if !enabled { repVoice.cancel() }
        voiceFeedbackEnabled = enabled
        if persistsVoicePreferences { rewardDefaults.set(enabled, forKey: "trainer.audioEnabled") }
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        if !active {
            spokenReps.stop()
            setRestCameraEnabled(false)
            if requiresForegroundCapture, sessionPhase == .active, configured?.hasStarted != false { pause() }
            else { cancelCoaching() }
        }
    }

    func setRestCameraEnabled(_ enabled: Bool) {
        guard enabled != restCameraEnabled else { return }
        if enabled {
            guard appActive, sessionPhase == .rest else { return }
            restCameraEnabled = true
            frontPreviewState = .idle
            vision.frontPreview(token: feedbackContext.generation)
        } else {
            restCameraEnabled = false
            frontPreviewState = .idle
            vision.stop()
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
        guard !spokenReps.isListening else { return }
        guard appActive else { cancelCoaching(); return }
        let time = time ?? now
        let context = feedbackContext
        remoteVoice?.exercise = trackingExercise
        defer { coachingVoice.update(context: context, event: coachingEvent, enabled: voiceFeedbackEnabled, now: time) }
        guard time.isFinite else { return }
        let mixedOrManual = configured.map { [.mixed, .selfReport, .activeTimer].contains($0.quantityOrigin(at: time)) } ?? false
        let reps = mixedOrManual ? 0 : (configured?.actualReps ?? session.actualReps ?? 0)
        let milestone = consumePreviewRep(context: context, reps: reps, time: time)
        repVoiceTick(context: context, reps: reps, clean: (configured?.cue ?? session.cue) == .controlled, at: time)
        if context.phase == .finished {
            if coachingEvent?.expiresAt.map({ time >= $0 }) == true { activeCoachingEvent = nil }
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
        let trackingFinished = trackingPromptFinished(context: context, cue: cue, at: time)
        let policyCue = spokenTrackingCue(context: context, cue: cue, at: time)
        let restElapsed = configured == nil ? actualRestElapsed(at: time) : configured?.restElapsed(at: time)
        let stopReason: StopReason?
        if let run = configured {
            stopReason = run.stoppedForDiscomfort ? .discomfort : (run.phase == .rest ? run.completed.last?.reason : nil)
        } else { stopReason = session.phase == .rest ? session.sets.last?.reason : nil }
        // An undelivered form intent may outlive its start window while another sentence finishes.
        // Re-issue only from the current observed warning; cleared warnings and muted actions cannot return.
        if let event = coachingEvent, event.decision.priority == .form,
           event.expiresAt.map({ time >= $0 }) == true, voiceFeedbackEnabled,
           coachingVoice.lastStartedCueID != event.id, context.phase == .active,
           (event.decision.reason == .tracking && cue == .tracking) ||
            (event.decision.reason == .alignment && cue == .alignment) {
            activeCoachingEvent = CoachingEvent(sessionID: context.sessionID, generation: context.generation,
                decision: event.decision, issuedAt: time, expiresAt: time + 6)
        }
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
            now: time, exercise: exercise, repCount: reps,
            lastRepDuration: configured == nil ? session.counter.lastRepDuration : configured?.counter?.lastRepDuration, cue: policyCue,
            heartRate: recentHeartRate(at: wallTime), wallTime: wallTime,
            restElapsed: restElapsed,
            target: configured?.current.target ?? session.exercise.target,
            stopReason: stopReason, source: configured?.source ?? source,
            encouragementEnabled: !previewMode && voiceFeedbackEnabled && remoteVoice != nil && !repVoiceEnabled,
            trackingPromptFinished: trackingFinished, measuredSeconds: configured?.quantityOrigin(at: time) == .cameraObserved ? configured?.measuredSeconds(at: time) : nil
        ))
        // Rep counting replaces the preview's "steady rhythm" encouragement while it is on, as it does outside preview.
        let previewEncouragement = previewMode && milestone && voiceFeedbackEnabled && remoteVoice?.preference == .arnold && !repVoiceEnabled &&
            context.phase == .active && acceptsTracking && (configured?.source ?? source) == .camera &&
            cue == .controlled && stopReason == nil && !reportedDiscomfort &&
            coachingEvent?.decision.priority != .stop && coachingEvent?.decision.priority != .form &&
            coachingEvent?.decision.reason != .slowerRep
        if let decision, !previewEncouragement || decision.reason != .targetReached {
            if decision.reason == .tracking { lastTrackingPromptAt = time }
            activeCoachingEvent = CoachingEvent(sessionID: context.sessionID, generation: context.generation,
                                               decision: decision, issuedAt: time,
                                               expiresAt: decision.priority == .stop ? nil : time + 6)
            return
        }
        guard previewEncouragement else { return }
        activeCoachingEvent = CoachingEvent(sessionID: context.sessionID, generation: context.generation,
            decision: .init(text: "Keep a steady rhythm.", priority: .pacing, reason: .steadyRhythm,
                            facts: ["\(reps) camera reps recorded in this set."], elapsed: nil),
            issuedAt: time, expiresAt: time + 6)
    }

    /// Visual feedback stays immediate. Brief missing joints do not need a spoken interruption.
    private func spokenTrackingCue(context: VoiceCueContext, cue: Cue, at time: Double) -> Cue {
        if trackingContext?.sessionID != context.sessionID || trackingContext?.generation != context.generation {
            trackingLoss = nil; lastTrackingPromptAt = nil; handledTrackingCompletion = nil
        }
        trackingContext = context
        guard context.phase == .active, cue == .tracking else { trackingLoss = nil; return cue }
        if trackingLoss == nil { trackingLoss = (context.sessionID, context.generation, time) }
        guard let loss = trackingLoss, time >= loss.since, time - loss.since >= 0.75,
              !coachingVoice.isTrackingPromptPlaying,
              time - (lastTrackingPromptAt ?? -.infinity) >= 2 else { return .ready }
        return cue
    }

    private func trackingPromptFinished(context: VoiceCueContext, cue: Cue, at time: Double) -> Bool {
        guard let completed = coachingVoice.completedTrackingPrompt,
              completed.id != handledTrackingCompletion else { return false }
        // Keep the completion pending while tracking is missing but the minimum repeat interval has not passed.
        guard cue != .tracking || time - (lastTrackingPromptAt ?? -.infinity) >= 2 else { return false }
        handledTrackingCompletion = completed.id
        return cue == .tracking && voiceFeedbackEnabled && context.phase == .active &&
            completed.sessionID == context.sessionID && completed.generation == context.generation
    }

    /// Rep counting replaces the occasional "steady rhythm" encouragement while it is on, so lines never double up.
    private var repVoiceEnabled: Bool {
        trackingExercise?.isTimed != true && voiceFeedbackEnabled && repVoice.coach != nil && (configured?.source ?? source) == .camera && !reportedDiscomfort
    }

    /// Speaks the count on each camera-counted rep (a line every third clean rep), a start line when a camera set begins
    /// and a closing line when it ends. Ordinary coaching waits for the current line; stop acts immediately.
    private func repVoiceTick(context: VoiceCueContext, reps: Int, clean: Bool, at time: Double) {
        let previous = repVoiceState
        let index = configured?.index ?? max(0, session.sets.count - ((context.phase == .rest || context.phase == .finished) ? 1 : 0))
        let set = SpokenSet(sessionID: context.sessionID, index: index)
        let firstStart = context.phase == .active && acceptsTracking && startedRepSets.insert(set).inserted
        repVoiceState = (set, context.phase, reps)
        if previous?.set.sessionID == context.sessionID, previous?.phase == .active,
           (context.phase == .rest || context.phase == .finished), (previous?.reps ?? 0) > 0 {
            pendingRepClosing = (set, time)
        }
        guard repVoiceEnabled, appActive else { pendingRepClosing = nil; return }
        if coachingVoice.isSpeaking { return }
        let sameSet = previous?.set == set
        if context.phase == .active, acceptsTracking {
            if firstStart {
                if reps == 0 { repVoice.start() } else if reps == 1 { repVoice.rep(1, clean: clean) }
            } else if sameSet, let before = previous?.reps, reps > before, reps > 0 {
                repVoice.rep(reps, clean: clean)
            }
        } else if let closing = pendingRepClosing {
            pendingRepClosing = nil
            if closing.set == set, time >= closing.issuedAt, time - closing.issuedAt <= 8,
               context.phase == .rest, coachingEvent == nil {
                repVoice.closing()
            }
        }
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

    init(historyURL: URL? = nil,
         voicePlayback: VoicePlayback? = nil, vision: VisionWorker? = nil, rewardsStore: NativeRewardsStore? = nil,
         defaults: UserDefaults = .standard, previewMode: Bool = false, previewPlayback: VoicePlayback? = nil,
         spokenReps: (any SpokenRepListening)? = nil, accountScope: AccountDataScope? = nil, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        monotonicClock = clock
        self.accountScope = accountScope
        self.spokenReps = spokenReps ?? SpokenRepInput()
        repVoice = RepVoicePlayer(defaults: defaults)
        rewardDefaults = defaults
        persistsVoicePreferences = !previewMode && (accountScope != nil || (historyURL == nil && voicePlayback == nil))
        voiceFeedbackEnabled = persistsVoicePreferences && defaults.bool(forKey: "trainer.audioEnabled")
        self.previewMode = previewMode
        self.vision = vision ?? VisionWorker()
        let playback = voicePlayback ?? RemoteVoicePlayback(offlineOnly: !previewMode, defaults: defaults, previewPlayback: previewMode ? (previewPlayback ?? DemoVoicePlayback()) : nil)
        remoteVoice = playback as? RemoteVoicePlayback

        coachingVoice = CoachingVoiceBridge(playback: playback)
        let root = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let folder = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        historyStore = HistoryStore(url: historyURL ?? folder.appendingPathComponent("history.json"))
        watchInbox = WatchTelemetryInbox(url: historyStore.url.deletingLastPathComponent().appendingPathComponent("watch-inbox.json"))
        rewards = rewardsStore ?? NativeRewardsStore(url: historyStore.url.deletingLastPathComponent().appendingPathComponent("rewards.json"))
        coachingVoice.repVoice = repVoice
        coachingVoice.onCancellation = { [weak self] in self?.cancelCoaching() }
        if remoteVoice?.gentleOnly == true { repVoice.choose(nil) }
        if !previewMode, defaults.string(forKey: RepVoicePlayer.defaultsKey) == nil,
           remoteVoice?.preference == .maya || remoteVoice?.preference == .leo { repVoice.coach = nil }
        do { history = try historyStore.load().reversed() }
        catch { historyAvailable = false; self.error = "Couldn’t read your saved sessions." }
        self.vision.onFrame = { [weak self] frame, image, generation in
            Task { @MainActor in
                guard let self else { return }
                self.receive(frame, image: image, generation: generation)
            }
        }
        self.vision.onState = { [weak self] state, generation in
            Task { @MainActor in
                guard let self, self.acceptsTracking, self.feedbackContext.generation == generation else { return }
                self.visionState = state
                if case .finished = state { self.pause() }
                if case .failed = state { self.pause() }
                if case .denied = state { self.pause() }
                if case .unavailable = state { self.pause() }
            }
        }
        self.vision.onPreviewState = { [weak self] state, generation in
            Task { @MainActor in
                guard let self, self.feedbackContext.generation == generation,
                      self.restCameraEnabled && self.sessionPhase == .rest else { return }
                self.frontPreviewState = state
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
        companion.onDurableTelemetryBatch = { [weak self] id, samples in
            Task { @MainActor in self?.receiveDurableTelemetry(id: id, samples: samples) }
        }
        companion.onTelemetryBatch = { [weak self] samples in
            Task { @MainActor in self?.receiveDurableTelemetry(id: UUID(), samples: samples) }
        }
        companion.onReachability = { [weak self] reachable in
            Task { @MainActor in self?.watchReachable = reachable; self?.publish() }
        }
        companion.onRequest = { [weak self] in Task { @MainActor in self?.publish() } }
    }

    func preservePendingWorkout() throws {
        guard let accountScope, sessionPhase != .idle, sessionPhase != .finished else { return }
        let pending = PendingPhoneWorkout(accountID: accountScope.accountID, profileID: accountScope.profileID,
            record: configured?.record ?? session.record, phase: sessionPhase,
            exerciseID: configured?.current.exerciseID ?? session.exercise.rawValue,
            actualReps: configured != nil ? configured?.actualReps : session.actualReps,
            measuredSeconds: configured?.current.unit == .seconds ? configured?.measuredSeconds(at: now) : nil,
            quantityOrigin: configured?.quantityOrigin(at: now))
        let url = accountScope.file("pending-phone-workout.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try JSONDecoder().decode(PendingPhoneWorkout.self, from: Data(contentsOf: url))
            if previous.record.id != pending.record.id {
                let archive = accountScope.file("pending-" + previous.record.id.uuidString + ".json")
                try ProtectedLocalStorage.write(Data(contentsOf: url), to: archive)
            }
        }
        try ProtectedLocalStorage.write(JSONEncoder().encode(pending), to: url)
    }

    func publish() {
        guard accountActive else { return }
        markWorkoutPhase()
        if let configured { companion.publish(CompanionSnapshot(session: configured, at: now)) }
        else { companion.publish(CompanionSnapshot(session: session)) }
    }
    private func command(_ command: CompanionCommand) {
        guard accountActive else { return }
        guard sessionPhase != .idle && sessionPhase != .finished else { publish(); return }
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

    var now: Double { monotonicClock() }
    var protectedProgrammeDayIDs: Set<String> {
        Set(history.compactMap(\.plannedWorkoutID)).union(sessionPhase != .idle && sessionPhase != .finished ? [configured?.plannedWorkoutID].compactMap { $0 } : [])
    }
    func launchPlanned(dayID: String, origin: WorkoutLaunchOrigin = .today, at date: Date? = nil) {
        guard let day = programme?.day(at: date), day.id == dayID, let plan = day.plan,
              !history.contains(where: { $0.plannedWorkoutID == dayID }), let launchCoordinator else {
            error = "Choose today's unstarted workout or practise a movement from the library."; return
        }
        launchCoordinator.request(plan: plan, origin: origin, plannedWorkoutID: dayID)
    }
    func start() {
        guard let launchCoordinator else { error = "Sign in and complete your training profile before starting."; return }
        guard let plan = try? CoachSavedPlan.catalogue(exerciseID: selectedExercise.rawValue, sets: 3, target: selectedExercise.target, restSeconds: 60) else { return }
        launchCoordinator.request(plan: plan, origin: .today)
    }
    func startPlan(_ plan: CoachSavedPlan, availableSupport: Set<String>, origin: WorkoutLaunchOrigin = .library) {
        guard let launchCoordinator else { error = "Sign in and complete your training profile before starting."; return }
        launchCoordinator.request(plan: plan, origin: origin)
    }
    func beginAuthorizedSession() {
        guard !selectedExercise.isTimed else { error = "Start timed exercises from the exercise library."; return }
        defer { publish() }
        remoteVoice?.reloadPreferences()
        configured = nil
        configuredInput = .manual
        stopCapture(); session = TrainingSession(firstExercise: selectedExercise)
        coachingPolicy = CoachingPolicy(history: history)
        reportedDiscomfort = false
        session.start(at: now); presented = true; error = nil; clearInput()
    }
    func beginAuthorizedPlan(_ plan: CoachSavedPlan, availableSupport: Set<String>, plannedWorkoutID: String? = nil, trainingContext: SessionTrainingContext? = nil) {
        do {
            var run = try ConfigurableSession(plan: plan, availableSupport: availableSupport, plannedWorkoutID: plannedWorkoutID, trainingContext: trainingContext)
            run.start(at: now)
            sessionTrainingContext = trainingContext
            stopCapture(); clearInput(); configured = run
            configuredInput = .manual; source = .manual; remoteVoice?.reloadPreferences()
            coachingPolicy = CoachingPolicy(history: history)
            reportedDiscomfort = false; presented = true; error = nil; publish()
        } catch { self.error = "This plan needs valid exercises and its required support selected in Coach before it can start." }
    }
    @discardableResult func selectConfiguredInput(_ input: ConfiguredInput) -> Bool {
        guard configured?.switchInput(source: input.source, at: now) == true else { return false }
        stopCapture(); clearInput()
        configuredInput = input; source = input.source
        startConfiguredCapture()
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
        hasInput = true; source = .camera
        vision.camera(token: run.generation)
    }
    func setConfiguredReps(_ reps: Int?) { spokenReps.stop(); configured?.setReps(reps); publish() }
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
    func startSpokenReps() {
        guard sessionPhase == .active, configured?.hasStarted != false,
              (configured?.source ?? source) == .manual else { return }
        cancelCoaching()
        let context = feedbackContext
        let initial = configured.map { $0.actualReps ?? 0 } ?? session.actualReps ?? 0
        spokenReps.start(initialCount: initial) { [weak self] count in
            guard let self, self.spokenReps.isListening, self.feedbackContext == context, self.sessionPhase == .active,
                  (self.configured?.source ?? self.source) == .manual else { return }
            if self.configured != nil { self.configured?.setReps(count) }
            else { self.session.setManualReps(count) }
            self.publish()
        }
    }
    func switchToManualReps() {
        guard source != .video else { error = "Finish this video analysis before starting a real workout set."; return }
        guard configured == nil, session.phase == .active || session.phase == .paused else { return }
        session.switchInput(source: .manual, at: now)
        stopCapture(); clearInput()
        source = .manual
        publish()
    }
    func setManualReps(_ reps: Int?) {
        guard configured == nil else { return }
        spokenReps.stop()
        session.setManualReps(reps)
        publish()
    }
    func camera() {
        guard source != .video else { error = "Finish this video analysis before starting a real workout set."; return }
        guard configured == nil else { return }
        defer { publish() }
        stopCapture(); session.switchInput(source: .camera, at: now); clearInput()
        source = .camera; hasInput = true
        if session.phase == .active { vision.camera(token: session.generation) }
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
        let heldSide = (configured?.counter ?? session.counter).continuitySide(at: frame.time)
        let sample = PoseGeometry.measure(frame, exercise: exercise, preferredSide: heldSide ?? preferredSide,
                                          allowSideFallback: heldSide == nil)
        preferredSide = sample?.side ?? preferredSide
        if configured != nil {
            let previousReps = configured?.actualReps, previousCue = configured?.cue
            let previousRecovery = configured?.cameraRecoveryState
            let previousSeconds = configuredDisplayedSeconds
            configuredStorage?.consume(sample ?? .init(time: frame.time, angle: .nan, confidence: 0), generation: generation)
            if previousReps != configured?.actualReps || previousCue != configured?.cue || previousSeconds != configuredDisplayedSeconds || previousRecovery != configured?.cameraRecoveryState {
                configuredRevision += 1; coachingTick(); publish()
            }
            return
        }
        let previousRecovery = session.cameraRecoveryState
        let previousReps = session.counter.reps, previousCue = session.cue
        session.consume(sample ?? .init(time: frame.time, angle: .nan, confidence: 0), generation: generation)
        if previousReps != session.counter.reps || previousCue != session.cue || previousRecovery != session.cameraRecoveryState {
            coachingTick()
            publish()
        }
    }
    func pause() {
        spokenReps.stop()
        if configured != nil {
            configured?.pause(at: now); vision.pause(); frontPreviewState = .idle
            frame = nil; image = nil; preferredSide = nil; cancelCoaching(); publish(); return
        }
        session.pause(at: now); vision.pause(); frontPreviewState = .idle; frame = nil; image = nil
        cancelCoaching()
        publish()
    }
    func resume() {
        guard appActive || !requiresForegroundCapture else { return }
        if configured != nil {
            guard configured?.phase == .paused || configured?.cameraRecoveryState == .needsResume else { return }
            let continuingCamera = configured?.phase == .active && configured?.cameraRecoveryState == .needsResume
            configured?.resume(at: now)
            if continuingCamera { transitionCoaching(continuingCamera: true) }
            frame = nil; image = nil; preferredSide = nil; startConfiguredCapture(); publish(); return
        }
        guard session.phase == .paused || session.cameraRecoveryState == .needsResume else { return }
        let continuingCamera = session.phase == .active && session.cameraRecoveryState == .needsResume
        session.resume(at: now)
        if continuingCamera { transitionCoaching(continuingCamera: true) }
        frame = nil; image = nil; preferredSide = nil
        if hasInput { vision.resume(token: session.generation, source: source) }
        publish()
    }
    func endSet() {
        if let run = configured {
            let quantity = run.current.unit == .reps ? Double(run.actualReps ?? 0) : run.measuredSeconds(at: now)
            guard configured?.endSet(at: now, reason: quantity >= Double(run.current.target) ? .target : .voluntary) == true else { return }
            stopCapture(); frame = nil; image = nil; preferredSide = nil
            transitionCoaching(); coachingTick(); publish(); return
        }
        guard session.phase == .active || session.phase == .paused, let reps = session.actualReps else { return }
        let time = now
        session.endSet(at: time, reason: reps >= session.exercise.target ? .target : .voluntary)
        stopCapture(); frame = nil; image = nil; restStartedAt = time
        restGeneration = session.generation
        transitionCoaching()
        coachingTick()
        publish()
    }
    func feedback(reserve: Int?, reason: StopReason) {
        if configured != nil { configured?.feedback(reserve: reserve, reason: reason); coachingTick(); publish(); return }
        if session.phase == .rest, reason == .discomfort { reportedDiscomfort = true }
        session.feedback(reserve: reserve, reason: reportedDiscomfort ? .discomfort : reason)
        coachingTick()
    }
    func setEffort(_ effort: SetEffort?) {
        guard let set = configured?.completed.last, configured?.phase == .rest else { return }
        configured?.feedback(reserve: set.reserve, reason: set.reason, effort: effort)
        publish()
    }
    func prepareAfterRest() {
        guard accountActive, appActive, let run = configured, run.phase == .rest,
              !run.stoppedForDiscomfort, !run.currentWasSkipped,
              let elapsed = run.restElapsed(at: now), elapsed >= Double(run.current.restSeconds),
              run.index + 1 < run.steps.count else { return }
        next()
        SpottrHaptics.success()
    }
    func next() {
        if configured != nil {
            guard configured?.phase == .rest, configured?.stoppedForDiscomfort == false else { return }
            configured?.nextSet(at: now)
            stopCapture(); clearInput(cancelAudio: configured?.phase != .finished)
            configuredInput = .manual; source = .manual
            if configured?.phase == .finished { transitionCoaching(); save(); announceCompletion() }
            publish(); return
        }
        guard !reportedDiscomfort, session.phase == .rest else { publish(); return }
        stopCapture(); session.nextSet(at: now); clearInput(cancelAudio: session.phase != .finished)
        if session.phase == .finished { transitionCoaching(); save(); announceCompletion() }
        publish()
    }
    func finish() {
        guard sessionPhase != .finished else { return }
        if configured != nil {
            configured?.finish(at: now); stopCapture(); clearInput(cancelAudio: false); transitionCoaching()
            configuredInput = .manual; source = .manual; save(); announceCompletion(); publish(); return
        }
        session.finish(at: now); stopCapture(); frame = nil; image = nil; transitionCoaching(); save(); announceCompletion(); publish()
    }
    private func announceCompletion() {
        guard voiceFeedbackEnabled, appActive, remoteVoice != nil,
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
        markWorkoutPhase()
        if let configured {
            guard configured.phase == .finished, !configured.completed.isEmpty || !configured.skippedSets.isEmpty else { return }
            persist(configured.record); return
        }
        persist(session.record)
    }
    func persist(_ record: SessionRecord, completedAt: Date = Date()) {
        if let scope = accountScope, let context = record.trainingContext,
           context.owner != WorkoutOwner(accountID: scope.accountID, profileID: scope.profileID) {
            error = "This workout belongs to another training profile. It has not been imported."; return
        }
        var before = history
        let saved: SessionRecord
        do {
            if !historyAvailable { before = try historyStore.load() }
            saved = try recordWithWatchArchive(record)
            history = try historyStore.save(saved).reversed(); historyAvailable = true; error = nil
            do { try watchInbox.remove(sessionID: saved.id); archiveDataWarning = nil }
            catch { archiveDataWarning = "Workout saved. Some Watch readings are waiting to finish syncing." }
        } catch { self.error = "Couldn’t save this session. Try again."; return }
        do {
            try rewards.award(record: saved, before: before, history: history, completedAt: completedAt)
        } catch { self.error = "Workout saved. Training rewards couldn’t be updated." }
        refreshRewards(at: completedAt)
    }
    func refreshRewards(at date: Date = Date()) {
        guard historyAvailable else { return }
        let week = rewardDefaults.data(forKey: "coach.approvedWeek").flatMap { try? CoachSavedWeek.decode($0) }
        do {
            try rewards.advance(history: history, at: date,
                                plannedRestDays: programme?.current?.days.filter { $0.kind == .rest || $0.kind == .recovery }.map(\.date) ?? week?.plannedRestDays(calendar: rewards.ledger.calendar, at: date) ?? [])
            try quests?.reconcile(history: history)
        } catch {
            if self.error == nil { self.error = "Training rewards couldn’t be updated. Your saved workouts are unchanged." }
        }
    }
    private func markWorkoutPhase() {
        let id = configured?.id ?? session.id
        if timelineSessionID != id {
            timelineSessionID = id; phaseTimeline = []; finishedWallTime = nil
        }
        guard phaseTimeline.last?.phase != sessionPhase else { return }
        let date = Date()
        phaseTimeline.append(WorkoutPhaseMark(date: date, phase: sessionPhase))
        if sessionPhase == .finished, finishedWallTime == nil { finishedWallTime = date }
    }
    private func recordWithWatchArchive(_ record: SessionRecord) throws -> SessionRecord {
        let owned = record.id == timelineSessionID
        var result = SessionRecord(id: record.id, date: record.date, sets: record.sets, telemetry: record.telemetry,
            loggedSets: record.loggedSets, skippedSets: record.skippedSets,
            endedAt: record.endedAt ?? (owned && sessionPhase == .finished ? finishedWallTime : nil),
            timeline: record.timeline.isEmpty && owned ? phaseTimeline : record.timeline,
            plannedWorkoutID: record.plannedWorkoutID, trainingContext: record.trainingContext ?? (owned ? sessionTrainingContext : nil))
        let pending = try watchInbox.samples(for: record.id)
        for offset in stride(from: 0, to: pending.count, by: 60) {
            result = try WatchTelemetryImporter.merge(Array(pending[offset..<min(offset+60,pending.count)]), into: result, through: Date(), allowsOpenSession: owned && sessionPhase != .finished)
        }
        return result
    }
    func receiveDurableTelemetry(id: UUID, samples: [WatchTelemetry]) {
        guard let sessionID = samples.first?.sessionID, !samples.isEmpty else { companion.acknowledgeTelemetryBatch(id, accepted: false); return }
        guard historyAvailable else { archiveDataWarning = "Watch sync is waiting for saved history to become available."; return }
        let saved = history.first { $0.id == sessionID }
        let current = configured?.record ?? session.record
        let open = saved == nil && current.id == sessionID && [.active,.paused,.rest].contains(sessionPhase)
        guard let record = saved ?? (open ? current : nil) else { companion.acknowledgeTelemetryBatch(id, accepted: false); return }
        if let scope = accountScope, let context = record.trainingContext,
           context.owner != WorkoutOwner(accountID: scope.accountID, profileID: scope.profileID) {
            companion.acknowledgeTelemetryBatch(id, accepted: false); return
        }
        let merged: SessionRecord
        do { merged = try WatchTelemetryImporter.merge(samples, into: record, through: Date(), allowsOpenSession: open) }
        catch { companion.acknowledgeTelemetryBatch(id, accepted: false); return }
        let dates = Set(samples.map(\.sentAt))
        let normalized = merged.telemetry.filter { dates.contains($0.sentAt) }
        guard !normalized.isEmpty else { companion.acknowledgeTelemetryBatch(id, accepted: false); return }
        do {
            try watchInbox.store(id: id, samples: normalized)
            if open {
                if configured != nil { try configured?.receiveArchivedTelemetry(normalized) }
                else { try session.receiveArchivedTelemetry(normalized) }
            } else {
                let enriched = try recordWithWatchArchive(merged)
                history = try historyStore.save(enriched).reversed()
                try watchInbox.remove(sessionID: sessionID)
            }
            archiveDataWarning = nil
            companion.acknowledgeTelemetryBatch(id)
        } catch { archiveDataWarning = "Some Watch readings are waiting to sync. They haven’t changed your recorded reps or sets. Try again when storage is available." }
    }
    func retryWatchArchive() {
        guard historyAvailable else { return }
        for record in history where record.endedAt != nil {
            do {
                guard !(try watchInbox.samples(for: record.id)).isEmpty else { continue }
                let enriched = try recordWithWatchArchive(record)
                history = try historyStore.save(enriched).reversed()
                try watchInbox.remove(sessionID: record.id)
            } catch { archiveDataWarning = "Watch readings are still waiting to sync. Check available storage and try again."; return }
        }
        archiveDataWarning = nil
        companion.request()
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
        try watchInbox.clear()
        try historyStore.clear()
        archiveDataWarning = nil
        history = []
        historyAvailable = true
        error = nil
        let exportDirectory = historyStore.url.appendingPathExtension("exports")
        if FileManager.default.fileExists(atPath: exportDirectory.path) {
            try FileManager.default.removeItem(at: exportDirectory)
        }
        try rewards.reset(at: Date())
        try quests?.reconcile(history: history)
        Task { await rewardReminders?.refresh() }
    }
    enum DataControlError: LocalizedError {
        case workoutInProgress
        var errorDescription: String? { "Finish your current workout before deleting training history." }
    }
    private func stopCapture() {
        spokenReps.stop()
        restCameraEnabled = false
        frontPreviewState = .idle
        vision.stop()
    }
    private func clearInput(cancelAudio: Bool = true) {
        frame = nil; image = nil; preferredSide = nil; hasInput = false; visionState = .idle; source = .camera
        frontPreviewState = .idle
        if cancelAudio { cancelCoaching() }
    }
}
