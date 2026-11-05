import AVFoundation

@MainActor
final class LocalVoicePlayback: NSObject, VoicePlayback, AVSpeechSynthesizerDelegate {
    var onFinish: ((UUID) -> Void)?
    var preferredGender: AVSpeechSynthesisVoiceGender?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private let synthesizer: AVSpeechSynthesizer
    private var current: (cueID: UUID, utterance: AVSpeechUtterance)?
    private var completing: [ObjectIdentifier: AVSpeechUtterance] = [:]

    init(synthesizer: AVSpeechSynthesizer? = nil) {
        self.synthesizer = synthesizer ?? AVSpeechSynthesizer()
        super.init()
        self.synthesizer.usesApplicationAudioSession = false
        self.synthesizer.delegate = self
    }

    func speak(_ cue: VoiceCue) {
        if current != nil { stop() }
        let utterance = AVSpeechUtterance(string: cue.text)
        if let preferredGender {
            let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") && $0.gender == preferredGender }
            utterance.voice = voices.sorted { $0.quality.rawValue > $1.quality.rawValue }.first
        }
        utterance.rate = rate
        current = (cue.id, utterance)
        synthesizer.speak(utterance)
    }

    func stop() {
        if let current { completing[ObjectIdentifier(current.utterance)] = current.utterance }
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completed(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completed(ObjectIdentifier(utterance))
    }

    private nonisolated func completed(_ utteranceID: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            completing.removeValue(forKey: utteranceID)
            guard let current, ObjectIdentifier(current.utterance) == utteranceID else { return }
            self.current = nil
            onFinish?(current.cueID)
        }
    }
}
