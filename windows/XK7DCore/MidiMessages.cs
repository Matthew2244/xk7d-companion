// Port of Sources/XK7DCore/MIDIMessages.swift.
using System.Globalization;

namespace XK7D.Core;

/// <summary>A complete MIDI message, after running status and SysEx reassembly.</summary>
public abstract record MidiMessage
{
    public abstract byte[] Bytes { get; }

    public sealed record ControlChange(int Channel, int Controller, int Value) : MidiMessage
    {
        public override byte[] Bytes => new[] { (byte)(0xB0 | (Channel & 0xF)), (byte)(Controller & 0x7F), (byte)(Value & 0x7F) };
    }

    public sealed record ProgramChange(int Channel, int Program) : MidiMessage
    {
        public override byte[] Bytes => new[] { (byte)(0xC0 | (Channel & 0xF)), (byte)(Program & 0x7F) };
    }

    public sealed record NoteOn(int Channel, int Note, int Velocity) : MidiMessage
    {
        public override byte[] Bytes => new[] { (byte)(0x90 | (Channel & 0xF)), (byte)(Note & 0x7F), (byte)(Velocity & 0x7F) };
    }

    public sealed record NoteOff(int Channel, int Note, int Velocity) : MidiMessage
    {
        public override byte[] Bytes => new[] { (byte)(0x80 | (Channel & 0xF)), (byte)(Note & 0x7F), (byte)(Velocity & 0x7F) };
    }

    public sealed record PitchBend(int Channel, int Value) : MidiMessage
    {
        public override byte[] Bytes => new[] { (byte)(0xE0 | (Channel & 0xF)), (byte)(Value & 0x7F), (byte)((Value >> 7) & 0x7F) };
    }

    public sealed record Other(byte[] Data) : MidiMessage
    {
        public override byte[] Bytes => Data;
        public bool Equals(Other? o) => o is not null && Data.AsSpan().SequenceEqual(o.Data);
        public override int GetHashCode() => Data.Length;
    }

    public sealed record Sysex(byte[] Data) : MidiMessage
    {
        public override byte[] Bytes => Data;
        public bool Equals(Sysex? o) => o is not null && Data.AsSpan().SequenceEqual(o.Data);
        public override int GetHashCode() => Data.Length;
    }
}

/// <summary>Turns a raw byte stream (in any chunking) into messages. Handles running status,
/// real-time bytes inside other messages, and SysEx split across packets.</summary>
public sealed class MidiByteParser
{
    byte status;
    readonly List<byte> data = new();
    List<byte>? sysex;

    public List<MidiMessage> Feed(IEnumerable<byte> bytes)
    {
        var output = new List<MidiMessage>();
        foreach (var b in bytes)
        {
            if (b >= 0xF8) { output.Add(new MidiMessage.Other(new[] { b })); continue; }   // real-time: never breaks running status
            if (b == 0xF0) { sysex = new List<byte> { b }; status = 0; data.Clear(); continue; }
            if (b == 0xF7)
            {
                if (sysex is not null) { sysex.Add(b); output.Add(new MidiMessage.Sysex(sysex.ToArray())); }
                sysex = null;
                continue;
            }
            if ((b & 0x80) != 0)
            {
                if (sysex is not null) sysex = null;                       // unterminated SysEx: drop it
                if (b >= 0xF0) { status = 0; data.Clear(); output.Add(new MidiMessage.Other(new[] { b })); continue; }
                status = b; data.Clear();
                continue;
            }
            if (sysex is not null) { sysex.Add(b); continue; }
            if (status == 0) continue;                                       // stray data byte
            data.Add(b);
            var channel = status & 0x0F;
            switch (status & 0xF0)
            {
                case 0xC0:
                    output.Add(new MidiMessage.ProgramChange(channel, b)); data.Clear();
                    break;
                case 0xD0:
                    output.Add(new MidiMessage.Other(new[] { status, b })); data.Clear();
                    break;
                case 0x80: case 0x90: case 0xA0: case 0xB0: case 0xE0:
                    if (data.Count == 2)
                    {
                        int d1 = data[0], d2 = data[1];
                        output.Add((status & 0xF0) switch
                        {
                            0xB0 => new MidiMessage.ControlChange(channel, d1, d2),
                            0x90 => d2 == 0 ? new MidiMessage.NoteOff(channel, d1, 0) : new MidiMessage.NoteOn(channel, d1, d2),
                            0x80 => new MidiMessage.NoteOff(channel, d1, d2),
                            0xE0 => new MidiMessage.PitchBend(channel, d1 | d2 << 7),
                            _ => new MidiMessage.Other(new[] { status, data[0], data[1] }),
                        });
                        data.Clear();
                    }
                    break;
                default:
                    data.Clear();
                    break;
            }
        }
        return output;
    }
}

public enum IndividualMode : byte { Off = 0, Nrpn = 1, Sysex = 2 }

public enum DumpType : byte { Temporary = 0x07, AdjustKeys = 0x08, System = 0x0A }

/// <summary>Everything the manual specifies about the XK-7's System Exclusive (p. 177).</summary>
public static class XK7SysEx
{
    public const byte SuzukiId = 0x55;
    public static readonly byte[] ModelId = { 0x10, 0x26 };

    public const byte CmdNrpnSwitch = 0x02, CmdDataPacket = 0x11, CmdDumpRequest = 0x12, CmdDataSet = 0x13, CmdAcknowledge = 0x14;

    public static string Title(this DumpType t) => t switch
    {
        DumpType.Temporary => "current patch",
        DumpType.AdjustKeys => "Adjust A# and B keys",
        _ => "system settings",
    };

    static List<byte> Header(byte device, byte command) => new() { 0xF0, SuzukiId, (byte)(device & 0x7F), ModelId[0], ModelId[1], command };

    /// <summary>Data Set: F0 55 dd 10 26 13 [address x5] [data] F7</summary>
    public static byte[] DataSet(byte device, Address address, IEnumerable<byte> data)
    {
        var m = Header(device, CmdDataSet);
        m.AddRange(address.Bytes);
        m.AddRange(data.Select(b => (byte)(b & 0x7F)));
        m.Add(0xF7);
        return m.ToArray();
    }

    /// <summary>The data bytes for a value: one byte, or two 7-bit bytes MSB first.</summary>
    public static byte[] ValueBytes(int raw, int length) => length switch
    {
        1 => new[] { (byte)(raw & 0x7F) },
        2 => new[] { (byte)((raw >> 7) & 0x7F), (byte)(raw & 0x7F) },
        _ => throw new ArgumentException($"length {length} is not a number"),
    };

    public static int Value(IEnumerable<byte> bytes) => bytes.Aggregate(0, (acc, b) => acc << 7 | (b & 0x7F));

    public static byte[] DataSet(byte device, Setting setting, int raw) =>
        DataSet(device, setting.Address, ValueBytes(raw, setting.Parameter.Length));

    public static byte[] DataSet(byte device, Setting setting, string text) =>
        DataSet(device, setting.Address, TextCodec.Encode(text, setting.Parameter.Length));

    /// <summary>Dump Request (organ receives only): F0 55 dd 10 26 12 [type] F7</summary>
    public static byte[] DumpRequest(byte device, DumpType type)
    {
        var m = Header(device, CmdDumpRequest);
        m.Add((byte)type); m.Add(0xF7);
        return m.ToArray();
    }

    /// <summary>NRPN Switch: F0 55 dd 10 26 02 [00 Off / 01 NRPN / 02 SysEx] F7</summary>
    public static byte[] NrpnSwitch(byte device, IndividualMode mode)
    {
        var m = Header(device, CmdNrpnSwitch);
        m.Add((byte)mode); m.Add(0xF7);
        return m.ToArray();
    }

    /// <summary>Acknowledge: F0 55 dd 10 26 14 [type] [result] [PNH] [PNL] F7</summary>
    public static byte[] Acknowledge(byte device, byte type, byte result, int packet)
    {
        var m = Header(device, CmdAcknowledge);
        m.AddRange(new[] { type, result, (byte)((packet >> 7) & 0x7F), (byte)(packet & 0x7F), (byte)0xF7 });
        return m.ToArray();
    }

    /// <summary>Identity Request (universal): F0 7E dd 06 01 F7</summary>
    public static byte[] IdentityRequest(byte device) => new byte[] { 0xF0, 0x7E, (byte)(device & 0x7F), 0x06, 0x01, 0xF7 };

    /// <summary>Identity Reply as printed on p. 177.</summary>
    public static byte[] IdentityReply(byte device) =>
        new byte[] { 0xF0, 0x7E, (byte)(device & 0x7F), 0x06, 0x02, 0x55, 0x00, 0x10, 0x00, 0x26, 0x00, 0x00, 0x00, 0x00, 0xF7 };

    /// <summary>Each byte becomes its two hex digits in ASCII ("7EH = 37H, 45H").</summary>
    public static byte[] Nibblize(IReadOnlyList<byte> data)
    {
        const string digits = "0123456789ABCDEF";
        var output = new byte[data.Count * 2];
        for (var i = 0; i < data.Count; i++)
        {
            output[2 * i] = (byte)digits[data[i] >> 4];
            output[2 * i + 1] = (byte)digits[data[i] & 0x0F];
        }
        return output;
    }

    public static byte[]? Denibblize(IReadOnlyList<byte> ascii)
    {
        if (ascii.Count % 2 != 0) return null;
        static int V(byte c) => c switch
        {
            >= 0x30 and <= 0x39 => c - 0x30,
            >= 0x41 and <= 0x46 => c - 0x41 + 10,
            >= 0x61 and <= 0x66 => c - 0x61 + 10,
            _ => -1,
        };
        var output = new byte[ascii.Count / 2];
        for (var i = 0; i < ascii.Count; i += 2)
        {
            int hi = V(ascii[i]), lo = V(ascii[i + 1]);
            if (hi < 0 || lo < 0) return null;
            output[i / 2] = (byte)(hi << 4 | lo);
        }
        return output;
    }

    /// <summary>"Check Digit: Lower 7 bits of XOR [DATA]".</summary>
    public static byte CheckDigit(IEnumerable<byte> bytes) => (byte)(bytes.Aggregate((byte)0, (a, b) => (byte)(a ^ b)) & 0x7F);

    /// <summary>Data Packet: F0 55 dd 10 26 11 [type] [PNH] [PNL] [128 ASCII] [check] F7 = 139 bytes.</summary>
    public static byte[] DataPacket(byte device, byte type, int packet, IReadOnlyList<byte> data64)
    {
        if (data64.Count != 64) throw new ArgumentException("a data packet carries 64 bytes");
        var ascii = Nibblize(data64);
        var m = Header(device, CmdDataPacket);
        m.AddRange(new[] { type, (byte)((packet >> 7) & 0x7F), (byte)(packet & 0x7F) });
        m.AddRange(ascii);
        m.Add(CheckDigit(ascii));
        m.Add(0xF7);
        return m.ToArray();
    }

    /// <summary>Number of packets per dump (p. 177).</summary>
    public const int TemporaryPackets = 6, AdjustPackets = 11, SystemPackets = 13;
}

/// <summary>A Suzuki/XK-7 SysEx message, decoded.</summary>
public abstract record XK7Inbound
{
    public sealed record DataSet(byte Device, Address Address, byte[] Data) : XK7Inbound
    {
        public bool Equals(DataSet? o) => o is not null && Device == o.Device && Address == o.Address && Data.AsSpan().SequenceEqual(o.Data);
        public override int GetHashCode() => HashCode.Combine(Device, Address);
    }

    public sealed record DataPacket(byte Device, byte Type, int Packet, byte[] Data, bool ChecksumOK, string ChecksumNote) : XK7Inbound;
    public sealed record Acknowledge(byte Device, byte Type, byte Result, int Packet) : XK7Inbound;
    public sealed record DumpRequest(byte Device, byte Type) : XK7Inbound;
    public sealed record NrpnSwitch(byte Device, byte Mode) : XK7Inbound;
    public sealed record IdentityRequest(byte Device) : XK7Inbound;

    public sealed record IdentityReply(byte Device, byte Manufacturer, byte[] Family, byte[] Member) : XK7Inbound
    {
        public bool Equals(IdentityReply? o) => o is not null && Device == o.Device && Manufacturer == o.Manufacturer
            && Family.AsSpan().SequenceEqual(o.Family) && Member.AsSpan().SequenceEqual(o.Member);
        public override int GetHashCode() => HashCode.Combine(Device, Manufacturer);
    }

    public sealed record Unknown(byte[] Data) : XK7Inbound
    {
        public bool Equals(Unknown? o) => o is not null && Data.AsSpan().SequenceEqual(o.Data);
        public override int GetHashCode() => Data.Length;
    }

    public static XK7Inbound Decode(byte[] m)
    {
        if (m.Length < 4 || m[0] != 0xF0 || m[^1] != 0xF7) return new Unknown(m);
        if (m[1] == 0x7E && m.Length >= 6 && m[3] == 0x06)
        {
            if (m[4] == 0x01) return new IdentityRequest(m[2]);
            if (m[4] == 0x02 && m.Length >= 11) return new IdentityReply(m[2], m[5], m[6..8], m[8..10]);
            return new Unknown(m);
        }
        if (m.Length < 7 || m[1] != XK7SysEx.SuzukiId || m[3] != 0x10 || m[4] != 0x26) return new Unknown(m);
        var dev = m[2];
        var body = m[6..^1];
        switch (m[5])
        {
            case XK7SysEx.CmdDataSet:
                if (body.Length < 6) return new Unknown(m);
                return new DataSet(dev, new Address(body[0..5]), body[5..]);
            case XK7SysEx.CmdDataPacket:
            {
                if (body.Length != 3 + 128 + 1) return new Unknown(m);
                var ascii = body[3..131];
                var check = body[131];
                var decoded = XK7SysEx.Denibblize(ascii) ?? Array.Empty<byte>();
                // The manual's wording allows two readings; note which one matched, for the hand-off.
                var okAscii = XK7SysEx.CheckDigit(ascii) == check;
                var okRaw = XK7SysEx.CheckDigit(decoded) == check;
                var note = okAscii ? "XOR of nibblized data" : (okRaw ? "XOR of decoded data" : "no match");
                return new DataPacket(dev, body[0], body[1] << 7 | body[2], decoded, okAscii || okRaw, note);
            }
            case XK7SysEx.CmdAcknowledge:
                if (body.Length != 4) return new Unknown(m);
                return new Acknowledge(dev, body[0], body[1], body[2] << 7 | body[3]);
            case XK7SysEx.CmdDumpRequest:
                if (body.Length != 1) return new Unknown(m);
                return new DumpRequest(dev, body[0]);
            case XK7SysEx.CmdNrpnSwitch:
                if (body.Length != 1) return new Unknown(m);
                return new NrpnSwitch(dev, body[0]);
            default:
                return new Unknown(m);
        }
    }
}

/// <summary>NRPN as the manual writes it: Bx 63 MSB, Bx 62 LSB, Bx 06 data MSB [, Bx 26 data LSB].</summary>
public static class Nrpn
{
    public static List<MidiMessage> Messages(int channel, byte msb, byte lsb, int raw, int length)
    {
        var m = new List<MidiMessage>
        {
            new MidiMessage.ControlChange(channel, 99, msb),
            new MidiMessage.ControlChange(channel, 98, lsb),
        };
        if (length == 2)
        {
            m.Add(new MidiMessage.ControlChange(channel, 6, (raw >> 7) & 0x7F));
            m.Add(new MidiMessage.ControlChange(channel, 38, raw & 0x7F));
        }
        else
        {
            m.Add(new MidiMessage.ControlChange(channel, 6, raw & 0x7F));
        }
        return m;
    }
}

public enum DrawbarPart { Upper, Lower, Pedal }

/// <summary>Drawbar control changes (p. 177): all on the UPPER channel.</summary>
public static class DrawbarCC
{
    public static string Raw(this DrawbarPart p) => p switch { DrawbarPart.Upper => "Upper", DrawbarPart.Lower => "Lower", _ => "Pedal" };

    public static readonly string[] Footages = { "16 foot", "5 and a third foot", "8 foot", "4 foot", "2 and two thirds foot",
                                                 "2 foot", "1 and three fifths foot", "1 and a third foot", "1 foot" };

    /// <summary>Controller number to (part, drawbar index 0...8, or 0/1 for the pedal's 16' and 8').</summary>
    public static (DrawbarPart Part, int Index)? Drawbar(int cc) => cc switch
    {
        >= 12 and <= 20 => (DrawbarPart.Upper, cc - 12),
        >= 21 and <= 29 => (DrawbarPart.Lower, cc - 21),
        33 => (DrawbarPart.Pedal, 0),
        35 => (DrawbarPart.Pedal, 1),
        _ => null,
    };

    public static int Controller(DrawbarPart part, int index) => part switch
    {
        DrawbarPart.Upper => 12 + index,
        DrawbarPart.Lower => 21 + index,
        _ => index == 0 ? 33 : 35,
    };

    /// <summary>00-0F = 0, 10-1F = 1, ... 70-7E = 7, 7F = 8.</summary>
    public static int Level(int v) => v >= 127 ? 8 : Math.Min(Math.Max(v, 0) / 16, 7);

    /// <summary>The value to send for a level: the bottom of each bucket, and 7F for 8.</summary>
    public static int Value(int level) => level >= 8 ? 127 : Math.Max(level, 0) * 16;

    public static string FootageName(DrawbarPart part, int index) =>
        part == DrawbarPart.Pedal ? (index == 0 ? "16 foot" : "8 foot") : Footages[index];
}

/// <summary>Program changes (p. 176).</summary>
public static class PatchSelect
{
    static readonly string[] Keys = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A" };

    public static string Describe(int? bank, int program)
    {
        switch (program)
        {
            case 0x7E: return "Adjust A#";
            case 0x7F: return "Adjust B";
            case >= 0x64 and <= 0x6D:
            {
                var key = Keys[program - 0x64];
                if (bank is { } b && b >= 0x64 && b <= 0x6D) return $"Favorite {Keys[b - 0x64]}-{key}";
                return $"Favorite key {key}";
            }
            case >= 0 and <= 0x63:
                return bank switch
                {
                    0 => "patch U" + program.ToString("00", CultureInfo.InvariantCulture),
                    1 => "patch F" + program.ToString("00", CultureInfo.InvariantCulture),
                    _ => $"patch {program}",
                };
            default:
                return $"program {program}";
        }
    }

    public static string Spoken(string s) => s.Replace("#", " sharp", StringComparison.Ordinal);
}
