import Foundation
import Observation

public enum HealthMetricKind: String, CaseIterable, Sendable {
    case restingHeartRate, walkingHeartRateAverage, heartRateVariabilitySDNN, vo2Max
    case heartRateRecoveryOneMinute, oxygenSaturation, respiratoryRate, steps, walkingRunningDistance

    public var isDaily: Bool { self == .steps || self == .walkingRunningDistance }

    public var title: String {
        switch self {
        case .restingHeartRate: "Resting heart rate"
        case .walkingHeartRateAverage: "Walking heart rate"
        case .heartRateVariabilitySDNN: "Heart rate variability (SDNN)"
        case .vo2Max: "Cardio fitness (VO₂ max)"
        case .heartRateRecoveryOneMinute: "One-minute heart rate recovery"
        case .oxygenSaturation: "Blood oxygen"
        case .respiratoryRate: "Respiratory rate"
        case .steps: "Steps today"
        case .walkingRunningDistance: "Walking/running distance today"
        }
    }

    public var unit: String {
        switch self {
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateRecoveryOneMinute: "bpm"
        case .heartRateVariabilitySDNN: "ms"
        case .vo2Max: "mL/kg/min"
        case .oxygenSaturation: "%"
        case .respiratoryRate: "breaths/min"
        case .steps: "steps"
        case .walkingRunningDistance: "km"
        }
    }
}

public struct HealthObservation: Equatable, Identifiable, Sendable {
    public let metric: HealthMetricKind
    public let value: Double
    public let date: Date
    public let source: String
    public var id: HealthMetricKind { metric }
    public var title: String { metric.title }
    public var unit: String { metric.unit }

    public init?(metric: HealthMetricKind, value: Double, date: Date, source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isFinite, date.timeIntervalSince1970.isFinite, value >= 0,
              metric.isDaily || value > 0, metric != .oxygenSaturation || value <= 100,
              !trimmed.isEmpty else { return nil }
        self.metric = metric
        self.value = value
        self.date = date
        self.source = trimmed
    }
}

public struct HealthSnapshot: Equatable, Sendable {
    public let observations: [HealthObservation]
    public let asOf: Date
    public let dayStart: Date
    public let dayEnd: Date
    public var latestObservations: [HealthObservation] { observations.filter { !$0.metric.isDaily } }
    public var dailyObservations: [HealthObservation] { observations.filter { $0.metric.isDaily } }

    public init(observations: [HealthObservation], asOf: Date, calendar: Calendar = .current) {
        self.asOf = asOf
        dayStart = calendar.startOfDay(for: asOf)
        dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let start = dayStart
        let eligible = observations.filter { $0.date <= asOf && (!$0.metric.isDaily || $0.date >= start) }
        self.observations = HealthMetricKind.allCases.compactMap { metric in
            eligible.filter { $0.metric == metric }.max { $0.date < $1.date }
        }
    }
}

@MainActor
public protocol HealthReadingClient: AnyObject {
    var isAvailable: Bool { get }
    func requestReadAuthorization() async throws
    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation]
}

public struct HealthZonePreference: Equatable, Sendable {
    public let maximumHeartRate: Double
    public let isEstimated: Bool
    public init(maximumHeartRate: Double, isEstimated: Bool) {
        self.maximumHeartRate = maximumHeartRate
        self.isEstimated = isEstimated
    }
}

public enum WatchSetupStatus: Sendable {
    case unsupported, notReady, notPaired, notInstalled, installedOffline, reachable

    public static func evaluate(supported: Bool, activated: Bool, paired: Bool, installed: Bool, reachable: Bool) -> WatchSetupStatus {
        guard supported else { return .unsupported }
        guard activated else { return .notReady }
        guard paired else { return .notPaired }
        guard installed else { return .notInstalled }
        return reachable ? .reachable : .installedOffline
    }
}

@MainActor @Observable
public final class HealthSnapshotStore {
    private var latestSnapshot: HealthSnapshot?
    public private(set) var statusMessage = "Apple Health is optional. Choose which data you want to show."
    public private(set) var isBusy = false
    public private(set) var hasRequestedAccess: Bool
    public private(set) var zonePreference: HealthZonePreference?
    private let client: any HealthReadingClient
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private let calendar: @MainActor () -> Calendar
    @ObservationIgnored private var dayRefresh: Task<Void, Never>?
    @ObservationIgnored private var readingID = UUID()

    public init(client: any HealthReadingClient, defaults: UserDefaults = .standard,
                now: @escaping @MainActor () -> Date = { .now },
                calendar: @escaping @MainActor () -> Calendar = { .current }) {
        self.client = client
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        hasRequestedAccess = defaults.bool(forKey: "health.accessRequested")
        if defaults.object(forKey: "health.zoneMaximum") != nil {
            zonePreference = .init(maximumHeartRate: defaults.double(forKey: "health.zoneMaximum"),
                                   isEstimated: defaults.bool(forKey: "health.zoneEstimated"))
        }
    }

    deinit { dayRefresh?.cancel() }

    public var snapshot: HealthSnapshot? {
        guard let latestSnapshot, calendar().startOfDay(for: now()) == latestSnapshot.dayStart else { return nil }
        return latestSnapshot
    }

    public func connect() async {
        guard !isBusy else { return }
        guard client.isAvailable else {
            statusMessage = "Apple Health is not available on this device."
            return
        }
        isBusy = true
        hasRequestedAccess = true
        defaults.set(true, forKey: "health.accessRequested")
        defer { isBusy = false }
        do {
            try await client.requestReadAuthorization()
            await readSnapshot()
        } catch {
            latestSnapshot = nil
            statusMessage = "Apple Health setup wasn’t completed. Try again or continue without it."
        }
    }

    public func refresh() async {
        guard !isBusy, hasRequestedAccess, client.isAvailable else { return }
        isBusy = true
        defer { isBusy = false }
        await readSnapshot()
    }

    private func readSnapshot() async {
        guard hasRequestedAccess else { return }
        let request = UUID()
        readingID = request
        let date = now()
        let currentCalendar = calendar()
        let bounds = HealthSnapshot(observations: [], asOf: date, calendar: currentCalendar)
        do {
            let observations = try await client.read(asOf: date, dayStart: bounds.dayStart, dayEnd: bounds.dayEnd)
            guard hasRequestedAccess, readingID == request else { return }
            latestSnapshot = HealthSnapshot(observations: observations, asOf: date, calendar: currentCalendar)
            statusMessage = snapshot?.observations.isEmpty == false
                ? "Showing dated Apple Health readings. Other data may be missing or not shared."
                : "No available data. Apple Health may have no readings, or access may not be shared."
            scheduleMidnightRefresh(dayEnd: bounds.dayEnd)
        } catch {
            guard hasRequestedAccess, readingID == request else { return }
            latestSnapshot = nil
            statusMessage = "Apple Health readings are unavailable right now. Your training is unchanged."
            scheduleMidnightRefresh(dayEnd: bounds.dayEnd)
        }
    }

    public func disconnect() {
        readingID = UUID()
        dayRefresh?.cancel()
        latestSnapshot = nil
        hasRequestedAccess = false
        defaults.set(false, forKey: "health.accessRequested")
        statusMessage = "Apple Health is optional. Choose which data you want to show."
    }

    public func setZonePreference(_ preference: HealthZonePreference?) {
        zonePreference = preference
        guard let preference else {
            defaults.removeObject(forKey: "health.zoneMaximum")
            defaults.removeObject(forKey: "health.zoneEstimated")
            return
        }
        defaults.set(preference.maximumHeartRate, forKey: "health.zoneMaximum")
        defaults.set(preference.isEstimated, forKey: "health.zoneEstimated")
    }

    private func scheduleMidnightRefresh(dayEnd: Date) {
        dayRefresh?.cancel()
        let delay = max(1, dayEnd.timeIntervalSince(now()))
        dayRefresh = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            await self?.refresh()
        }
    }
}
