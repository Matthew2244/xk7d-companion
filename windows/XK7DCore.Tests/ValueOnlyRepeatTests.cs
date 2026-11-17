// Port of Tests/XK7DCoreTests/ValueOnlyRepeatTests.swift.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class ValueOnlyRepeatTests
{
    readonly OrganSession session;
    double now = 100;
    readonly List<string> spoken = new();

    public ValueOnlyRepeatTests()
    {
        session = new OrganSession(coalescer: new AnnouncementCoalescer(0.3, 2));
        session.Clock = () => now;
        session.OnAnnouncement = spoken.Add;
    }

    void Advance(double dt) { now += dt; session.Tick(); }

    /// <summary>Upper 8 foot drawbar to a level, as the organ sends it.</summary>
    void Drawbar(int level) =>
        session.Receive(new byte[] { 0xB0, (byte)DrawbarCC.Controller(DrawbarPart.Upper, 2), (byte)DrawbarCC.Value(level) });
    /// <summary>Organ Type by NRPN: 1 Mellow, 2 Vx.</summary>
    void OrganType(byte raw) => session.Receive(new byte[] { 0xB0, 0x63, 0x10, 0x62, 0x04, 0x06, raw });

    [Fact]
    public void FirstMoveIsFullAndTheNextIsTheValueOnly()
    {
        Drawbar(6); Advance(0.4);
        Drawbar(4); Advance(0.4);
        Assert.Equal(new[] { "Upper 8 foot: 6", "4" }, spoken);
        Assert.Equal("Upper 8 foot: 4", session.LastAnnouncement);
        OrganType(1); Advance(0.4);
        OrganType(2); Advance(0.4);
        Assert.Equal(new[] { "Organ type: Mellow", "Vx." }, spoken.TakeLast(2));
    }

    [Fact]
    public void AnotherControlInBetweenBringsTheNameBack()
    {
        Drawbar(6); Advance(0.4);
        OrganType(1); Advance(0.4);
        Drawbar(5); Advance(0.4);
        OrganType(2); Advance(0.4);
        Assert.Equal(new[] { "Upper 8 foot: 6", "Organ type: Mellow", "Upper 8 foot: 5", "Organ type: Vx." }, spoken);
    }

    [Fact]
    public void AStatusLineOrAnUrgentLineBringsTheNameBack()
    {
        Drawbar(6); Advance(0.4);
        session.Speak("Organ connected again");
        Drawbar(5); Advance(0.4);
        session.Receive(new byte[] { 0xB0, 92, 127 });   // Leslie fast, said at once
        Drawbar(4); Advance(0.4);
        Assert.Equal(new[] { "Upper 8 foot: 6", "Organ connected again", "Upper 8 foot: 5", "Fast", "Upper 8 foot: 4" }, spoken);
    }

    [Fact]
    public void TheAppSayingSomethingBringsTheNameBack()
    {
        Drawbar(6); Advance(0.4);
        session.Coalescer.BreakRepeat();     // what the app does for its own confirmations
        Drawbar(5); Advance(0.4);
        Assert.Equal(new[] { "Upper 8 foot: 6", "Upper 8 foot: 5" }, spoken);
    }

    [Fact]
    public void AQuietGapBringsTheNameBack()
    {
        Drawbar(6); Advance(0.4);
        Advance(AnnouncementCoalescer.RepeatQuietGap - 1);
        Drawbar(5); Advance(0.4);
        Advance(AnnouncementCoalescer.RepeatQuietGap + 0.1);
        Drawbar(4); Advance(0.4);
        Assert.Equal(new[] { "Upper 8 foot: 6", "5", "Upper 8 foot: 4" }, spoken);
        Assert.Equal(10, AnnouncementCoalescer.RepeatQuietGap);
    }

    [Fact]
    public void ALongSweepSaysTheNameOnceThenNumbers()
    {
        // One step every 0.1 s for 5 s: past MaxWait twice, so two lines along the way and one at the end.
        for (var i = 0; i < 50; i++) { Drawbar(i / 6 % 9); Advance(0.1); }
        Advance(0.4);
        Assert.True(spoken.Count >= 3, string.Join(" | ", spoken));
        Assert.StartsWith("Upper 8 foot: ", spoken[0]);
        foreach (var line in spoken.Skip(1)) Assert.True(int.TryParse(line, out _), "value only: " + string.Join(" | ", spoken));
    }

    [Fact]
    public void TurnedOffSaysTheNameEveryTime()
    {
        session.SayValueOnlyOnRepeat = false;
        Drawbar(6); Advance(0.4);
        Drawbar(4); Advance(0.4);
        Assert.Equal(new[] { "Upper 8 foot: 6", "Upper 8 foot: 4" }, spoken);
        for (var i = 0; i < 30; i++) { Drawbar(i / 4 % 9); Advance(0.1); }
        Advance(0.4);
        Assert.All(spoken, l => Assert.StartsWith("Upper 8 foot: ", l));
    }

    [Fact]
    public void BurstsAndPatchChangesAreAlwaysFull()
    {
        Drawbar(6); Advance(0.4);
        // A patch recall sending ten settings at once: one summary line, and it resets the repeat.
        for (var i = 0; i < 9; i++) session.Receive(new byte[] { 0xB0, (byte)DrawbarCC.Controller(DrawbarPart.Upper, i), 0x20 });
        OrganType(2);
        Advance(0.4);
        Assert.Equal(2, spoken.Count);
        Assert.EndsWith("and 9 more settings changed", spoken[1]);
        Drawbar(6); Advance(0.4);
        Assert.Equal("Upper 8 foot: 6", spoken[^1]);
        // A patch change twice in a row: full both times (it has no value-only form).
        session.Receive(new byte[] { 0xB0, 0x00, 0x01, 0xC0, 15 }); Advance(0.4);
        session.Receive(new byte[] { 0xB0, 0x00, 0x01, 0xC0, 16 }); Advance(0.4);
        Assert.StartsWith("Upper: ", spoken[^2]);
        Assert.StartsWith("Upper: ", spoken[^1]);
    }

    [Fact]
    public void ValueOnlyFormsAreBuiltNotCut()
    {
        var percussion = S(A(0, 0, 0, 0x11, 0x00));
        Assert.Equal("Percussion on", OrganSession.Line(percussion, 1));
        Assert.Equal("on", OrganSession.ValueOnly(percussion, 1));
        Assert.Equal("340 rpm", OrganSession.ValueOnly(S(A(0x42, 0, 0, 0, 0)), 141));
        Assert.Equal("442 Hz", OrganSession.ValueOnly(S(A(0, 0, 0, 0, 0)), 442));
    }

    [Fact]
    public void CoalescerAlone()
    {
        var c = new AnnouncementCoalescer(0.3, 2);
        c.Submit("a", "A: 1", 0, valueOnly: "1");
        Assert.Equal(new[] { new AnnouncementCoalescer.Line("A: 1", "A: 1") }, c.DueLines(0.4));
        c.Submit("a", "A: 2", 1, valueOnly: "2");
        Assert.Equal(new[] { new AnnouncementCoalescer.Line("2", "A: 2") }, c.DueLines(1.4));
        c.Submit("a", "A: 3", 2);   // no value-only form: full
        Assert.Equal(new[] { "A: 3" }, c.Due(2.4));
        c.Submit("a", "A: 4", 3, valueOnly: "4");
        Assert.Equal(new[] { "A: 4" }, c.Flush());
        c.Submit("a", "A: 5", 4, valueOnly: "5");
        Assert.Equal(new[] { "A: 5" }, c.Due(4.4));
    }
}
