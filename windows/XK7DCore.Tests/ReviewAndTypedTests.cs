// Ports of Tests/XK7DCoreTests/ReviewFixTests.swift, TypedValueTests.swift and EmbeddedTableTests.swift.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class PortPolicyTests
{
    static PortChoice Dev(string n) => new PortChoice.Device(n);

    [Fact]
    public void LooksLikeOrgan()
    {
        Assert.True(PortPolicy.LooksLikeOrgan("XK-7D"));
        Assert.True(PortPolicy.LooksLikeOrgan("Hammond XK 7 USB MIDI"));
        Assert.True(PortPolicy.LooksLikeOrgan("SUZUKI MIDI"));
        Assert.False(PortPolicy.LooksLikeOrgan("IAC Driver Bus 1"));
    }

    [Fact]
    public void RememberedPortWinsWhenPresent() =>
        Assert.Equal(Dev("My Interface"), PortPolicy.LaunchChoice("My Interface", new[] { "XK-7D", "My Interface" }));

    [Fact]
    public void APluggedInOrganBeatsARememberedSimulator()
    {
        Assert.Equal(Dev("XK-7D"), PortPolicy.LaunchChoice("simulator", new[] { "IAC Driver Bus 1", "XK-7D" }));
        Assert.Equal(PortChoice.BuiltInSimulator, PortPolicy.LaunchChoice("simulator", new[] { "IAC Driver Bus 1" }));
    }

    [Fact]
    public void NothingToPick()
    {
        Assert.Equal(PortChoice.NotConnected, PortPolicy.LaunchChoice(null, Array.Empty<string>()));
        Assert.Equal(PortChoice.NotConnected, PortPolicy.LaunchChoice("XK-7D", new[] { "IAC Driver Bus 1" }));
    }

    [Fact]
    public void UnplugIsReportedOnceAndReplugReconnects()
    {
        Assert.Equal(new PortPolicy.Change.Lost("XK-7D"), PortPolicy.AfterPortsChanged(Dev("XK-7D"), false, "XK-7D", Array.Empty<string>()));
        Assert.Equal(new PortPolicy.Change.Nothing(), PortPolicy.AfterPortsChanged(Dev("XK-7D"), true, "XK-7D", new[] { "IAC Driver Bus 1" }));
        Assert.Equal(new PortPolicy.Change.Back("XK-7D"), PortPolicy.AfterPortsChanged(Dev("XK-7D"), true, "XK-7D", new[] { "XK-7D" }));
        Assert.Equal(new PortPolicy.Change.Nothing(), PortPolicy.AfterPortsChanged(Dev("XK-7D"), false, "XK-7D", new[] { "XK-7D" }));
    }

    [Fact]
    public void OrganPluggedInAfterLaunchIsFound()
    {
        Assert.Equal(new PortPolicy.Change.Found("XK-7D"), PortPolicy.AfterPortsChanged(PortChoice.NotConnected, false, null, new[] { "XK-7D" }));
        Assert.Equal(new PortPolicy.Change.Found("My Interface"),
                     PortPolicy.AfterPortsChanged(PortChoice.NotConnected, false, "My Interface", new[] { "My Interface" }));
    }

    [Fact]
    public void DisconnectChosenByThePersonIsRespected()
    {
        Assert.Equal(new PortPolicy.Change.Nothing(), PortPolicy.AfterPortsChanged(PortChoice.NotConnected, false, "none", new[] { "XK-7D" }));
        Assert.Equal(new PortPolicy.Change.Nothing(), PortPolicy.AfterPortsChanged(PortChoice.BuiltInSimulator, false, "simulator", new[] { "XK-7D" }));
    }
}

public class BurstTests
{
    [Fact]
    public void AFewChangesAreSpokenSeparately()
    {
        var c = new AnnouncementCoalescer(0.3, 2);
        for (var i = 0; i < 3; i++) c.Submit($"k{i}", $"t{i}", 0);
        Assert.Equal(new[] { "t0", "t1", "t2" }, c.Due(0.4));
    }

    [Fact]
    public void AFloodIsSpokenOnceWithACount()
    {
        var c = new AnnouncementCoalescer(0.3, 2);
        for (var i = 0; i < 40; i++) c.Submit($"k{i}", $"t{i}", i * 0.005);
        Assert.Empty(c.Due(0.3));
        Assert.Equal(new[] { "t0, and 39 more settings changed" }, c.Due(0.6));
        Assert.True(c.IsEmpty);
    }

    [Fact]
    public void ALongFloodStillSpeaksAfterMaxWait()
    {
        var c = new AnnouncementCoalescer(0.3, 2);
        var t = 0.0;
        var output = new List<string>();
        for (var i = 0; i < 300; i++)
        {
            c.Submit($"k{i % 20}", $"t{i}", t);
            t += 0.01;
            output.AddRange(c.Due(t));
        }
        Assert.Single(output);
        Assert.EndsWith("and 19 more settings changed", output[0]);
    }

    [Fact]
    public void PatchRecallFloodThroughTheSession()
    {
        double now = 0;
        var session = new OrganSession(coalescer: new AnnouncementCoalescer(0.3, 2)) { Clock = () => now };
        var spoken = new List<string>();
        session.OnAnnouncement = spoken.Add;
        session.Receive(Bytes("B0 00 00 C0 05"));
        foreach (var p in Db.Parameters.Where(p => p.Section == Section.Patch && !p.HasIndices && !p.IsText).Take(30))
        {
            session.Receive(XK7SysEx.DataSet(0, new Setting(p), p.RawMin));
            now += 0.002;
        }
        for (var i = 0; i < 20; i++) { now += 0.05; session.Tick(); }
        Assert.Equal(new[] { "Upper: patch U05, and 30 more settings changed" }, spoken);
    }
}

public class TypedNameTests
{
    [Fact]
    public void TypographicQuotesBecomePlain()
    {
        Assert.Equal("Jimmy's \"Ballad\"", TextCodec.Decode(TextCodec.Encode("Jimmy’s “Ballad”")));
        Assert.Equal("Gospel - Slow", TextCodec.Decode(TextCodec.Encode("Gospel – Slow")));
        Assert.Equal("Caf?", TextCodec.Decode(TextCodec.Encode("Café")));
    }
}

public class VibratoOrderTests
{
    [Fact]
    public void KnobOrder()
    {
        var p = S(A(0, 0, 0, 0x12, 0x01)).Parameter;
        Assert.Equal(new[] { "V-1", "C-1", "V-2", "C-2", "V-3", "C-3" }, p.AllRawValues().Select(r => p.Display(r)));
    }
}

public class ChannelMismatchTests
{
    [Fact]
    public void ControlsOnTheWrongChannelAreReportedOncePerConnection()
    {
        var session = new OrganSession();
        var reported = new List<int>();
        session.OnChannelMismatch = reported.Add;
        session.Receive(Bytes("B3 63 10 62 04 06 01"));
        session.Receive(Bytes("B3 63 11 62 00 06 01"));
        session.Receive(Bytes("B3 0E 40"));
        Assert.Equal(new[] { 3 }, reported);
        session.ResetConnection();
        session.Receive(Bytes("B3 0E 50"));
        Assert.Equal(new[] { 3, 3 }, reported);
    }

    [Fact]
    public void RightChannelAndOtherTrafficSayNothing()
    {
        var session = new OrganSession();
        var reported = new List<int>();
        session.OnChannelMismatch = reported.Add;
        session.Receive(Bytes("B0 63 10 62 04 06 01"));
        session.Receive(Bytes("B1 07 64 B2 0B 40"));
        session.Receive(Bytes("91 3C 40 C1 05"));
        Assert.Empty(reported);
    }
}

public class TypedValueTests
{
    [Fact]
    public void NumbersInDisplayUnits()
    {
        var fast = P(A(0x42, 0, 0, 0, 0));
        Assert.Equal(141, fast.RawValueFromTyped("340 rpm"));
        Assert.Equal(141, fast.RawValueFromTyped("340"));
        Assert.Equal(0, fast.RawValueFromTyped("0"));
        Assert.Null(fast.RawValueFromTyped("150"));
        Assert.Null(fast.RawValueFromTyped("600"));
        Assert.Equal(442, P(A(0, 0, 0, 0, 0)).RawValueFromTyped("442 Hz"));
        var level = P(A(0x10, 0, 0, 0, 6));
        Assert.Equal(880, level.RawValueFromTyped("-12.1 dB"));
        Assert.Equal(1041, level.RawValueFromTyped("+4"));
        Assert.Equal(0, level.RawValueFromTyped("-inf"));
        Assert.Null(level.RawValueFromTyped("-"));
        var oct = P(A(0, 0, 0, 0x1A, 0));
        Assert.Equal(8193, oct.RawValueFromTyped("+1"));
        Assert.Equal(8190, oct.RawValueFromTyped("-2"));
        Assert.Null(oct.RawValueFromTyped("3"));
        var angle = P(A(0x42, 0, 0, 0, 6));
        Assert.Equal(360, angle.RawValueFromTyped("random"));
        Assert.Equal(90, angle.RawValueFromTyped("90"));
        var chan = P(A(0, 0, 0, 0x0D, 0));
        Assert.Equal(2, chan.RawValueFromTyped("3"));
        Assert.Equal(16, chan.RawValueFromTyped("off"));
        Assert.Null(chan.RawValueFromTyped("17"));
        var brake = P(A(0, 0, 0, 0x18, 1));
        Assert.Equal(24, brake.RawValueFromTyped("2.5 sec"));
        Assert.Equal("2.5 sec", brake.Display(24));
    }

    [Fact]
    public void NotesBothWays()
    {
        var split = P(A(0, 0, 0, 0x1A, 2));
        Assert.Equal(60, split.RawValueFromTyped("3C"));
        Assert.Equal(60, split.RawValueFromTyped("C3"));
        Assert.Equal(61, split.RawValueFromTyped("3C#"));
        Assert.Equal(61, split.RawValueFromTyped("c sharp 3"));
        Assert.Equal(0, split.RawValueFromTyped("-2C"));
        Assert.Equal(72, split.RawValueFromTyped("72"));
        Assert.Null(split.RawValueFromTyped("H3"));
    }

    [Fact]
    public void BalanceAndSteps()
    {
        var pan = P(A(0, 0, 0, 0x30, 0x0A));
        Assert.Equal(64, pan.RawValueFromTyped("center"));
        Assert.Equal(54, pan.RawValueFromTyped("L10"));
        Assert.Equal(127, pan.RawValueFromTyped("right 63"));
        Assert.Null(pan.RawValueFromTyped("R64"));
        var mix = P(A(0, 0, 0, 0x12, 0x04));
        Assert.Equal(64, mix.RawValueFromTyped("even"));
        Assert.Equal(0, mix.RawValueFromTyped("D64"));
        Assert.Equal(127, mix.RawValueFromTyped("63V"));
        var rise = P(A(0x42, 0, 0, 0, 2));
        Assert.Equal(12, rise.RawValueFromTyped("step 12"));
        Assert.Equal(0x24, rise.RawValueFromTyped("12.5 sec"));
        Assert.Null(rise.RawValueFromTyped("step 40"));
    }

    [Fact]
    public void HugeNumbersAreNotValuesAndDontStopTheApp()
    {
        var level = P(A(0x10, 0, 0, 0, 6));
        var pan = P(A(0, 0, 0, 0x30, 0x0A));
        var rise = P(A(0x42, 0, 0, 0, 2));
        foreach (var typed in new[] { "1e400", "-1e400", "99999999999999999999", "-99999999999999999999", "1e19" })
        {
            Assert.Null(level.RawValueFromTyped(typed));
            Assert.Null(pan.RawValueFromTyped(typed));
            Assert.Null(pan.RawValueFromTyped("l" + typed));
            Assert.Null(rise.RawValueFromTyped("step " + typed));
        }
    }

    [Fact]
    public void EveryDisplayedValueTypesBackToItself()
    {
        var checkedCount = 0;
        foreach (var p in Db.Parameters)
        {
            if (p.Kind.Type is not (ValueType.Number or ValueType.Note or ValueType.Balance or ValueType.Steps)) continue;
            foreach (var raw in new[] { p.RawMin, p.RawMax, (p.RawMin + p.RawMax) / 2 }.Distinct())
            {
                Assert.True(p.RawValueFromTyped(p.Display(raw)) == raw, $"{p.Id}: {p.Display(raw)}");
                checkedCount++;
            }
        }
        Assert.True(checkedCount > 500);
    }
}

/// <summary>The table is compiled into the DLL, as on the Mac, so there's no file to lose.</summary>
public class EmbeddedTableTests
{
    [Fact]
    public void TheEmbeddedTableIsTheSharedJSONFile()
    {
        using var s = typeof(ParameterDatabase).Assembly.GetManifestResourceStream("parameters.json")!;
        using var r = new StreamReader(s);
        Assert.Equal(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "parameters.json")), r.ReadToEnd());
    }

    [Fact]
    public void SharedLoadsWithoutFiles()
    {
        Assert.Null(ParameterDatabase.LoadError);
        Assert.Equal(537, ParameterDatabase.Shared.Parameters.Count);
    }

    [Fact]
    public void ABrokenTableSaysWhyInsteadOfCrashing()
    {
        var e = Assert.Throws<ParameterDatabaseException>(() => ParameterDatabase.FromJson("{\"parameters\": [{\"id\": \"x\"}]}"));
        Assert.StartsWith("parameters.json could not be read", e.Message);
    }
}
