import Foundation
import XCTest
@testable import SpottrCore

final class WatchSetupTests: XCTestCase {
    func testWatchChoiceIsOptionalAndOnlyTailorsSensorExplanation() {
        XCTAssertEqual(WatchModelPreference.allCases, [.se, .series6OrLater, .ultra, .notSure, .noWatch])
        XCTAssertTrue(WatchModelPreference.se.sensorExplanation.contains("doesn’t measure blood oxygen"))
        XCTAssertTrue(WatchModelPreference.se.sensorExplanation.contains("another device"))
        XCTAssertFalse(WatchModelPreference.notSure.sensorExplanation.contains("supported sensors confirmed"))
        XCTAssertEqual(WatchModelPreference.noWatch.title, "No Watch")
    }
    func testMilestonesRequireEachRealObservationAndExpireCompanionConfirmation() {
        let now = Date(timeIntervalSince1970: 1000)
        let reply = WatchSetupConfirmation(checkedAt: now, pendingSamples: 3, droppedSamples: 0, queueMessage: nil)
        let online = WatchSetupObservation(supported: true, activated: true, paired: true, installed: true, reachable: true, confirmation: reply)
        let presentation = WatchSetupPresentation(observation: online, at: now)
        XCTAssertEqual(presentation.milestones.map(\.isComplete), [true, true, true, true])
        XCTAssertEqual(presentation.queueText, "3 Watch samples waiting for iPhone")
        XCTAssertEqual(presentation.summary, "Your Watch companion responded")
        XCTAssertNil(presentation.lastDataReceivedAt)
        let expired = WatchSetupPresentation(observation: online, at: now.addingTimeInterval(16))
        XCTAssertEqual(expired.milestones.map(\.isComplete), [true, true, true, false])
        XCTAssertNil(expired.queueText)
        let offline = WatchSetupObservation(supported: true, activated: true, paired: true, installed: true, reachable: false, confirmation: reply)
        XCTAssertEqual(WatchSetupPresentation(observation: offline, at: now).milestones.map(\.isComplete), [true, true, false, false])
        let unpaired = WatchSetupObservation(supported: true, activated: true, paired: false, installed: true, reachable: true, confirmation: reply)
        XCTAssertEqual(WatchSetupPresentation(observation: unpaired, at: now).milestones.map(\.isComplete), [false, false, false, false])
        let notReady = WatchSetupObservation(supported: true, activated: false, paired: true, installed: true, reachable: true, confirmation: reply)
        XCTAssertTrue(WatchSetupPresentation(observation: notReady, at: now).milestones.allSatisfy { !$0.isComplete })
    }

    func testSetupReplyMustMatchCurrentLiveProbeAndCannotUseWatchClockForFreshness() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let probe = WatchSetupProbe(sentAt: now)
        let reply = WatchSetupReply(requestID: probe.id, pendingSamples: 2, droppedSamples: 1, queueMessage: nil)
        let decoded = try JSONDecoder().decode(WatchSetupReply.self, from: JSONEncoder().encode(reply))
        XCTAssertEqual(decoded.confirmation(for: probe, receivedAt: now.addingTimeInterval(1))?.pendingSamples, 2)
        XCTAssertNil(decoded.confirmation(for: WatchSetupProbe(sentAt: now), receivedAt: now))
        XCTAssertNil(decoded.confirmation(for: probe, receivedAt: now.addingTimeInterval(16)))
        XCTAssertNil(decoded.confirmation(for: probe, receivedAt: now.addingTimeInterval(-1)))
        XCTAssertNil(WatchSetupReply(requestID: probe.id, pendingSamples: -1, droppedSamples: 0, queueMessage: nil).confirmation(for: probe, receivedAt: now))
        XCTAssertNil(WatchSetupReply(requestID: probe.id, pendingSamples: 0, droppedSamples: -1, queueMessage: nil).confirmation(for: probe, receivedAt: now))
        XCTAssertNil(WatchSetupReply(requestID: probe.id, pendingSamples: 0, droppedSamples: 0, queueMessage: String(repeating: "x", count: 513)).confirmation(for: probe, receivedAt: now))
        let futureProtocol = Data("{\"version\":99,\"requestID\":\"\(probe.id.uuidString)\",\"pendingSamples\":0,\"droppedSamples\":0}".utf8)
        XCTAssertNil(try JSONDecoder().decode(WatchSetupReply.self, from: futureProtocol).confirmation(for: probe, receivedAt: now))
    }

    func testMotionCapabilityComesFromReplyAndStaysUnknownForLegacyCompanion() throws {
        let now = Date(timeIntervalSince1970: 1000), probe = WatchSetupProbe(sentAt: Date(timeIntervalSince1970: 1000))
        let noMotion = WatchSetupReply(requestID: probe.id, pendingSamples: 0, droppedSamples: 0, queueMessage: nil, motionAvailable: false)
        XCTAssertEqual(noMotion.confirmation(for: probe, receivedAt: now)?.motionAvailable, false)
        let legacy = Data("{\"version\":1,\"requestID\":\"\(probe.id.uuidString)\",\"pendingSamples\":0,\"droppedSamples\":0}".utf8)
        XCTAssertNil(try JSONDecoder().decode(WatchSetupReply.self, from: legacy).confirmation(for: probe, receivedAt: now)?.motionAvailable)
        let snapshot = WatchSetupObservation(supported: true, activated: true, paired: true, installed: true, reachable: true, confirmation: noMotion.confirmation(for: probe, receivedAt: now))
        XCTAssertEqual(WatchSetupPresentation(observation: snapshot, at: now).motionText, "Motion is unavailable on this Watch")
        XCTAssertEqual(WatchSetupPresentation(observation: snapshot, at: now.addingTimeInterval(16)).motionText, "Motion availability has not been confirmed")
    }

    @MainActor func testModelPreferenceIsLocalOptionalAndNoWatchDoesNotRequestConnection() async throws {
        let name = "WatchSetupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var requests = 0
        let store = WatchSetupStore(defaults: defaults, observe: { .init() }, request: { requests += 1 })
        XCTAssertEqual(store.selectedModel, .notSure)
        store.select(.noWatch)
        store.checkConnection()
        XCTAssertEqual(requests, 0)
        let reopened = WatchSetupStore(defaults: defaults, observe: { .init() }, request: { requests += 1 })
        XCTAssertEqual(reopened.selectedModel, .noWatch)
        reopened.select(.se)
        reopened.checkConnection()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(WatchSetupStore(defaults: defaults, observe: { .init() }, request: {}).selectedModel, .se)
    }

    @MainActor func testReturningFromWatchSetupReloadsPhoneOnlyWithoutObservingOrRequesting() async throws {
        let name = "WatchSetupReturnTests.\(UUID().uuidString)"
        let summaryDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let destinationDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { summaryDefaults.removePersistentDomain(forName: name) }
        var requests = 0, observations = 0
        let destination = WatchSetupStore(defaults: destinationDefaults, observe: { .init() }, request: { requests += 1 })
        destination.select(.se)
        let summary = WatchSetupStore(defaults: summaryDefaults, observe: {
            observations += 1
            return .init(supported: true, activated: true, paired: true, installed: true, reachable: true)
        }, request: { requests += 1 })
        XCTAssertEqual(summary.selectedModel, .se)

        destination.select(.noWatch)
        summary.refresh()

        XCTAssertEqual(summary.selectedModel, .noWatch, "The returning permissions summary must use the destination's current Phone only choice")
        XCTAssertEqual(observations, 0, "Phone only must suppress connection observation after reloading the choice")
        XCTAssertEqual(requests, 0, "Returning to the summary must never request a connection")
    }

    @MainActor func testReturningFromPhoneOnlyReloadsWatchChoiceAndObservesWithoutRequesting() async throws {
        let name = "WatchSetupReturnTests.\(UUID().uuidString)"
        let summaryDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let destinationDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { summaryDefaults.removePersistentDomain(forName: name) }
        var requests = 0, observations = 0
        let destination = WatchSetupStore(defaults: destinationDefaults, observe: { .init() }, request: { requests += 1 })
        destination.select(.noWatch)
        let summary = WatchSetupStore(defaults: summaryDefaults, observe: {
            observations += 1
            return .init(supported: true, activated: true, paired: true, installed: true, reachable: true)
        }, request: { requests += 1 })
        XCTAssertEqual(summary.selectedModel, .noWatch)

        destination.select(.ultra)
        summary.refresh()

        XCTAssertEqual(summary.selectedModel, .ultra, "The returning permissions summary must stop displaying Phone only")
        XCTAssertEqual(summary.presentation.summary, "Your Watch is reachable. Check the companion.")
        XCTAssertEqual(observations, 1, "The current Watch choice must restore observation after the prior Phone only guard")
        XCTAssertEqual(requests, 0, "A status refresh must not request a connection")
    }

    @MainActor func testLiveSetupChecksAreThrottledAndRetryWhenWatchBecomesReachable() async throws {
        let name = "WatchSetupPollingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date(timeIntervalSince1970: 1000)
        var reachable = true, requests = 0
        let store = WatchSetupStore(defaults: defaults, observe: {
            .init(supported: true, activated: true, paired: true, installed: true, reachable: reachable)
        }, request: { requests += 1 })
        store.refreshConnection(at: now)
        store.refreshConnection(at: now.addingTimeInterval(3))
        XCTAssertEqual(requests, 1)
        store.refreshConnection(at: now.addingTimeInterval(12))
        XCTAssertEqual(requests, 2)
        store.checkConnection(at: now.addingTimeInterval(13))
        store.refreshConnection(at: now.addingTimeInterval(14))
        XCTAssertEqual(requests, 3)
        reachable = false
        store.refreshConnection(at: now.addingTimeInterval(15))
        reachable = true
        store.refreshConnection(at: now.addingTimeInterval(16))
        XCTAssertEqual(requests, 4)
        store.select(.noWatch)
        store.refreshConnection(at: now.addingTimeInterval(60))
        XCTAssertEqual(requests, 4)
    }

}
