// Port of Tests/XK7DCoreTests/DatabaseAndSessionTests.swift.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class ParameterDatabaseTests
{
    [Fact]
    public void TableLoadsWithEverySection()
    {
        Assert.Equal(537, Db.Parameters.Count);
        Assert.Equal(new[] { Section.Patch, Section.Custom, Section.System }.OrderBy(x => x),
                     Db.Parameters.Select(p => p.Section).Distinct().OrderBy(x => x));
        Assert.Equal(Db.Parameters.Count, Db.Parameters.Select(p => p.Id).Distinct().Count());
    }

    [Fact]
    public void EveryNRPNEqualsTheLastTwoAddressBytes()
    {
        foreach (var p in Db.Parameters)
        {
            if (p.Nrpn is not { } n) continue;
            Assert.Equal((0, 0, 0), ((int)p.BaseAddress.B0, (int)p.BaseAddress.B1, (int)p.BaseAddress.B2));
            Assert.Equal((p.BaseAddress.B3, p.BaseAddress.B4), (n.Msb, n.Lsb));
        }
    }

    [Fact]
    public void EveryAddressLooksUpToItsOwnParameter()
    {
        var checkedCount = 0;
        foreach (var p in Db.Parameters)
        {
            if (p.HasIndices)
            {
                var picks = p.Indices.Select(d => new[] { d.Options[0].Raw, d.Options[d.Options.Count / 2].Raw, d.Options[^1].Raw }).ToList();
                for (var k = 0; k < 3; k++)
                {
                    var iv = picks.Select(x => x[k]).ToArray();
                    var s = new Setting(p, iv);
                    Assert.Equal(p.Id, Db.SettingAt(s.Address)?.Parameter.Id);
                    Assert.Equal(iv, Db.SettingAt(s.Address)?.IndexValues);
                    checkedCount++;
                }
            }
            else
            {
                Assert.Equal(p.Id, Db.SettingAt(p.BaseAddress)?.Parameter.Id);
                checkedCount++;
            }
            if (p.Nrpn is { } n && !p.HasIndices) Assert.Equal(p.Id, Db.SettingForNrpn(n.Msb, n.Lsb)?.Parameter.Id);
        }
        Assert.True(checkedCount > 600);
    }

    [Fact]
    public void NoTwoParametersShareAnAddress()
    {
        var seen = new Dictionary<Address, string>();
        foreach (var p in Db.Parameters.Where(p => !p.HasIndices))
        {
            Assert.False(seen.ContainsKey(p.BaseAddress), $"{p.Id} shares {p.BaseAddress}");
            seen[p.BaseAddress] = p.Id;
        }
        foreach (var (addr, id) in seen) Assert.Equal(id, Db.SettingAt(addr)?.Parameter.Id);
    }

    [Fact]
    public void ValuesFitTheirByteLength()
    {
        foreach (var p in Db.Parameters)
        {
            Assert.True(p.BaseAddress.Bytes.All(b => b < 0x80), $"{p.Id} address must be 7-bit");
            if (p.Nrpn is { } n) Assert.True(n.Msb < 0x80 && n.Lsb < 0x80, p.Id);
            foreach (var d in p.Indices)
                Assert.True(d.Options.All(o => p.BaseAddress[d.Position] + o.Raw < 0x80), p.Id);
        }
        foreach (var p in Db.Parameters.Where(p => !p.IsText))
        {
            var limit = p.Length == 1 ? 127 : 16383;
            Assert.True(p.RawMax <= limit, p.Id);
            Assert.True(p.RawMin >= 0, p.Id);
            Assert.Contains(p.Length, new[] { 1, 2 });
            foreach (var raw in new[] { p.RawMin, p.RawMax })
                Assert.False(p.Display(raw).StartsWith("Unknown", StringComparison.Ordinal), $"{p.Id} {raw}");
        }
    }

    [Fact]
    public void IndexedFamiliesUseOnlyManualRanges()
    {
        Assert.Equal("Tone wheel level, F96", S(A(0x10, 0, 0, 1, 0x6B)).SpokenName);
        Assert.Null(Db.SettingAt(A(0x10, 0, 0, 1, 0x6C)));
        Assert.Equal("Tone wheel level, number 13", Db.SettingAt(A(0x10, 0, 0, 1, 0x18))?.SpokenName);
        Assert.Equal("Tone wheel level, F01", Db.SettingAt(A(0x10, 0, 0, 1, 0x0C))?.SpokenName);
        Assert.Null(Db.SettingAt(A(0x11, 0, 0, 0x60, 0)));
        Assert.Null(Db.SettingAt(A(0x11, 2, 0, 0, 0)));
        Assert.NotNull(Db.SettingAt(A(0x11, 2, 3, 0, 0)));
        Assert.Null(Db.SettingAt(A(0x13, 1, 3, 0, 0x3D)));
    }

    [Fact]
    public void SearchFindsByFriendlyOrManualName()
    {
        Assert.Contains(Db.Search("leslie horn fast"), p => p.ManualName == "Fast Speed Horn");
        Assert.Contains(Db.Search("Organ Type"), p => p.ManualName == "Organ Type");
        Assert.True(Db.Search("percussion third").Count > 0 || Db.Search("percussion harmonic").Count > 0);
        Assert.Contains(Db.Search("master tune"), p => p.ManualName == "Master Tune");
        Assert.Equal(Db.Parameters.Count, Db.Search("").Count);
    }
}

public class ValueFormatTests
{
    [Fact]
    public void NotesFollowTheDisplay()
    {
        Assert.Equal("3C", NoteName.Display(60));
        Assert.Equal("-2C", NoteName.Display(0));
        Assert.Equal("8G", NoteName.Display(127));
        Assert.Equal("3C#", NoteName.Display(61));
        Assert.Equal("C sharp 3", NoteName.Spoken(61));
    }

    [Fact]
    public void BalanceValues()
    {
        var pan = P(A(0, 0, 0, 0x30, 0x0A));
        Assert.Equal("L64", pan.Display(0));
        Assert.Equal("Center", pan.Display(64));
        Assert.Equal("R63", pan.Display(127));
        Assert.Equal("left 64", pan.Spoken(0));
        var mix = P(A(0, 0, 0, 0x12, 0x04));
        Assert.Equal("D64", mix.Display(0));
        Assert.Equal("Even", mix.Display(64));
        Assert.Equal("63V", mix.Display(127));
        Assert.Equal("vibrato 63", mix.Spoken(127));
    }

    [Fact]
    public void StepsOnlyNameTheEndPoints()
    {
        var rate = P(A(0, 0, 0, 0x12, 0x03));
        Assert.Equal("5.78 Hz", rate.Display(0));
        Assert.Equal("7.90 Hz", rate.Display(127));
        Assert.Equal("step 64 of 127", rate.Display(64));
        var rise = P(A(0x42, 0, 0, 0, 2));
        Assert.Equal("0.8 sec", rise.Display(0));
        Assert.Equal("12.5 sec", rise.Display(0x24));
    }

    [Fact]
    public void OtherDisplays()
    {
        Assert.Equal("5.0 sec", P(A(0, 0, 0, 0x18, 0x01)).Display(0x31));
        Assert.Equal("0.1 sec", P(A(0, 0, 0, 0x18, 0x01)).Display(0));
        Assert.Equal("-24 semitones", P(A(0, 0, 0, 0x18, 0x00)).Display(0x28));
        Assert.Equal("+12 semitones", P(A(0, 0, 0, 0x18, 0x00)).Display(0x4C));
        Assert.Equal("-9", P(A(0, 0, 0, 0x16, 0x03)).Display(0));
        Assert.Equal("0", P(A(0, 0, 0, 0x16, 0x03)).Display(9));
        Assert.Equal("1", P(A(0, 0, 0, 0x0D, 0x00)).Display(0));
        Assert.Equal("Off", P(A(0, 0, 0, 0x0D, 0x00)).Display(16));
        Assert.Equal("Off", P(A(0, 0, 0, 0x04, 0x04)).Display(0));
        Assert.Equal("-40 dB", P(A(0, 0, 0, 0x04, 0x04)).Display(1));
        Assert.Equal("0 dB", P(A(0, 0, 0, 0x04, 0x04)).Display(0x29));
        Assert.Equal("-50 cm", P(A(0x43, 0, 0, 0, 3)).Display(0x0E));
        Assert.Equal("0 dB", P(A(0x43, 0, 0, 0, 0)).Display(0x4D));
        Assert.Equal("minus infinity", P(A(0x43, 0, 0, 0, 0)).Spoken(0));
        Assert.Equal("Continue", P(A(0, 0, 0, 0x1F, 0x09)).Display(0x0A));
        Assert.Equal("Bass 1C", P(A(0, 0, 0, 0x03, 0x00)).Display(0x10));
        Assert.Equal("Bass 3C", P(A(0, 0, 0, 0x03, 0x00)).Display(0x28));
        Assert.Equal("To Adjust A#", P(A(0, 0, 0, 0x03, 0x00)).Display(0x29));
    }
}

/// <summary>The session on its own, fed raw bytes, with a fake clock.</summary>
public class OrganSessionTests
{
    readonly OrganSession session;
    double now = 100;
    readonly List<string> spoken = new();
    readonly Capture output = new();
    readonly List<(OrganEvent, bool)> events = new();
    List<byte[]> Sent => output.Sent;

    public OrganSessionTests()
    {
        session = new OrganSession(coalescer: new AnnouncementCoalescer(0.3, 2));
        session.Clock = () => now;
        session.OnAnnouncement = spoken.Add;
        session.OnEvent = (e, echo) => events.Add((e, echo));
        session.Output = output;
    }

    void Advance(double dt) { now += dt; session.Tick(); }

    [Fact]
    public void IncomingNRPNIsAnnounced()
    {
        session.Receive(Bytes("B0 63 10 62 04 06 01"));
        Assert.Empty(spoken);
        Advance(0.4);
        Assert.Equal(new[] { "Organ type: Mellow" }, spoken);
        Assert.Equal(1, session.ValueOf(S(A(0, 0, 0, 0x10, 4))));
    }

    [Fact]
    public void NRPNOnAnotherChannelIsIgnored()
    {
        session.Receive(Bytes("B3 63 10 62 04 06 01"));
        Advance(1);
        Assert.Empty(spoken);
    }

    [Fact]
    public void IncomingDataSetIsAnnouncedFrontLoaded()
    {
        session.Receive(Bytes("F0 55 00 10 26 13 42 00 00 00 00 01 0D F7"));
        Advance(0.4);
        Assert.Equal(new[] { "Leslie horn fast speed: 340 rpm" }, spoken);
    }

    [Fact]
    public void KnobBurstSpeaksOnceWithTheLatestValue()
    {
        for (var v = 100; v <= 141; v++)
        {
            var b = XK7SysEx.ValueBytes(v, 2);
            session.Receive(Bytes("F0 55 00 10 26 13 42 00 00 00 00").Concat(b).Append((byte)0xF7));
            Advance(0.03);
        }
        Advance(0.4);
        Assert.Equal(new[] { "Leslie horn fast speed: 340 rpm" }, spoken);
    }

    [Fact]
    public void OwnEchoIsNotReannounced()
    {
        var s = S(A(0, 0, 0, 0x11, 0x00));
        session.Set(s, 1);
        Bytes(Bytes("F0 55 00 10 26 13 00 00 00 11 00 01 F7"), Sent[^1]);
        session.Receive(Bytes("B0 63 11 62 00 06 01"));   // the organ repeats it back
        Advance(1);
        Assert.Empty(spoken);
        Assert.True(events[^1].Item2, "reported as an echo");
        session.Receive(Bytes("B0 06 00"));                // a different value is not an echo
        Advance(1);
        Assert.Equal(new[] { "Percussion on: Off" }, spoken);
        session.Set(s, 1);
        now += 10;                                         // and the same value much later is a real change
        session.Receive(Bytes("B0 63 11 62 00 06 01"));
        Advance(1);
        Assert.Equal("Percussion on: On", spoken[^1]);
    }

    [Fact]
    public void DrawbarCCAndRegistrationSpeakOnce()
    {
        session.Receive(Bytes("B0 0E 60"));                                   // Upper 8' to 6 as a CC
        session.Receive(Bytes("F0 55 00 10 26 13 00 00 01 01 02 06 F7"));     // and as SysEx
        Advance(0.4);
        Assert.Equal(new[] { "Upper 8 foot: 6" }, spoken);
        var s = session.RegistrationSetting(DrawbarPart.Lower, 3)!;
        session.Set(s, 4);
        session.Receive(Bytes("B0 18 40"));                                   // our own change echoed as a CC
        Advance(1);
        Assert.Equal(new[] { "Upper 8 foot: 6" }, spoken);
    }

    [Fact]
    public void ProgramChanges()
    {
        session.Receive(Bytes("B0 00 01 B0 20 00 C0 0F"));
        session.Receive(Bytes("B1 00 65 C1 69"));
        session.Receive(Bytes("C2 7F"));
        Advance(0.4);
        Assert.Equal(new[] { "Upper: patch F15", "Lower: Favorite C sharp-F", "Pedal: Adjust B" }, spoken);
    }

    [Fact]
    public void ControllersAndLeslieSpeed()
    {
        session.Receive(Bytes("B0 01 00 B0 31 7F"));
        Advance(0.4);
        Assert.Equal(new[] { "Leslie speed: slow", "Tone wheel brake: on" }.OrderBy(x => x), spoken.OrderBy(x => x));
    }

    [Fact]
    public void DataSetCarryingSeveralParameters()
    {
        session.Receive(Bytes("F0 55 00 10 26 13 00 00 00 11 00 01 01 00 F7"));
        Advance(0.4);
        Assert.Equal(new[] { "Percussion on: On", "Percussion harmonic: Third", "Percussion decay: Slow" }, spoken);
    }

    [Fact]
    public void NamesAndUnknownAddresses()
    {
        session.Receive(XK7SysEx.DataSet(0, A(0, 0, 0x10, 0, 0), TextCodec.Encode("Jimmy's Blues")));
        session.Receive(XK7SysEx.DataSet(0, A(0x7E, 0, 0, 0, 0), new byte[] { 1 }));
        Advance(0.4);
        Assert.Equal(new[] { "Patch name, upper: Jimmy's Blues" }, spoken);
        Assert.Contains(events, e => e.Item1 is OrganEvent.UnknownAddress);
    }

    [Fact]
    public void DeviceIDIsLearnedFromTheOrgan()
    {
        byte? learned = null;
        session.OnDeviceIdLearned = d => learned = d;
        session.Receive(XK7SysEx.IdentityReply(0x11));
        Assert.Equal((byte)0x11, learned);
        Assert.True(session.OrganAnswered);
        Assert.Equal(0x11, session.Addressing.DeviceId);
        Assert.Equal(0x11, session.Set(S(A(0, 0, 0, 0x11, 0)), 0)[2]);
    }

    [Fact]
    public void IdentityRequestGoesToOurIDAndAllCall()
    {
        session.RequestIdentity();
        Assert.Equal(new[] { "F0 7E 00 06 01 F7", "F0 7E 7F 06 01 F7" }, Sent.Select(Hex));
    }

    [Fact]
    public void DumpPacketsAreCollectedAndAcknowledged()
    {
        session.RequestDump(DumpType.Temporary);
        Bytes(Bytes("F0 55 00 10 26 12 07 F7"), Sent[^1]);
        for (var n = 0; n < 3; n++) session.Receive(XK7SysEx.DataPacket(0, 7, n, Enumerable.Repeat((byte)n, 64).ToArray()));
        Assert.Equal(4, Sent.Count);
        Bytes(XK7SysEx.Acknowledge(0, 7, 0, 2), Sent[^1]);
        var snap = session.FinishDump()!;
        Assert.Equal(3, snap.Count);
        Assert.True(snap.AllChecksumsOK);
        Assert.Equal(3 * 139, snap.SyxData.Length);
    }

    [Fact]
    public void SendingClampsToTheManualRange()
    {
        var msg = session.Set(S(A(0, 0, 0, 0, 0)), 999);   // Master tune 430-450
        Bytes(new byte[] { 0x03, 0x42 }, msg[11..13]);
    }
}
