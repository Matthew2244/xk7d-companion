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

    private struct Pending {
        var text: String
        var firstAt: TimeInterval
        var lastAt: TimeInterval
        var order: Int
    }

    private var pending: [String: Pending] = [:]
    private var counter = 0

    public init(settle: TimeInterval = 0.35, maxWait: TimeInterval = 2.0) {
        self.settle = settle
        self.maxWait = maxWait
    }

    public var isEmpty: Bool { pending.isEmpty }

    public func submit(key: String, text: String, at now: TimeInterval) {
        counter += 1
        if var p = pending[key] {
            p.text = text
            p.lastAt = now
            p.order = counter
            pending[key] = p
        } else {
            pending[key] = Pending(text: text, firstAt: now, lastAt: now, order: counter)
        }
    }

    /// Drop anything waiting under a key (for example, when the change turned out to be our own echo).
    public func cancel(key: String) { pending[key] = nil }

    /// Texts ready to speak at `now`, oldest change first.
    public func due(at now: TimeInterval) -> [String] {
        var ready: [(Int, String)] = []
        for (key, p) in pending {
            if now - p.lastAt >= settle || now - p.firstAt >= maxWait {
                ready.append((p.order, p.text))
                pending[key] = nil
            }
        }
        return ready.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Everything still waiting, regardless of time.
    public func flush() -> [String] {
        let out = pending.values.sorted { $0.order < $1.order }.map(\.text)
        pending.removeAll()
        return out
    }
}
