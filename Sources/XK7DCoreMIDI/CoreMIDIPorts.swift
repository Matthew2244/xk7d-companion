import CoreMIDI
import Foundation
import XK7DCore

/// One MIDI endpoint as the user sees it.
public struct MIDIPortInfo: Hashable, Sendable {
    public let uniqueID: Int32
    public let name: String
    public let isVirtualSimulator: Bool

    /// Loose match for the organ's USB port: "XK-7", "XK-7D", "Hammond", any spacing or case.
    public var looksLikeXK7: Bool { PortPolicy.looksLikeOrgan(name) }
}

public enum CoreMIDIError: Error, CustomStringConvertible {
    case status(String, OSStatus)
    case notFound(String)

    public var description: String {
        switch self {
        case .status(let what, let s): return "\(what) failed (CoreMIDI error \(s))."
        case .notFound(let n): return "The MIDI port \(n) is not available."
        }
    }
}

func endpointName(_ e: MIDIEndpointRef) -> String {
    var cf: Unmanaged<CFString>?
    if MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &cf) == noErr, let s = cf?.takeRetainedValue() {
        return s as String
    }
    if MIDIObjectGetStringProperty(e, kMIDIPropertyName, &cf) == noErr, let s = cf?.takeRetainedValue() {
        return s as String
    }
    return "Unnamed port"
}

func uniqueID(_ obj: MIDIObjectRef) -> Int32 {
    var id: Int32 = 0
    MIDIObjectGetIntegerProperty(obj, kMIDIPropertyUniqueID, &id)
    return id
}

/// Builds a packet list for any length of message (SysEx included) and calls `body` with it.
func withPacketList(_ bytes: [UInt8], _ body: (UnsafePointer<MIDIPacketList>) -> Void) {
    let size = 1024 + bytes.count * 2
    let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
    defer { raw.deallocate() }
    let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
    var packet = MIDIPacketListInit(list)
    var offset = 0
    while offset < bytes.count {
        let chunk = Array(bytes[offset..<min(offset + 256, bytes.count)])
        packet = chunk.withUnsafeBufferPointer { MIDIPacketListAdd(list, size, packet, 0, chunk.count, $0.baseAddress!) }
        offset += chunk.count
    }
    body(list)
}

func bytes(of list: UnsafePointer<MIDIPacketList>) -> [UInt8] {
    // Read each packet's bytes straight from memory: a received packet can be longer than the
    // 256-byte tuple Swift declares for MIDIPacket.data (long SysEx).
    let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!
    var out: [UInt8] = []
    for packet in list.unsafeSequence() {
        let len = Int(packet.pointee.length)
        let base = UnsafeRawPointer(packet).advanced(by: dataOffset)
        out.append(contentsOf: UnsafeRawBufferPointer(start: base, count: len))
    }
    return out
}

/// The app's CoreMIDI client: lists ports, connects to one source and one destination, sends and receives.
public final class CoreMIDIConnection: MIDIOutput {
    public static let simulatorPortName = "XK-7D Simulator (not a real organ)"

    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0
    private let receiveQueue: DispatchQueue

    /// Bytes from the connected source, delivered on `receiveQueue`.
    public var onReceive: (([UInt8]) -> Void)?
    /// Called on the main queue when ports appear or disappear.
    public var onSetupChanged: (() -> Void)?

    public private(set) var sourceName: String?
    public private(set) var destinationName: String?

    public init(name: String = "XK-7D Companion", receiveQueue: DispatchQueue = .main) throws {
        self.receiveQueue = receiveQueue
        var status = MIDIClientCreateWithBlock(name as CFString, &client) { [weak self] notice in
            if notice.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.onSetupChanged?() }
            }
        }
        guard status == noErr else { throw CoreMIDIError.status("Creating the MIDI client", status) }
        status = MIDIInputPortCreateWithBlock(client, "Input" as CFString, &inPort) { [weak self] list, _ in
            let b = bytes(of: list)
            guard let self, !b.isEmpty else { return }
            self.receiveQueue.async { self.onReceive?(b) }
        }
        guard status == noErr else { throw CoreMIDIError.status("Creating the MIDI input", status) }
        status = MIDIOutputPortCreate(client, "Output" as CFString, &outPort)
        guard status == noErr else { throw CoreMIDIError.status("Creating the MIDI output", status) }
    }

    deinit {
        MIDIClientDispose(client)
    }

    public static func sources() -> [MIDIPortInfo] {
        (0..<MIDIGetNumberOfSources()).map { i in
            let e = MIDIGetSource(i)
            let n = endpointName(e)
            return MIDIPortInfo(uniqueID: uniqueID(e), name: n, isVirtualSimulator: n == simulatorPortName)
        }
    }

    public static func destinations() -> [MIDIPortInfo] {
        (0..<MIDIGetNumberOfDestinations()).map { i in
            let e = MIDIGetDestination(i)
            let n = endpointName(e)
            return MIDIPortInfo(uniqueID: uniqueID(e), name: n, isVirtualSimulator: n == simulatorPortName)
        }
    }

    static func endpoint(source: Bool, id: Int32) -> MIDIEndpointRef? {
        let count = source ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let e = source ? MIDIGetSource(i) : MIDIGetDestination(i)
            if uniqueID(e) == id { return e }
        }
        return nil
    }

    /// Listen to `source` and send to `destination`. Either may be nil to leave that side unconnected.
    public func connect(source: MIDIPortInfo?, destination dest: MIDIPortInfo?) throws {
        disconnect()
        if let source {
            guard let e = Self.endpoint(source: true, id: source.uniqueID) else { throw CoreMIDIError.notFound(source.name) }
            let status = MIDIPortConnectSource(inPort, e, nil)
            guard status == noErr else { throw CoreMIDIError.status("Listening to \(source.name)", status) }
            connectedSource = e
            sourceName = source.name
        }
        if let dest {
            guard let e = Self.endpoint(source: false, id: dest.uniqueID) else { throw CoreMIDIError.notFound(dest.name) }
            destination = e
            destinationName = dest.name
        }
    }

    public func disconnect() {
        if connectedSource != 0 { MIDIPortDisconnectSource(inPort, connectedSource) }
        connectedSource = 0
        destination = 0
        sourceName = nil
        destinationName = nil
    }

    public var isConnected: Bool { connectedSource != 0 || destination != 0 }

    public func send(_ bytes: [UInt8]) {
        guard destination != 0, !bytes.isEmpty else { return }
        withPacketList(bytes) { list in _ = MIDISend(outPort, destination, list) }
    }
}

/// Publishes a SimulatedOrgan as a pair of virtual MIDI ports, so the app (or any MIDI app)
/// talks to it over real CoreMIDI exactly as it would to the organ's USB port.
public final class VirtualSimulatorPorts {
    public let organ: SimulatedOrgan
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private let queue: DispatchQueue

    public init(organ: SimulatedOrgan, name: String = CoreMIDIConnection.simulatorPortName,
                queue: DispatchQueue = .main) throws {
        self.organ = organ
        self.queue = queue
        var status = MIDIClientCreateWithBlock("XK-7D Simulator" as CFString, &client, nil)
        guard status == noErr else { throw CoreMIDIError.status("Creating the simulator", status) }
        status = MIDISourceCreate(client, name as CFString, &source)
        guard status == noErr else { throw CoreMIDIError.status("Creating the simulator's output", status) }
        status = MIDIDestinationCreateWithBlock(client, name as CFString, &destination) { [weak self] list, _ in
            let b = bytes(of: list)
            guard let self, !b.isEmpty else { return }
            self.queue.async { self.organ.receive(b) }
        }
        guard status == noErr else { throw CoreMIDIError.status("Creating the simulator's input", status) }
        organ.send = { [weak self] bytes in self?.emit(bytes) }
    }

    deinit {
        MIDIEndpointDispose(source)
        MIDIEndpointDispose(destination)
        MIDIClientDispose(client)
    }

    public var sourceID: Int32 { uniqueID(source) }
    public var destinationID: Int32 { uniqueID(destination) }

    private func emit(_ bytes: [UInt8]) {
        withPacketList(bytes) { list in _ = MIDIReceived(source, list) }
    }
}
