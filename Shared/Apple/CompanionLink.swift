import Foundation
import WatchConnectivity

protocol CompanionContextChannel {
    var activated: Bool { get }
    var paired: Bool { get }
    var reachable: Bool { get }
    var applicationContext: [String: Any] { get }
    func replaceContext(_ value: [String: Any]) throws
    func sendContext(_ value: [String: Any])
}

private struct SystemCompanionContextChannel: CompanionContextChannel {
    let session: WCSession
    var activated: Bool { session.activationState == .activated }
    var paired: Bool {
        #if os(iOS)
        session.isPaired
        #else
        true
        #endif
    }
    var reachable: Bool { session.isReachable }
    var applicationContext: [String: Any] { session.applicationContext }
    func replaceContext(_ value: [String: Any]) throws { try session.updateApplicationContext(value) }
    func sendContext(_ value: [String: Any]) { session.sendMessage(value, replyHandler: nil, errorHandler: nil) }
}

final class CompanionLink: NSObject, WCSessionDelegate {
    var onProgramme: ((WatchProgrammeTransport) -> Void)?
    var onScopedSnapshot: ((WatchScopedSnapshot) -> Void)?
    var onWorkout: ((WatchWorkoutJournal) -> Void)?
    var onWorkoutAcknowledgement: ((WatchWorkoutAcknowledgement) -> Void)?
    private var supportsScopedWorkouts = false
    private var lastProgramme: WatchProgrammeTransport?
    private var lastProgrammeData: Data?
    private var lastIdleData: Data?
    private var lastIdleProtocol: Bool?
    func publishProgramme(_ transport: WatchProgrammeTransport) {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        guard supportsScopedWorkouts, let channel = publicationChannel, channel.activated, channel.paired else { return }
        if lastProgramme == transport, let lastProgrammeData,
           channel.applicationContext["watchProgramme"] as? Data == lastProgrammeData { return }
        lastIdleData = nil; lastIdleProtocol = nil
        guard let data = try? JSONEncoder().encode(transport) else { return }
        if updateContext(key: "watchProgramme", data: data) { lastProgramme = transport; lastProgrammeData = data }
    }
    func publishScoped(_ snapshot: WatchScopedSnapshot?) {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        guard let channel = publicationChannel, channel.activated, channel.paired else { return }
        var payload = channel.applicationContext
        if snapshot == nil, let lastIdleData, lastIdleProtocol == supportsScopedWorkouts,
           payload["snapshot"] as? Data == lastIdleData, payload["scopedSnapshot"] == nil,
           supportsScopedWorkouts || payload["watchProgramme"] == nil { return }
        lastIdleData = nil; lastIdleProtocol = nil
        guard let idle = try? JSONEncoder().encode(CompanionSnapshot(session: TrainingSession())) else { return }
        payload["snapshot"] = idle
        if !supportsScopedWorkouts { payload["watchProgramme"] = nil }
        payload["scopedSnapshot"] = supportsScopedWorkouts ? snapshot.flatMap { try? JSONEncoder().encode($0) } : nil
        do {
            try channel.replaceContext(payload)
            if snapshot == nil { lastIdleData = idle; lastIdleProtocol = supportsScopedWorkouts }
        } catch {}
        if channel.reachable { channel.sendContext(payload) }
    }
    func sendWorkout(_ journal: WatchWorkoutJournal) {
        guard let session, session.activationState == .activated, journal.finishedAt != nil,
              !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo["watchWorkoutID"] as? String == journal.id.uuidString }),
              !session.outstandingFileTransfers.contains(where: { $0.file.metadata?["watchWorkoutID"] as? String == journal.id.uuidString }) else { return }
        let pending = session.outstandingUserInfoTransfers.filter { $0.userInfo["watchWorkoutID"] != nil }.count + session.outstandingFileTransfers.count
        guard pending < 4 else { return }
        do {
            let data = try JSONEncoder().encode(journal)
            guard data.count <= 8 * 1024 * 1024 else { throw WatchWorkoutJournal.Failure.capacity }
            if data.count <= 48 * 1024 {
                _ = session.transferUserInfo(["watchWorkout": data, "watchWorkoutID": journal.id.uuidString])
            } else {
                let attempt = UUID()
                let url = workoutFile(id: journal.id, owner: journal.grant.owner, folder: "outgoing", attempt: attempt)
                try ProtectedLocalStorage.write(data, to: url)
                _ = session.transferFile(url, metadata: ["watchWorkoutID": journal.id.uuidString, "watchTransferID": attempt.uuidString,
                    "accountID": journal.grant.owner.accountID.uuidString, "profileID": journal.grant.owner.profileID.uuidString])
            }
        } catch {
            telemetryLock.lock(); deliveryMessage = "A completed workout could not be transferred. It remains saved on Watch."; notifyDeliveryStatus(); telemetryLock.unlock()
        }
    }
    private func workoutFile(id: UUID, owner: WorkoutOwner, folder: String, attempt: UUID? = nil) -> URL {
        workoutTransferRoot.appendingPathComponent(folder).appendingPathComponent(owner.accountID.uuidString)
            .appendingPathComponent(owner.profileID.uuidString).appendingPathComponent(id.uuidString + (attempt.map { "-" + $0.uuidString } ?? "") + ".json")
    }
    func acknowledgeWorkout(_ value: WatchWorkoutAcknowledgement) {
        guard let session, session.activationState == .activated, let data = try? JSONEncoder().encode(value) else { return }
        _ = session.transferUserInfo(["watchWorkoutAck": data])
        try? FileManager.default.removeItem(at: workoutFile(id: value.id, owner: value.owner, folder: "incoming"))
    }
    private func updateContext(key: String, data: Data) -> Bool {
        guard let channel = publicationChannel, channel.activated, channel.paired else { return false }
        var payload = channel.applicationContext; payload[key] = data
        let replaced: Bool
        do { try channel.replaceContext(payload); replaced = true } catch { replaced = false }
        if channel.reachable { channel.sendContext(payload) }
        return replaced
    }
    private func resetPublications() {
        lastProgramme = nil; lastProgrammeData = nil; lastIdleData = nil; lastIdleProtocol = nil
    }
    var onSnapshot: ((CompanionSnapshot) -> Void)?
    var onCommand: ((CompanionCommand) -> Void)?
    var onTelemetry: ((WatchTelemetry) -> Void)?
    var onTelemetryBatch: (([WatchTelemetry]) -> Void)?
    var onDurableTelemetryBatch: ((UUID, [WatchTelemetry]) -> Void)?
    var onTelemetryDeliveryStatus: ((WatchTelemetryDeliveryStatus) -> Void)?
    var onReachability: ((Bool) -> Void)?
    var onRequest: (() -> Void)?
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let suppliedPublicationChannel: (any CompanionContextChannel)?
    private var publicationChannel: (any CompanionContextChannel)? { suppliedPublicationChannel ?? session.map(SystemCompanionContextChannel.init) }
    private let telemetryLock = NSRecursiveLock()
    private let outbox: WatchTelemetryOutbox?
    private let workoutTransferRoot: URL
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

    init(telemetryOutboxURL: URL? = nil, publicationChannel: (any CompanionContextChannel)? = nil) {
        suppliedPublicationChannel = publicationChannel
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = telemetryOutboxURL ?? directory.appendingPathComponent("Spottr/watch-telemetry-outbox.json")
        workoutTransferRoot = url.deletingLastPathComponent().appendingPathComponent("workout-transfers")
        do { outbox = try WatchTelemetryOutbox(url: url) }
        catch { outbox = nil; deliveryMessage = "Watch data queue unavailable. Local storage needs attention." }
        super.init()
        if publicationChannel == nil { session?.delegate = self; session?.activate(); requestProtocol() }
    }
    private func requestProtocol() {
        telemetryLock.lock(); supportsScopedWorkouts = false; resetPublications(); telemetryLock.unlock()
        guard let session, session.activationState == .activated, session.isReachable else { return }
        publishScoped(nil)
        session.sendMessage(["workoutProbe": true], replyHandler: { [weak self] payload in
            self?.receive(payload); self?.onRequest?()
        }, errorHandler: nil)
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
        session.sendMessage(["request": true, "workoutProtocol": 1], replyHandler: { [weak self] payload in self?.receive(payload) }, errorHandler: nil)
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        invalidateSetupStatus(); requestProtocol()
        receive(session.receivedApplicationContext, marksArrival: false)
        telemetryLock.lock()
        retryAfter.removeAll(); queueTelemetry(includeUnsealed: true); notifyDeliveryStatus()
        telemetryLock.unlock()
        onReachability?(session.isReachable)
        onRequest?()
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        if !session.isReachable { invalidateSetupStatus() }
        else { requestProtocol() }
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
        replyHandler(["received": true, "workoutProtocol": 1])
    }
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: file.fileURL)
            let value = try JSONDecoder().decode(WatchWorkoutJournal.self, from: data)
            guard value.isValid else { return }
            guard file.metadata?["watchWorkoutID"] as? String == value.id.uuidString,
                  file.metadata?["accountID"] as? String == value.grant.owner.accountID.uuidString,
                  file.metadata?["profileID"] as? String == value.grant.owner.profileID.uuidString else { throw CocoaError(.fileReadCorruptFile) }
            let saved = workoutFile(id: value.id, owner: value.grant.owner, folder: "incoming")
            if FileManager.default.fileExists(atPath: saved.path) {
                let existing = try JSONDecoder().decode(WatchWorkoutJournal.self, from: Data(contentsOf: saved))
                guard existing == value else { throw CocoaError(.fileReadCorruptFile) }
            } else { try ProtectedLocalStorage.write(data, to: saved) }
            onWorkout?(value)
        } catch {
            telemetryLock.lock(); deliveryMessage = "A workout file could not be imported. The original remains on Watch."; notifyDeliveryStatus(); telemetryLock.unlock()
        }
    }
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let metadata = fileTransfer.file.metadata,
              let rawAttempt = metadata["watchTransferID"] as? String, let attempt = UUID(uuidString: rawAttempt),
              let rawID = metadata["watchWorkoutID"] as? String, let id = UUID(uuidString: rawID),
              let rawAccount = metadata["accountID"] as? String, let account = UUID(uuidString: rawAccount),
              let rawProfile = metadata["profileID"] as? String, let profile = UUID(uuidString: rawProfile) else { return }
        let url = workoutFile(id: id, owner: .init(accountID: account, profileID: profile), folder: "outgoing", attempt: attempt)
        guard url.standardizedFileURL == fileTransfer.file.fileURL.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
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
        if payload["workoutProtocol"] as? Int == 1 {
            telemetryLock.lock()
            if !supportsScopedWorkouts { resetPublications() }
            supportsScopedWorkouts = true; telemetryLock.unlock()
        }
        if let data = payload["watchProgramme"] as? Data, data.count <= 256 * 1024,
           let value = try? JSONDecoder().decode(WatchProgrammeTransport.self, from: data) { onProgramme?(value) }
        if let data = payload["scopedSnapshot"] as? Data, data.count <= 64 * 1024,
           let value = try? JSONDecoder().decode(WatchScopedSnapshot.self, from: data) { onScopedSnapshot?(value) }
        if let data = payload["watchWorkout"] as? Data, data.count <= 1024 * 1024,
           let value = try? JSONDecoder().decode(WatchWorkoutJournal.self, from: data), value.isValid { onWorkout?(value) }
        if let data = payload["watchWorkoutAck"] as? Data, data.count <= 4096,
           let value = try? JSONDecoder().decode(WatchWorkoutAcknowledgement.self, from: data) { onWorkoutAcknowledgement?(value) }
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
        if payload["request"] as? Bool == true {
            telemetryLock.lock(); resetPublications(); telemetryLock.unlock()
            onRequest?()
        }
    }
    #if os(iOS)
    func sessionWatchStateDidChange(_ session: WCSession) {
        invalidateSetupStatus(clearReceipt: true); requestProtocol(); onRequest?()
    }
    func sessionDidBecomeInactive(_ session: WCSession) { invalidateSetupStatus(clearReceipt: true) }
    func sessionDidDeactivate(_ session: WCSession) { invalidateSetupStatus(clearReceipt: true); session.activate() }
    #endif
}
