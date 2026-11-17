import AppKit
import AVFoundation

/// Speaks announcements through VoiceOver when it is running, or the Mac's own voice otherwise.
final class Announcer {
    enum Method: String, CaseIterable {
        case automatic, voiceOver, macVoice

        var title: String {
            switch self {
            case .automatic: return "Automatic (VoiceOver when it is on, otherwise the Mac's voice)"
            case .voiceOver: return "VoiceOver only"
            case .macVoice: return "The Mac's voice"
            }
        }
    }

    var method: Method {
        get { Method(rawValue: UserDefaults.standard.string(forKey: "announceMethod") ?? "") ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "announceMethod") }
    }

    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "announcementsMuted") }
        set { UserDefaults.standard.set(newValue, forKey: "announcementsMuted") }
    }

    /// Use the Mac's voice while this app is not frontmost, even when VoiceOver is on.
    var macVoiceInBackground: Bool {
        get { UserDefaults.standard.bool(forKey: "macVoiceInBackground") }
        set { UserDefaults.standard.set(newValue, forKey: "macVoiceInBackground") }
    }

    /// The Mac's voice: an identifier from `AVSpeechSynthesisVoice`, or empty for the system's
    /// Spoken Content voice (System Settings, Accessibility, Spoken Content).
    var voiceIdentifier: String {
        get { UserDefaults.standard.string(forKey: "macVoiceIdentifier") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "macVoiceIdentifier") }
    }

    /// Speaking speed of the Mac's voice. 0 means the system's Spoken Content speed.
    enum Speed: Int, CaseIterable {
        case system = 0, slow, normal, fast, faster
        var title: String {
            switch self {
            case .system: return "System speed"
            case .slow: return "Slow"
            case .normal: return "Normal"
            case .fast: return "Fast"
            case .faster: return "Very fast"
            }
        }
        var rate: Float {
            let d = AVSpeechUtteranceDefaultSpeechRate, top = AVSpeechUtteranceMaximumSpeechRate
            switch self {
            case .system, .normal: return d
            case .slow: return d * 0.8
            case .fast: return d + (top - d) * 0.25
            case .faster: return d + (top - d) * 0.5
            }
        }
    }
    var speed: Speed {
        get { Speed(rawValue: UserDefaults.standard.integer(forKey: "macVoiceSpeed")) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "macVoiceSpeed") }
    }

    /// Loudness of the Mac's voice, 25 to 100 percent.
    var volumePercent: Int {
        get { let v = UserDefaults.standard.integer(forKey: "macVoiceVolume"); return v == 0 ? 100 : min(max(v, 25), 100) }
        set { UserDefaults.standard.set(min(max(newValue, 25), 100), forKey: "macVoiceVolume") }
    }

    /// Voices for the popup: the system voice first, then installed voices in the Mac's language.
    static func voiceChoices() -> [(id: String, title: String)] {
        let lang = String((Locale.preferredLanguages.first ?? "en").prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(lang) }
            .sorted { ($0.name, $0.language) < ($1.name, $1.language) }
        return [("", "System voice")] + voices.map { ($0.identifier, "\($0.name) (\($0.language))") }
    }

    /// Test and self-test hook: when set, nothing is spoken; text goes here instead.
    var silentSink: ((String) -> Void)?
    /// Every announcement, for the history list.
    var onAnnounced: ((String) -> Void)?

    private let synth = AVSpeechSynthesizer()

    var voiceOverRunning: Bool { NSWorkspace.shared.isVoiceOverEnabled }

    /// `force` speaks even when muted (for things the user asked for, like Repeat Last).
    /// `polite` lets VoiceOver finish what it's saying first (the Windows version does the same).
    /// `historyText` is what the history list and Repeat Last keep, when it differs from what is
    /// said (a value said alone keeps its setting's name there).
    func announce(_ text: String, force: Bool = false, polite: Bool = false, historyText: String? = nil) {
        onAnnounced?(historyText ?? text)
        if let sink = silentSink { sink(text); return }
        if muted && !force { return }
        switch effectiveMethod {
        case .voiceOver: postToVoiceOver(text, polite: polite)
        case .macVoice: speak(text, polite: polite)
        case .automatic: break
        }
    }

    private var effectiveMethod: Method {
        switch method {
        case .voiceOver: return .voiceOver
        case .macVoice: return .macVoice
        case .automatic:
            if !voiceOverRunning { return .macVoice }
            if macVoiceInBackground && !NSApp.isActive { return .macVoice }
            return .voiceOver
        }
    }

    private func postToVoiceOver(_ text: String, polite: Bool) {
        let element: Any = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSApp as Any
        NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: (polite ? NSAccessibilityPriorityLevel.medium : .high).rawValue,
        ])
    }

    private func speak(_ text: String, polite: Bool) {
        // The latest value matters, not a queue of old ones.
        if synth.isSpeaking && !polite { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        let voice = voiceIdentifier.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        // With neither chosen, the system's Spoken Content voice and speed are used.
        u.prefersAssistiveTechnologySettings = voice == nil && speed == .system
        if let voice { u.voice = voice }
        if speed != .system { u.rate = speed.rate }
        u.volume = Float(volumePercent) / 100
        synth.speak(u)
    }

    /// Say a sample in the chosen voice, speed and loudness (from Settings).
    func sample() { speak("Upper: Dr. L.S., F00", polite: false) }
}
