import AVFoundation
import Speech
import Observation
import SwiftUI

@MainActor protocol SpokenRepListening: AnyObject {
    var isListening: Bool { get }
    var message: String? { get }
    func start(initialCount: Int, onCount: @escaping @MainActor (Int) -> Void)
    func stop()
}

@MainActor @Observable
final class SpokenRepInput: SpokenRepListening {
    private(set) var isListening = false
    private(set) var message: String?
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var counter = SpokenRepCounter()
    private var hasTap = false
    private var audioActive = false

    func start(initialCount: Int, onCount: @escaping @MainActor (Int) -> Void) {
        stop()
        let token = UUID(); generation = token
        message = "Checking on-device speech access…"
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                guard authorization == .authorized else { self.message = "Speech access is off. You can enter reps manually."; return }
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        guard granted else { self.message = "Microphone access is off. You can enter reps manually."; return }
                        self.begin(initialCount: initialCount, token: token, onCount: onCount)
                    }
                }
            }
        }
    }
    private func begin(initialCount: Int, token: UUID, onCount: @escaping @MainActor (Int) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_GB")),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            message = "Offline speech isn’t available on this iPhone. Use manual reps instead."; return
        }
        do {
            self.recognizer = recognizer
            let engine = AVAudioEngine()
            self.engine = engine
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: [])
            try audio.setActive(true); audioActive = true
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request
            counter = SpokenRepCounter(initialCount: initialCount)
            let node = engine.inputNode, format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasTap = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                Task { @MainActor in
                    guard let self, self.generation == token, self.isListening else { return }
                    if let text, let count = self.counter.consume(text) { onCount(count) }
                    if error != nil || final {
                        self.stop()
                        self.message = "Listening ended. Your count is saved. Tap to continue."
                    }
                }
            }
            engine.prepare(); try engine.start()
            isListening = true
            message = "Say each completed rep number, starting with \(initialCount + 1)."
        } catch {
            stop(); message = "Couldn’t start the microphone. Your count is safe. Use manual reps or try again."
        }
    }
    func stop() {
        generation = UUID(); isListening = false
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        engine?.stop()
        if hasTap { engine?.inputNode.removeTap(onBus: 0); hasTap = false }
        engine = nil; recognizer = nil
        if audioActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); audioActive = false }
        message = nil
    }
}

struct SpokenRepControls: View {
    let store: TrainingStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if store.spokenReps.isListening { store.spokenReps.stop() }
                else { store.startSpokenReps() }
            } label: {
                Label(store.spokenReps.isListening ? "Stop listening" : "Count with my voice", systemImage: store.spokenReps.isListening ? "mic.fill" : "mic")
            }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("spoken-rep-toggle")
            if let message = store.spokenReps.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Text("Optional English on-device recognition. Spoken counts are self-reported. Coach audio stays quiet while listening.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
