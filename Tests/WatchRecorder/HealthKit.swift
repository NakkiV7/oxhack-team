// Test-only SDK boundary. Never linked into the app or used to access HealthKit.
@_exported import Foundation

public protocol HKWorkoutSessionDelegate: AnyObject {}
public protocol HKLiveWorkoutBuilderDelegate: AnyObject {}
public enum HKAuthorizationStatus { case sharingAuthorized, sharingDenied }
public enum HKQuantityTypeIdentifier: Hashable { case heartRate, activeEnergyBurned }
public enum HKWorkoutSessionState { case running, paused, ended }
public enum HKWorkoutActivityType { case traditionalStrengthTraining }
public enum HKWorkoutSessionLocationType { case indoor }
public class HKSampleType: NSObject {
    public static func workoutType() -> HKSampleType { HKSampleType() }
}
public final class HKQuantityType: HKSampleType {
    public let identifier: HKQuantityTypeIdentifier
    public init(_ identifier: HKQuantityTypeIdentifier) { self.identifier = identifier; super.init() }
    public override var hash: Int { identifier.hashValue }
    public override func isEqual(_ object: Any?) -> Bool { (object as? HKQuantityType)?.identifier == identifier }
}
public final class HKHealthStore {
    public static var authorization = HKAuthorizationStatus.sharingAuthorized
    public static var deferAuthorization = false
    public static var authorizationRequests: [(Bool, Error?) -> Void] = []
    public static var requestedReadTypes = Set<HKQuantityTypeIdentifier>()
    public init() {}
    public static func isHealthDataAvailable() -> Bool { true }
    public func authorizationStatus(for type: HKSampleType) -> HKAuthorizationStatus { Self.authorization }
    public func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKSampleType>,
                                     completion: @escaping (Bool, Error?) -> Void) {
        Self.authorizationRequests.append(completion)
        Self.requestedReadTypes = Set(read.compactMap { ($0 as? HKQuantityType)?.identifier })
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
    public private(set) var typesToCollect = Set<HKQuantityType>()
    public func enableCollection(for type: HKQuantityType, predicate: NSPredicate?) { typesToCollect.insert(type) }
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
    public var statisticsByType: [HKQuantityTypeIdentifier: HKStatistics] = [:]
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
    public func statistics(for type: HKQuantityType) -> HKStatistics? { statisticsByType[type.identifier] }
}
public final class HKWorkout {}
public final class HKStatistics {
    private let recent: HKQuantity?
    private let sum: HKQuantity?
    public let endDate: Date
    public init(recent: HKQuantity? = nil, sum: HKQuantity? = nil, endDate: Date) {
        self.recent = recent; self.sum = sum; self.endDate = endDate
    }
    public func mostRecentQuantity() -> HKQuantity? { recent }
    public func mostRecentQuantityDateInterval() -> DateInterval? { recent.map { _ in DateInterval(start: endDate, duration: 0) } }
    public func sumQuantity() -> HKQuantity? { sum }
}
public final class HKQuantity {
    private let value: Double
    private let unit: HKUnit
    public init(unit: HKUnit, doubleValue: Double) { self.unit = unit; value = doubleValue }
    public func doubleValue(for unit: HKUnit) -> Double { unit.symbol == self.unit.symbol ? value : .nan }
}
public final class HKUnit {
    public let symbol: String
    private init(_ symbol: String) { self.symbol = symbol }
    public static func count() -> HKUnit { HKUnit("count") }
    public static func minute() -> HKUnit { HKUnit("min") }
    public static func kilocalorie() -> HKUnit { HKUnit("kcal") }
    public func unitDivided(by unit: HKUnit) -> HKUnit { HKUnit("\(symbol)/\(unit.symbol)") }
}
