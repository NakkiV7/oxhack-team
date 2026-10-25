// Test-only SDK boundary. Never linked into the app or used to access HealthKit.
@_exported import Foundation

public protocol HKWorkoutSessionDelegate: AnyObject {}
public protocol HKLiveWorkoutBuilderDelegate: AnyObject {}
public enum HKAuthorizationStatus { case sharingAuthorized, sharingDenied }
public enum HKQuantityTypeIdentifier { case heartRate }
public enum HKWorkoutSessionState { case running, paused, ended }
public enum HKWorkoutActivityType { case traditionalStrengthTraining }
public enum HKWorkoutSessionLocationType { case indoor }
public class HKSampleType: NSObject {
    public static func workoutType() -> HKSampleType { HKSampleType() }
}
public final class HKQuantityType: HKSampleType {
    public init(_ identifier: HKQuantityTypeIdentifier) { super.init() }
}
public final class HKHealthStore {
    public static var authorization = HKAuthorizationStatus.sharingAuthorized
    public static var deferAuthorization = false
    public static var authorizationRequests: [(Bool, Error?) -> Void] = []
    public init() {}
    public static func isHealthDataAvailable() -> Bool { true }
    public func authorizationStatus(for type: HKSampleType) -> HKAuthorizationStatus { Self.authorization }
    public func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKSampleType>,
                                     completion: @escaping (Bool, Error?) -> Void) {
        Self.authorizationRequests.append(completion)
        if !Self.deferAuthorization { completion(true, nil) }
    }
}
public final class HKWorkoutConfiguration {
    public init() {}
    public var activityType = HKWorkoutActivityType.traditionalStrengthTraining
    public var locationType = HKWorkoutSessionLocationType.indoor
}
public final class HKLiveWorkoutDataSource {
    public init(healthStore: HKHealthStore, workoutConfiguration: HKWorkoutConfiguration) {}
}
public final class HKWorkoutSession {
    public static var created: [HKWorkoutSession] = []
    public weak var delegate: HKWorkoutSessionDelegate?
    public var state = HKWorkoutSessionState.running
    public private(set) var endCount = 0
    public let liveBuilder = HKLiveWorkoutBuilder()
    public init(healthStore: HKHealthStore, configuration: HKWorkoutConfiguration) throws { Self.created.append(self) }
    public func associatedWorkoutBuilder() -> HKLiveWorkoutBuilder { liveBuilder }
    public func startActivity(with date: Date) { state = .running }
    public func pause() { state = .paused }
    public func resume() { state = .running }
    public func end() { endCount += 1; state = .ended }
}
public final class HKLiveWorkoutBuilder {
    public var dataSource: HKLiveWorkoutDataSource?
    public weak var delegate: HKLiveWorkoutBuilderDelegate?
    public private(set) var collectionCompletion: ((Bool, Error?) -> Void)?
    public private(set) var discardCount = 0
    public private(set) var endCollectionCount = 0
    public private(set) var finishCount = 0
    public func beginCollection(withStart date: Date, completion: @escaping (Bool, Error?) -> Void) {
        collectionCompletion = completion
    }
    public func discardWorkout() { discardCount += 1 }
    public func endCollection(withEnd date: Date, completion: @escaping (Bool, Error?) -> Void) {
        endCollectionCount += 1; completion(true, nil)
    }
    public func finishWorkout(completion: @escaping (HKWorkout?, Error?) -> Void) {
        finishCount += 1; completion(HKWorkout(), nil)
    }
    public func statistics(for type: HKQuantityType) -> HKStatistics? { nil }
}
public final class HKWorkout {}
public final class HKStatistics {
    public func mostRecentQuantity() -> HKQuantity? { nil }
    public func mostRecentQuantityDateInterval() -> DateInterval? { nil }
}
public final class HKQuantity { public func doubleValue(for unit: HKUnit) -> Double { 0 } }
public final class HKUnit {
    public static func count() -> HKUnit { HKUnit() }
    public static func minute() -> HKUnit { HKUnit() }
    public func unitDivided(by unit: HKUnit) -> HKUnit { self }
}
