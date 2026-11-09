// Port of Tests/XK7DCoreTests/CodecTests.swift.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class SysExCodecTests
{
    [Fact]
    public void NibblizeMatchesManualExample()
    {
        Bytes(new byte[] { 0x37, 0x45 }, XK7SysEx.Nibblize(new byte[] { 0x7E }));
        Bytes(new byte[] { 0x7E }, XK7SysEx.Denibblize(new byte[] { 0x37, 0x45 })!);
        var all = Enumerable.Range(0, 256).Select(i => (byte)i).ToArray();
        Bytes(all, XK7SysEx.Denibblize(XK7SysEx.Nibblize(all))!);
        Assert.Null(XK7SysEx.Denibblize(new byte[] { 0x37 }));
        Assert.Null(XK7SysEx.Denibblize(new byte[] { 0x37, 0x5A }));
    }

    [Fact]
    public void CheckDigitIsLowSevenBitsOfXor()
    {
        Assert.Equal(0x71, XK7SysEx.CheckDigit(new byte[] { 0x30, 0x41 }));
        Assert.Equal(0, XK7SysEx.CheckDigit(new byte[] { 0x7F, 0x7F }));
        Assert.Equal(0x46, XK7SysEx.CheckDigit(new byte[] { 0x46, 0x46, 0x46 }));
    }

    [Fact]
    public void DataPacketIs139BytesAndRoundTrips()
    {
        var data = Enumerable.Range(0, 64).Select(i => (byte)(i * 3 & 0xFF)).ToArray();
        var p = XK7SysEx.DataPacket(0x05, 0x07, 3, data);
        Assert.Equal(139, p.Length);
        Bytes(new byte[] { 0xF0, 0x55, 0x05, 0x10, 0x26, 0x11, 0x07, 0x00, 0x03 }, p.Take(9).ToArray());
        Assert.True(p.Skip(1).Take(p.Length - 2).All(b => b < 0x80), "SysEx body must be 7-bit");
        var d = Assert.IsType<XK7Inbound.DataPacket>(XK7Inbound.Decode(p));
        Assert.Equal((5, 7, 3), ((int)d.Device, (int)d.Type, d.Packet));
        Bytes(data, d.Data);
        Assert.True(d.ChecksumOK);
        Assert.Equal("XOR of nibblized data", d.ChecksumNote);
        var bad = (byte[])p.Clone();
        bad[137] ^= 0x01;
        Assert.False(Assert.IsType<XK7Inbound.DataPacket>(XK7Inbound.Decode(bad)).ChecksumOK);
    }

    [Fact]
    public void OtherMessagesAsPrinted()
    {
        Bytes(Bytes("F0 55 00 10 26 12 07 F7"), XK7SysEx.DumpRequest(0, DumpType.Temporary));
        Bytes(Bytes("F0 55 00 10 26 12 0A F7"), XK7SysEx.DumpRequest(0, DumpType.System));
        Bytes(Bytes("F0 55 00 10 26 02 02 F7"), XK7SysEx.NrpnSwitch(0, IndividualMode.Sysex));
        Bytes(Bytes("F0 55 00 10 26 14 07 00 01 02 F7"), XK7SysEx.Acknowledge(0, 7, 0, 130));
        Bytes(Bytes("F0 7E 7F 06 01 F7"), XK7SysEx.IdentityRequest(0x7F));
        Bytes(Bytes("F0 7E 00 06 02 55 00 10 00 26 00 00 00 00 F7"), XK7SysEx.IdentityReply(0));
        Assert.Equal(new XK7Inbound.IdentityReply(3, 0x55, new byte[] { 0, 0x10 }, new byte[] { 0, 0x26 }),
                     XK7Inbound.Decode(XK7SysEx.IdentityReply(3)));
        Assert.Equal(new XK7Inbound.DataSet(0, A(0, 0, 0, 0x10, 4), new byte[] { 1 }),
                     XK7Inbound.Decode(Bytes("F0 55 00 10 26 13 00 00 00 10 04 01 F7")));
        Assert.Equal(new XK7Inbound.Unknown(Bytes("F0 43 10 F7")), XK7Inbound.Decode(Bytes("F0 43 10 F7")));
        // A different model's ID must not be read as ours.
        var other = Bytes("F0 55 00 10 25 13 00 00 00 10 04 01 F7");
        Assert.Equal(new XK7Inbound.Unknown(other), XK7Inbound.Decode(other));
    }

    [Fact]
    public void ValueBytePacking()
    {
        Bytes(new byte[] { 5 }, XK7SysEx.ValueBytes(5, 1));
        Bytes(new byte[] { 0x03, 0x3A }, XK7SysEx.ValueBytes(442, 2));
        Bytes(new byte[] { 0x08, 0x11 }, XK7SysEx.ValueBytes(1041, 2));
        Assert.Equal(442, XK7SysEx.Value(new byte[] { 0x03, 0x3A }));
        Assert.Equal(127, XK7SysEx.Value(new byte[] { 0x7F }));
        for (var v = 0; v <= 16383; v += 97) Assert.Equal(v, XK7SysEx.Value(XK7SysEx.ValueBytes(v, 2)));
    }

    [Fact]
    public void TextCodecs()
    {
        Bytes(System.Text.Encoding.ASCII.GetBytes("Jimmy           "), TextCodec.Encode("Jimmy"));
        Assert.Equal(16, TextCodec.Encode("A name that is far too long").Length);
        Assert.Equal((byte)'?', TextCodec.Encode("Café")[3]);
        Assert.Equal("Jimmy", TextCodec.Decode(System.Text.Encoding.ASCII.GetBytes("Jimmy           ")));
    }
}

public class ByteParserTests
{
    [Fact]
    public void RunningStatusNRPN()
    {
        var p = new MidiByteParser();
        Assert.Equal(new MidiMessage[]
        {
            new MidiMessage.ControlChange(0, 0x63, 0x10), new MidiMessage.ControlChange(0, 0x62, 0x04),
            new MidiMessage.ControlChange(0, 0x06, 0x01),
        }, p.Feed(Bytes("B0 63 10 62 04 06 01")));
    }

    [Fact]
    public void MessagesSplitAcrossPacketsAndRealTimeInterleaved()
    {
        var p = new MidiByteParser();
        var output = new List<MidiMessage>();
        output.AddRange(p.Feed(Bytes("F0 55 00 10")));
        output.AddRange(p.Feed(Bytes("F8 26 13 00 00 00")));      // clock byte inside SysEx
        output.AddRange(p.Feed(Bytes("10 04 01 F7 B1 0E")));
        output.AddRange(p.Feed(Bytes("FE 7F")));                   // active sensing inside a CC
        Assert.Equal(new MidiMessage[]
        {
            new MidiMessage.Other(new byte[] { 0xF8 }),
            new MidiMessage.Sysex(Bytes("F0 55 00 10 26 13 00 00 00 10 04 01 F7")),
            new MidiMessage.Other(new byte[] { 0xFE }),
            new MidiMessage.ControlChange(1, 0x0E, 0x7F),
        }, output);
    }

    [Fact]
    public void ProgramChangeAndNotes()
    {
        var p = new MidiByteParser();
        Assert.Equal(new MidiMessage[] { new MidiMessage.ProgramChange(2, 15), new MidiMessage.ProgramChange(2, 16) },
                     p.Feed(Bytes("C2 0F 10")));
        Assert.Equal(new MidiMessage[] { new MidiMessage.NoteOff(0, 60, 0) }, p.Feed(new byte[] { 0x90, 60, 0 }));
        Assert.Equal(new MidiMessage[] { new MidiMessage.NoteOn(0, 60, 100), new MidiMessage.NoteOn(0, 62, 90) },
                     p.Feed(new byte[] { 0x90, 60, 100, 62, 90 }));
    }

    [Fact]
    public void UnterminatedSysExIsDropped()
    {
        var p = new MidiByteParser();
        Assert.Equal(new MidiMessage[] { new MidiMessage.ControlChange(0, 7, 0x40) }, p.Feed(Bytes("F0 55 00 B0 07 40")));
    }
}

public class NrpnDecoderTests
{
    static NrpnDecoder Decoder() => new((m, l) => Db.SettingForNrpn(m, l)?.Parameter.Length);

    static List<NrpnDecoder.Value> Feed(NrpnDecoder d, params (int, int)[] pairs) =>
        pairs.Select(p => d.Handle(p.Item1, p.Item2)).Where(v => v is not null).Select(v => v!.Value).ToList();

    [Fact]
    public void OneByteParameterCompletesOnDataEntryMSB()
    {
        var d = Decoder();
        Assert.Equal(new[] { new NrpnDecoder.Value(0x10, 0x04, 1) }, Feed(d, (99, 0x10), (98, 0x04), (6, 0x01)));
        Assert.Equal(new[] { new NrpnDecoder.Value(0x10, 0x04, 3) }, Feed(d, (6, 0x03)));
    }

    [Fact]
    public void TwoByteParameterWaitsForLSB()
    {
        var d = Decoder();
        Assert.Empty(Feed(d, (99, 0), (98, 0), (6, 3)));
        Assert.Equal(new[] { new NrpnDecoder.Value(0, 0, 442) }, Feed(d, (38, 0x3A)));
        Assert.Equal(new[] { new NrpnDecoder.Value(0, 0, 443) }, Feed(d, (38, 0x3B)));
    }

    [Fact]
    public void TwoByteParameterWithoutLSBNeverGuesses()
    {
        var d = Decoder();
        Assert.Equal(new[] { new NrpnDecoder.Value(0x11, 0, 1) }, Feed(d, (99, 0), (98, 0), (6, 3), (99, 0x11), (98, 0), (6, 1)));
    }

    [Fact]
    public void NullAndResetAndUnknown()
    {
        var d = Decoder();
        Assert.Empty(Feed(d, (99, 0x10), (98, 0x04), (99, 127), (98, 127), (6, 1)));
        Assert.Empty(Feed(d, (99, 0x10), (98, 0x04), (121, 0), (6, 1)));
        Assert.Empty(Feed(d, (99, 0x7E), (98, 0x7E), (6, 1)));     // an NRPN not in the manual is ignored
        Assert.Empty(Feed(d, (99, 0x10), (98, 0x04), (101, 0), (6, 1)));   // RPN selection cancels NRPN
    }

    [Fact]
    public void OrderMSBThenLSBOrLSBThenMSB()
    {
        var d = Decoder();
        Assert.Equal(new[] { new NrpnDecoder.Value(0x10, 0x04, 2) }, Feed(d, (98, 0x04), (99, 0x10), (6, 2)));
    }
}

public class DrawbarBucketTests
{
    // p. 177: 00-0F 0, 10-1F 1, ... 70-7E 7, 7F 8.
    [Fact]
    public void EveryValueLandsInTheManualsBucket()
    {
        var buckets = new[] { (0, 15, 0), (16, 31, 1), (32, 47, 2), (48, 63, 3), (64, 79, 4), (80, 95, 5), (96, 111, 6), (112, 126, 7), (127, 127, 8) };
        foreach (var (lo, hi, level) in buckets)
            for (var v = lo; v <= hi; v++) Assert.Equal(level, DrawbarCC.Level(v));
        for (var level = 0; level <= 8; level++) Assert.Equal(level, DrawbarCC.Level(DrawbarCC.Value(level)));
    }

    [Fact]
    public void ControllerMap()
    {
        Assert.Equal(DrawbarPart.Upper, DrawbarCC.Drawbar(12)?.Part);
        Assert.Equal(8, DrawbarCC.Drawbar(20)?.Index);
        Assert.Equal(DrawbarPart.Lower, DrawbarCC.Drawbar(21)?.Part);
        Assert.Equal(DrawbarPart.Pedal, DrawbarCC.Drawbar(33)?.Part);
        Assert.Equal(1, DrawbarCC.Drawbar(35)?.Index);
        Assert.Null(DrawbarCC.Drawbar(34));
        Assert.Null(DrawbarCC.Drawbar(11));
        foreach (var part in new[] { DrawbarPart.Upper, DrawbarPart.Lower })
            for (var i = 0; i < 9; i++) Assert.Equal(i, DrawbarCC.Drawbar(DrawbarCC.Controller(part, i))?.Index);
    }
}

public class CoalescerTests
{
    [Fact]
    public void BurstSpeaksOnlyTheLatestAfterSettling()
    {
        var c = new AnnouncementCoalescer(0.3, 5);
        for (var i = 0; i < 20; i++) c.Submit("horn", $"Horn fast speed: {300 + i} rpm", i * 0.05);
        Assert.Empty(c.Due(1.0));
        Assert.Equal(new[] { "Horn fast speed: 319 rpm" }, c.Due(1.26));
        Assert.Empty(c.Due(5));
    }

    [Fact]
    public void SeparateSettingsEachSpeakInOrder()
    {
        var c = new AnnouncementCoalescer(0.3, 5);
        c.Submit("a", "A 1", 0);
        c.Submit("b", "B 1", 0.1);
        c.Submit("a", "A 2", 0.2);
        Assert.Equal(new[] { "B 1" }, c.Due(0.45));
        Assert.Equal(new[] { "A 2" }, c.Due(0.6));
    }

    [Fact]
    public void LongSweepIsNotSilent()
    {
        var c = new AnnouncementCoalescer(0.3, 1.0);
        var spoken = new List<string>();
        var t = 0.0;
        while (t < 2.5)
        {
            c.Submit("k", $"v{(int)(t * 10)}", t);
            spoken.AddRange(c.Due(t));
            t += 0.1;
        }
        Assert.InRange(spoken.Count, 2, 3);
    }

    [Fact]
    public void CancelAndFlush()
    {
        var c = new AnnouncementCoalescer();
        c.Submit("a", "A", 0);
        c.Submit("b", "B", 0);
        c.Cancel("a");
        Assert.Equal(new[] { "B" }, c.Flush());
        Assert.True(c.IsEmpty);
    }
}
