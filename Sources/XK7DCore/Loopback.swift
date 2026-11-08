import Foundation

/// Connects an OrganSession and a SimulatedOrgan in-process, with no CoreMIDI.
/// Delivery is asynchronous on the given queue (like real MIDI) unless `synchronous` is set,
/// which tests use to step through exchanges deterministically.
public final class LoopbackLink: MIDIOutput {
    public let organ: SimulatedOrgan
    public weak var session: OrganSession?
    public var synchronous: Bool
    private let queue: DispatchQueue

    public init(session: OrganSession, organ: SimulatedOrgan, synchronous: Bool = false, queue: DispatchQueue = .main) {
        self.session = session
        self.organ = organ
        self.synchronous = synchronous
        self.queue = queue
        session.output = self
        organ.send = { [weak self] bytes in self?.deliverToSession(bytes) }
    }

    public func send(_ bytes: [UInt8]) {
        if synchronous { organ.receive(bytes) } else { queue.async { [organ] in organ.receive(bytes) } }
    }

    private func deliverToSession(_ bytes: [UInt8]) {
        if synchronous { session?.receive(bytes) } else { queue.async { [weak self] in self?.session?.receive(bytes) } }
    }
}
