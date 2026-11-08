import Foundation

/// What the "Organ" popup offers.
public enum PortChoice: Equatable, Sendable {
    case none
    case simulator
    case device(String)

    public var title: String {
        switch self {
        case .none: return "Not connected"
        case .simulator: return "Built-in simulator (not a real organ)"
        case .device(let n): return n
        }
    }
}

/// Which port to use at launch and when ports come and go. No CoreMIDI here, so it can be tested.
public enum PortPolicy {
    /// Loose match for the organ's USB port: "XK-7", "XK-7D", "Hammond", "Suzuki", any spacing or case.
    public static func looksLikeOrgan(_ name: String) -> Bool {
        let n = name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        return n.contains("xk7") || n.contains("hammond") || n.contains("suzuki")
    }

    /// At launch. `remembered` is what was chosen last time: a port name, "simulator", "none" or nil.
    /// A real organ that is plugged in beats a remembered simulator, so a session spent trying the
    /// simulator at home can't leave the app deaf to the organ at the next gig.
    public static func launchChoice(remembered: String?, devices: [String]) -> PortChoice {
        if let r = remembered, r != "simulator", r != "none", devices.contains(r) { return .device(r) }
        if let organ = devices.first(where: looksLikeOrgan) { return .device(organ) }
        if remembered == "simulator" { return .simulator }
        return .none
    }

    public enum Change: Equatable, Sendable {
        /// Nothing to do.
        case nothing
        /// The chosen organ's port went away.
        case lost(String)
        /// The chosen organ's port came back; connect to it again.
        case back(String)
        /// Nothing was chosen and an organ (or the remembered port) appeared; connect to it.
        case found(String)
    }

    /// When MIDI ports appear or disappear. `missing` is true while the chosen device is known to
    /// be gone, so the loss is reported once, not on every later change to the MIDI setup.
    public static func afterPortsChanged(choice: PortChoice, missing: Bool, remembered: String?,
                                         devices: [String]) -> Change {
        switch choice {
        case .device(let name):
            let present = devices.contains(name)
            if !present && !missing { return .lost(name) }
            if present && missing { return .back(name) }
            return .nothing
        case .none:
            // "none" means the person chose Disconnect; respect that.
            guard remembered != "none" else { return .nothing }
            if let r = remembered, r != "simulator", devices.contains(r) { return .found(r) }
            if let organ = devices.first(where: looksLikeOrgan) { return .found(organ) }
            return .nothing
        case .simulator:
            return .nothing
        }
    }
}
