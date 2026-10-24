import HealthKit
import CoreMotion

@MainActor
final class WorkoutRecorder: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    var onHeart: ((SensorReading) -> Void)?
    var onMotion: ((SensorReading, SensorReading) -> Void)?
    var onStatus: ((String) -> Void)?
    var onRecording: ((Bool) -> Void)?
    private let health = HKHealthStore()
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var generation = UUID()
    private var capture = WatchCaptureLifecycle()
    private var lastMotion = Date.distantPast

    func start() {
        #if targetEnvironment(simulator)
        onStatus?("Heart rate needs Apple Watch."); onRecording?(false)
        #else
        guard workout == nil, HKHealthStore.isHealthDataAvailable() else { onStatus?("Health data unavailable"); onRecording?(false); return }
        let token = capture.start(); generation = token
        health.requestAuthorization(toShare: [.workoutType()], read: [HKQuantityType(.heartRate)]) { [weak self] success, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                guard success, error == nil, self.health.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
                    self.onStatus?("Workout permission wasn’t granted."); self.onRecording?(false); return
                }
                self.begin(token: token)
            }
        }
        #endif
    }
    private func begin(token: UUID) {
        guard capture.beginCollection(for: token) else { return }
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
                        self.onRecording?(false); self.onStatus?("Couldn’t collect workout data.")
                        return
                    }
                    self.onStatus?("Workout recording")
                }
            }
            if capture.isPaused { session.pause() }
            else { startMotion() }
        } catch { capture.end(); onStatus?("Couldn’t start a workout."); onRecording?(false) }
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
    func pause() { capture.pause(); workout?.pause(); motion.stopDeviceMotionUpdates() }
    func resume() {
        guard capture.isPaused else { return }
        guard let workout else { capture.resume(); return }
        guard workout.state == .paused else { return }
        capture.resume(); workout.resume(); startMotion()
    }
    func end() {
        capture.end(); motion.stopDeviceMotionUpdates()
        guard let workout, let builder else { return }
        let token = generation
        self.workout = nil; self.builder = nil; workout.end()
        onStatus?("Ending workout…"); onRecording?(false)
        builder.endCollection(withEnd: Date()) { [weak self] success, _ in
            guard let self else { return }
            guard success else {
                builder.discardWorkout()
                Task { @MainActor in
                    guard self.capture.isCurrent(token) else { return }
                    self.onStatus?("Couldn’t save workout.")
                }; return
            }
            builder.finishWorkout { workout, error in
                Task { @MainActor in
                    guard self.capture.isCurrent(token) else { return }
                    self.onStatus?(workout != nil && error == nil ? "Workout saved" : "Couldn’t save workout.")
                }
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.workout === workoutSession else { return }
            self.onStatus?("Workout interrupted."); self.end()
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
