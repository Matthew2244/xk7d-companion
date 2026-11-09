// Ports of Sources/XK7DCore/SimulatedOrgan.swift and Loopback.swift.
namespace XK7D.Core;

/// <summary>A stand-in XK-7D for testing and demonstrating without the real organ. It follows the
/// protocol as the manual describes it and as this app implements it. Where the manual is silent
/// (the contents of a dump, whether the organ echoes, how fast it transmits) its behaviour is an
/// assumption, listed in HANDOFF.md.</summary>
public sealed class SimulatedOrgan
{
    public ParameterDatabase Database { get; }
    public byte DeviceId { get; set; }
    /// <summary>Upper channel, 0-based, used for NRPN and drawbars in both directions.</summary>
    public int UpperChannel { get; set; }
    public int LowerChannel { get; set; } = 1;
    public int PedalChannel { get; set; } = 2;
    /// <summary>Where the simulator's MIDI goes (the app's input).</summary>
    public Action<byte[]>? Send { get; set; }
    /// <summary>Called whenever the simulator's stored state changes, for its window.</summary>
    public Action<string>? OnChange { get; set; }

    readonly Dictionary<Address, int> values = new();
    readonly Dictionary<Address, string> texts = new();
    readonly List<byte[]> received = new();
    public IReadOnlyDictionary<Address, int> Values => values;
    public IReadOnlyDictionary<Address, string> Texts => texts;
    /// <summary>Every message received, for tests and the simulator window.</summary>
    public IReadOnlyList<byte[]> Received => received;
    public int Acknowledgements { get; private set; }

    readonly MidiByteParser parser = new();
    readonly NrpnDecoder nrpn;
    readonly Dictionary<int, int> bank = new();

    public SimulatedOrgan(ParameterDatabase? database = null)
    {
        Database = database ?? ParameterDatabase.Shared;
        var db = Database;
        nrpn = new NrpnDecoder((m, l) => db.SettingForNrpn(m, l)?.Parameter.Length);
        LoadDefaults();
    }

    int? SystemValue(byte b3, byte b4) => values.TryGetValue(new Address(0, 0, 0, b3, b4), out var v) ? v : null;

    public IndividualMode IndividualMode
    {
        get
        {
            var v = SystemValue(0x0C, 0x03) ?? 1;
            return v is >= 0 and <= 2 ? (IndividualMode)v : IndividualMode.Nrpn;
        }
        set => values[new Address(0, 0, 0, 0x0C, 0x03)] = (int)value;
    }

    public bool TransmitsDrawbars
    {
        get => (SystemValue(0x0C, 0x05) ?? 1) == 1;
        set => values[new Address(0, 0, 0, 0x0C, 0x05)] = value ? 1 : 0;
    }

    public bool TransmitsProgramChange
    {
        get => (SystemValue(0x0C, 0x04) ?? 1) == 1;
        set => values[new Address(0, 0, 0, 0x0C, 0x04)] = value ? 1 : 0;
    }

    /// <summary>Sensible starting values: the centre of signed ranges, 440 Hz, drawbars 888000000, names.</summary>
    public void LoadDefaults()
    {
        values.Clear(); texts.Clear();
        foreach (var p in Database.Parameters.Where(p => !p.HasIndices))
        {
            var s = new Setting(p);
            switch (p.Kind.Type)
            {
                case ValueType.Text:
                    texts[s.Address] = p.ManualCategory.Contains("Upper", StringComparison.Ordinal) ? "Simulator Upper"
                        : p.ManualCategory.Contains("Lower", StringComparison.Ordinal) ? "Simulator Lower" : "Simulator";
                    break;
                case ValueType.Number:
                    values[s.Address] = p.Kind.Zero >= p.Kind.Min && p.Kind.Zero <= p.Kind.Max ? p.Kind.Zero : p.Kind.Min;
                    break;
                case ValueType.Balance: values[s.Address] = p.Kind.Center; break;
                case ValueType.Note: values[s.Address] = 60; break;
                default: values[s.Address] = p.RawMin; break;
            }
        }
        var upper = new[] { 8, 8, 8, 0, 0, 0, 0, 0, 0 };
        var lower = new[] { 0, 0, 8, 4, 0, 0, 0, 0, 0 };
        for (var i = 0; i < 9; i++)
        {
            values[new Address(0, 0, 1, 1, (byte)i)] = upper[i];
            values[new Address(0, 0, 1, 2, (byte)i)] = lower[i];
        }
        values[new Address(0, 0, 1, 3, 0)] = 5;
        values[new Address(0, 0, 1, 3, 1)] = 2;
        // The Basic MIDI template (p. 175).
        values[new Address(0, 0, 0, 0x0C, 0x01)] = 64;
        values[new Address(0, 0, 0, 0x0C, 0x02)] = 1;
        IndividualMode = IndividualMode.Nrpn;
        TransmitsProgramChange = true;
        TransmitsDrawbars = true;
        var chans = new[] { 0, 1, 2, 0, 1, 2 };
        for (var i = 0; i < chans.Length; i++) values[new Address(0, 0, 0, 0x0D, (byte)i)] = chans[i];
        values[new Address(0, 0, 0, 0x0B, 0x04)] = 0;             // Favorites Off (p. 185 default)
    }

    public int? Value(Setting s)
    {
        if (values.TryGetValue(s.Address, out var v)) return v;
        return s.Parameter.HasIndices ? s.Parameter.RawMin : null;
    }

    // Receiving (what the app sends)

    public void Receive(IEnumerable<byte> bytes)
    {
        foreach (var m in parser.Feed(bytes))
        {
            received.Add(m.Bytes);
            switch (m)
            {
                case MidiMessage.Sysex s: HandleSysEx(s.Data); break;
                case MidiMessage.ControlChange c:
                {
                    if (c.Controller == 0) bank[c.Channel] = c.Value;
                    if (c.Channel != UpperChannel || nrpn.Handle(c.Controller, c.Value) is not { } n
                        || Database.SettingForNrpn(n.Msb, n.Lsb) is not { } st || IndividualMode != IndividualMode.Nrpn) continue;
                    Store(st, n.Raw);
                    break;
                }
            }
        }
    }

    bool Accepts(byte dev) => dev == DeviceId || dev == 0x7F;

    void HandleSysEx(byte[] b)
    {
        switch (XK7Inbound.Decode(b))
        {
            case XK7Inbound.DataSet ds:
            {
                if (!Accepts(ds.Device)) return;   // "The receiving is ignored by unmatched Device ID" (p. 157)
                var addr = ds.Address;
                var rest = ds.Data.AsMemory();
                while (!rest.IsEmpty && Database.SettingAt(addr) is { } s && rest.Length >= s.Parameter.Length)
                {
                    var chunk = rest[..s.Parameter.Length].ToArray();
                    rest = rest[s.Parameter.Length..];
                    if (s.Parameter.IsText)
                    {
                        texts[s.Address] = TextCodec.Decode(chunk);
                        OnChange?.Invoke($"{s.SpokenName} set to {texts[s.Address]}");
                    }
                    else
                    {
                        Store(s, s.Parameter.Clamp(XK7SysEx.Value(chunk)));
                    }
                    addr = new Address(addr.B0, addr.B1, addr.B2, addr.B3, unchecked((byte)(addr.B4 + 1)));
                }
                break;
            }
            case XK7Inbound.IdentityRequest ir:
                if (!Accepts(ir.Device)) return;
                Transmit(XK7SysEx.IdentityReply(DeviceId));
                break;
            case XK7Inbound.DumpRequest dr:
                if (!Accepts(dr.Device)) return;
                SendDump(dr.Type);
                break;
            case XK7Inbound.NrpnSwitch ns:
                if (!Accepts(ns.Device) || ns.Mode > 2) return;
                IndividualMode = (IndividualMode)ns.Mode;
                OnChange?.Invoke($"Individual parameters set to {new[] { "Off", "NRPN", "SysEx" }[ns.Mode]}");
                break;
            case XK7Inbound.Acknowledge:
                Acknowledgements++;
                break;
        }
    }

    void Store(Setting s, int raw)
    {
        values[s.Address] = raw;
        OnChange?.Invoke($"{s.SpokenName} set to {s.Parameter.Display(raw)}");
    }

    // Dump

    /// <summary>Packets framed exactly as p. 177 describes. Their contents are this simulator's own
    /// invention (the manual does not publish the dump layout).</summary>
    void SendDump(byte type)
    {
        (byte, int)[] plan = type switch
        {
            0x07 => new[] { ((byte)0x07, XK7SysEx.TemporaryPackets), ((byte)0x08, XK7SysEx.AdjustPackets) },
            0x0A => new[] { ((byte)0x0A, XK7SysEx.SystemPackets) },
            _ => Array.Empty<(byte, int)>(),
        };
        if (plan.Length == 0) return;
        var stream = new List<byte>();
        foreach (var (addr, v) in values.OrderBy(kv => kv.Key))
        {
            stream.AddRange(addr.Bytes);
            stream.Add((byte)((v >> 7) & 0x7F));
            stream.Add((byte)(v & 0x7F));
        }
        var offset = 0;
        foreach (var (t, count) in plan)
        {
            for (var n = 0; n < count; n++)
            {
                var chunk = new byte[64];
                for (var i = 0; i < 64 && offset + i < stream.Count; i++) chunk[i] = stream[offset + i];
                offset += 64;
                Transmit(XK7SysEx.DataPacket(DeviceId, t, n, chunk));
            }
        }
    }

    // Panel actions (what a player does on the organ)

    /// <summary>A change made on the organ's panel or menu, sent as the Individual Parameters setting says.</summary>
    public void PanelChange(Setting s, int raw)
    {
        raw = s.Parameter.Clamp(raw);
        Store(s, raw);
        if (DrawbarPartOf(s) is { } part)
        {
            // A drawbar move also goes out as its control change.
            if (TransmitsDrawbars)
                Transmit(new MidiMessage.ControlChange(UpperChannel, DrawbarCC.Controller(part.Part, part.Index), DrawbarCC.Value(raw)).Bytes);
            return;
        }
        TransmitParameter(s, raw);
    }

    public void PanelText(Setting s, string text)
    {
        texts[s.Address] = TextCodec.Decode(TextCodec.Encode(text, s.Parameter.Length));
        OnChange?.Invoke($"{s.SpokenName} set to {text}");
        if (IndividualMode == IndividualMode.Sysex) Transmit(XK7SysEx.DataSet(DeviceId, s, text));
    }

    void TransmitParameter(Setting s, int raw)
    {
        switch (IndividualMode)
        {
            case IndividualMode.Sysex:
                Transmit(XK7SysEx.DataSet(DeviceId, s, raw));
                break;
            case IndividualMode.Nrpn:
            {
                if ((s.Parameter.Nrpn ?? NrpnFromAddress(s)) is not { } n) return;
                foreach (var m in Nrpn.Messages(UpperChannel, n.Msb, n.Lsb, raw, s.Parameter.Length)) Transmit(m.Bytes);
                break;
            }
        }
    }

    static (byte Msb, byte Lsb)? NrpnFromAddress(Setting s) => s.Parameter.Nrpn is null ? null : (s.Address.B3, s.Address.B4);

    static (DrawbarPart Part, int Index)? DrawbarPartOf(Setting s)
    {
        var b = s.Address;
        if (b.B0 != 0 || b.B1 != 0 || b.B2 != 1) return null;
        return b.B3 switch
        {
            1 => (DrawbarPart.Upper, b.B4),
            2 => (DrawbarPart.Lower, b.B4),
            3 => (DrawbarPart.Pedal, b.B4),
            _ => null,
        };
    }

    /// <summary>Recall a patch from the panel: bank select and program change on the part's channel.</summary>
    public void SelectPatch(string part, int bankMsb, int program)
    {
        if (!TransmitsProgramChange) return;
        var ch = part == "Lower" ? LowerChannel : part == "Pedal" ? PedalChannel : UpperChannel;
        Transmit(new MidiMessage.ControlChange(ch, 0, bankMsb).Bytes);
        Transmit(new MidiMessage.ControlChange(ch, 32, 0).Bytes);
        Transmit(new MidiMessage.ProgramChange(ch, program).Bytes);
    }

    /// <summary>The raw values a knob passes through when turned from its current value to target.</summary>
    public List<int> KnobSweep(Setting s, int target, int steps)
    {
        var start = Value(s) ?? s.Parameter.RawMin;
        target = s.Parameter.Clamp(target);
        if (steps <= 1) return new List<int> { target };
        return Enumerable.Range(1, steps)
            .Select(i => start + (int)SwiftText.Round((double)(target - start) * i / steps)).ToList();
    }

    void Transmit(byte[] bytes) => Send?.Invoke(bytes);
}

/// <summary>Connects an OrganSession and a SimulatedOrgan in-process, with no MIDI API. Delivery
/// goes through post (the app's UI thread, like real MIDI arriving later) unless Synchronous is
/// set, which tests use to step through exchanges deterministically.</summary>
public sealed class LoopbackLink : IMidiOutput
{
    public SimulatedOrgan Organ { get; }
    public OrganSession? Session { get; set; }
    public bool Synchronous { get; set; }
    readonly Action<Action> post;

    public LoopbackLink(OrganSession session, SimulatedOrgan organ, bool synchronous = false, Action<Action>? post = null)
    {
        Session = session;
        Organ = organ;
        Synchronous = synchronous;
        this.post = post ?? (a => a());
        session.Output = this;
        organ.Send = DeliverToSession;
    }

    public void Send(byte[] bytes)
    {
        if (Synchronous) Organ.Receive(bytes); else post(() => Organ.Receive(bytes));
    }

    void DeliverToSession(byte[] bytes)
    {
        if (Synchronous) Session?.Receive(bytes); else post(() => Session?.Receive(bytes));
    }
}
