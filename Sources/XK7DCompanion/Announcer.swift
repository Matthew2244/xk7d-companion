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

    /// Test and self-test hook: when set, nothing is spoken; text goes here instead.
    var silentSink: ((String) -> Void)?
    /// Every announcement, for the history list.
    var onAnnounced: ((String) -> Void)?

    private let synth = AVSpeechSynthesizer()

    var voiceOverRunning: Bool { NSWorkspace.shared.isVoiceOverEnabled }

    /// `force` speaks even when muted (for things the user asked for, like Repeat Last).
    /// `polite` lets VoiceOver finish what it's saying first (the Windows version does the same).
    func announce(_ text: String, force: Bool = false, polite: Bool = false) {
        onAnnounced?(text)
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
        synth.speak(AVSpeechUtterance(string: text))
    }
}
