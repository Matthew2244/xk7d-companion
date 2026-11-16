import Foundation

/// Keeps speech usable while a knob is turning.
///
/// Each change is filed under a key (one per setting). A key speaks only after it has been quiet
/// for `settle` seconds, and only its latest text: a knob swept through forty values says one
/// thing at the end, never a queue of stale numbers. If a key keeps changing for longer than
/// `maxWait`, its current value is spoken anyway so a long sweep is not silent; after that it
/// settles again as normal.
public final class AnnouncementCoalescer {
    public var settle: TimeInterval
    public var maxWait: TimeInterval
    /// More than this many different settings changing together (a patch recall that sends every
    /// parameter, for example) is spoken as one line: the first change and a count of the rest.
    public var burstLimit = 8

    private struct Pending {
        var text: String
        var firstAt: TimeInterval
        var lastAt: TimeInterval
        var order: Int
        /// Not spoken before this time (a patch change waiting for its name), unless released.
        var heldUntil: TimeInterval?
    }

    private var pending: [String: Pending] = [:]
    private var counter = 0

    public init(settle: TimeInterval = 0.35, maxWait: TimeInterval = 2.0) {
        self.settle = settle
        self.maxWait = maxWait
    }

    public var isEmpty: Bool { pending.isEmpty }

    public func submit(key: String, text: String, at now: TimeInterval, holdUntil: TimeInterval? = nil) {
        counter += 1
        if var p = pending[key] {
            p.text = text
            p.lastAt = now
            p.order = counter
            p.heldUntil = holdUntil
            pending[key] = p
        } else {
            pending[key] = Pending(text: text, firstAt: now, lastAt: now, order: counter, heldUntil: holdUntil)
        }
    }

    /// Change the text of something still waiting and stop holding it, keeping its place and its
    /// timing (a patch change whose name has just arrived). False if it has already been spoken.
    @discardableResult
    public func release(key: String, text: String) -> Bool {
        guard var p = pending[key] else { return false }
        p.text = text
        p.heldUntil = nil
        pending[key] = p
        return true
    }

    /// Whether something is waiting under a key.
    public func isPending(key: String) -> Bool { pending[key] != nil }

    private func held(_ p: Pending, _ now: TimeInterval) -> Bool {
        guard let h = p.heldUntil else { return false }
        return now < h
    }

    /// Drop anything waiting under a key (for example, when the change turned out to be our own echo).
    public func cancel(key: String) { pending[key] = nil }

    /// Texts ready to speak at `now`, oldest change first.
    public func due(at now: TimeInterval) -> [String] {
        if pending.count > burstLimit {
            // Wait for the whole burst to go quiet, then say it once.
            let newest = pending.values.map(\.lastAt).max() ?? now
            let oldest = pending.values.map(\.firstAt).min() ?? now
            guard now - newest >= settle || now - oldest >= maxWait else { return [] }
            guard !pending.values.contains(where: { held($0, now) }) else { return [] }
            let texts = pending.values.sorted { $0.order < $1.order }.map(\.text)
            pending.removeAll()
            return [Self.summary(texts)]
        }
        var ready: [(Int, String)] = []
        for (key, p) in pending {
            if !held(p, now), now - p.lastAt >= settle || now - p.firstAt >= maxWait {
                ready.append((p.order, p.text))
                pending[key] = nil
            }
        }
        return ready.sorted { $0.0 < $1.0 }.map(\.1)
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
        return out
    }
}
