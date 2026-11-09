// Ports of Tests/XK7DCoreTests/FixPassTests.swift and PicturePassTests.swift.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class SendPacingTests
{
    double now;
    readonly OrganSession session = new();
    readonly Capture output = new();

    public SendPacingTests()
    {
        session.Clock = () => now;
        session.Output = output;
    }

    [Fact]
    public void FastSweepIsMergedLatestValueWins()
    {
        var s = S(A(0x42, 0, 0, 0, 0));
        for (var raw = 100; raw <= 140; raw++) { session.Set(s, raw); now += 0.001; }
        Assert.Single(output.Sent);
        now += 0.05;
        session.Tick();
        Assert.Equal(2, output.Sent.Count);
        Bytes(XK7SysEx.ValueBytes(140, 2), output.Sent[^1][11..13]);
        Assert.Equal(140, session.ValueOf(s));
    }

    [Fact]
    public void DifferentSettingsAreAllSentInOrder()
    {
        session.Set(S(A(0, 0, 0, 0x0C, 0x03)), 2);
        session.Set(S(A(0, 0, 0, 0x0C, 0x04)), 1);
        session.Set(S(A(0, 0, 0, 0x0C, 0x05)), 1);
        now += 0.05;
        session.Tick();
        Assert.Equal(new byte[] { 0x03, 0x04, 0x05 }, output.Sent.Select(m => m[10]));
        Assert.Equal(0, session.PacedCount);
    }

    [Fact]
    public void SlowChangesGoOutImmediately()
    {
        var s = S(A(0, 0, 0, 0x11, 0));
        session.Set(s, 1); now += 0.1;
        session.Set(s, 0);
        Assert.Equal(2, output.Sent.Count);
    }
}

public class HoldUntilAnsweredTests
{
    [Fact]
    public void MessagesWaitForTheIdentityReplyThenGoWithTheLearnedID()
    {
        double now = 0;
        var output = new Capture();
        var session = new OrganSession { Clock = () => now, Output = output, HoldUntilAnswered = true };
        session.RequestIdentity();
        var s = S(A(0, 0, 0, 0x10, 0x04));
        session.Set(s, 5);
        Assert.Equal(2, output.Sent.Count);
        Assert.Equal(1, session.HeldCount);
        session.Receive(XK7SysEx.IdentityReply(0x09));
        Assert.Equal(0, session.HeldCount);
        Bytes(XK7SysEx.DataSet(0x09, s, 5), output.Sent[^1]);
    }

    [Fact]
    public void AsksAgainThenGivesUpRatherThanHoldingForever()
    {
        double now = 0;
        var output = new Capture();
        var session = new OrganSession { Clock = () => now, Output = output, HoldUntilAnswered = true };
        session.RequestIdentity();
        session.Set(S(A(0, 0, 0, 0x11, 0)), 1);
        for (var i = 0; i < 40; i++) { now += 0.1; session.Tick(); }
        Assert.Equal(0, session.HeldCount);
        Assert.Equal(0x13, output.Sent[^1][5]);
        Assert.True(output.Sent.Count(m => m[1] == 0x7E) > 4);
    }

    [Fact]
    public void OffByDefaultForTheRealOrgan()
    {
        var output = new Capture();
        var session = new OrganSession { Output = output };
        session.RequestIdentity();
        session.Set(S(A(0, 0, 0, 0x11, 0)), 1);
        Assert.Equal(3, output.Sent.Count);
    }
}

public class SpokenLabelTests
{
    [Fact]
    public void IndexLabelsReadNaturally()
    {
        Assert.Equal("8 foot", IndexDimension.Spoken("8'"));
        Assert.Equal("5 and a third foot", IndexDimension.Spoken("5 1/3'"));
        Assert.Equal("16 foot-1 and a third foot", IndexDimension.Spoken("16'-1 1/3'"));
        Assert.Equal("number 13", IndexDimension.Spoken("#13"));
        Assert.Equal("F92", IndexDimension.Spoken("#F92"));
        Assert.Equal("3C sharp ", IndexDimension.Spoken("3C# "));
        Assert.Equal("E-C sharp", IndexDimension.Spoken("E-C#"));
    }

    [Fact]
    public void SpokenNamesDropRedundantWords()
    {
        Assert.Equal("Lower matrix level, 4 foot, 3C (middle C)", S(A(0x13, 0x01, 0x03, 0x00, 0x18)).SpokenName);
        Assert.Equal("Upper leak level, 8 foot, tone wheel number 13, leaking wheel number 14", S(A(0x11, 0x00, 0x02, 0x0C, 0x0D)).SpokenName);
        Assert.Equal("Pedal sub drawbar level, main footage 8 foot, sub footage 8 foot", S(A(0x31, 0, 0, 1, 2)).SpokenName);
        Assert.Equal("Favorite, Upper, E-C sharp", S(A(0, 0, 0, 0x50, 0x29)).SpokenName);
    }
}

public class MenuSettledValueTests
{
    [Fact]
    public void FoldBackKeysAreKeysLikeTheMenu()
    {
        Assert.Equal("1C", P(A(0x10, 0, 0, 0, 3)).Display(0));
        Assert.Equal("2C", P(A(0x10, 0, 0, 0, 3)).Display(0x0C));
        Assert.Equal("4G", P(A(0x10, 0, 0, 0, 4)).Display(0));
        Assert.Equal("5C", P(A(0x10, 0, 0, 0, 4)).Display(5));
    }

    [Fact]
    public void PercussionDecayIsOneToTwentyFourThenCont()
    {
        var d = P(A(0, 0, 0, 0x11, 0x06));
        Assert.Equal("1", d.Display(0));
        Assert.Equal("24", d.Display(0x17));
        Assert.Equal("Cont", d.Display(0x18));
    }

    [Fact]
    public void OtherMenuNames()
    {
        Assert.Equal("1", P(A(0, 0, 0, 0x30, 0x04)).Display(0));
        Assert.Equal("128", P(A(0, 0, 0, 0x30, 0x04)).Display(127));
        Assert.Equal("Velocity", P(A(0, 0, 0, 0x09, 0x01)).Display(7));
        Assert.Equal("Mid", P(A(0x51, 0, 0, 0, 5)).Display(2));
        Assert.Equal("0 cm", P(A(0x43, 0, 0, 0, 4)).Display(0x1E));
        Assert.Equal("170 cm", P(A(0x43, 0, 0, 0, 4)).Display(200));
        Assert.Equal("100", P(A(0x43, 0, 0, 0, 2)).Display(100));
    }
}

public class PicturePassTests
{
    static Setting Sys(byte a, byte b) => S(A(0, 0, 0, a, b));

    [Fact]
    public void EQBassFrequencyIsTwelveHertzSteps()
    {
        foreach (var setting in new[] { Sys(0x16, 0x00), Sys(0x01, 0x03) })
        {
            var p = setting.Parameter;
            Assert.Equal("20 Hz", p.Display(0));
            Assert.Equal("104 Hz", p.Display(7));
            Assert.Equal("308 Hz", p.Display(0x18));
        }
    }

    [Fact]
    public void PatchEQMidFrequency()
    {
        var p = Sys(0x16, 0x01).Parameter;
        Assert.Equal("250 Hz", p.Display(0));
        Assert.Equal("1.2 kHz", p.Display(5));
        Assert.Equal("3.1 kHz", p.Display(0x0F));
    }

    [Fact]
    public void MasterEQMidIsThirdOctaves()
    {
        var p = Sys(0x01, 0x04).Parameter;
        Assert.Equal(new[] { "125 Hz", "160 Hz", "200 Hz", "250 Hz", "315 Hz", "400 Hz", "500 Hz", "630 Hz", "800 Hz",
                             "1 kHz", "1.25 kHz", "1.6 kHz", "2 kHz", "2.5 kHz", "3.15 kHz", "4 kHz" },
                     p.AllRawValues().Select(r => p.Display(r)));
    }

    [Fact]
    public void TrebleFrequencyIsStillOnlyEndPoints() => Assert.Equal("step 3 of 19", Sys(0x16, 0x02).Parameter.Display(3));

    [Fact]
    public void PreampOutputLevelIsCentred()
    {
        var p = Sys(0x14, 0x02).Parameter;
        Assert.Equal("-64", p.Display(0));
        Assert.Equal("0", p.Display(64));
        Assert.Equal("+63", p.Display(127));
    }

    [Fact]
    public void PedalContactHasThreeLeaves()
    {
        var pedal = S(A(0x21, 0x03, 0x00, 0x00, 0x18)).Parameter;
        Assert.Equal((0, 2), (pedal.RawMin, pedal.RawMax));
        Assert.Equal("3", pedal.Display(2));
        var upper = S(A(0x21, 0x00, 0x00, 0x00, 0x18)).Parameter;
        Assert.Equal((0, 5), (upper.RawMin, upper.RawMax));
    }

    [Fact]
    public void KnobControlNumberGapIsCC66To69()
    {
        var p = Sys(0x19, 0x09).Parameter;
        Assert.StartsWith("CC 65", p.Display(0x1B));
        Assert.StartsWith("CC 66", p.Display(0x1C));
        Assert.StartsWith("CC 69", p.Display(0x1F));
        Assert.StartsWith("CC 70", p.Display(0x20));
    }

    [Fact]
    public void OctaveButtonModesAreXK7Only()
    {
        for (byte b = 1; b <= 3; b++) Assert.True(Sys(0x06, b).Parameter.Xk7Only);
    }

    [Fact]
    public void PatchLoadDrawbarIsTheOrganSettings() =>
        Assert.Contains("organ settings", S(A(0, 0, 0, 0x40, 0x01)).Parameter.Name);
}
