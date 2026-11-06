import Foundation
import HealthKit

typealias HealthDataStore = HealthSnapshotStore

extension HealthSnapshotStore {
    convenience init() {
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let defaults = namespace.flatMap { UserDefaults(suiteName: "Spottr.Health.\($0.uuidString)") } ?? .standard
        self.init(client: AppleHealthReadingClient(), defaults: defaults)
    }

    var zones: HeartRateZoneConfiguration? {
        guard let preference = zonePreference else { return nil }
        return try? HeartRateZoneConfiguration(maximumHeartRate: preference.maximumHeartRate, isEstimated: preference.isEstimated)
    }

    func setMaximumHeartRate(_ value: Double) throws {
        let configuration = try HeartRateZoneConfiguration(maximumHeartRate: value)
        setZonePreference(.init(maximumHeartRate: configuration.maximumHeartRate, isEstimated: configuration.isEstimated))
    }

    func estimateZones(age: Int) throws {
        guard let configuration = HeartRateZoneConfiguration.estimated(age: age) else { throw HealthSetupError.invalidAge }
        setZonePreference(.init(maximumHeartRate: configuration.maximumHeartRate, isEstimated: configuration.isEstimated))
    }

    func clearZones() { setZonePreference(nil) }
}

private enum HealthSetupError: LocalizedError {
    case invalidAge
    var errorDescription: String? { "Enter an age from 18 to 100, or leave zones unconfigured." }
}

@MainActor
final class AppleHealthReadingClient: HealthReadingClient {
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let metrics: [(HealthMetricKind, HKQuantityTypeIdentifier)] = [
        (.restingHeartRate, .restingHeartRate), (.walkingHeartRateAverage, .walkingHeartRateAverage),
        (.heartRateVariabilitySDNN, .heartRateVariabilitySDNN), (.vo2Max, .vo2Max),
        (.heartRateRecoveryOneMinute, .heartRateRecoveryOneMinute), (.oxygenSaturation, .oxygenSaturation),
        (.respiratoryRate, .respiratoryRate), (.steps, .stepCount), (.walkingRunningDistance, .distanceWalkingRunning)
    ]

    static var requestedReadTypes: [HKQuantityType] {
        metrics.compactMap { HKObjectType.quantityType(forIdentifier: $0.1) }
    }

    func requestReadAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Set(Self.requestedReadTypes.map { $0 as HKObjectType }))
    }

    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation] {
        var observations: [HealthObservation] = []
        for (metric, identifier) in Self.metrics {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let observation: HealthObservation?
            if metric.isDaily {
                observation = try? await daily(metric: metric, type: type, start: dayStart, end: min(asOf, dayEnd))
            } else {
                observation = try? await latest(metric: metric, type: type, asOf: asOf)
            }
            if let observation { observations.append(observation) }
        }
        return observations
    }

    private func latest(metric: HealthMetricKind, type: HKQuantityType, asOf: Date) async throws -> HealthObservation? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: nil, end: asOf, options: .strictEndDate)
            let order = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [order]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                guard let sample = samples?.first as? HKQuantitySample else { continuation.resume(returning: nil); return }
                continuation.resume(returning: Self.observation(metric: metric, quantity: sample.quantity,
                                                                 date: sample.endDate, source: sample.sourceRevision.source.name))
            }
            store.execute(query)
        }
    }

    private func daily(metric: HealthMetricKind, type: HKQuantityType, start: Date, end: Date) async throws -> HealthObservation? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                guard let quantity = statistics?.sumQuantity() else { continuation.resume(returning: nil); return }
                let names = Set(statistics?.sources?.map(\.name) ?? []).sorted()
                let source = names.isEmpty ? "Apple Health (merged sources)" : "Apple Health, \(names.joined(separator: ", "))"
                continuation.resume(returning: Self.observation(metric: metric, quantity: quantity, date: end, source: source))
            }
            store.execute(query)
        }
    }

    nonisolated static func observation(metric: HealthMetricKind, quantity: HKQuantity, date: Date, source: String) -> HealthObservation? {
        let expectedUnit = unit(metric)
        guard quantity.is(compatibleWith: expectedUnit) else { return nil }
        let rawValue = quantity.doubleValue(for: expectedUnit)
        let value = metric == .oxygenSaturation ? rawValue * 100 : rawValue
        return HealthObservation(metric: metric, value: value, date: date, source: source)
    }

    nonisolated private static func unit(_ metric: HealthMetricKind) -> HKUnit {
        switch metric {
        case .restingHeartRate, .walkingHeartRateAverage, .respiratoryRate:
            return HKUnit.count().unitDivided(by: .minute())
        case .heartRateRecoveryOneMinute: return .count()
        case .heartRateVariabilitySDNN: return .secondUnit(with: .milli)
        case .vo2Max:
            return HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .oxygenSaturation: return .percent()
        case .steps: return .count()
        case .walkingRunningDistance: return .meterUnit(with: .kilo)
        }
    }
}
