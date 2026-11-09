// Port of Sources/XK7DCore/OrganSession.swift.
using System.Diagnostics;

namespace XK7D.Core;

/// <summary>Anything that can carry bytes to the organ (Windows MIDI, the in-process simulator, a test).</summary>
public interface IMidiOutput
{
    void Send(byte[] bytes);
}

/// <summary>MIDI channels and SysEx device ID the session assumes. Channels are 0-based.</summary>
public sealed class OrganAddressing
{
    public byte DeviceId { get; set; }          // p. 157 screenshot shows 0
    public int UpperChannel { get; set; }       // Basic template: Upper 1, Lower 2, Pedal 3 (p. 175)
    public int LowerChannel { get; set; } = 1;
    public int PedalChannel { get; set; } = 2;

    internal string? Part(int c)
    {
        if (c == UpperChannel) return "Upper";
        if (c == LowerChannel) return "Lower";
        if (c == PedalChannel) return "Pedal";
        return null;
    }
}

/// <summary>Something that happened on the organ, decoded.</summary>
public abstract record OrganEvent
{
    public sealed record Value(Setting Setting, int Raw) : OrganEvent;
    public sealed record Text(Setting Setting, string Name) : OrganEvent;
    public sealed record Program(string Part, string Description) : OrganEvent;
    public sealed record Drawbar(DrawbarPart Part, int Index, int Level) : OrganEvent;
    public sealed record LeslieSpeed(int Position) : OrganEvent;
    public sealed record Controller(string Name, bool On) : OrganEvent;
    public sealed record Identity(byte Device) : OrganEvent;
    public sealed record DumpPacket(byte Type, int Packet, bool ChecksumOK, string ChecksumNote) : OrganEvent;
    public sealed record Acknowledge(byte Type, byte Result, int Packet) : OrganEvent;
    public sealed record UnknownAddress(Address Address) : OrganEvent;
}

/// <summary>What a memory dump request brought back.</summary>
public sealed class DumpSnapshot
{
    public readonly record struct Packet(byte Type, int Number, byte[] Data, bool ChecksumOK);

    public List<Packet> Packets { get; } = new();
    public List<byte[]> RawMessages { get; } = new();
    public HashSet<string> ChecksumReadings { get; } = new();
    public DateTime Started { get; } = DateTime.Now;

    public int Count => Packets.Count;
    public bool AllChecksumsOK => Packets.All(p => p.ChecksumOK);
    public byte[] SyxData => RawMessages.SelectMany(m => m).ToArray();
}

/// <summary>The heart of the app, with no UI and no MIDI API: decodes what the organ sends, keeps
/// what is known of its settings, sends changes, hides our own echoes, and produces announcement text.</summary>
public sealed class OrganSession
{
    public ParameterDatabase Database { get; }
    public OrganAddressing Addressing { get; set; } = new();
    public IMidiOutput? Output { get; set; }

    /// <summary>Called for every decoded event; the bool is true when it repeats something this app just sent.</summary>
    public Action<OrganEvent, bool>? OnEvent { get; set; }
    /// <summary>Called with text ready to be spoken (already coalesced).</summary>
    public Action<string>? OnAnnouncement { get; set; }
    /// <summary>Called when the device ID was learned from the organ.</summary>
    public Action<byte>? OnDeviceIdLearned { get; set; }
    /// <summary>Called once per connection when the organ's controls arrive on a channel other than
    /// the Upper channel the app listens on. The argument is that channel, 0-based.</summary>
    public Action<int>? OnChannelMismatch { get; set; }
    readonly HashSet<int> reportedMismatch = new();

    /// <summary>Called for each dump packet while a dump is being received.</summary>
    public Action<DumpSnapshot>? OnDumpProgress { get; set; }

    public AnnouncementCoalescer Coalescer { get; }
    static readonly Stopwatch Uptime = Stopwatch.StartNew();
    public Func<double> Clock { get; set; } = () => Uptime.Elapsed.TotalSeconds;
    /// <summary>How long after sending a value an identical value coming back counts as our own echo.</summary>
    public double EchoWindow { get; set; } = 2.0;
    /// <summary>Answer each received dump packet with an Acknowledge (p. 177).</summary>
    public bool AcknowledgeDumpPackets { get; set; } = true;
    /// <summary>Hold outgoing messages until the other end has answered an Identity Request.</summary>
    public bool HoldUntilAnswered { get; set; }
    /// <summary>The shortest gap between two value changes sent to the organ.</summary>
    public double MinimumSendGap { get; set; } = 0.02;

    readonly Dictionary<Address, int> values = new();
    readonly Dictionary<Address, string> texts = new();
    readonly Dictionary<string, int> drawbars = new();
    public IReadOnlyDictionary<Address, int> Values => values;
    public IReadOnlyDictionary<Address, string> Texts => texts;
    public IReadOnlyDictionary<string, int> Drawbars => drawbars;
    public string? LastAnnouncement { get; private set; }
    public DumpSnapshot? CurrentDump { get; private set; }
    public bool OrganAnswered { get; private set; }

    readonly MidiByteParser parser = new();
    readonly NrpnDecoder nrpn;
    readonly Dictionary<int, int> bankMsb = new();
    readonly Dictionary<Address, (int Raw, double At)> sentValues = new();
    readonly Dictionary<Address, (string Text, double At)> sentTexts = new();
    readonly Dictionary<string, (int Level, double At)> sentDrawbars = new();
    readonly List<byte[]> heldUntilAnswered = new();
    double? identityAskedAt;
    int identityAttempts;
    double lastValueSendAt = double.NegativeInfinity;
    readonly List<(Address Address, byte[] Message)> paced = new();

    public OrganSession(ParameterDatabase? database = null, AnnouncementCoalescer? coalescer = null)
    {
        Database = database ?? ParameterDatabase.Shared;
        Coalescer = coalescer ?? new AnnouncementCoalescer();
        var db = Database;
        nrpn = new NrpnDecoder((m, l) => db.SettingForNrpn(m, l)?.Parameter.Length);
    }

    // State

    public int? ValueOf(Setting s) => values.TryGetValue(s.Address, out var v) ? v : null;
    public string? TextOf(Setting s) => texts.TryGetValue(s.Address, out var t) ? t : null;

    /// <summary>Start afresh on a new connection: nothing has answered yet and nothing is waiting to go.</summary>
    public void ResetConnection()
    {
        OrganAnswered = false;
        heldUntilAnswered.Clear();
        paced.Clear();
        identityAskedAt = null;
        identityAttempts = 0;
        reportedMismatch.Clear();
    }

    public void ForgetAllValues() { values.Clear(); texts.Clear(); drawbars.Clear(); }

    // Sending

    /// <summary>Send a value with SysEx Data Set. Works for every parameter in the table.</summary>
    public byte[] Set(Setting setting, int raw)
    {
        raw = setting.Parameter.Clamp(raw);
        var msg = XK7SysEx.DataSet(Addressing.DeviceId, setting, raw);
        values[setting.Address] = raw;
        sentValues[setting.Address] = (raw, Clock());
        if (DrawbarKey(setting) is { } d)
        {
            drawbars[d] = raw;
            sentDrawbars[d] = (raw, Clock());
        }
        Coalescer.Cancel(AnnounceKey(setting));
        var now = Clock();
        if (now - lastValueSendAt < MinimumSendGap || paced.Count > 0)
        {
            var i = paced.FindIndex(p => p.Address == setting.Address);
            if (i >= 0) paced[i] = (setting.Address, msg);
            else paced.Add((setting.Address, msg));
        }
        else
        {
            lastValueSendAt = now;
            Transmit(msg);
        }
        return msg;
    }

    /// <summary>Messages waiting for the pacing gap (for tests).</summary>
    public int PacedCount => paced.Count;

    void Transmit(byte[] msg)
    {
        var isIdentityRequest = msg.Length == 6 && msg[1] == 0x7E && msg[3] == 0x06 && msg[4] == 0x01;
        if (HoldUntilAnswered && !OrganAnswered && !isIdentityRequest)
        {
            heldUntilAnswered.Add(msg);
            return;
        }
        Output?.Send(msg);
    }

    void FlushPaced()
    {
        if (paced.Count == 0 || Clock() - lastValueSendAt < MinimumSendGap) return;
        var batch = paced.ToList();
        paced.Clear();
        lastValueSendAt = Clock();
        foreach (var p in batch) Transmit(p.Message);
    }

    void ReleaseHeld()
    {
        var held = heldUntilAnswered.ToList();
        heldUntilAnswered.Clear();
        foreach (var original in held)
        {
            var m = (byte[])original.Clone();
            // The organ may have told us a different Device ID while these waited.
            if (m.Length > 2 && m[1] == XK7SysEx.SuzukiId) m[2] = Addressing.DeviceId;
            Output?.Send(m);
        }
    }

    /// <summary>Messages held until the other end answers (for tests).</summary>
    public int HeldCount => heldUntilAnswered.Count;

    public byte[] Set(Setting setting, string text)
    {
        var msg = XK7SysEx.DataSet(Addressing.DeviceId, setting, text);
        var stored = TextCodec.Decode(TextCodec.Encode(text, setting.Parameter.Length));
        texts[setting.Address] = stored;
        sentTexts[setting.Address] = (stored, Clock());
        Transmit(msg);
        return msg;
    }

    public void RequestIdentity()
    {
        if (!HoldUntilAnswered) OrganAnswered = false;
        identityAskedAt = Clock();
        identityAttempts = 1;
        Output?.Send(XK7SysEx.IdentityRequest(Addressing.DeviceId));
        if (Addressing.DeviceId != 0x7F)
        {
            // All-call as well, in case the organ's Device ID is not the one we assume.
            Output?.Send(XK7SysEx.IdentityRequest(0x7F));
        }
    }

    public void RequestDump(DumpType type)
    {
        CurrentDump = new DumpSnapshot();
        Transmit(XK7SysEx.DumpRequest(Addressing.DeviceId, type));
    }

    public DumpSnapshot? FinishDump()
    {
        var d = CurrentDump;
        CurrentDump = null;
        return d;
    }

    // Receiving

    public void Receive(IEnumerable<byte> bytes)
    {
        foreach (var m in parser.Feed(bytes)) Handle(m);
    }

    /// <summary>Speak whatever has settled. Call this often (the app does every 50 ms).</summary>
    public void Tick()
    {
        FlushPaced();
        if (HoldUntilAnswered && !OrganAnswered && identityAskedAt is { } asked && Clock() - asked >= 0.3)
        {
            // Ask again a few times; after about three seconds send anyway rather than hold forever.
            if (identityAttempts < 10)
            {
                identityAttempts++;
                identityAskedAt = Clock();
                Output?.Send(XK7SysEx.IdentityRequest(Addressing.DeviceId));
                Output?.Send(XK7SysEx.IdentityRequest(0x7F));
            }
            else
            {
                identityAskedAt = null;
                ReleaseHeld();
            }
        }
        foreach (var text in Coalescer.Due(Clock())) Speak(text);
    }

    /// <summary>Speak a line now, bypassing coalescing (used for the app's own status messages).</summary>
    public void Speak(string text)
    {
        LastAnnouncement = text;
        OnAnnouncement?.Invoke(text);
    }

    void Handle(MidiMessage m)
    {
        switch (m)
        {
            case MidiMessage.Sysex s: HandleSysEx(s.Data); break;
            case MidiMessage.ControlChange c: HandleCC(c.Channel, c.Controller, c.Value); break;
            case MidiMessage.ProgramChange pc:
            {
                if (Addressing.Part(pc.Channel) is not { } part) return;
                var desc = PatchSelect.Describe(bankMsb.TryGetValue(pc.Channel, out var b) ? b : null, pc.Program);
                Emit(new OrganEvent.Program(part, desc), $"program.{part}", $"{part}: {PatchSelect.Spoken(desc)}", false);
                break;
            }
        }
    }

    void HandleCC(int channel, int controller, int value)
    {
        if (controller == 0) { bankMsb[channel] = value; return; }
        if (channel != Addressing.UpperChannel)
        {
            // The organ sends NRPN and drawbars only on its Upper channel (p. 156), so seeing them
            // elsewhere means the app's Upper channel doesn't match the organ's.
            if ((controller == 99 || DrawbarCC.Drawbar(controller) is not null) && reportedMismatch.Add(channel))
                OnChannelMismatch?.Invoke(channel);
            return;
        }
        if (nrpn.Handle(controller, value) is { } v)
        {
            if (Database.SettingForNrpn(v.Msb, v.Lsb) is { } s) Received(s, v.Raw);
            else Emit(new OrganEvent.UnknownAddress(new Address(0, 0, 0, v.Msb, v.Lsb)), null, null, false);
            return;
        }
        if (DrawbarCC.Drawbar(controller) is { } d)
        {
            var level = DrawbarCC.Level(value);
            var key = $"{d.Part.Raw()}.{d.Index}";
            drawbars[key] = level;
            var echo = IsRecent(sentDrawbars.TryGetValue(key, out var sd) ? (sd.Level == level, sd.At) : null);
            Emit(new OrganEvent.Drawbar(d.Part, d.Index, level), $"drawbar.{key}",
                 $"{d.Part.Raw()} {DrawbarCC.FootageName(d.Part, d.Index)}: {level}", echo);
            // Keep the registration setting in step with the drawbar.
            if (RegistrationSetting(d.Part, d.Index) is { } reg) values[reg.Address] = level;
            return;
        }
        switch (controller)
        {
            case 1:
            {
                var text = value switch
                {
                    0 => "Leslie speed: slow",
                    127 => "Leslie speed: fast",
                    _ => $"Leslie speed: {(int)SwiftText.Round(value / 127.0 * 100)} percent",
                };
                Emit(new OrganEvent.LeslieSpeed(value), "cc1", text, false);
                break;
            }
            case 49: OnOff("Tone wheel brake", value); break;
            case 69: OnOff("Sustain", value); break;
            case 85: OnOff("ProChord", value); break;
            case 92: OnOff("Leslie fast", value); break;
        }
    }

    void OnOff(string name, int value)
    {
        var on = value >= 64;
        Emit(new OrganEvent.Controller(name, on), $"cc.{name}", $"{name}: {(on ? "on" : "off")}", false);
    }

    void HandleSysEx(byte[] bytes)
    {
        switch (XK7Inbound.Decode(bytes))
        {
            case XK7Inbound.DataSet ds:
                LearnDevice(ds.Device);
                DecodeDataSet(ds.Address, ds.Data);
                break;
            case XK7Inbound.IdentityReply r:
                if (r.Manufacturer != XK7SysEx.SuzukiId || !r.Family.AsSpan().SequenceEqual(new byte[] { 0x00, 0x10 })
                    || !r.Member.AsSpan().SequenceEqual(new byte[] { 0x00, 0x26 })) return;
                OrganAnswered = true;
                identityAskedAt = null;
                LearnDevice(r.Device);
                ReleaseHeld();
                Emit(new OrganEvent.Identity(r.Device), null, null, false);
                break;
            case XK7Inbound.DataPacket p:
                LearnDevice(p.Device);
                CurrentDump ??= new DumpSnapshot();
                CurrentDump.Packets.Add(new DumpSnapshot.Packet(p.Type, p.Packet, p.Data, p.ChecksumOK));
                CurrentDump.RawMessages.Add(bytes);
                CurrentDump.ChecksumReadings.Add(p.ChecksumNote);
                if (AcknowledgeDumpPackets)
                    Transmit(XK7SysEx.Acknowledge(p.Device, p.Type, p.ChecksumOK ? (byte)0x00 : (byte)0x05, p.Packet));
                Emit(new OrganEvent.DumpPacket(p.Type, p.Packet, p.ChecksumOK, p.ChecksumNote), null, null, false);
                OnDumpProgress?.Invoke(CurrentDump);
                break;
            case XK7Inbound.Acknowledge a:
                Emit(new OrganEvent.Acknowledge(a.Type, a.Result, a.Packet), null, null, false);
                break;
        }
    }

    /// <summary>One Data Set can carry several neighbouring parameters ("Data (Flexible bytes)"). Read
    /// the first, then step the last address byte by one for each further parameter.</summary>
    void DecodeDataSet(Address address, byte[] data)
    {
        var addr = address;
        var rest = data.AsMemory();
        while (!rest.IsEmpty)
        {
            if (Database.SettingAt(addr) is not { } s)
            {
                Emit(new OrganEvent.UnknownAddress(addr), null, null, false);
                return;
            }
            var len = s.Parameter.Length;
            if (rest.Length < len) return;
            var chunk = rest[..len].ToArray();
            rest = rest[len..];
            if (s.Parameter.IsText) ReceivedText(s, TextCodec.Decode(chunk));
            else Received(s, XK7SysEx.Value(chunk));
            if (addr.B4 >= 0x7F) return;
            addr = new Address(addr.B0, addr.B1, addr.B2, addr.B3, (byte)(addr.B4 + 1));
        }
    }

    void Received(Setting s, int raw)
    {
        values[s.Address] = raw;
        var echo = IsRecent(sentValues.TryGetValue(s.Address, out var sv) ? (sv.Raw == raw, sv.At) : null);
        if (DrawbarKey(s) is { } d) drawbars[d] = raw;
        Emit(new OrganEvent.Value(s, raw), AnnounceKey(s), $"{s.SpokenName}: {s.Parameter.Spoken(raw)}", echo);
    }

    void ReceivedText(Setting s, string text)
    {
        texts[s.Address] = text;
        var echo = IsRecent(sentTexts.TryGetValue(s.Address, out var st) ? (st.Text == text, st.At) : null);
        Emit(new OrganEvent.Text(s, text), s.Address.ToString(), $"{s.SpokenName}: {(text.Length == 0 ? "blank" : text)}", echo);
    }

    bool IsRecent((bool Same, double At)? match)
    {
        if (match is not { } m || !m.Same) return false;
        return Clock() - m.At <= EchoWindow;
    }

    void Emit(OrganEvent e, string? key, string? text, bool echo)
    {
        OnEvent?.Invoke(e, echo);
        if (key is null || text is null) return;
        if (echo) Coalescer.Cancel(key);
        else Coalescer.Submit(key, text, Clock());
    }

    void LearnDevice(byte dev)
    {
        if (dev == 0x7F || dev == Addressing.DeviceId) return;
        Addressing.DeviceId = dev;
        OnDeviceIdLearned?.Invoke(dev);
    }

    /// <summary>A drawbar can arrive both as a control change and as its registration setting;
    /// both file under one key so a move is spoken once.</summary>
    string AnnounceKey(Setting s) => DrawbarKey(s) is { } d ? $"drawbar.{d}" : s.Address.ToString();

    // Drawbars as registration settings (00 00 01 0p 0n)

    static string? DrawbarKey(Setting s)
    {
        var b = s.Address;
        if (b.B0 != 0 || b.B1 != 0 || b.B2 != 1) return null;
        return b.B3 switch
        {
            1 => $"Upper.{b.B4}",
            2 => $"Lower.{b.B4}",
            3 => $"Pedal.{b.B4}",
            _ => null,
        };
    }

    public Setting? RegistrationSetting(DrawbarPart part, int index)
    {
        byte p = part == DrawbarPart.Upper ? (byte)1 : part == DrawbarPart.Lower ? (byte)2 : (byte)3;
        return Database.SettingAt(new Address(0, 0, 1, p, (byte)index));
    }
}
