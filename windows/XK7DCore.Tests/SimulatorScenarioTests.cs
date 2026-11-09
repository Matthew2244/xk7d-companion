// Port of Tests/XK7DIntegrationTests/AppSimulatorTests.swift (the in-process half; Windows has no
// virtual MIDI ports, so the Windows app always uses this link to its simulator). Messages are queued
// both ways like real MIDI and delivered as the clock moves, so the timing is deterministic.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class SimulatorScenarioTests
{
    readonly OrganSession session;
    readonly SimulatedOrgan organ;
    readonly List<string> spoken = new();
    readonly Queue<Action> queue = new();
    double now;

    public SimulatorScenarioTests()
    {
        session = new OrganSession(coalescer: new AnnouncementCoalescer(0.25, 3)) { Clock = () => now };
        session.OnAnnouncement = spoken.Add;
        organ = new SimulatedOrgan();
        _ = new LoopbackLink(session, organ, synchronous: false, post: queue.Enqueue);
    }

    /// <summary>Deliver queued messages and tick the session every 10 ms of fake time until the condition holds.</summary>
    bool WaitUntil(Func<bool> condition, double timeout = 3)
    {
        var end = now + timeout;
        while (now < end)
        {
            while (queue.Count > 0) queue.Dequeue()();
            session.Tick();
            if (condition()) return true;
            now += 0.01;
        }
        session.Tick();
        return condition();
    }

    void Settle(double seconds) => WaitUntil(() => false, seconds);

    [Fact]
    public void AppAndSimulatorInProcess()
    {
        // 1. A change made in the app reaches the organ.
        var organType = S(A(0, 0, 0, 0x10, 0x04));
        session.Set(organType, 5);
        Assert.True(WaitUntil(() => organ.Value(organType) == 5));
        var name = S(A(0, 0, 0x10, 0, 0));
        session.Set(name, "Gospel Shout");
        Assert.True(WaitUntil(() => organ.Texts.TryGetValue(name.Address, out var t) && t == "Gospel Shout"));
        var wheel = new Setting(S(A(0x10, 0, 0, 1, 0)).Parameter, new[] { 0x18 });
        session.Set(wheel, 900);
        Assert.True(WaitUntil(() => organ.Value(wheel) == 900), "indexed SysEx-only parameter");

        // 2. The organ answers who it is.
        session.RequestIdentity();
        Assert.True(WaitUntil(() => session.OrganAnswered));

        // 3. A panel change in SysEx mode is announced, name first.
        organ.IndividualMode = IndividualMode.Sysex;
        var hornFast = S(A(0x42, 0, 0, 0, 0));
        organ.PanelChange(hornFast, 141);
        Assert.True(WaitUntil(() => spoken.Contains("Leslie horn fast speed: 340 rpm")), string.Join(" | ", spoken));

        // 4. A knob turned through many values: one announcement, the final value.
        spoken.Clear();
        foreach (var v in organ.KnobSweep(hornFast, 201, 30)) organ.PanelChange(hornFast, v);
        Assert.True(WaitUntil(() => spoken.Count > 0));
        Settle(0.6);
        Assert.Equal(new[] { "Leslie horn fast speed: 400 rpm" }, spoken);

        // 5. In NRPN mode (the template default), NRPN parameters are announced too...
        spoken.Clear();
        organ.IndividualMode = IndividualMode.Nrpn;
        organ.PanelChange(S(A(0, 0, 0, 0x11, 0x01)), 1);
        Assert.True(WaitUntil(() => spoken.SequenceEqual(new[] { "Percussion harmonic: Third" })), string.Join(" | ", spoken));
        organ.PanelChange(S(A(0, 0, 0, 0, 0)), 442);
        Assert.True(WaitUntil(() => spoken.Count > 0 && spoken[^1] == "Master tune: 442 Hz"), string.Join(" | ", spoken));
        // ...but SysEx-only parameters cannot travel as NRPN, so nothing arrives for them.
        spoken.Clear();
        organ.PanelChange(hornFast, 50);
        Settle(0.6);
        Assert.Empty(spoken);

        // 6. Drawbars and patches.
        organ.PanelChange(S(A(0, 0, 1, 1, 2)), 6);
        Assert.True(WaitUntil(() => spoken.Contains("Upper 8 foot: 6")), string.Join(" | ", spoken));
        organ.SelectPatch("Lower", 1, 15);
        Assert.True(WaitUntil(() => spoken.Contains("Lower: patch F15")), string.Join(" | ", spoken));

        // 7. Our own change coming straight back is not re-announced.
        spoken.Clear();
        organ.IndividualMode = IndividualMode.Sysex;
        var reverb = S(A(0, 0, 0, 0x17, 0x07));
        session.Set(reverb, 5);
        organ.PanelChange(reverb, 5);
        Settle(0.6);
        Assert.Empty(spoken);
        Assert.Equal(5, session.ValueOf(reverb));

        // 8. Memory dump: 6 + 11 packets, checksums good, every packet acknowledged.
        session.RequestDump(DumpType.Temporary);
        Assert.True(WaitUntil(() => (session.CurrentDump?.Count ?? 0) == 17));
        Assert.True(session.CurrentDump!.AllChecksumsOK);
        Assert.True(WaitUntil(() => organ.Acknowledgements == 17));
        var snap = session.FinishDump()!;
        Assert.Equal(6, snap.Packets.Count(p => p.Type == 7));
        Assert.Equal(11, snap.Packets.Count(p => p.Type == 8));
    }

    [Fact]
    public void DeviceIDMismatchIsIgnoredLikeTheOrgan()
    {
        organ.DeviceId = 5;
        session.Addressing.DeviceId = 0;
        var s = S(A(0, 0, 0, 0x11, 0));
        session.Set(s, 1);
        Settle(0.1);
        Assert.Equal(0, organ.Value(s));
        session.RequestIdentity();
        Assert.True(WaitUntil(() => session.Addressing.DeviceId == 5));
        session.Set(s, 1);
        Assert.True(WaitUntil(() => organ.Value(s) == 1));
    }

    [Fact]
    public void SetupForThisAppSwitchesTheOrganToSysEx()
    {
        session.Set(S(A(0, 0, 0, 0x0C, 0x03)), 2);
        Assert.True(WaitUntil(() => organ.IndividualMode == IndividualMode.Sysex));
        organ.PanelChange(S(A(0x41, 0, 0, 0, 0)), 4);
        Assert.True(WaitUntil(() => spoken.Contains("Leslie speaker: 122 Front")), string.Join(" | ", spoken));
    }

    [Fact]
    public void SystemDumpHasThirteenGoodPackets()
    {
        session.RequestDump(DumpType.System);
        Assert.True(WaitUntil(() => (session.CurrentDump?.Count ?? 0) == 13));
        Assert.True(session.CurrentDump!.AllChecksumsOK);
    }
}
