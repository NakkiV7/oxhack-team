import Foundation
import WatchConnectivity

// Synthetic values shaped like the recorder's Apple-origin measurements, never physiology evidence.
@main struct TelemetryReplayTests {
    static func durableBatchWaitsForPhonePersistenceAcknowledgement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptURL = directory.appendingPathComponent("corrupt-outbox.json"), wire = WCSession.default
        try Data("interrupted file".utf8).write(to: corruptURL)
        let unavailable = CompanionLink(telemetryOutboxURL: corruptURL)
        precondition(unavailable.telemetryDeliveryStatus.message != nil)
        unavailable.session(wire, didReceiveUserInfo: ["telemetryAck": UUID().uuidString, "accepted": true])
        precondition(unavailable.telemetryDeliveryStatus.message != nil,
                     "An unrelated ACK cannot hide an unreadable durable queue")
        let url = directory.appendingPathComponent("watch-outbox.json")
        let link = CompanionLink(telemetryOutboxURL: url), owner = UUID()
        wire.isReachable = false
        let samples = (0..<35).map { WatchTelemetry(sessionID: owner, sentAt: Date(timeIntervalSince1970: Double($0)),
            heartRate: nil, accelerationG: nil, rotationRadiansPerSecond: nil) }
        link.telemetryBatch(samples)
        precondition(link.telemetryDeliveryStatus.pendingSamples == 35, "Queued delivery cannot pretend phone persistence happened")
        let batches = wire.transfers.filter { $0.userInfo["telemetryBatch"] != nil }
        precondition(batches.count == 2, "Unreachable Watch still queues bounded background batches")
        for transfer in batches {
            let decoded = try JSONDecoder().decode([WatchTelemetry].self, from: transfer.userInfo["telemetryBatch"] as! Data)
            precondition(decoded.count <= 30)
        }
        let first = batches[0], firstID = first.userInfo["telemetryBatchID"] as! String
        wire.complete(first)
        link.session(wire, didFinish: first, error: nil)
        precondition(link.telemetryDeliveryStatus.pendingSamples == 35, "WC delivery alone must not delete durable data")
        let count = wire.transfers.count
        link.flushTelemetry()
        precondition(wire.transfers.count == count, "A successful delivery waits for ACK with a bounded cooldown")
        link.sessionReachabilityDidChange(wire)
        precondition(wire.transfers.last?.userInfo["telemetryBatchID"] as? String == firstID, "Unacknowledged delivery retries the same stable batch identity")
        link.session(wire, didReceiveUserInfo: ["telemetryAck": firstID, "accepted": true])
        precondition(link.telemetryDeliveryStatus.pendingSamples == 5)
        link.session(wire, didReceiveUserInfo: ["telemetryAck": firstID, "accepted": true])
        precondition(link.telemetryDeliveryStatus.pendingSamples == 5, "Duplicate ACK cannot remove another batch")
        let secondID = batches[1].userInfo["telemetryBatchID"] as! String
        link.session(wire, didReceiveUserInfo: ["telemetryAck": secondID, "accepted": false])
        precondition(link.telemetryDeliveryStatus.pendingSamples == 0 && link.telemetryDeliveryStatus.message != nil,
                     "A permanent phone rejection removes only its batch and stays visible")
        for transfer in wire.outstandingUserInfoTransfers {
            wire.complete(transfer); link.session(wire, didFinish: transfer, error: nil)
        }
        link.telemetryBatch([samples[0]]); link.flushTelemetry()
        let retryTransfer = wire.transfers.last!, retryID = retryTransfer.userInfo["telemetryBatchID"] as! String
        wire.complete(retryTransfer)
        link.session(wire, didFinish: retryTransfer, error: NSError(domain: "synthetic-link", code: 1))
        precondition(link.telemetryDeliveryStatus.pendingSamples == 1 && link.telemetryDeliveryStatus.message != nil,
                     "Transport failure retains durable samples and surfaces retry status")
        link.session(wire, activationDidCompleteWith: .activated, error: nil)
        precondition(wire.transfers.last?.userInfo["telemetryBatchID"] as? String == retryID,
                     "Activation retries the original failed batch identity")
        link.session(wire, didReceiveUserInfo: ["telemetryAck": retryID, "accepted": true])
        precondition(link.telemetryDeliveryStatus.pendingSamples == 0 && link.telemetryDeliveryStatus.message != nil,
                     "A later successful ACK must not silently erase an earlier permanent rejection notice")
        var durable: [(UUID, [WatchTelemetry])] = [], compatibility: [[WatchTelemetry]] = []
        link.onDurableTelemetryBatch = { durable.append(($0, $1)) }
        link.onTelemetryBatch = { compatibility.append($0) }
        link.session(wire, didReceiveUserInfo: first.userInfo)
        precondition(durable.count == 1 && durable.first?.0.uuidString == firstID && durable.first?.1 == Array(samples.prefix(30)))
        precondition(compatibility.isEmpty, "Durable consumer has one explicit ownership path")
        link.onDurableTelemetryBatch = nil
        link.session(wire, didReceiveUserInfo: first.userInfo)
        precondition(compatibility.count == 1)
        let oversized = try JSONEncoder().encode(Array(repeating: samples[0], count: 61))
        link.session(wire, didReceiveUserInfo: ["telemetryBatch": oversized, "telemetryBatchID": UUID().uuidString])
        link.session(wire, didReceiveUserInfo: ["telemetryBatch": Data("broken".utf8)])
        precondition(compatibility.count == 1, "Malformed and oversized batches never enter application history handling")
        link.acknowledgeTelemetryBatch(UUID(uuidString: firstID)!)
        precondition(wire.transfers.last?.userInfo["telemetryAck"] as? String == firstID)
        wire.isReachable = true
    }

    static func main() throws {
        try durableBatchWaitsForPhonePersistenceAcknowledgement()
        var session = TrainingSession(); session.start(at: 0)
        let start = session.date, run = UUID(), link = CompanionLink(), wire = WCSession.default
        var receiveAt = start
        link.onTelemetry = { session.receiveTelemetry($0, now: receiveAt) }
        func packet(_ sent: Double, measured: Double, heart: Double? = 118, energy: Double? = nil,
                    owner: UUID? = nil) -> WatchTelemetry {
            let date = start.addingTimeInterval(measured)
            return .init(sessionID: owner ?? session.id, sentAt: start.addingTimeInterval(sent),
                         heartRate: heart.map { .init(value: $0, date: date) },
                         accelerationG: .init(value: 0.3741657387, date: date),
                         rotationRadiansPerSecond: .init(value: 1.25, date: date),
                         activeEnergy: energy.map { .init(recordingID: run, kilocalories: $0, asOf: date) })
        }
        func deliver(_ payload: [String: Any], at offset: Double, context: Bool = false) {
            receiveAt = start.addingTimeInterval(offset)
            if context { link.session(wire, didReceiveApplicationContext: payload) }
            else { link.session(wire, didReceiveMessage: payload) }
        }
        func transmit(_ message: WatchTelemetry, at offset: Double) {
            link.telemetry(message)
            if let data = wire.applicationContext["telemetry"] as? Data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                precondition(json["sentAt"] as? Double == message.sentAt.timeIntervalSinceReferenceDate,
                             "Wire dates use Foundation's 2001 reference epoch, not Unix seconds or boot uptime")
            } else { preconditionFailure("Real link encodes a telemetry Data payload") }
            deliver(wire.applicationContext, at: offset, context: true)
            if wire.isReachable, let live = wire.messages.last { deliver(live, at: offset) }
        }
        transmit(packet(1, measured: 1, energy: 0), at: 1) // context + live duplicate
        transmit(packet(2, measured: 1, energy: 0), at: 2) // cached sample, fresh envelope
        transmit(packet(5, measured: 5, heart: 122, energy: 0.6), at: 5)
        transmit(packet(4, measured: 4, heart: 120), at: 5) // out of order envelope
        transmit(packet(6, measured: 6, owner: UUID()), at: 6)
        transmit(packet(7, measured: 7), at: 21) // expired transport
        deliver(["telemetry": Data("{broken".utf8)], at: 21)
        let messagesBeforeDisconnect = wire.messages.count
        wire.isReachable = false
        link.telemetry(packet(8, measured: 8))
        precondition(wire.messages.count == messagesBeforeDisconnect, "Disconnected transport cannot send live")
        deliver(wire.applicationContext, at: 30, context: true) // retained context expires
        wire.isReachable = true
        transmit(packet(31, measured: 5), at: 31) // fresh transport cannot make cached readings fresh
        transmit(packet(32, measured: 32, heart: nil, energy: 1.25), at: 32)
        precondition(session.record.telemetry.count == 5, "Duplicate, stale, foreign and old envelopes rejected")
        session.finish(at: 33)
        transmit(packet(34, measured: 34, energy: 2), at: 34)
        precondition(session.record.telemetry.count == 5, "Finished session cannot accept telemetry")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = HistoryStore(url: directory.appendingPathComponent("history.json"))
        try history.save(session.record)
        let export = directory.appendingPathComponent("export.json"); try history.export(to: export)
        let records = try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: export))
        let loaded = try history.load()
        precondition(records == loaded, "Real persistence/export retains transported values")
        let report = WorkoutReport(record: records[0])
        precondition(report.heartRate.samples.map(\.value) == [118, 122], "No duplicate, stale or missing HR fabricated")
        precondition(report.acceleration.samples.count == 3 && report.rotation.samples.count == 3)
        precondition(report.acceleration.samples.first?.value == 0.3741657387 && report.rotation.samples.first?.value == 1.25)
        precondition(report.heartRate.samples.first?.date == start.addingTimeInterval(1), "Measurement date survives transport and disk")
        precondition(report.acceleration.samples.last?.segment == 1, "Disconnect stays a timeline gap")
        precondition(report.heartRate.sourceLabel == "Apple Watch · HealthKit")
        precondition(report.rotation.sourceLabel == "Apple Watch · Core Motion")
        precondition(report.activeEnergy.first?.kilocalories == 1.25, "Cumulative energy is never summed per packet")
        precondition(report.energyTimeline.map(\.kilocalories) == [0, 0.6, 1.25])
        let plan = try JSONDecoder().decode(CoachSavedPlan.self, from: Data("""
        {"items":[{"exerciseID":"wallPushup","sets":1,"target":8,"unit":"reps","restSeconds":30}],
         "approvedAt":0,"rationale":"Synthetic transport replay"}
        """.utf8))
        var configured = try ConfigurableSession(plan: plan, availableSupport: ["Wall"])
        configured.start(at: 0)
        link.onTelemetry = { configured.receiveTelemetry($0, now: receiveAt) }
        transmit(packet(40, measured: 40, heart: 124, energy: 2, owner: configured.id), at: 40)
        transmit(packet(39, measured: 39, heart: 123, owner: configured.id), at: 40)
        transmit(packet(41, measured: 41), at: 41) // previous phone session must not leak into configured workout
        transmit(packet(42, measured: 42, owner: configured.id), at: 60)
        configured.finish(at: 61)
        transmit(packet(62, measured: 62, owner: configured.id), at: 62)
        precondition(configured.record.telemetry.count == 1, "Configured workouts enforce the same freshness/order/ownership/end boundary")
        try history.save(configured.record)
        let configuredReport = WorkoutReport(record: try history.load().first { $0.id == configured.id }!)
        precondition(configuredReport.heartRate.samples.map(\.value) == [124])
        precondition(configuredReport.activeEnergy.first?.kilocalories == 2)
        print("Watch transport replay: actual link/decoder → session → history/export → report passed (synthetic SDK boundary; no physical acceptance)")
    }
}
