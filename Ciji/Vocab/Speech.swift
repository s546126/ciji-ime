import AVFoundation

/// Reads English glosses (or a translation) aloud with the system voice.
final class Speech {
    static let shared = Speech()
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String, language: String = "en-US") {
        let clean = text
            .replacingOccurrences(of: "≈", with: "")
            .replacingOccurrences(of: " + ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synth.speak(utterance)
    }

    /// First sense of a gloss, e.g. "hello; hi" -> "hello".
    static func headword(_ gloss: String) -> String {
        var g = String(gloss.split(separator: ";").first ?? "")
        if let paren = g.firstIndex(of: "(") { g = String(g[..<paren]) }
        return g.trimmingCharacters(in: .whitespaces)
    }
}
