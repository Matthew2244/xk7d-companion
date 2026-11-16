// Port of Sources/XK7DCore/MIDILog.swift.
using System.Globalization;

namespace XK7D.Core;

/// <summary>Turns MIDI going to and from the organ into lines for the MIDI log. One line per message:
/// direction, the bytes in hex, and a short note of what it is. Notes, the expression pedal, the
/// damper and real-time bytes are counted, not written.</summary>
public sealed class MidiLogger
{
    readonly MidiByteParser inbound = new();
    readonly MidiByteParser outbound = new();
    readonly ParameterDatabase database;
    public int Skipped { get; private set; }

    public MidiLogger(ParameterDatabase? database = null) { this.database = database ?? ParameterDatabase.Shared; }

    public List<string> Lines(bool incoming, byte[] bytes)
    {
        var messages = incoming ? inbound.Feed(bytes) : outbound.Feed(bytes);
        var output = new List<string>();
        foreach (var m in messages)
        {
            if (IsChatter(m)) { Skipped++; continue; }
            if (Skipped > 0)
            {
                output.Add($"    ({Skipped} note, expression or timing message{(Skipped == 1 ? "" : "s")} not written)");
                Skipped = 0;
            }
            var hex = string.Join(" ", m.Bytes.Select(b => b.ToString("X2", CultureInfo.InvariantCulture)));
            output.Add($"{(incoming ? "IN " : "OUT")} {hex}  [{Describe(m)}]");
        }
        return output;
    }

    static bool IsChatter(MidiMessage m) => m switch
    {
        MidiMessage.NoteOn or MidiMessage.NoteOff or MidiMessage.PitchBend => true,
        MidiMessage.ControlChange c => c.Controller == 11 || c.Controller == 64,
        MidiMessage.Other o => o.Data.Length == 1 && o.Data[0] >= 0xF8,
        _ => false,
    };

    static string X2(int v) => v.ToString("X2", CultureInfo.InvariantCulture);

    public string Describe(MidiMessage m)
    {
        switch (m)
        {
            case MidiMessage.ProgramChange pc: return $"program change, channel {pc.Channel + 1}, program {pc.Program}";
            case MidiMessage.ControlChange c:
            {
                string name = c.Controller switch
                {
                    0 => "bank select MSB",
                    32 => "bank select LSB",
                    99 => "NRPN MSB",
                    98 => "NRPN LSB",
                    6 => "data entry MSB",
                    38 => "data entry LSB",
                    1 => "Leslie speed",
                    92 => "Leslie fast",
                    _ => DrawbarCC.Drawbar(c.Controller) is { } d
                        ? $"{d.Part.Raw()} drawbar {DrawbarCC.FootageName(d.Part, d.Index)}"
                        : $"control {c.Controller}",
                };
                return $"{name}, channel {c.Channel + 1}, value {c.Value}";
            }
            case MidiMessage.Sysex s:
                return XK7Inbound.Decode(s.Data) switch
                {
                    XK7Inbound.DataSet ds => $"Data Set {ds.Address} {database.SettingAt(ds.Address)?.SpokenName ?? "unknown address"}, {ds.Data.Length} byte{(ds.Data.Length == 1 ? "" : "s")}",
                    XK7Inbound.DataPacket p => $"dump packet type {X2(p.Type)} number {p.Packet}, check {(p.ChecksumOK ? "good" : "failed")}",
                    XK7Inbound.Acknowledge a => $"acknowledge type {X2(a.Type)} result {X2(a.Result)} packet {a.Packet}",
                    XK7Inbound.DumpRequest dr => $"dump request type {X2(dr.Type)}",
                    XK7Inbound.NrpnSwitch n => $"NRPN switch {n.Mode}",
                    XK7Inbound.IdentityRequest ir => $"identity request, device {ir.Device}",
                    XK7Inbound.IdentityReply r => $"identity reply, device {r.Device}",
                    _ => "SysEx",
                };
            default: return "other";
        }
    }
}
