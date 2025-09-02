import Foundation
import AVFoundation
import Combine

final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()

    // User-facing controls
    @Published var enabled: Bool = true
    @Published var voiceIdentifier: String? = AVSpeechSynthesisVoice.speechVoices().first?.identifier
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate    // ~0.5
    @Published var volume: Float = 0.9                                 // 0.0...1.0
    @Published var minGapSeconds: TimeInterval = 20                    // cooldown

    private let synth = AVSpeechSynthesizer()
    private var lastSpokenAt: Date = .distantPast

    override init() {
        super.init()
        synth.delegate = self
        // (nothing else to apply up-front; AVSpeech uses utterance-scoped props)
    }

    /// Speak a short nudge if enabled, not in cooldown.
    func maybeSpeakNudge(_ text: String) {
        guard enabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSpokenAt) >= minGapSeconds else { return }

        let line = Self.trimForSpeech(text)
        guard !line.isEmpty else { return }

        // Avoid overlap
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }

        let utt = AVSpeechUtterance(string: line)

        // Voice
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            utt.voice = v
        } else {
            // Choose a sensible default English voice if present
            let fallback = AVSpeechSynthesisVoice.speechVoices()
                .first { $0.language.hasPrefix("en") }
            utt.voice = fallback
        }

        // Rate on macOS: 0.0 ... 1.0, with AVSpeechUtteranceDefaultSpeechRate around 0.5.
        // Keep a natural range.
        utt.rate = max(0.35, min(rate, 0.65))

        // Volume: 0.0 ... 1.0
        utt.volume = max(0.0, min(volume, 1.0))

        // Optional: keep pitch normal (0.5 ... 2.0); tweak if you expose it.
        utt.pitchMultiplier = 1.0

        synth.speak(utt)
        lastSpokenAt = now
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    // MARK: - Helpers

    private static func trimForSpeech(_ s: String) -> String {
        var t = s
        // Remove parenthetical URL bits and extra punctuation/whitespace
        t = t.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "—", with: "— ")
        t = t.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 120 { t = String(t.prefix(120)) }
        return t
    }

    // MARK: - AVSpeechSynthesizerDelegate (optional hooks)

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // You could log or adjust cooldown here if desired.
    }

    // Convenience for UI
    static var availableVoices: [(id: String, name: String, lang: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { (id: $0.identifier, name: $0.name, lang: $0.language) }
            .sorted { $0.name < $1.name }
    }
}
