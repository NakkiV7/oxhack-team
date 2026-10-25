import HealthKit
import CoreMotion

@MainActor
final class WorkoutRecorder: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    enum State: Equatable {
        case idle, requestingAccess, starting, recording, paused, saving, saved
        case unavailable, failed(String)

        var isRecording: Bool { self == .recording || self == .paused }
        var isBusy: Bool { self == .requestingAccess || self == .starting || isRecording || self == .saving }
        var message: String {
            switch self {
            case .idle: return "Record on Watch to see heart rate."
            case .requestingAccess: return "Requesting workout access…"
            case .starting: return "Starting workout…"
            case .recording: return "Workout recording"
            case .paused: return "Workout paused"
            case .saving: return "Saving workout…"
            case .saved: return "Workout saved"
            case .unavailable: return "Health data unavailable on this device."
            case .failed(let message): return message
            }
        }
    }

    var onHeart: ((SensorReading) -> Void)?
    var onMotion: ((SensorReading, SensorReading) -> Void)?
    var onState: ((State) -> Void)?
    private(set) var state = State.idle { didSet { onState?(state) } }
    private let health = HKHealthStore()
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var generation = UUID()
    private var capture = WatchCaptureLifecycle()
    private var lastMotion = Date.distantPast

    func start() {
        guard !state.isBusy else { return }
        #if targetEnvironment(simulator)
        state = .unavailable
        #else
        guard workout == nil, HKHealthStore.isHealthDataAvailable() else { state = .unavailable; return }
        let token = capture.start(); generation = token
        state = .requestingAccess
        health.requestAuthorization(toShare: [.workoutType()], read: [HKQuantityType(.heartRate)]) { [weak self] success, error in
            Task { @MainActor in
                guard let self, self.generation == token, self.state == .requestingAccess else { return }
                guard success, error == nil, self.health.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
                    self.capture.end(); self.state = .failed("Workout access wasn’t granted or couldn’t be requested."); return
                }
                self.begin(token: token)
            }
        }
        #endif
    }
    private func begin(token: UUID) {
        guard capture.beginCollection(for: token) else { return }
        state = .starting
        do {
            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining; config.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: health, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: config)
            session.delegate = self; builder.delegate = self
            self.workout = session; self.builder = builder
            let date = Date(); session.startActivity(with: date)
            builder.beginCollection(withStart: date) { [weak self] success, _ in
                Task { @MainActor in
                    guard let self, self.capture.isCurrent(token), self.builder === builder else { return }
                    guard success else {
                        self.capture.end(); self.motion.stopDeviceMotionUpdates()
                        self.workout = nil; self.builder = nil
                        session.end(); builder.discardWorkout()
                        self.state = .failed("Couldn’t collect workout data.")
                        return
                    }
                    self.state = self.capture.isPaused ? .paused : .recording
                    if !self.capture.isPaused { self.startMotion() }
                }
            }
            if capture.isPaused { session.pause() }
        } catch { capture.end(); state = .failed("Couldn’t start a workout.") }
    }
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        let token = generation
        guard let stream = capture.startMotion(for: token) else { return }
        lastMotion = .distantPast
        motion.deviceMotionUpdateInterval = 0.1
        motionQueue.maxConcurrentOperationCount = 1
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, _ in
            guard let data else { return }
            let acceleration = data.userAcceleration, rotation = data.rotationRate
            let magnitude = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
            let angularSpeed = sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z)
            let sampledAt = Date(timeIntervalSinceNow: data.timestamp - ProcessInfo.processInfo.systemUptime)
            Task { @MainActor in
                guard let self, self.capture.acceptsMotion(for: token, stream: stream, measuredAt: sampledAt),
                      self.workout != nil, Date().timeIntervalSince(self.lastMotion) >= 1 else { return }
                self.lastMotion = Date()
                self.onMotion?(.init(value: magnitude, date: sampledAt), .init(value: angularSpeed, date: sampledAt))
            }
        }
    }
    func pause() {
        capture.pause(); workout?.pause(); motion.stopDeviceMotionUpdates()
        if state == .recording { state = .paused }
    }
    func resume() {
        guard capture.isPaused else { return }
        guard let workout else { capture.resume(); return }
        guard workout.state == .paused else { return }
        capture.resume(); workout.resume()
        if state == .paused { state = .recording; startMotion() }
    }
    func end() {
        guard state.isBusy, state != .saving else { return }
        let collected = state.isRecording
        capture.end(); motion.stopDeviceMotionUpdates()
        guard let workout, let builder else { state = .idle; return }
        let token = generation
        self.workout = nil; self.builder = nil; workout.end()
        guard collected else { builder.discardWorkout(); state = .idle; return }
        state = .saving
        builder.endCollection(withEnd: Date()) { [weak self] success, _ in
            guard let self else { return }
            guard success else {
                builder.discardWorkout()
                Task { @MainActor in
                    guard self.capture.isCurrent(token) else { return }
                    self.state = .failed("Couldn’t save workout.")
                }; return
            }
            builder.finishWorkout { workout, error in
                Task { @MainActor in
                    guard self.capture.isCurrent(token) else { return }
                    self.state = workout != nil && error == nil ? .saved : .failed("Couldn’t save workout.")
                }
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.workout === workoutSession else { return }
            self.end()
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type), let stats = workoutBuilder.statistics(for: type),
              let value = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
              let date = stats.mostRecentQuantityDateInterval()?.end else { return }
        Task { @MainActor in
            guard self.builder === workoutBuilder,
                  self.capture.acceptsSamples(for: self.generation, measuredAt: date) else { return }
            self.onHeart?(.init(value: value, date: date))
        }
    }
}
