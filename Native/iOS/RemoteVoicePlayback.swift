import AVFoundation
import Foundation
import Observation
import UIKit

enum VoiceCoachPreference: String, CaseIterable, Identifiable, Sendable {
    case maya, leo, local
    var id: String { rawValue }
    var title: String { switch self { case .local: "Local voice"; case .maya: "Maya"; case .leo: "Leo" } }
}

enum RemoteVoiceError: Error, LocalizedError {
    case configuration, unavailable, invalidResponse
    case rejected(Int)
    var errorDescription: String? {
        switch self {
        case .configuration: return "Configure an HTTPS gateway and access token, or localhost for development."
        case .unavailable: return "This remote voice is unavailable. Local voice remains an explicit choice."
        case .invalidResponse: return "The remote voice response could not be played safely."
        case .rejected(let status): return "The voice gateway refused the request (\(status))."
        }
    }
}

struct VoiceCoachAvailability: Decodable {
    let id: VoiceCoachPreference
    let tones: [String]
    private enum CodingKeys: String, CodingKey { case id, name, tones }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = VoiceCoachPreference(rawValue: try values.decode(String.self, forKey: .id)), id != .local,
              try values.decode(String.self, forKey: .name) == id.title else { throw RemoteVoiceError.invalidResponse }
        self.id = id
        tones = try values.decodeIfPresent([String].self, forKey: .tones) ?? ["calm"]
        guard tones == ["calm"] else { throw RemoteVoiceError.invalidResponse }
    }
}

@MainActor
struct VoiceGatewayClient {
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    private let baseURL: URL
    private let token: String
    private let transport: Transport
    init(baseURL: URL, token: String, transport: Transport? = nil) {
        self.baseURL = baseURL; self.token = token
        self.transport = transport ?? { try await Self.boundedTransport($0) }
    }
    static func configured() throws -> Self {
        guard let url = URL(string: CoachSettings.gatewayURL), let token = CoachSettings.token() else { throw RemoteVoiceError.configuration }
        return Self(baseURL: url, token: token)
    }
    func voices() async throws -> [VoiceCoachAvailability] {
        struct Reply: Decodable { let voices: [VoiceCoachAvailability]; let availability: String }
        let data = try await send(path: "voices", body: nil, timeout: 6, limit: 4096)
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.availability == "configured_not_verified",
              reply.voices.count <= 2, Set(reply.voices.map(\.id)).count == reply.voices.count else { throw RemoteVoiceError.invalidResponse }
        return reply.voices
    }
    func audio(cue: VoiceCue, voice: VoiceCoachPreference, playbackToken: UUID, expiresAt: Date, remaining: Double) async throws -> Data {
        guard case .coaching(let priority) = cue.kind, priority != .stop else { throw RemoteVoiceError.invalidResponse }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = ["generationID": cue.generation.uuidString, "sessionID": cue.sessionID.uuidString, "cueID": cue.id.uuidString,
                    "playbackToken": playbackToken.uuidString, "voice": voice.rawValue, "priority": priority.rawValue,
                    "text": cue.text.trimmingCharacters(in: .whitespacesAndNewlines), "expiresAt": formatter.string(from: expiresAt)]
        let data = try await send(path: "voice", body: body, timeout: remaining, limit: 360_448)
        guard var reply = try? JSONDecoder().decode([String: String].self, from: data),
              reply.removeValue(forKey: "mimeType") == "audio/mpeg", let encoded = reply.removeValue(forKey: "audioBase64"), reply == body,
              let audio = Data(base64Encoded: encoded), !audio.isEmpty, audio.count <= 262_144,
              audio.base64EncodedString() == encoded else { throw RemoteVoiceError.invalidResponse }
        return audio
    }
    private func send(path: String, body: [String: String]?, timeout: Double, limit: Int) async throws -> Data {
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(baseURL.host ?? "")
        guard baseURL.scheme == "https" || local && baseURL.scheme == "http", baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, token.utf8.count <= 4096,
              token.rangeOfCharacter(from: .controlCharacters) == nil else { throw RemoteVoiceError.configuration }
        try Task.checkCancellation()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/\(path)"))
        request.httpMethod = body == nil ? "GET" : "POST"; request.timeoutInterval = max(0.001, min(6, timeout))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            guard request.httpBody!.count <= 8192 else { throw RemoteVoiceError.invalidResponse }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == request.url else { throw RemoteVoiceError.invalidResponse }
        guard http.statusCode == 200 else { throw RemoteVoiceError.rejected(http.statusCode) }
        guard http.mimeType == "application/json", !data.isEmpty, data.count <= limit else { throw RemoteVoiceError.invalidResponse }
        return data
    }
    private nonisolated static func boundedTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration, delegate: VoiceRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        let limit = request.url?.lastPathComponent == "voices" ? 4096 : 360_448
        guard response.expectedContentLength <= Int64(limit) else { throw RemoteVoiceError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw RemoteVoiceError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (data, response)
    }
}

private final class VoiceRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
protocol VoiceAudioOutput: AnyObject {
    var onFinish: (() -> Void)? { get set }
    func prepare() throws
    func play() -> Bool
    func stop()
}

extension VoiceAudioOutput {
    func prepare() throws {}
}

@MainActor @Observable
final class RemoteVoicePlayback: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var onInterrupt: (() -> Void)?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var previewObservers: [NSObjectProtocol] = []
    private var explicitPreview = false
    private(set) var preference: VoiceCoachPreference = .maya
    private(set) var configuredVoices: [VoiceCoachPreference] = [.maya, .leo, .local]
    private(set) var errorMessage: String?
    var isPreview: Bool { previewPlayback != nil }
    private let local: VoicePlayback
    private let offlineOnly: Bool
    private let defaults: UserDefaults
    var preferencesDefaults: UserDefaults { defaults }
    let gentleOnly: Bool
    var exercise: Exercise?
    private var cueLibrary = TrainerCueLibrary()
    var tone: TrainerTone { gentleOnly ? .gentle : TrainerTone(rawValue: defaults.string(forKey: "trainer.tone") ?? "") ?? .encouraging }
    private let previewPlayback: VoicePlayback?
    private let naturalPlayback: VoicePlayback
    private let overridesNaturalPlayback: Bool
    private let client: @MainActor () throws -> VoiceGatewayClient
    private let makeAudio: @MainActor (Data) throws -> VoiceAudioOutput
    private let wallNow: () -> Date
    private let uptime: () -> Double
    private var availability: [VoiceCoachAvailability] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var active: (cueID: UUID, token: UUID)?
    @ObservationIgnored private var output: VoiceAudioOutput?
    @ObservationIgnored private var localCueID: UUID?
    @ObservationIgnored private var previewCueID: UUID?

    init(local: VoicePlayback? = nil, offlineOnly: Bool = false, defaults: UserDefaults = .standard, gentleOnly: Bool = false, previewPlayback: VoicePlayback? = nil, naturalPlayback: VoicePlayback? = nil, client: @escaping @MainActor () throws -> VoiceGatewayClient = { try VoiceGatewayClient.configured() },
         makeAudio: (@MainActor (Data) throws -> VoiceAudioOutput)? = nil,
         wallNow: @escaping () -> Date = Date.init, uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.offlineOnly = offlineOnly
        self.defaults = defaults
        self.gentleOnly = gentleOnly
        self.local = local ?? LocalVoicePlayback(); self.previewPlayback = previewPlayback
        self.naturalPlayback = previewPlayback ?? naturalPlayback ?? DemoVoicePlayback(tone: gentleOnly ? .gentle : TrainerTone(rawValue: defaults.string(forKey: "trainer.tone") ?? "") ?? .encouraging)
        overridesNaturalPlayback = previewPlayback != nil || naturalPlayback != nil
        self.client = client; self.makeAudio = makeAudio ?? { try SystemVoiceAudioOutput(data: $0) }
        self.wallNow = wallNow; self.uptime = uptime
        configuredVoices = [.maya, .leo, .local]
        let saved = VoiceCoachPreference(rawValue: defaults.string(forKey: "trainer.voice") ?? "") ?? .maya
        preference = offlineOnly || previewPlayback != nil ? saved : .maya
        if offlineOnly || previewPlayback != nil { defaults.set(saved.rawValue, forKey: "trainer.voice") }
        self.local.onFinish = { [weak self] id in self?.finishedPlayback(id) }
        self.naturalPlayback.onFinish = { [weak self] id in self?.finishedPlayback(id) }
        for name in [AVAudioSession.routeChangeNotification, UIApplication.didEnterBackgroundNotification] {
            previewObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.explicitPreview == true else { return }
                    self?.stop()
                }
            })
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
            guard (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.stop()
                self?.onInterrupt?()
            }
        }
    }
    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        previewObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func refreshVoices() async throws {
        guard previewPlayback == nil, !offlineOnly else { return }
        let options = try await client().voices()
        availability = options
        configuredVoices = [.maya, .leo, .local]
    }
    func reloadPreferences() {
        guard offlineOnly || previewPlayback != nil else { return }
        let voice = VoiceCoachPreference(rawValue: defaults.string(forKey: "trainer.voice") ?? "") ?? .maya
        defaults.set(voice.rawValue, forKey: "trainer.voice")
        try? select(voice)
    }
    func select(_ preference: VoiceCoachPreference) throws {
        guard configuredVoices.contains(preference),
              offlineOnly || previewPlayback != nil || preference == .maya || preference == .local || availability.contains(where: { $0.id == preference }) else { throw RemoteVoiceError.unavailable }
        guard self.preference != preference else { return }
        stop(); onInterrupt?(); self.preference = preference; errorMessage = nil
        if offlineOnly || previewPlayback != nil { defaults.set(preference.rawValue, forKey: "trainer.voice") }
    }
    func supportsAudio(for event: CoachingEvent?) -> Bool {
        event != nil
    }
    func configureSelection(_ preference: VoiceCoachPreference, tone: TrainerTone) throws {
        guard (offlineOnly || previewPlayback != nil), configuredVoices.contains(preference) else { throw RemoteVoiceError.unavailable }
        self.preference = preference
        defaults.set(preference.rawValue, forKey: "trainer.voice")
        defaults.set((gentleOnly ? .gentle : tone).rawValue, forKey: "trainer.tone")
    }
    /// Explicit setup interaction only. Never sends a synthesis request or substitutes an imitation.
    func previewSelection(_ preference: VoiceCoachPreference, tone: TrainerTone) throws {
        guard offlineOnly || previewPlayback != nil else { throw RemoteVoiceError.unavailable }
        stop(); errorMessage = nil
        try configureSelection(preference, tone: tone)
        let currentTone = self.tone
        if preference == .local {
            let now = uptime()
            speak(.init(id: UUID(), sessionID: UUID(), generation: UUID(),
                text: TrainerCueLibrary.lines(reason: .steadyRhythm, tone: currentTone)[0],
                kind: .coaching(.pacing), issuedAt: now, expiresAt: now + 6, reason: .steadyRhythm))
            explicitPreview = true
            return
        }
        let folder: String, clip: String
        switch preference {
        case .maya, .leo:
            folder = "DemoVoice/\(preference.rawValue)/\(currentTone.rawValue)"; clip = "steadyRhythm-1"
        case .local: return
        }
        guard let url = Bundle.main.url(forResource: clip, withExtension: "mp3", subdirectory: folder) else { throw RemoteVoiceError.unavailable }
        let player = try makeAudio(Data(contentsOf: url, options: .mappedIfSafe))
        try player.prepare()
        let token = UUID(); active = (UUID(), token); explicitPreview = true
        player.onFinish = { [weak self] in self?.complete(token: token) }
        output = player
        guard player.play() else { stop(); throw RemoteVoiceError.unavailable }
    }
    func speak(_ cue: VoiceCue) {
        stop(); errorMessage = nil
        let token = UUID(); active = (cue.id, token)
        if offlineOnly || previewPlayback != nil {
            guard cue.kind == .coaching(.stop) || (cue.expiresAt.map { $0 > uptime() } ?? false) else { complete(token: token); return }
            if preference == .maya && overridesNaturalPlayback {
                previewCueID = cue.id; naturalPlayback.speak(cue); return
            }
            let reason: CoachingReason = cue.kind == .coaching(.stop) ? .discomfort : (cue.reason ?? .steadyRhythm)
            let text = cueLibrary.next(reason: reason, tone: tone, exercise: exercise)
            if preference == .maya || preference == .leo {
                do {
                    guard let index = TrainerCueLibrary.lines(reason: reason, tone: tone).firstIndex(of: text),
                          let url = Bundle.main.url(forResource: "\(reason.rawValue)-\(index + 1)", withExtension: "mp3",
                              subdirectory: "DemoVoice/\(preference.rawValue)/\(tone.rawValue)") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let player = try makeAudio(Data(contentsOf: url, options: .mappedIfSafe))
                    try player.prepare()
                    guard cue.kind == .coaching(.stop) || (cue.expiresAt.map { $0 > uptime() } ?? false) else {
                        player.stop(); complete(token: token); return
                    }
                    player.onFinish = { [weak self] in self?.complete(token: token) }
                    output = player
                    guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
                } catch {
                    if cue.kind == .coaching(.stop) {
                        output?.onFinish = nil; output?.stop(); output = nil
                        localCueID = cue.id
                        local.speak(.init(id: cue.id, sessionID: cue.sessionID, generation: cue.generation,
                            text: text, kind: cue.kind, issuedAt: cue.issuedAt, expiresAt: cue.expiresAt, reason: reason))
                    } else { complete(token: token, error: error) }
                }
                return
            }
            if let system = local as? LocalVoicePlayback {
                system.preferredGender = preference == .local ? nil : (preference == .maya ? .female : .male)
                system.rate = tone == .gentle ? 0.43 : tone == .direct ? 0.50 : 0.47
            }
            localCueID = cue.id
            local.speak(.init(id: cue.id, sessionID: cue.sessionID, generation: cue.generation,
                text: text, kind: cue.kind, issuedAt: cue.issuedAt, expiresAt: cue.expiresAt, reason: cue.reason))
            return
        }
        if cue.reason == .workoutCompleted && preference != .maya {
            complete(token: token); return
        }
        if preference == .local || (cue.kind == .coaching(.stop) && preference != .maya) {
            localCueID = cue.id; local.speak(cue); return
        }
        if preference == .maya && cue.kind == .coaching(.stop) {
            previewCueID = cue.id
            naturalPlayback.speak(cue)
            return
        }
        let now = uptime(), wall = wallNow(), text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuredVoices.contains(preference), case .coaching = cue.kind,
              now.isFinite, cue.issuedAt.isFinite, cue.issuedAt <= now, let deadline = cue.expiresAt,
              deadline.isFinite, deadline > now, deadline - now <= 6, wall.timeIntervalSince1970.isFinite,
              !text.isEmpty, text.utf16.count <= 500, text.rangeOfCharacter(from: .controlCharacters) == nil else {
            complete(token: token, error: RemoteVoiceError.invalidResponse); return
        }
        let voice = preference, expiresAt = wall.addingTimeInterval(deadline - now)
        if voice == .maya {
            previewCueID = cue.id
            naturalPlayback.speak(cue)
            return
        }
        pending = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await client().audio(cue: cue, voice: voice, playbackToken: token, expiresAt: expiresAt, remaining: deadline - now)
                try Task.checkCancellation()
                guard active?.token == token, preference == voice, uptime().isFinite, uptime() >= now, uptime() < deadline else {
                    complete(token: token); return
                }
                let player = try makeAudio(audio)
                try player.prepare()
                guard active?.token == token, preference == voice, uptime().isFinite, uptime() >= now, uptime() < deadline else {
                    player.stop(); complete(token: token); return
                }
                player.onFinish = { [weak self] in self?.complete(token: token) }
                output = player
                guard player.play() else { throw RemoteVoiceError.invalidResponse }
            } catch {
                guard active?.token == token else { return }
                complete(token: token, error: error)
            }
        }
    }
    func stop() {
        explicitPreview = false
        active = nil; pending?.cancel(); pending = nil
        output?.onFinish = nil; output?.stop(); output = nil
        if localCueID != nil { localCueID = nil; local.stop() }
        if previewCueID != nil { previewCueID = nil; naturalPlayback.stop() }
    }
    private func finishedPlayback(_ id: UUID) {
        guard localCueID == id || previewCueID == id, let active, active.cueID == id else { return }
        complete(token: active.token)
    }
    private func complete(token: UUID, error: Error? = nil) {
        guard let current = active, current.token == token else { return }
        stop()
        if error != nil {
            errorMessage = previewPlayback == nil ? "Remote voice couldn’t play this cue. It wasn’t retried." : "Preview voice couldn’t play this cue. It wasn’t retried."
        }
        onFinish?(current.cueID)
    }
}

@MainActor
private final class SystemVoiceAudioOutput: NSObject, VoiceAudioOutput, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    private let player: AVAudioPlayer
    private var audioSessionActive = false
    init(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        super.init()
        guard player.format.sampleRate == 22_050, player.duration.isFinite, player.duration > 0, player.duration <= 66 else { throw RemoteVoiceError.invalidResponse }
        player.delegate = self; player.prepareToPlay()
    }
    func prepare() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try session.setActive(true)
        audioSessionActive = true
    }
    func play() -> Bool { player.play() }
    func stop() {
        player.stop()
        if audioSessionActive {
            audioSessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished(ObjectIdentifier(player)) }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { finished(ObjectIdentifier(player)) }
    private nonisolated func finished(_ identity: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, ObjectIdentifier(player) == identity else { return }
            onFinish?()
        }
    }
}
