import Foundation

/// Keeps speech usable while a knob is turning.
///
/// Each change is filed under a key (one per setting). A key speaks only after it has been quiet
/// for `settle` seconds, and only its latest text: a knob swept through forty values says one
/// thing at the end, never a queue of stale numbers. If a key keeps changing for longer than
/// `maxWait`, its current value is spoken anyway so a long sweep is not silent; after that it
/// settles again as normal.
///
/// When the same setting speaks twice in a row, with nothing else said in between and less than
/// `repeatQuietGap` apart, the second time says only the value ("6", not "Upper 8 foot: 6"), if
/// the change came with a value-only line and `sayValueOnlyOnRepeat` is on. A long sweep says the
/// name once and then numbers. Anything else spoken in between (another setting, a burst summary,
/// a status line: the owner calls `breakRepeat()` for those) gets the name back.
public final class AnnouncementCoalescer {
    public var settle: TimeInterval
    public var maxWait: TimeInterval
    /// More than this many different settings changing together (a patch recall that sends every
    /// parameter, for example) is spoken as one line: the first change and a count of the rest.
    public var burstLimit = 8
    /// Say only the value when the setting spoken last speaks again (see above). On by default.
    public var sayValueOnlyOnRepeat = true
    /// After this long without the setting speaking, its name is said again, even if nothing else
    /// was said in between: by then you may not remember which control it was.
    public static let repeatQuietGap: TimeInterval = 10

    /// One line ready to speak: what to say, and the full line (for history and Repeat Last).
    public struct Line: Equatable {
        public let text: String
        public let fullText: String
    }

    private struct Pending {
        var text: String
        var valueOnly: String?
        var firstAt: TimeInterval
        var lastAt: TimeInterval
        var order: Int
        /// Not spoken before this time (a patch change waiting for its name), unless released.
        var heldUntil: TimeInterval?
    }

    private var pending: [String: Pending] = [:]
    private var counter = 0
    /// The key spoken last and when, for value-only repeats. Nil once anything else has been said.
    private var lastSpokenKey: String?
    private var lastSpokenAt: TimeInterval = -.infinity

    public init(settle: TimeInterval = 0.35, maxWait: TimeInterval = 2.0) {
        self.settle = settle
        self.maxWait = maxWait
    }

    public var isEmpty: Bool { pending.isEmpty }

    /// File a change. `valueOnly` is what to say instead of `text` when this setting was the last
    /// thing spoken ("6" for "Upper 8 foot: 6"); nil means always say `text` in full.
    public func submit(key: String, text: String, valueOnly: String? = nil, at now: TimeInterval, holdUntil: TimeInterval? = nil) {
        counter += 1
        if var p = pending[key] {
            p.text = text
            p.valueOnly = valueOnly
            p.lastAt = now
            p.order = counter
            p.heldUntil = holdUntil
            pending[key] = p
        } else {
            pending[key] = Pending(text: text, valueOnly: valueOnly, firstAt: now, lastAt: now, order: counter, heldUntil: holdUntil)
        }
    }

    /// Change the text of something still waiting and stop holding it, keeping its place and its
    /// timing (a patch change whose name has just arrived). False if it has already been spoken.
    @discardableResult
    public func release(key: String, text: String) -> Bool {
        guard var p = pending[key] else { return false }
        p.text = text
        p.valueOnly = nil
        p.heldUntil = nil
        pending[key] = p
        return true
    }

    /// Drop everything waiting under keys that start with this (all drawbars, say).
    public func cancel(keyPrefix: String) {
        for k in pending.keys where k.hasPrefix(keyPrefix) { pending[k] = nil }
    }

    /// Whether something is waiting under a key.
    public func isPending(key: String) -> Bool { pending[key] != nil }

    private func held(_ p: Pending, _ now: TimeInterval) -> Bool {
        guard let h = p.heldUntil else { return false }
        return now < h
    }

    /// Drop anything waiting under a key (for example, when the change turned out to be our own echo).
    public func cancel(key: String) { pending[key] = nil }

    /// Something other than this coalescer's lines was said (a status message, a line said at
    /// once, the app's own confirmation): the next change says its setting's name again.
    public func breakRepeat() { lastSpokenKey = nil }

    /// Texts ready to speak at `now`, oldest change first.
    public func due(at now: TimeInterval) -> [String] { dueLines(at: now).map(\.text) }

    /// Lines ready to speak at `now`, oldest change first, each with its full text.
    public func dueLines(at now: TimeInterval) -> [Line] {
        if pending.count > burstLimit {
            // Wait for the whole burst to go quiet, then say it once.
            let newest = pending.values.map(\.lastAt).max() ?? now
            let oldest = pending.values.map(\.firstAt).min() ?? now
            guard now - newest >= settle || now - oldest >= maxWait else { return [] }
            guard !pending.values.contains(where: { held($0, now) }) else { return [] }
            let texts = pending.values.sorted { $0.order < $1.order }.map(\.text)
            pending.removeAll()
            lastSpokenKey = nil
            let line = Self.summary(texts)
            return [Line(text: line, fullText: line)]
        }
        var ready: [(key: String, p: Pending)] = []
        for (key, p) in pending {
            if !held(p, now), now - p.lastAt >= settle || now - p.firstAt >= maxWait {
                ready.append((key, p))
                pending[key] = nil
            }
        }
        return ready.sorted { $0.p.order < $1.p.order }.map { spoken(key: $0.key, $0.p, at: now) }
    }

    /// The line for one setting, value only if it repeats the setting spoken last.
    private func spoken(key: String, _ p: Pending, at now: TimeInterval) -> Line {
        let repeats = sayValueOnlyOnRepeat && key == lastSpokenKey && now - lastSpokenAt < Self.repeatQuietGap
        lastSpokenKey = key
        lastSpokenAt = now
        if repeats, let short = p.valueOnly { return Line(text: short, fullText: p.text) }
        return Line(text: p.text, fullText: p.text)
    }

    /// "Upper: patch U05, and 40 more settings changed."
    static func summary(_ texts: [String]) -> String {
        guard let first = texts.first else { return "" }
        let rest = texts.count - 1
        return rest == 0 ? first : "\(first), and \(rest) more setting\(rest == 1 ? "" : "s") changed"
    }

    /// Everything still waiting, regardless of time.
    public func flush() -> [String] {
        let out = pending.values.sorted { $0.order < $1.order }.map(\.text)
        pending.removeAll()
        lastSpokenKey = nil
        return out
    }
}
