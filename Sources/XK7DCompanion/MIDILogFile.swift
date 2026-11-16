import Foundation
import XK7DCore

/// The MIDI log: everything that goes to and from the organ, written to a text file someone can
/// send back. Off unless turned on (Help, Keep a MIDI Log). Notes and the expression pedal are
/// counted, not written (MIDILogger).
final class MIDILogFile {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/\(AppIdentity.name)", isDirectory: true)
    static let file = folder.appendingPathComponent("MIDI Log.txt")
    static let previous = folder.appendingPathComponent("MIDI Log (previous).txt")
    /// When the file passes this size it becomes the previous log and a new one starts.
    static let limit = 20_000_000

    private let logger = MIDILogger()
    private var handle: FileHandle?
    private let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "keepMIDILog") }
        set {
            UserDefaults.standard.set(newValue, forKey: "keepMIDILog")
            if newValue { note("MIDI log started, \(AppIdentity.name) \(AppIdentity.version)") } else { note("MIDI log stopped"); close() }
        }
    }

    func midi(incoming: Bool, _ bytes: [UInt8]) {
        guard isOn else { return }
        for line in logger.lines(incoming: incoming, bytes) { write(line) }
    }

    /// A line of the app's own, such as asking the organ for a patch name.
    func note(_ text: String) {
        guard isOn else { return }
        write("--- " + text)
    }

    private func write(_ line: String) {
        guard let h = openHandle() else { return }
        h.write(Data((timeFormat.string(from: Date()) + " " + line + "\n").utf8))
        if (try? h.offset()) ?? 0 > UInt64(Self.limit) {
            close()
            try? FileManager.default.removeItem(at: Self.previous)
            try? FileManager.default.moveItem(at: Self.file, to: Self.previous)
        }
    }

    private func openHandle() -> FileHandle? {
        if let handle { return handle }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Self.file.path) {
            FileManager.default.createFile(atPath: Self.file.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: Self.file)
        _ = try? handle?.seekToEnd()
        return handle
    }

    private func close() {
        try? handle?.close()
        handle = nil
    }
}
