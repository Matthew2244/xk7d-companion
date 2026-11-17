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
/// text. If a key keeps changing for longer than MaxWait, its current value is spoken anyway.
///
/// When the same setting speaks twice in a row, with nothing else said in between and less than
/// RepeatQuietGap apart, the second time says only the value ("6", not "Upper 8 foot: 6"), if the
/// change came with a value-only line and SayValueOnlyOnRepeat is on. A long sweep says the name once
/// and then numbers. Anything else spoken in between (another setting, a burst summary, a status
/// line: the owner calls BreakRepeat for those) gets the name back.</summary>
public sealed class AnnouncementCoalescer
{
    public double Settle { get; set; }
    public double MaxWait { get; set; }
    /// <summary>More than this many different settings changing together is spoken as one line.</summary>
    public int BurstLimit { get; set; } = 8;
    /// <summary>Say only the value when the setting spoken last speaks again (see above). On by default.</summary>
    public bool SayValueOnlyOnRepeat { get; set; } = true;
    /// <summary>After this long without the setting speaking, its name is said again, even if nothing
    /// else was said in between: by then you may not remember which control it was.</summary>
    public const double RepeatQuietGap = 10;

    /// <summary>One line ready to speak: what to say, and the full line (for history and Repeat Last).</summary>
    public readonly record struct Line(string Text, string FullText);

    sealed class Pending
    {
        public required string Text;
        public string? ValueOnly;
        public double FirstAt, LastAt;
        public int Order;
        /// <summary>Not spoken before this time (a patch change waiting for its name), unless released.</summary>
        public double? HeldUntil;
    }

    readonly Dictionary<string, Pending> pending = new();
    int counter;
    /// <summary>The key spoken last and when, for value-only repeats. Null once anything else has been said.</summary>
    string? lastSpokenKey;
    double lastSpokenAt = double.NegativeInfinity;

    public AnnouncementCoalescer(double settle = 0.35, double maxWait = 2.0) { Settle = settle; MaxWait = maxWait; }

    public bool IsEmpty => pending.Count == 0;

    /// <summary>File a change. valueOnly is what to say instead of text when this setting was the last
    /// thing spoken ("6" for "Upper 8 foot: 6"); null means always say text in full.</summary>
    public void Submit(string key, string text, double now, double? holdUntil = null, string? valueOnly = null)
    {
        counter++;
        if (pending.TryGetValue(key, out var p)) { p.Text = text; p.ValueOnly = valueOnly; p.LastAt = now; p.Order = counter; p.HeldUntil = holdUntil; }
        else pending[key] = new Pending { Text = text, ValueOnly = valueOnly, FirstAt = now, LastAt = now, Order = counter, HeldUntil = holdUntil };
    }

    /// <summary>Change the text of something still waiting and stop holding it, keeping its place and
    /// timing. False if it has already been spoken.</summary>
    public bool Release(string key, string text)
    {
        if (!pending.TryGetValue(key, out var p)) return false;
        p.Text = text;
        p.ValueOnly = null;
        p.HeldUntil = null;
        return true;
    }

    /// <summary>Drop everything waiting under keys that start with this (all drawbars, say).</summary>
    public void CancelPrefix(string keyPrefix)
    {
        foreach (var k in pending.Keys.Where(k => k.StartsWith(keyPrefix, StringComparison.Ordinal)).ToList()) pending.Remove(k);
    }

    /// <summary>Whether something is waiting under a key.</summary>
    public bool IsPending(string key) => pending.ContainsKey(key);

    static bool Held(Pending p, double now) => p.HeldUntil is { } h && now < h;

    /// <summary>Drop anything waiting under a key (for example, when it turned out to be our own echo).</summary>
    public void Cancel(string key) => pending.Remove(key);

    /// <summary>Something other than this coalescer's lines was said (a status message, a line said at
    /// once, the app's own confirmation): the next change says its setting's name again.</summary>
    public void BreakRepeat() => lastSpokenKey = null;

    /// <summary>Texts ready to speak at now, oldest change first.</summary>
    public List<string> Due(double now) => DueLines(now).Select(l => l.Text).ToList();

    /// <summary>Lines ready to speak at now, oldest change first, each with its full text.</summary>
    public List<Line> DueLines(double now)
    {
        if (pending.Count > BurstLimit)
        {
            // Wait for the whole burst to go quiet, then say it once.
            var newest = pending.Values.Max(p => p.LastAt);
            var oldest = pending.Values.Min(p => p.FirstAt);
            if (!(now - newest >= Settle || now - oldest >= MaxWait)) return new List<Line>();
            if (pending.Values.Any(p => Held(p, now))) return new List<Line>();
            var texts = pending.Values.OrderBy(p => p.Order).Select(p => p.Text).ToList();
            pending.Clear();
            lastSpokenKey = null;
            var summary = Summary(texts);
            return new List<Line> { new(summary, summary) };
        }
        var ready = new List<(string Key, Pending P)>();
        foreach (var (key, p) in pending.ToList())
        {
            if (!Held(p, now) && (now - p.LastAt >= Settle || now - p.FirstAt >= MaxWait))
            {
                ready.Add((key, p));
                pending.Remove(key);
            }
        }
        return ready.OrderBy(r => r.P.Order).Select(r => Spoken(r.Key, r.P, now)).ToList();
    }

    /// <summary>The line for one setting, value only if it repeats the setting spoken last.</summary>
    Line Spoken(string key, Pending p, double now)
    {
        var repeats = SayValueOnlyOnRepeat && key == lastSpokenKey && now - lastSpokenAt < RepeatQuietGap;
        lastSpokenKey = key;
        lastSpokenAt = now;
        if (repeats && p.ValueOnly is { } valueOnly) return new Line(valueOnly, p.Text);
        return new Line(p.Text, p.Text);
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
        lastSpokenKey = null;
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
