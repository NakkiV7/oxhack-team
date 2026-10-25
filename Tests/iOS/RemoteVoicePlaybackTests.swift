import XCTest
@testable import Spottr

@MainActor
final class RemoteVoicePlaybackTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:8788")!
    private let wall = Date(timeIntervalSince1970: 1_792_915_200)

    func testArnoldIsAvailableOfflineAndLocalRequiresExplicitSelection() throws {
        let local = SilentLocalVoice()
        let cached = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, arnoldPlayback: cached, client: { XCTFail("No gateway access without explicit remote selection"); throw TestFailure.invalid }, uptime: { 2 })
        XCTAssertEqual(playback.preference, .arnold)
        playback.speak(cue())
        XCTAssertEqual(cached.spoken.count, 1)
        XCTAssertTrue(local.spoken.isEmpty)
        try playback.select(.local)
        XCTAssertThrowsError(try playback.select(.david))
        let event = cue()
        playback.speak(event)
        XCTAssertEqual(local.spoken, [event])
        playback.stop()
        XCTAssertEqual(local.stops, 1)
    }

    func testExplicitConfiguredVoiceSendsRemainingOriginalDeadlineAndPlaysOneValidatedReply() async throws {
        let played = expectation(description: "Validated audio starts")
        var requests: [URLRequest] = []
        var receivedAudio: [Data] = []
        let output = SilentRemoteAudio(onPlay: { played.fulfill() })
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { request in
            requests.append(request)
            return try self.reply(request)
        })
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), client: { client }, makeAudio: { receivedAudio.append($0); return output }, wallNow: { self.wall }, uptime: { 2 })
        try await playback.refreshVoices()
        XCTAssertEqual(playback.configuredVoices, [.david, .arnold])
        XCTAssertEqual(requests.count, 1, "Discovery must not synthesize")
        try playback.select(.david)
        XCTAssertEqual(requests.count, 1, "Selection must not synthesize")
        let event = cue()
        playback.speak(event)
        await fulfillment(of: [played], timeout: 1)
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.url?.path, "/v1/voice")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-owner")
        XCTAssertLessThanOrEqual(request.timeoutInterval, 4)
        let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["expiresAt"], timestamp(wall.addingTimeInterval(4)))
        XCTAssertEqual(body["generationID"], event.generation.uuidString)
        XCTAssertEqual(body["sessionID"], event.sessionID.uuidString)
        XCTAssertEqual(body["cueID"], event.id.uuidString)
        XCTAssertNotNil(body["playbackToken"].flatMap(UUID.init(uuidString:)))
        XCTAssertEqual(body["voice"], "david")
        XCTAssertEqual(receivedAudio, [audio])
        playback.stop()
        XCTAssertEqual(output.stops, 1)
    }

    func testControllerOptInPriorityAndImmediateLocalStopSuppressLateRemoteAudio() async throws {
        let started = expectation(description: "One explicit remote request")
        let lateAudio = expectation(description: "Cancelled audio never plays"); lateAudio.isInverted = true
        var pending: CheckedContinuation<(Data, URLResponse), Error>?
        var pendingRequest: URLRequest?
        var calls = 0
        let local = SilentLocalVoice()
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { request in
            if request.url?.path == "/v1/voices" { return try self.reply(request) }
            calls += 1; pendingRequest = request; started.fulfill()
            return try await withCheckedThrowingContinuation { pending = $0 }
        })
        let playback = RemoteVoicePlayback(local: local, client: { client }, makeAudio: { _ in SilentRemoteAudio(onPlay: { lateAudio.fulfill() }) }, wallNow: { self.wall }, uptime: { 2 })
        try await playback.refreshVoices(); try playback.select(.david)
        let controller = VoiceCuePlaybackController(playback: playback)
        let first = cue(), context = VoiceCueContext(sessionID: first.sessionID, generation: first.generation, phase: .active)
        controller.update(context: context, event: first, enabled: false, now: 2)
        controller.update(context: context, event: first, enabled: true, now: 2)
        XCTAssertEqual(calls, 0)
        let current = cue(session: first.sessionID, generation: first.generation)
        controller.update(context: context, event: current, enabled: true, now: 2)
        await fulfillment(of: [started], timeout: 1)
        controller.update(context: context, event: cue(session: first.sessionID, generation: first.generation, kind: .coaching(.rest)), enabled: true, now: 2)
        XCTAssertEqual(calls, 1, "Lower-priority cues must not queue")
        let stop = cue(session: first.sessionID, generation: first.generation, kind: .coaching(.stop), expiry: nil)
        controller.update(context: context, event: stop, enabled: true, now: 2)
        XCTAssertEqual(local.spoken, [stop], "Stop feedback cannot wait for networking")
        pending?.resume(returning: try reply(XCTUnwrap(pendingRequest)))
        await fulfillment(of: [lateAudio], timeout: 0.05)
        XCTAssertEqual(calls, 1)
    }

    func testExpiredCueNeverSendsAndLateReplyCannotExtendItsUptimeDeadline() async throws {
        var uptime = 2.0, calls = 0
        let completed = expectation(description: "Late request finishes without playback")
        let played = expectation(description: "Expired audio never plays"); played.isInverted = true
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { request in
            if request.url?.path == "/v1/voices" { return try self.reply(request) }
            calls += 1; uptime = 6.1
            return try self.reply(request)
        })
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), client: { client }, makeAudio: { _ in SilentRemoteAudio(onPlay: { played.fulfill() }) }, wallNow: { self.wall }, uptime: { uptime })
        try await playback.refreshVoices(); try playback.select(.david)
        playback.speak(cue(expiry: 2))
        XCTAssertEqual(calls, 0)
        playback.onFinish = { _ in completed.fulfill() }
        playback.speak(cue())
        await fulfillment(of: [completed, played], timeout: 0.05)
        XCTAssertEqual(calls, 1)
    }

    func testAudioPreparationCrossingOriginalDeadlineCannotStartPlayback() async throws {
        var uptime = 2.0, played = 0, synthesisRequests = 0
        let prepared = expectation(description: "Audio preparation crossed the original deadline")
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { request in
            if request.url?.path == "/v1/voice" { synthesisRequests += 1 }
            return try self.reply(request)
        })
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), client: { client }, makeAudio: { _ in
            uptime = 6.001
            prepared.fulfill()
            return SilentRemoteAudio(onPlay: { played += 1 })
        }, wallNow: { self.wall }, uptime: { uptime })
        defer { playback.stop() }
        try await playback.refreshVoices()
        try playback.select(.david)
        playback.speak(cue(expiry: 6))
        await fulfillment(of: [prepared], timeout: 1)
        XCTAssertEqual(synthesisRequests, 1)
        XCTAssertEqual(played, 0, "Decoding/preparation must not extend the original cue deadline")
    }

    func testChangedReplyIdentityExpiryFormatAndAudioAreRejectedWithoutLocalFallback() async throws {
        let mutations: [([String: String]) -> [String: String]] = [
            { var x = $0; x["sessionID"] = UUID().uuidString; return x },
            { var x = $0; x["generationID"] = UUID().uuidString; return x },
            { var x = $0; x["cueID"] = UUID().uuidString; return x },
            { var x = $0; x["playbackToken"] = UUID().uuidString; return x },
            { var x = $0; x["expiresAt"] = self.timestamp(self.wall.addingTimeInterval(6)); return x },
            { var x = $0; x["priority"] = "stop"; return x },
            { var x = $0; x["voice"] = "arnold"; return x },
            { var x = $0; x["text"] = "Different cue"; return x },
            { var x = $0; x["mimeType"] = "audio/wav"; return x },
            { var x = $0; x["audioBase64"] = "invalid!"; return x },
            { var x = $0; x["audioBase64"] = Data(repeating: 0, count: 262_145).base64EncodedString(); return x },
            { var x = $0; x["extra"] = "unexpected"; return x }
        ]
        for mutate in mutations {
            let finished = expectation(description: "Invalid reply discarded")
            let local = SilentLocalVoice()
            let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { try self.reply($0, mutate: mutate) })
            let playback = RemoteVoicePlayback(local: local, client: { client }, makeAudio: { _ in XCTFail("Invalid audio must not reach the decoder"); throw TestFailure.invalid }, wallNow: { self.wall }, uptime: { 2 })
            try await playback.refreshVoices(); try playback.select(.david)
            playback.onFinish = { _ in finished.fulfill() }
            playback.speak(cue())
            await fulfillment(of: [finished], timeout: 1)
            XCTAssertTrue(local.spoken.isEmpty)
            XCTAssertNotNil(playback.errorMessage)
        }
    }

    func testPreferenceChangeStopsAudioAndOldCompletionCannotFinishTheReplacement() async throws {
        let firstPlayed = expectation(description: "Remote audio")
        let first = SilentRemoteAudio(onPlay: { firstPlayed.fulfill() })
        let cached = SilentLocalVoice()
        var finished: [UUID] = []
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { try self.reply($0) })
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), arnoldPlayback: cached, client: { client },
            makeAudio: { _ in first }, wallNow: { self.wall }, uptime: { 2 })
        try await playback.refreshVoices(); try playback.select(.david)
        playback.onFinish = { finished.append($0) }
        playback.speak(cue()); await fulfillment(of: [firstPlayed], timeout: 1)
        let oldCompletion = first.onFinish
        try playback.select(.arnold)
        XCTAssertEqual(first.stops, 1)
        let replacement = cue()
        playback.speak(replacement)
        XCTAssertEqual(cached.spoken, [replacement])
        oldCompletion?()
        XCTAssertTrue(finished.isEmpty)
        cached.onFinish?(replacement.id)
        XCTAssertEqual(finished, [replacement.id])
    }

    func testAudioDecodeFailureDoesNotClaimPlaybackOrSilentlySwitchToLocal() async throws {
        let finished = expectation(description: "Decoder rejection")
        let local = SilentLocalVoice()
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { try self.reply($0) })
        let playback = RemoteVoicePlayback(local: local, client: { client }, makeAudio: { _ in throw TestFailure.invalid }, wallNow: { self.wall }, uptime: { 2 })
        try await playback.refreshVoices(); try playback.select(.david)
        playback.onFinish = { _ in finished.fulfill() }
        playback.speak(cue())
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(local.spoken.isEmpty)
        XCTAssertNotNil(playback.errorMessage)
    }

    func testDavidIntenseUsesOnlyConfiguredPositivePacingAndKeepsCautionFormAndRestCalm() async throws {
        var requests: [[String: String]] = []
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { request in
            if request.url?.path == "/v1/voices" {
                let data = Data(#"{"voices":[{"id":"david","name":"David","tones":["calm","intense"]}],"availability":"configured_not_verified"}"#.utf8)
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
            requests.append(try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody)))
            return try self.reply(request)
        })
        var played: XCTestExpectation?
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), client: { client }, makeAudio: { _ in SilentRemoteAudio(onPlay: { played?.fulfill() }) }, wallNow: { self.wall }, uptime: { 2 })
        try await playback.refreshVoices(); try playback.select(.david)
        for (kind, text) in [(VoiceCue.Kind.coaching(.pacing), "Keep a steady rhythm."), (.coaching(.pacing), "That rep took longer. Pause or end the set if you need to."), (.coaching(.form), "Keep a steady rhythm."), (.coaching(.rest), "Keep a steady rhythm.")] {
            played = expectation(description: "Context-appropriate clip")
            playback.speak(cue(kind: kind, text: text))
            await fulfillment(of: [played!], timeout: 1)
        }
        XCTAssertEqual(requests.map { $0["tone"] ?? "calm" }, ["intense", "calm", "calm", "calm"])
    }

    func testDavidWithoutIntenseConfigurationNeverClaimsOrRequestsShouting() async throws {
        let played = expectation(description: "Configured calm clip")
        var tone: String?
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { request in
            if request.url?.path == "/v1/voice" { tone = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))["tone"] }
            return try self.reply(request)
        })
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), client: { client }, makeAudio: { _ in SilentRemoteAudio(onPlay: { played.fulfill() }) }, wallNow: { self.wall }, uptime: { 2 })
        try await playback.refreshVoices(); try playback.select(.david)
        playback.speak(cue(kind: .coaching(.pacing), text: "Keep a steady rhythm."))
        await fulfillment(of: [played], timeout: 1)
        XCTAssertNotEqual(tone, "intense")
    }

    func testInjectedPreviewDefaultsToArnoldWithoutDiscoveryOrGatewayRequests() async throws {
        let cached = SilentLocalVoice(), local = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, previewPlayback: cached, client: {
            XCTFail("Preview voice must not access the gateway, even for discovery")
            throw TestFailure.invalid
        }, uptime: { 2 })
        defer { playback.stop() }
        XCTAssertEqual(playback.preference, .arnold)
        XCTAssertEqual(playback.configuredVoices, [.arnold])
        XCTAssertTrue(cached.spoken.isEmpty, "Selection must not autoplay")
        try await playback.refreshVoices()
        XCTAssertEqual(playback.configuredVoices, [.arnold])
        XCTAssertThrowsError(try playback.select(.david))
        let current = cue()
        playback.speak(current)
        XCTAssertEqual(cached.spoken, [current])
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testPreviewCompletionAndImmediateArnoldStopRespectCurrentCueIdentity() throws {
        let cached = SilentLocalVoice(), local = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, previewPlayback: cached, client: {
            XCTFail("Cached playback cannot contact a provider")
            throw TestFailure.invalid
        }, uptime: { 2 })
        defer { playback.stop() }
        var finished: [UUID] = []
        playback.onFinish = { finished.append($0) }
        let first = cue(), replacement = cue()
        playback.speak(first)
        cached.onFinish?(first.id)
        cached.onFinish?(first.id)
        XCTAssertEqual(finished, [first.id])
        playback.speak(replacement)
        cached.onFinish?(first.id)
        XCTAssertEqual(finished, [first.id], "A stale cached completion cannot finish its replacement")
        let stop = cue(kind: .coaching(.stop), expiry: nil)
        playback.speak(stop)
        XCTAssertEqual(cached.stops, 2, "Completion and Stop both release the active cached clip")
        XCTAssertTrue(local.spoken.isEmpty)
        XCTAssertEqual(cached.spoken.last, stop, "Stop is immediately available offline in Arnold")
        cached.onFinish?(replacement.id)
        XCTAssertEqual(finished, [first.id])
        cached.onFinish?(stop.id)
        XCTAssertEqual(finished, [first.id, stop.id])
    }

    func testPreviewMuteAndExpiredCuesCannotPlayOrReplayCachedAudio() throws {
        let cached = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), previewPlayback: cached, client: {
            XCTFail("Preview playback must remain offline")
            throw TestFailure.invalid
        }, uptime: { 2 })
        defer { playback.stop() }
        let expired = cue(expiry: 2)
        playback.speak(expired)
        XCTAssertTrue(cached.spoken.isEmpty)
        let current = cue()
        let controller = VoiceCuePlaybackController(playback: playback)
        let context = VoiceCueContext(sessionID: current.sessionID, generation: current.generation, phase: .active)
        controller.update(context: context, event: current, enabled: true, now: 2)
        XCTAssertEqual(cached.spoken, [current])
        controller.update(context: context, event: current, enabled: false, now: 2)
        XCTAssertEqual(cached.stops, 1)
        controller.update(context: context, event: current, enabled: true, now: 2)
        XCTAssertEqual(cached.spoken, [current], "Enabling feedback cannot replay an already seen cue")
    }

    func testWorkoutCompletionNeverReachesLiveGatewayOrLocalFallback() async throws {
        var synthesisRequests = 0
        let local = SilentLocalVoice()
        let forbidden = expectation(description: "Completion must not synthesize remotely")
        forbidden.isInverted = true
        let client = VoiceGatewayClient(baseURL: baseURL, token: "test-owner", transport: { request in
            if request.url?.path == "/v1/voice" { synthesisRequests += 1; forbidden.fulfill() }
            return try self.reply(request)
        })
        let playback = RemoteVoicePlayback(local: local, client: { client },
            makeAudio: { _ in SilentRemoteAudio(onPlay: {}) }, wallNow: { self.wall }, uptime: { 2 })
        defer { playback.stop() }
        try await playback.refreshVoices()
        try playback.select(.david)
        let completion = VoiceCue(id: UUID(), sessionID: UUID(), generation: UUID(), text: "Workout complete.",
            kind: .coaching(.rest), issuedAt: 2, expiresAt: 6, reason: .workoutCompleted)
        playback.speak(completion)
        await fulfillment(of: [forbidden], timeout: 0.05)
        XCTAssertEqual(synthesisRequests, 0)
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testTypedFinishedCompletionUsesOnlyInjectedPreviewPlayback() {
        let cached = SilentLocalVoice(), local = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, previewPlayback: cached, client: {
            XCTFail("Preview completion must stay offline")
            throw TestFailure.invalid
        }, uptime: { 2 })
        defer { playback.stop() }
        let completion = VoiceCue(id: UUID(), sessionID: UUID(), generation: UUID(), text: "Workout complete.",
            kind: .coaching(.rest), issuedAt: 2, expiresAt: 6, reason: .workoutCompleted)
        let controller = VoiceCuePlaybackController(playback: playback)
        controller.update(context: .init(sessionID: completion.sessionID, generation: completion.generation, phase: .finished),
                          event: completion, enabled: true, now: 2)
        XCTAssertEqual(cached.spoken, [completion])
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testArnoldWorkoutAndStopUseBundledPlaybackOutsidePreviewWithoutGateway() throws {
        let cached = SilentLocalVoice(), local = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, arnoldPlayback: cached, client: {
            XCTFail("Arnold workout cues must remain offline")
            throw TestFailure.invalid
        }, uptime: { 2 })
        try playback.select(.arnold)
        let normal = cue(), stop = cue(kind: .coaching(.stop), expiry: nil)
        playback.speak(normal)
        playback.speak(stop)
        XCTAssertEqual(cached.spoken, [normal, stop])
        XCTAssertTrue(local.spoken.isEmpty)
        XCTAssertFalse(playback.isPreview)
    }

    private var audio: Data { Data([0xff, 0xf3, 0x40, 0xc0] + Array(repeating: 0, count: 100)) }
    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private func cue(session: UUID = UUID(), generation: UUID = UUID(), kind: VoiceCue.Kind = .coaching(.form), expiry: Double? = 6, text: String = "Keep your whole body in view.") -> VoiceCue {
        .init(id: UUID(), sessionID: session, generation: generation, text: text, kind: kind, issuedAt: 0, expiresAt: expiry)
    }
    private func reply(_ request: URLRequest, mutate: (([String: String]) -> [String: String])? = nil) throws -> (Data, URLResponse) {
        let body: Data
        if request.url?.path == "/v1/voices" {
            body = Data(#"{"voices":[{"id":"david","name":"David"},{"id":"arnold","name":"Arnold"}],"availability":"configured_not_verified"}"#.utf8)
        } else {
            var json = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
            json["mimeType"] = "audio/mpeg"; json["audioBase64"] = audio.base64EncodedString()
            body = try JSONEncoder().encode(mutate?(json) ?? json)
        }
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
    private enum TestFailure: Error { case invalid }
}

@MainActor
private final class SilentLocalVoice: VoicePlayback {
    var onFinish: ((UUID) -> Void)?
    var spoken: [VoiceCue] = []
    var stops = 0
    func speak(_ cue: VoiceCue) { spoken.append(cue) }
    func stop() { stops += 1 }
}

@MainActor
private final class SilentRemoteAudio: VoiceAudioOutput {
    var onFinish: (() -> Void)?
    var stops = 0
    let onPlay: () -> Void
    init(onPlay: @escaping () -> Void) { self.onPlay = onPlay }
    func play() -> Bool { onPlay(); return true }
    func stop() { stops += 1 }
}
