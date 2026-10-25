import AVFoundation
import Foundation
import Observation

enum VoiceCoachPreference: String, CaseIterable, Identifiable, Sendable {
    case local, david, arnold
    var id: String { rawValue }
    var title: String { switch self { case .local: "Local voice"; case .david: "David"; case .arnold: "Arnold" } }
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
        guard tones == ["calm"] || id == .david && tones == ["calm", "intense"] else { throw RemoteVoiceError.invalidResponse }
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
    func audio(cue: VoiceCue, voice: VoiceCoachPreference, playbackToken: UUID, expiresAt: Date, remaining: Double, intense: Bool) async throws -> Data {
        guard case .coaching(let priority) = cue.kind, priority != .stop else { throw RemoteVoiceError.invalidResponse }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var body = ["generationID": cue.generation.uuidString, "sessionID": cue.sessionID.uuidString, "cueID": cue.id.uuidString,
                    "playbackToken": playbackToken.uuidString, "voice": voice.rawValue, "priority": priority.rawValue,
                    "text": cue.text.trimmingCharacters(in: .whitespacesAndNewlines), "expiresAt": formatter.string(from: expiresAt)]
        if intense { body["tone"] = "intense" }
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
    func play() -> Bool
    func stop()
}

@MainActor @Observable
final class RemoteVoicePlayback: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    private(set) var preference: VoiceCoachPreference = .arnold
    private(set) var configuredVoices: [VoiceCoachPreference] = [.arnold]
    private(set) var errorMessage: String?
    var isPreview: Bool { previewPlayback != nil }
    private let local: VoicePlayback
    private let previewPlayback: VoicePlayback?
    private let arnoldPlayback: VoicePlayback
    private let client: @MainActor () throws -> VoiceGatewayClient
    private let makeAudio: @MainActor (Data) throws -> VoiceAudioOutput
    private let wallNow: () -> Date
    private let uptime: () -> Double
    private var availability: [VoiceCoachAvailability] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var active: (cueID: UUID, token: UUID)?
    @ObservationIgnored private var output: VoiceAudioOutput?
    @ObservationIgnored private var localCueID: UUID?
    @ObservationIgnored private var previewCueID: UUID?

    init(local: VoicePlayback? = nil, previewPlayback: VoicePlayback? = nil, arnoldPlayback: VoicePlayback? = nil, client: @escaping @MainActor () throws -> VoiceGatewayClient = { try VoiceGatewayClient.configured() },
         makeAudio: (@MainActor (Data) throws -> VoiceAudioOutput)? = nil,
         wallNow: @escaping () -> Date = Date.init, uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.local = local ?? LocalVoicePlayback(); self.previewPlayback = previewPlayback
        self.arnoldPlayback = previewPlayback ?? arnoldPlayback ?? DemoVoicePlayback()
        self.client = client; self.makeAudio = makeAudio ?? { try SystemVoiceAudioOutput(data: $0) }
        self.wallNow = wallNow; self.uptime = uptime
        if previewPlayback != nil { preference = .arnold; configuredVoices = [.arnold] }
        self.local.onFinish = { [weak self] id in self?.finishedPlayback(id) }
        self.arnoldPlayback.onFinish = { [weak self] id in self?.finishedPlayback(id) }
    }
    func refreshVoices() async throws {
        guard previewPlayback == nil else { return }
        let options = try await client().voices()
        availability = options; configuredVoices = options.map(\.id)
        if !configuredVoices.contains(.arnold) { configuredVoices.append(.arnold) }
    }
    func select(_ preference: VoiceCoachPreference) throws {
        guard preference == .local || configuredVoices.contains(preference) else { throw RemoteVoiceError.unavailable }
        guard self.preference != preference else { return }
        stop(); self.preference = preference; errorMessage = nil
    }
    func speak(_ cue: VoiceCue) {
        stop(); errorMessage = nil
        let token = UUID(); active = (cue.id, token)
        if cue.reason == .workoutCompleted && preference != .arnold {
            complete(token: token); return
        }
        if preference == .local || (cue.kind == .coaching(.stop) && preference != .arnold) {
            localCueID = cue.id; local.speak(cue); return
        }
        if preference == .arnold && cue.kind == .coaching(.stop) {
            previewCueID = cue.id
            arnoldPlayback.speak(cue)
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
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(deadline - now)) } catch { return }
            self?.complete(token: token, error: RemoteVoiceError.invalidResponse)
        }
        if voice == .arnold {
            previewCueID = cue.id
            arnoldPlayback.speak(cue)
            return
        }
        // Existing pacing cautions remain calm. Only a short positive rhythm cue can use the separately configured voice.
        let intense = voice == .david && cue.kind == .coaching(.pacing) && text == "Keep a steady rhythm." &&
            availability.contains { $0.id == .david && $0.tones.contains("intense") }
        pending = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await client().audio(cue: cue, voice: voice, playbackToken: token, expiresAt: expiresAt, remaining: deadline - now, intense: intense)
                try Task.checkCancellation()
                guard active?.token == token, preference == voice, uptime().isFinite, uptime() >= now, uptime() < deadline else {
                    complete(token: token); return
                }
                let player = try makeAudio(audio)
                guard active?.token == token, preference == voice, uptime().isFinite, uptime() >= now, uptime() < deadline else {
                    complete(token: token); return
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
        active = nil; pending?.cancel(); pending = nil; expiry?.cancel(); expiry = nil
        output?.onFinish = nil; output?.stop(); output = nil
        if localCueID != nil { localCueID = nil; local.stop() }
        if previewCueID != nil { previewCueID = nil; arnoldPlayback.stop() }
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
    init(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        super.init()
        guard player.format.sampleRate == 22_050, player.duration.isFinite, player.duration > 0, player.duration <= 66 else { throw RemoteVoiceError.invalidResponse }
        player.delegate = self; player.prepareToPlay()
    }
    func play() -> Bool { player.play() }
    func stop() { player.stop() }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished(ObjectIdentifier(player)) }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { finished(ObjectIdentifier(player)) }
    private nonisolated func finished(_ identity: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, ObjectIdentifier(player) == identity else { return }
            onFinish?()
        }
    }
}
