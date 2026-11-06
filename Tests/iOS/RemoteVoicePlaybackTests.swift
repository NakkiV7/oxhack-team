import AVFoundation
import XCTest
@testable import Spottr

@MainActor
final class RemoteVoicePlaybackTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:8788")!
    private let wall = Date(timeIntervalSince1970: 1_792_915_200)

    func testExplicitCoachAndTonePreviewsUseNaturalBankWithoutSystemImitation() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let local = SilentLocalVoice()
        var recordings: [Data] = []
        let playback = RemoteVoicePlayback(local: local, offlineOnly: true, defaults: defaults,
            client: { XCTFail("Setup previews must stay offline"); throw TestFailure.invalid },
            makeAudio: { recordings.append($0); return SilentRemoteAudio(onPlay: {}) }, uptime: { 2 })
        try playback.previewSelection(.maya, tone: .gentle)
        try playback.previewSelection(.leo, tone: .direct)
        XCTAssertEqual(recordings.count, 2)
        XCTAssertNotEqual(recordings.first, recordings.last)
        XCTAssertTrue(local.spoken.isEmpty)
        try playback.previewSelection(.david, tone: .encouraging)
        XCTAssertEqual(recordings.count, 3, "Goggins uses its existing bundled start recording")
        XCTAssertTrue(local.spoken.isEmpty, "A named recorded voice cannot silently become a system imitation")
        try playback.previewSelection(.local, tone: .gentle)
        XCTAssertEqual(local.spoken.count, 1)
        playback.stop()
    }

    func testOriginalCoachesPlayBundledRecordingsInsteadOfSystemSpeechOrNetworking() throws {
        let local = SilentLocalVoice()
        var recordings: [Data] = []
        let playback = RemoteVoicePlayback(local: local, offlineOnly: true,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            client: { XCTFail("Offline coaching cannot access the gateway"); throw TestFailure.invalid },
            makeAudio: { recordings.append($0); return SilentRemoteAudio(onPlay: {}) }, uptime: { 2 })
        for coach in [VoiceCoachPreference.maya, .leo] {
            try playback.select(coach)
            playback.speak(cue())
            playback.stop()
        }
        XCTAssertTrue(local.spoken.isEmpty, "Original coaches must use their natural recordings")
        XCTAssertEqual(recordings.count, 2)
        if recordings.count == 2 { XCTAssertNotEqual(recordings[0], recordings[1]) }
    }

    func testNaturalCoachingRotatesEightPhrasesAndUsesTheSelectedStyle() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("gentle", forKey: "trainer.tone")
        var recordings: [Data] = []
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), offlineOnly: true, defaults: defaults,
            makeAudio: { recordings.append($0); return SilentRemoteAudio(onPlay: {}) }, uptime: { 2 })
        for _ in 0..<9 { playback.speak(cue(reason: .steadyRhythm)) }
        XCTAssertEqual(recordings.count, 9)
        if recordings.count == 9 {
            XCTAssertEqual(Set(recordings.prefix(8)).count, 8)
            XCTAssertEqual(recordings.first, recordings.last)
        }
        defaults.set("direct", forKey: "trainer.tone")
        playback.speak(cue(reason: .steadyRhythm))
        XCTAssertEqual(recordings.count, 10)
        if recordings.count == 10 { XCTAssertNotEqual(recordings[0], recordings[9]) }
        playback.stop()
    }

    func testNaturalTrackingSentenceFinishesAfterItsDeadlineAndStopCanInterrupt() {
        var time = 2.0
        var outputs: [SilentRemoteAudio] = []
        var plays = 0
        let local = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, offlineOnly: true,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, makeAudio: { _ in
                let output = SilentRemoteAudio(onPlay: { plays += 1 })
                outputs.append(output)
                return output
            }, uptime: { time })
        let controller = VoiceCuePlaybackController(playback: playback)
        let tracking = cue(reason: .tracking)
        let context = VoiceCueContext(sessionID: tracking.sessionID, generation: tracking.generation, phase: .active)
        controller.update(context: context, event: tracking, enabled: true, now: time)
        time = 9
        controller.update(context: context, event: cue(session: tracking.sessionID, generation: tracking.generation,
            expiry: 12, reason: .alignment), enabled: true, now: time)
        XCTAssertEqual(plays, 1)
        XCTAssertEqual(outputs.first?.stops, 0)
        let staleCompletion = outputs.first?.onFinish
        staleCompletion?()
        XCTAssertEqual(controller.completedTrackingPrompt?.id, tracking.id)
        let secondTracking = cue(session: tracking.sessionID, generation: tracking.generation, expiry: 12, reason: .tracking)
        controller.update(context: context, event: secondTracking, enabled: true, now: time)
        let stop = cue(session: tracking.sessionID, generation: tracking.generation, kind: .coaching(.stop), expiry: nil)
        controller.update(context: context, event: stop, enabled: true, now: time)
        XCTAssertEqual(plays, 3)
        XCTAssertEqual(outputs.count, 3)
        if outputs.count == 3 {
            XCTAssertEqual(outputs[1].stops, 1)
            staleCompletion?()
            XCTAssertEqual(outputs[2].stops, 0, "An old completion cannot cancel a new safety cue")
            controller.update(context: context, event: stop, enabled: false, now: time)
            XCTAssertEqual(outputs[2].stops, 1)
        }
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testNaturalRecordingPreparationCannotExtendFreshnessAndMissingSafetyUsesLocalSpeech() {
        var time = 2.0
        var plays = 0
        var decodingFails = false
        let local = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, offlineOnly: true,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, makeAudio: { _ in
                if decodingFails { throw TestFailure.invalid }
                time = 9
                return SilentRemoteAudio(onPlay: { plays += 1 })
            }, uptime: { time })
        playback.speak(cue(reason: .alignment))
        XCTAssertEqual(plays, 0)
        XCTAssertTrue(local.spoken.isEmpty)
        decodingFails = true
        playback.speak(cue(kind: .coaching(.stop), expiry: nil))
        XCTAssertEqual(local.spoken.count, 1)
        XCTAssertEqual(local.spoken.first?.kind, .coaching(.stop))
        XCTAssertEqual(local.spoken.first?.reason, .discomfort)
        XCTAssertTrue(local.spoken.first?.text.contains("Stop") == true)
    }

    func testNaturalVoiceUsesSpokenPlaybackAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default)
        let playback = RemoteVoicePlayback(offlineOnly: true,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, uptime: { 2 })
        defer { playback.stop() }
        playback.speak(cue(reason: .alignment))
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
        XCTAssertTrue(session.categoryOptions.contains(.duckOthers))
    }

    func testAudioActivationCannotStartExpiredNaturalCue() throws {
        var time = 2.0
        var plays = 0
        let output = SilentRemoteAudio(onPlay: { plays += 1 }, onPrepare: { time = 9 })
        let local = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, offlineOnly: true,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, makeAudio: { _ in output }, uptime: { time })
        playback.speak(cue(reason: .alignment))
        XCTAssertEqual(plays, 0, "Session activation must not extend the cue's starting deadline")
        XCTAssertEqual(output.stops, 1, "An expired prepared output must release its audio session")
        XCTAssertTrue(local.spoken.isEmpty)
    }

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

    func testStartedArnoldVisibilityClipFinishesBeyondItsStartDeadline() async throws {
        let cached = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), arnoldPlayback: cached, client: {
            XCTFail("Visibility audio stays offline")
            throw TestFailure.invalid
        }, uptime: { 1.99 })
        defer { playback.stop() }
        let event = VoiceCue(id: UUID(), sessionID: UUID(), generation: UUID(), text: "Keep your whole body visible.",
            kind: .coaching(.form), issuedAt: 0, expiresAt: 2, reason: .tracking)
        playback.speak(event)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(cached.spoken, [event])
        XCTAssertEqual(cached.stops, 0, "The deadline governs starting, not cutting off a playing visibility clip")
        cached.onFinish?(event.id)
        XCTAssertEqual(cached.stops, 1)
    }

    func testAllStartedArnoldSentencesFinishBeyondTheirStartDeadline() async throws {
        let cached = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), arnoldPlayback: cached, uptime: { 1.99 })
        let event = VoiceCue(id: UUID(), sessionID: UUID(), generation: UUID(), text: "Keep control.",
            kind: .coaching(.pacing), issuedAt: 0, expiresAt: 2, reason: .steadyRhythm)
        playback.speak(event)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(cached.stops, 0)
        cached.onFinish?(event.id)
        XCTAssertEqual(cached.stops, 1)
    }

    func testCoachChangeCancelsControllerSoFreshCoachingCanStart() throws {
        let cached = SilentLocalVoice(), local = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: local, arnoldPlayback: cached, uptime: { 2 })
        let controller = VoiceCuePlaybackController(playback: playback)
        let first = cue(reason: .tracking)
        let context = VoiceCueContext(sessionID: first.sessionID, generation: first.generation, phase: .active)
        controller.update(context: context, event: first, enabled: true, now: 2)
        try playback.select(.local)
        XCTAssertFalse(controller.isTrackingPromptPlaying)
        let fresh = cue(session: first.sessionID, generation: first.generation, reason: .alignment)
        controller.update(context: context, event: fresh, enabled: true, now: 3)
        XCTAssertEqual(local.spoken, [fresh])
        controller.cancel()
    }

    func testInterruptionClearsControllerAndOldSpeechCannotRestart() async {
        let cached = SilentLocalVoice()
        let playback = RemoteVoicePlayback(local: SilentLocalVoice(), arnoldPlayback: cached, uptime: { 2 })
        let controller = VoiceCuePlaybackController(playback: playback)
        let first = cue(reason: .tracking)
        let context = VoiceCueContext(sessionID: first.sessionID, generation: first.generation, phase: .active)
        controller.update(context: context, event: first, enabled: true, now: 2)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(controller.isTrackingPromptPlaying)
        XCTAssertEqual(cached.stops, 1)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        for _ in 0..<10 { await Task.yield() }
        controller.update(context: context, event: first, enabled: true, now: 3)
        XCTAssertEqual(cached.spoken.count, 1)
        let fresh = cue(session: first.sessionID, generation: first.generation, reason: .tracking)
        controller.update(context: context, event: fresh, enabled: true, now: 3)
        XCTAssertEqual(cached.spoken.count, 2)
        controller.cancel()
    }

    private var audio: Data { Data([0xff, 0xf3, 0x40, 0xc0] + Array(repeating: 0, count: 100)) }
    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private func cue(session: UUID = UUID(), generation: UUID = UUID(), kind: VoiceCue.Kind = .coaching(.form), expiry: Double? = 6, text: String = "Keep your whole body in view.", reason: CoachingReason? = nil) -> VoiceCue {
        .init(id: UUID(), sessionID: session, generation: generation, text: text, kind: kind, issuedAt: 0, expiresAt: expiry, reason: reason)
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
    let onPrepare: () throws -> Void
    init(onPlay: @escaping () -> Void, onPrepare: @escaping () throws -> Void = {}) {
        self.onPlay = onPlay; self.onPrepare = onPrepare
    }
    func prepare() throws { try onPrepare() }
    func play() -> Bool { onPlay(); return true }
    func stop() { stops += 1 }
}

extension RemoteVoicePlaybackTests {
    func testGenericMovementFilteringKeepsTheOriginalMP3VariantNumbers() throws {
        for exercise in [Exercise.plank, .frontArmRaise] {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            defaults.set("direct", forKey: "trainer.tone")
            var recordings: [Data] = []
            let playback = RemoteVoicePlayback(local: SilentLocalVoice(), offlineOnly: true, defaults: defaults,
                makeAudio: { recordings.append($0); return SilentRemoteAudio(onPlay: {}) }, uptime: { 2 })
            playback.exercise = exercise
            for _ in 0..<4 { playback.speak(cue(reason: .steadyRhythm)) }
            let expected = try [2,6,7,8].map { number in
                try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "steadyRhythm-\(number)", withExtension: "mp3", subdirectory: "DemoVoice/maya/direct")))
            }
            XCTAssertEqual(recordings, expected)
            playback.stop()
        }
    }
}
