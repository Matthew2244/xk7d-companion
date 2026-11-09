// Ports of Sources/XK7DCore/NRPNDecoder.swift, Coalescer.swift and PortPolicy.swift.
namespace XK7D.Core;

/// <summary>Follows CC 99 / 98 / 6 / 38 on one channel and reports complete NRPN values.
/// One-byte parameters are complete on CC 6; two-byte ones wait for CC 38. A later CC 38 on its
/// own updates the low bits of the last value, as MIDI allows.</summary>
public sealed class NrpnDecoder
{
    public readonly record struct Value(byte Msb, byte Lsb, int Raw);

    byte? msb, lsb;
    int? dataMsb;
    readonly Func<byte, byte, int?> length;

    public NrpnDecoder(Func<byte, byte, int?> length) { this.length = length; }

    /// <summary>Feed one control change; returns a value when one is complete.</summary>
    public Value? Handle(int controller, int value)
    {
        switch (controller)
        {
            case 99:
                msb = (byte)value; dataMsb = null;
                if (value == 127) { msb = null; lsb = null; }
                break;
            case 98:
                lsb = (byte)value; dataMsb = null;
                if (value == 127) { msb = null; lsb = null; }
                break;
            case 6:
            {
                if (msb is not { } m || lsb is not { } l || length(m, l) is not { } len) { dataMsb = null; return null; }
                if (len == 2) { dataMsb = value; }
                else { dataMsb = null; return new Value(m, l, value); }
                break;
            }
            case 38:
            {
                if (msb is not { } m || lsb is not { } l || dataMsb is not { } hi || length(m, l) != 2) return null;
                return new Value(m, l, hi << 7 | value);
            }
            case 101: case 100:
                // RPN selected: NRPN data entry no longer applies.
                msb = null; lsb = null; dataMsb = null;
                break;
            case 121:
                // Reset All Controllers: "NRPN: unset" (p. 176).
                msb = null; lsb = null; dataMsb = null;
                break;
        }
        return null;
    }
}

/// <summary>Keeps speech usable while a knob is turning. Each change is filed under a key (one per
/// setting). A key speaks only after it has been quiet for Settle seconds, and only its latest
/// text. If a key keeps changing for longer than MaxWait, its current value is spoken anyway.</summary>
public sealed class AnnouncementCoalescer
{
    public double Settle { get; set; }
    public double MaxWait { get; set; }
    /// <summary>More than this many different settings changing together is spoken as one line.</summary>
    public int BurstLimit { get; set; } = 8;

    sealed class Pending
    {
        public required string Text;
        public double FirstAt, LastAt;
        public int Order;
    }

    readonly Dictionary<string, Pending> pending = new();
    int counter;

    public AnnouncementCoalescer(double settle = 0.35, double maxWait = 2.0) { Settle = settle; MaxWait = maxWait; }

    public bool IsEmpty => pending.Count == 0;

    public void Submit(string key, string text, double now)
    {
        counter++;
        if (pending.TryGetValue(key, out var p)) { p.Text = text; p.LastAt = now; p.Order = counter; }
        else pending[key] = new Pending { Text = text, FirstAt = now, LastAt = now, Order = counter };
    }

    /// <summary>Drop anything waiting under a key (for example, when it turned out to be our own echo).</summary>
    public void Cancel(string key) => pending.Remove(key);

    /// <summary>Texts ready to speak at now, oldest change first.</summary>
    public List<string> Due(double now)
    {
        if (pending.Count > BurstLimit)
        {
            // Wait for the whole burst to go quiet, then say it once.
            var newest = pending.Values.Max(p => p.LastAt);
            var oldest = pending.Values.Min(p => p.FirstAt);
            if (!(now - newest >= Settle || now - oldest >= MaxWait)) return new List<string>();
            var texts = pending.Values.OrderBy(p => p.Order).Select(p => p.Text).ToList();
            pending.Clear();
            return new List<string> { Summary(texts) };
        }
        var ready = new List<(int, string)>();
        foreach (var (key, p) in pending.ToList())
        {
            if (now - p.LastAt >= Settle || now - p.FirstAt >= MaxWait)
            {
                ready.Add((p.Order, p.Text));
                pending.Remove(key);
            }
        }
        return ready.OrderBy(r => r.Item1).Select(r => r.Item2).ToList();
    }

    /// <summary>"Upper: patch U05, and 40 more settings changed."</summary>
    public static string Summary(IReadOnlyList<string> texts)
    {
        if (texts.Count == 0) return "";
        var rest = texts.Count - 1;
        return rest == 0 ? texts[0] : $"{texts[0]}, and {rest} more setting{(rest == 1 ? "" : "s")} changed";
    }

    /// <summary>Everything still waiting, regardless of time.</summary>
    public List<string> Flush()
    {
        var output = pending.Values.OrderBy(p => p.Order).Select(p => p.Text).ToList();
        pending.Clear();
        return output;
    }
}

/// <summary>What the "Organ" choice offers.</summary>
public abstract record PortChoice
{
    public sealed record None : PortChoice;
    public sealed record Simulator : PortChoice;
    public sealed record Device(string Name) : PortChoice;

    public static readonly PortChoice NotConnected = new None();
    public static readonly PortChoice BuiltInSimulator = new Simulator();

    public string Title => this switch
    {
        None => "Not connected",
        Simulator => "Built-in simulator (not a real organ)",
        Device d => d.Name,
        _ => "",
    };
}

/// <summary>Which port to use at launch and when ports come and go. No MIDI API here, so it can be tested.</summary>
public static class PortPolicy
{
    /// <summary>Loose match for the organ's USB port: "XK-7", "XK-7D", "Hammond", "Suzuki", any spacing or case.</summary>
    public static bool LooksLikeOrgan(string name)
    {
        var n = name.ToLowerInvariant().Replace(" ", "", StringComparison.Ordinal).Replace("-", "", StringComparison.Ordinal);
        return n.Contains("xk7", StringComparison.Ordinal) || n.Contains("hammond", StringComparison.Ordinal)
            || n.Contains("suzuki", StringComparison.Ordinal);
    }

    /// <summary>At launch. remembered is a port name, "simulator", "none" or null. A plugged-in
    /// organ beats a remembered simulator.</summary>
    public static PortChoice LaunchChoice(string? remembered, IReadOnlyList<string> devices)
    {
        if (remembered is { } r && r != "simulator" && r != "none" && devices.Contains(r)) return new PortChoice.Device(r);
        if (devices.FirstOrDefault(LooksLikeOrgan) is { } organ) return new PortChoice.Device(organ);
        if (remembered == "simulator") return PortChoice.BuiltInSimulator;
        return PortChoice.NotConnected;
    }

    public abstract record Change
    {
        public sealed record Nothing : Change;
        /// <summary>The chosen organ's port went away.</summary>
        public sealed record Lost(string Name) : Change;
        /// <summary>The chosen organ's port came back; connect to it again.</summary>
        public sealed record Back(string Name) : Change;
        /// <summary>Nothing was chosen and an organ (or the remembered port) appeared.</summary>
        public sealed record Found(string Name) : Change;
    }

    /// <summary>When MIDI ports appear or disappear. missing is true while the chosen device is
    /// known to be gone, so the loss is reported once.</summary>
    public static Change AfterPortsChanged(PortChoice choice, bool missing, string? remembered, IReadOnlyList<string> devices)
    {
        switch (choice)
        {
            case PortChoice.Device d:
            {
                var present = devices.Contains(d.Name);
                if (!present && !missing) return new Change.Lost(d.Name);
                if (present && missing) return new Change.Back(d.Name);
                return new Change.Nothing();
            }
            case PortChoice.None:
                // "none" means the person chose Disconnect; respect that.
                if (remembered == "none") return new Change.Nothing();
                if (remembered is { } r && r != "simulator" && devices.Contains(r)) return new Change.Found(r);
                if (devices.FirstOrDefault(LooksLikeOrgan) is { } organ) return new Change.Found(organ);
                return new Change.Nothing();
            default:
                return new Change.Nothing();
        }
    }

    /// <summary>Why a change can't be sent to the organ right now, as a sentence to say, or null when it
    /// can. hasOutput is false when nothing is open; canSend is false when the port could only be
    /// opened for listening, so a change would go nowhere while the app said it was sent.</summary>
    public static string? CannotSend(PortChoice choice, bool hasOutput, bool missing, bool canSend)
    {
        if (missing) return "The organ is disconnected, so nothing was sent. Check the USB cable and that the organ is on.";
        if (choice is PortChoice.None || !hasOutput) return "Not connected. Choose the organ or the simulator first.";
        if (!canSend) return "The app can listen to this MIDI port but can't send to it, so nothing was sent. Choose the organ again, or check that no other program is using it.";
        return null;
    }
}
