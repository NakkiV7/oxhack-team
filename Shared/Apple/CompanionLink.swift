import Foundation
import WatchConnectivity

final class CompanionLink: NSObject, WCSessionDelegate {
    var onSnapshot: ((CompanionSnapshot) -> Void)?
    var onCommand: ((CompanionCommand) -> Void)?
    var onTelemetry: ((WatchTelemetry) -> Void)?
    var onTelemetryBatch: (([WatchTelemetry]) -> Void)?
    var onDurableTelemetryBatch: ((UUID, [WatchTelemetry]) -> Void)?
    var onTelemetryDeliveryStatus: ((WatchTelemetryDeliveryStatus) -> Void)?
    var onReachability: ((Bool) -> Void)?
    var onRequest: (() -> Void)?
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let telemetryLock = NSRecursiveLock()
    private let outbox: WatchTelemetryOutbox?
    private var queuedBatchIDs = Set<UUID>()
    private var retryAfter: [UUID: Date] = [:]
    private var deliveryMessage: String?
    private var rejectionMessage: String?
    private var setupProbe: WatchSetupProbe?
    private var confirmedSetup: WatchSetupConfirmation?
    private var receivedDataAt: Date?
    private var setupMotionAvailable: Bool?

    var setupConfirmation: WatchSetupConfirmation? {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        return confirmedSetup
    }
    var lastDataReceivedAt: Date? {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        return receivedDataAt
    }
    func setSetupMotionAvailability(_ available: Bool) {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        setupMotionAvailable = available
    }
    func requestSetupStatus() {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        setupProbe = nil; confirmedSetup = nil
        guard let session, session.activationState == .activated, session.isReachable else { return }
        let probe = WatchSetupProbe()
        guard let data = try? JSONEncoder().encode(probe) else { return }
        setupProbe = probe
        session.sendMessage(["setupProbe": data], replyHandler: { [weak self] payload in
            guard let self else { return }
            self.telemetryLock.lock(); defer { self.telemetryLock.unlock() }
            guard self.setupProbe?.id == probe.id, session.activationState == .activated, session.isReachable,
                  let data = payload["setupReply"] as? Data, data.count <= 4096,
                  let reply = try? JSONDecoder().decode(WatchSetupReply.self, from: data),
                  let confirmation = reply.confirmation(for: probe, receivedAt: Date()) else { return }
            self.confirmedSetup = confirmation
            self.setupProbe = nil
        }, errorHandler: { [weak self] _ in
            guard let self else { return }
            self.telemetryLock.lock(); defer { self.telemetryLock.unlock() }
            if self.setupProbe?.id == probe.id { self.setupProbe = nil }
        })
    }
    private func invalidateSetupStatus(clearReceipt: Bool = false) {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        setupProbe = nil; confirmedSetup = nil
        if clearReceipt { receivedDataAt = nil }
    }
    private func noteDataReceived() {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        receivedDataAt = Date()
    }

    var telemetryDeliveryStatus: WatchTelemetryDeliveryStatus {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        return .init(pendingSamples: outbox?.pendingSampleCount ?? 0,
                     droppedSamples: outbox?.droppedSampleCount ?? 0, message: deliveryMessage ?? rejectionMessage)
    }

    init(telemetryOutboxURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = telemetryOutboxURL ?? directory.appendingPathComponent("Spottr/watch-telemetry-outbox.json")
        do { outbox = try WatchTelemetryOutbox(url: url) }
        catch { outbox = nil; deliveryMessage = "Watch data queue unavailable. Local storage needs attention." }
        super.init(); session?.delegate = self; session?.activate()
    }
    func publish(_ snapshot: CompanionSnapshot) {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        let payload: [String: Any] = ["snapshot": data]
        try? session.updateApplicationContext(payload)
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
    }
    func command(_ command: CompanionCommand, completion: @escaping (Bool) -> Void) {
        guard let session, session.activationState == .activated, session.isReachable,
              let data = try? JSONEncoder().encode(command) else { completion(false); return }
        session.sendMessage(["command": data], replyHandler: { _ in completion(true) }, errorHandler: { _ in completion(false) })
    }
    func telemetry(_ telemetry: WatchTelemetry) {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(telemetry) else { return }
        let payload: [String: Any] = ["telemetry": data]
        try? session.updateApplicationContext(payload)
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
    }
    func telemetryBatch(_ samples: [WatchTelemetry]) {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        guard let outbox else { notifyDeliveryStatus(); return }
        do {
            try outbox.append(samples)
            queueTelemetry(includeUnsealed: outbox.unsealedSampleCount >= 10)
        } catch {
            deliveryMessage = "Watch samples couldn’t be saved locally. Some recent data may be missing."
        }
        notifyDeliveryStatus()
    }
    func flushTelemetry() {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        queueTelemetry(includeUnsealed: true); notifyDeliveryStatus()
    }
    func retryTelemetry() {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        queueTelemetry(includeUnsealed: false); notifyDeliveryStatus()
    }
    private func queueTelemetry(includeUnsealed: Bool) {
        guard let session, session.activationState == .activated, let outbox else { return }
        let outstanding = Set(session.outstandingUserInfoTransfers.compactMap {
            ($0.userInfo["telemetryBatchID"] as? String).flatMap(UUID.init(uuidString:))
        })
        queuedBatchIDs.formUnion(outstanding)
        let pendingIDs = outbox.pendingBatchIDs
        retryAfter = retryAfter.filter { pendingIDs.contains($0.key) }
        let waiting = Set(retryAfter.filter { $0.value > Date() }.map(\.key))
        do {
            while queuedBatchIDs.count < 4,
                  let batch = try outbox.nextBatch(excluding: queuedBatchIDs.union(waiting), includeUnsealed: includeUnsealed) {
                let data = try JSONEncoder().encode(batch.samples)
                guard data.count <= 256 * 1024 else {
                    deliveryMessage = "A Watch data batch exceeds the transfer limit."; return
                }
                queuedBatchIDs.insert(batch.id)
                _ = session.transferUserInfo(["telemetryBatch": data, "telemetryBatchID": batch.id.uuidString])
            }
        } catch { deliveryMessage = "Watch data queue couldn’t be updated. Previously saved samples are retained." }
    }
    func acknowledgeTelemetryBatch(_ id: UUID, accepted: Bool = true) {
        guard let session, session.activationState == .activated else { return }
        _ = session.transferUserInfo(["telemetryAck": id.uuidString, "accepted": accepted])
    }
    func request() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": true], replyHandler: nil, errorHandler: nil)
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        invalidateSetupStatus()
        receive(session.receivedApplicationContext, marksArrival: false)
        telemetryLock.lock()
        retryAfter.removeAll(); queueTelemetry(includeUnsealed: true); notifyDeliveryStatus()
        telemetryLock.unlock()
        onReachability?(session.isReachable)
        onRequest?()
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        if !session.isReachable { invalidateSetupStatus() }
        telemetryLock.lock()
        retryAfter.removeAll(); queueTelemetry(includeUnsealed: true); notifyDeliveryStatus()
        telemetryLock.unlock()
        onReachability?(session.isReachable); onRequest?()
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        if let data = message["setupProbe"] as? Data, data.count <= 1024,
           let probe = try? JSONDecoder().decode(WatchSetupProbe.self, from: data), probe.version == 1 {
            telemetryLock.lock()
            let status = telemetryDeliveryStatus
            let response = WatchSetupReply(requestID: probe.id, pendingSamples: status.pendingSamples,
                                           droppedSamples: status.droppedSamples, queueMessage: status.message,
                                           motionAvailable: setupMotionAvailable)
            telemetryLock.unlock()
            if let encoded = try? JSONEncoder().encode(response) { replyHandler(["setupReply": encoded]); return }
        }
        replyHandler(["received": true])
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard let rawID = userInfoTransfer.userInfo["telemetryBatchID"] as? String, let id = UUID(uuidString: rawID) else { return }
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        queuedBatchIDs.remove(id); retryAfter[id] = Date().addingTimeInterval(30)
        if error != nil { deliveryMessage = "Watch data delivery will retry." }
        notifyDeliveryStatus()
    }
    private func notifyDeliveryStatus() { onTelemetryDeliveryStatus?(telemetryDeliveryStatus) }
    private func receive(_ payload: [String: Any], marksArrival: Bool = true) {
        if let data = payload["snapshot"] as? Data, let snapshot = try? JSONDecoder().decode(CompanionSnapshot.self, from: data) { onSnapshot?(snapshot) }
        if let data = payload["command"] as? Data, let command = try? JSONDecoder().decode(CompanionCommand.self, from: data) { onCommand?(command) }
        if let data = payload["telemetry"] as? Data, let telemetry = try? JSONDecoder().decode(WatchTelemetry.self, from: data) {
            if marksArrival { noteDataReceived() }
            onTelemetry?(telemetry)
        }
        if let data = payload["telemetryBatch"] as? Data, data.count <= 256 * 1024,
           let samples = try? JSONDecoder().decode([WatchTelemetry].self, from: data), !samples.isEmpty, samples.count <= 60 {
            if marksArrival { noteDataReceived() }
            if let rawID = payload["telemetryBatchID"] as? String, let id = UUID(uuidString: rawID), let onDurableTelemetryBatch {
                onDurableTelemetryBatch(id, samples)
            } else { onTelemetryBatch?(samples) }
        }
        if let rawID = payload["telemetryAck"] as? String, let id = UUID(uuidString: rawID), let accepted = payload["accepted"] as? Bool {
            telemetryLock.lock()
            if let outbox, outbox.pendingBatchIDs.contains(id) {
                do {
                    try outbox.acknowledge(id)
                    retryAfter[id] = nil; queuedBatchIDs.remove(id)
                    deliveryMessage = nil
                    if !accepted { rejectionMessage = "iPhone rejected a Watch data batch. Those samples were not added to history." }
                } catch { deliveryMessage = "Couldn’t update the Watch data queue. Retrying may send duplicates." }
            }
            queueTelemetry(includeUnsealed: false); notifyDeliveryStatus()
            telemetryLock.unlock()
        }
        if payload["request"] as? Bool == true { onRequest?() }
    }
    #if os(iOS)
    func sessionWatchStateDidChange(_ session: WCSession) { invalidateSetupStatus(clearReceipt: true) }
    func sessionDidBecomeInactive(_ session: WCSession) { invalidateSetupStatus(clearReceipt: true) }
    func sessionDidDeactivate(_ session: WCSession) { invalidateSetupStatus(clearReceipt: true); session.activate() }
    #endif
}
