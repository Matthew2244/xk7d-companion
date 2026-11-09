// Port of Tests/XK7DCoreTests/ManualExampleTests.swift: every worked example printed in the
// manual's MIDI appendix, encoded through the generated parameter table.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class ManualExampleTests
{
    const byte dd = 0x10;   // any device ID; the manual writes "dd"

    // p. 181: "ex: select Organ Type at Mellow"
    [Fact]
    public void OrganTypeMellow()
    {
        var s = S(A(0, 0, 0, 0x10, 0x04));
        Assert.Equal("Organ Type", s.Parameter.ManualName);
        Assert.Equal("Mellow", s.Parameter.Display(1));
        Bytes(Bytes("F0 55 10 10 26 13 00 00 00 10 04 01 F7"), XK7SysEx.DataSet(dd, s, 1));
        var n = s.Parameter.Nrpn!.Value;
        Bytes(Bytes("B0 63 10 B0 62 04 B0 06 01"), CC(Nrpn.Messages(0, n.Msb, n.Lsb, 1, s.Parameter.Length)));
    }

    // p. 185: "ex: set Master Tune set at 442 Hz"
    [Fact]
    public void MasterTune442()
    {
        var s = S(A(0, 0, 0, 0, 0));
        Assert.Equal("Master Tune", s.Parameter.ManualName);
        Assert.Equal("442 Hz", s.Parameter.Display(442));
        Assert.Equal((430, 450), (s.Parameter.RawMin, s.Parameter.RawMax));
        Bytes(Bytes("F0 55 10 10 26 13 00 00 00 00 00 03 3A F7"), XK7SysEx.DataSet(dd, s, 442));
        Bytes(Bytes("B0 63 00 B0 62 00 B0 06 03 B0 26 3A"), CC(Nrpn.Messages(0, 0, 0, 442, 2)));
        Assert.Equal("440 Hz", s.Parameter.Display(0x03 << 7 | 0x38));
    }

    // p. 185: "ex: select Expression Source set at MIDI". The printed NRPN (62 01) is a misprint; see PARAMETER-REVIEW.md.
    [Fact]
    public void ExpressionSourceMIDI()
    {
        var s = S(A(0, 0, 0, 0x04, 0x00));
        Assert.Equal("Source", s.Parameter.ManualName);
        Assert.Equal("MIDI", s.Parameter.Display(1));
        Bytes(Bytes("F0 55 10 10 26 13 00 00 00 04 00 01 F7"), XK7SysEx.DataSet(dd, s, 1));
        Bytes(Bytes("B0 63 04 B0 62 00 B0 06 01"), CC(Nrpn.Messages(0, 4, 0, 1, 1)));
        Assert.Equal("Device", Db.SettingForNrpn(4, 1)?.Parameter.ManualName);
    }

    // p. 185: "Set Upper E-C# at F04 via System Exclusive"
    [Fact]
    public void FavoriteUpperECSharpF04()
    {
        var s = S(A(0, 0, 0, 0x50, 0x29));
        Assert.Equal("Assign Upper", s.Parameter.ManualName);
        Assert.Equal(new[] { 0x29 }, s.IndexValues);
        Assert.Equal("E-C#", s.Parameter.Indices[0].Label(0x29));
        Assert.Equal("F04", s.Parameter.Display(0x68));
        Bytes(Bytes("F0 55 10 10 26 13 00 00 00 50 29 00 68 F7"), XK7SysEx.DataSet(dd, s, 0x68));
        Assert.Equal(s.Address, Db.SettingForNrpn(0x50, 0x29)?.Address);
    }

    // p. 183: "Set the Matrix Level for Lower, 4', middle C at -12.1[dB]"
    [Fact]
    public void MatrixLevelLower4MiddleC()
    {
        var s = S(A(0x13, 0x01, 0x03, 0x00, 0x18));
        Assert.Equal("Lower matrix level", s.Parameter.Name);
        Assert.Equal(new[] { "Footage", "Key" }, s.Parameter.Indices.Select(d => d.Name));
        Assert.Equal("4'", s.Parameter.Indices[0].Label(s.IndexValues[0]));
        Assert.Equal("3C (middle C)", s.Parameter.Indices[1].Label(s.IndexValues[1]));
        var raw = 0x06 << 7 | 0x70;
        Assert.Equal("-12.1 dB", s.Parameter.Display(raw));
        Bytes(Bytes("F0 55 10 10 26 13 13 01 03 00 18 06 70 F7"), XK7SysEx.DataSet(dd, s, raw));
    }

    // p. 183: "Assign the Contact for Middle C, Percussion Third at #3" (the manual prints device 00 here)
    [Fact]
    public void ContactPercussionThirdMiddleC()
    {
        var s = S(A(0x21, 0x02, 0x00, 0x01, 0x18));
        Assert.Equal("Percussion contact leaf", s.Parameter.Name);
        Assert.Equal("Third", s.Parameter.Indices[0].Label(s.IndexValues[0]));
        Assert.Equal("3", s.Parameter.Display(2));
        Bytes(Bytes("F0 55 00 10 26 13 21 02 00 01 18 02 F7"), XK7SysEx.DataSet(0, s, 2));
    }

    // p. 183: "Set Drawbar [LOWER 2] at S04 C-Bourdon 1"
    [Fact]
    public void PipeLower2Bourdon()
    {
        var s = S(A(0x51, 0x00, 0x01, 0x01, 0x00));
        Assert.Equal("Lower pipe stop", s.Parameter.Name);
        Assert.Equal("5 1/3'", s.Parameter.Indices[0].Label(s.IndexValues[0]));
        Assert.Equal("S04 C-Bourdon 1", s.Parameter.Display(3));
        Bytes(Bytes("F0 55 10 10 26 13 51 00 01 01 00 00 03 F7"), XK7SysEx.DataSet(dd, s, 3));
    }

    // p. 177: "ex: Set Lower 8' to level 7 via MIDI. Bx 17 70"
    [Fact]
    public void DrawbarLower8Level7()
    {
        Assert.Equal(0x17, DrawbarCC.Controller(DrawbarPart.Lower, 2));
        Assert.Equal(0x70, DrawbarCC.Value(7));
        Assert.Equal(7, DrawbarCC.Level(0x70));
        Bytes(Bytes("B0 17 70"), new MidiMessage.ControlChange(0, 0x17, 0x70).Bytes);
    }

    // p. 176 program change examples.
    [Fact]
    public void ProgramChangeExamples()
    {
        Assert.Equal("patch F15", PatchSelect.Describe(0x01, 0x0F));
        Assert.Equal("Favorite C#-F", PatchSelect.Describe(0x65, 0x69));
        Assert.Equal("Adjust B", PatchSelect.Describe(null, 0x7F));
        Assert.Equal("patch U07", PatchSelect.Describe(0, 7));
    }

    // The signed two-byte forms printed in the tables.
    [Fact]
    public void SignedTwoByteRanges()
    {
        var oct = S(A(0, 0, 0, 0x1A, 0x00)).Parameter;
        Assert.Equal((0x3F << 7 | 0x7E, 0x40 << 7 | 0x02), (oct.RawMin, oct.RawMax));
        Assert.Equal("-2 octaves", oct.Display(0x3F << 7 | 0x7E));
        Assert.Equal("0 octaves", oct.Display(0x40 << 7));
        Assert.Equal("+1 octave", oct.Display(0x40 << 7 | 0x01));
        Bytes(new byte[] { 0x3F, 0x7E }, XK7SysEx.ValueBytes(0x3F << 7 | 0x7E, 2));

        var transpose = S(A(0, 0, 0, 0, 1)).Parameter;
        Assert.Equal((0x3F << 7 | 0x7A, 0x40 << 7 | 0x06), (transpose.RawMin, transpose.RawMax));
        Assert.Equal("-6 semitones", transpose.Display(0x3F << 7 | 0x7A));

        var vel = S(A(0, 0, 0, 0x09, 0x00)).Parameter;
        Assert.Equal("-15", vel.Display(0x3F << 7 | 0x71));
        Assert.Equal("+15", vel.Display(0x40 << 7 | 0x0F));

        var detune = S(A(0x51, 0, 0, 0, 3)).Parameter;
        Assert.Equal("-50 cents", detune.Display(0x3F << 7 | 0x4E));
        Assert.Equal("+50 cents", detune.Display(0x40 << 7 | 0x32));

        var cutoff = S(A(0x51, 0, 0, 0, 6)).Parameter;
        Assert.Equal("-127", cutoff.Display(0x3F << 7 | 0x01));
        Assert.Equal("0", cutoff.Display(0x40 << 7));
    }

    // Two-byte unsigned ranges printed as MSB LSB pairs.
    [Fact]
    public void TwoByteUnsignedRanges()
    {
        var fast = S(A(0x42, 0, 0, 0, 0)).Parameter;
        Assert.Equal((0, 0x02 << 7 | 0x2D), (fast.RawMin, fast.RawMax));
        Assert.Equal("0 rpm", fast.Display(0));
        Assert.Equal("200 rpm", fast.Display(1));
        Assert.Equal("500 rpm", fast.Display(0x02 << 7 | 0x2D));
        Assert.Equal("120 rpm", S(A(0x42, 0, 0, 1, 1)).Parameter.Display(0x65));
        var angle = S(A(0x42, 0, 0, 0, 6)).Parameter;
        Assert.Equal("359 degrees", angle.Display(0x02 << 7 | 0x67));
        Assert.Equal("Random", angle.Display(0x02 << 7 | 0x68));
        var level = S(A(0x10, 0, 0, 0, 6)).Parameter;
        Assert.Equal("-inf", level.Display(0));
        Assert.Equal("-100.0 dB", level.Display(1));
        Assert.Equal("+4.0 dB", level.Display(0x08 << 7 | 0x11));
        var pipeVol = S(A(0x51, 0, 0, 0, 1)).Parameter;
        Assert.Equal("+4.0 dB", pipeVol.Display(0x01 << 7 | 0x41));
        Assert.Equal("-92.0 dB", pipeVol.Display(1));
        var fav = S(A(0, 0, 0, 0x51, 0)).Parameter;
        Assert.Equal("U99", fav.Display(0x63));
        Assert.Equal("F00", fav.Display(0x64));
        Assert.Equal("F99", fav.Display(0x01 << 7 | 0x47));
        var dist = S(A(0x43, 0, 0, 0, 4)).Parameter;
        Assert.Equal((0x1E, 0x01 << 7 | 0x48), (dist.RawMin, dist.RawMax));
    }
}
