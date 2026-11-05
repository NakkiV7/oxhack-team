import Foundation
import Observation

@MainActor @Observable
public final class WatchSetupStore {
    public private(set) var selectedModel: WatchModelPreference
    public private(set) var presentation: WatchSetupPresentation
    private let defaults: UserDefaults
    private let observe: () -> WatchSetupObservation
    private let request: () -> Void
    private var lastProbeAt: Date?
    private static let modelKey = "Spottr.watch-model"

    public init(defaults: UserDefaults, observe: @escaping () -> WatchSetupObservation, request: @escaping () -> Void) {
        self.defaults = defaults; self.observe = observe; self.request = request
        selectedModel = defaults.string(forKey: Self.modelKey).flatMap(WatchModelPreference.init(rawValue:)) ?? .notSure
        presentation = .init(observation: .init(), at: Date())
    }

    public func select(_ model: WatchModelPreference) {
        selectedModel = model
        if model == .noWatch { lastProbeAt = nil }
        defaults.set(model.rawValue, forKey: Self.modelKey)
    }

    public func refresh(at date: Date = Date()) {
        guard selectedModel != .noWatch else { return }
        presentation = .init(observation: observe(), at: date)
    }

    public func refreshConnection(at date: Date = Date()) {
        guard selectedModel != .noWatch else { return }
        let observation = observe()
        presentation = .init(observation: observation, at: date)
        guard observation.supported, observation.activated, observation.paired,
              observation.installed, observation.reachable else { lastProbeAt = nil; return }
        if let lastProbeAt, (0..<12).contains(date.timeIntervalSince(lastProbeAt)) { return }
        lastProbeAt = date
        request()
    }

    public func checkConnection(at date: Date = Date()) {
        guard selectedModel != .noWatch else { return }
        lastProbeAt = date
        request()
        refresh(at: date)
    }
}
