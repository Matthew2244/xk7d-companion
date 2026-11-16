// Port of Tests/XK7DCoreTests/SpeechLineTests.swift.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class SpeechLineTests
{
    readonly OrganSession session;
    double now = 100;
    readonly List<string> spoken = new();
    readonly List<string> urgent = new();

    public SpeechLineTests()
    {
        session = new OrganSession(coalescer: new AnnouncementCoalescer(0.3, 2));
        session.Clock = () => now;
        session.OnAnnouncement = spoken.Add;
        session.OnUrgentAnnouncement = urgent.Add;
    }

    void Nrpn(byte msb, byte lsb, byte v) => session.Receive(new byte[] { 0xB0, 0x63, msb, 0x62, lsb, 0x06, v });

    [Fact]
    public void LeslieSpeedIsOneWordAndSaidAtOnce()
    {
        Nrpn(0x12, 0x0A, 1);
        Assert.Equal(new[] { "Fast" }, urgent);
        Nrpn(0x12, 0x0A, 0);
        Assert.Equal("Slow", urgent[^1]);
        Nrpn(0x12, 0x09, 1);
        Assert.Equal("Stop", urgent[^1]);
        Nrpn(0x12, 0x0A, 1);
        Assert.Equal("Fast", urgent[^1]);
        Nrpn(0x12, 0x0A, 0);
        Assert.Equal("Stop", urgent[^1]);
        Nrpn(0x12, 0x0A, 1);
        Nrpn(0x12, 0x09, 0);
        Assert.Equal("Stop mode off", urgent[^1]);
        now += 1; session.Tick();
        Assert.Empty(spoken);
    }

    [Fact]
    public void LeslieFastControlChange()
    {
        session.Receive(Bytes("B0 5C 7F"));
        session.Receive(Bytes("B0 5C 00"));
        Assert.Equal(new[] { "Fast", "Slow" }, urgent);
    }

    [Fact]
    public void LeslieFallsBackToTheNormalCallback()
    {
        session.OnUrgentAnnouncement = null;
        Nrpn(0x12, 0x0A, 1);
        Assert.Equal(new[] { "Fast" }, spoken);
    }

    [Fact]
    public void OwnLeslieChangeEchoedIsNotSaid()
    {
        session.Set(S(A(0, 0, 0, 0x12, 0x0A)), 1);
        Nrpn(0x12, 0x0A, 1);
        Assert.Empty(urgent);
    }

    [Fact]
    public void OffOnSettingsAreSaidShort()
    {
        string Line(Address a, int raw) => OrganSession.Line(S(a), raw);
        Assert.Equal("Percussion on", Line(A(0, 0, 0, 0x11, 0x00), 1));
        Assert.Equal("Percussion off", Line(A(0, 0, 0, 0x11, 0x00), 0));
        Assert.Equal("Leslie bypass on", Line(A(0, 0, 0, 0x12, 0x08), 1));
        Assert.Equal("External zone Upper 1 off", Line(A(0, 0, 0, 0x30, 0x00), 0));
        Assert.Equal("Organ type: Mellow", Line(A(0, 0, 0, 0x10, 0x04), 1));
    }

    [Fact]
    public void OrganInNrpnModeIsNoticedOnce()
    {
        var told = 0;
        session.OnNrpnModeNoticed = () => told++;
        Nrpn(0x10, 0x04, 1);
        Nrpn(0x10, 0x04, 2);
        Assert.Equal(1, told);
        session.ResetConnection();
        session.Receive(XK7SysEx.DataSet(0, S(A(0, 0, 0, 0x10, 0x04)), 1));
        Nrpn(0x10, 0x04, 2);
        Assert.Equal(1, told);
    }
}

/// <summary>Every setting the manual lists is said when it arrives, as a SysEx Data Set and, for
/// settings with an NRPN, as NRPN on the Upper channel.</summary>
public class EverySettingSpeaksTests
{
    static List<int[]> Samples(Parameter p)
    {
        if (!p.HasIndices) return new List<int[]> { Array.Empty<int>() };
        var firsts = p.Indices.Select(d => d.Options[0].Raw).ToArray();
        var output = new List<int[]>();
        for (var i = 0; i < p.Indices.Count; i++)
            foreach (var o in p.Indices[i].Options)
            {
                var v = (int[])firsts.Clone();
                v[i] = o.Raw;
                if (!output.Any(x => x.SequenceEqual(v))) output.Add(v);
            }
        var lasts = p.Indices.Select(d => d.Options[^1].Raw).ToArray();
        if (!output.Any(x => x.SequenceEqual(lasts))) output.Add(lasts);
        return output;
    }

    static (int Checked, List<string> Silent) Check(bool viaNrpn)
    {
        var silent = new List<string>();
        var count = 0;
        foreach (var p in Db.Parameters)
        {
            if (viaNrpn && p.Nrpn is null) continue;
            foreach (var indices in Samples(p))
            {
                double now = 100;
                var said = new List<string>();
                var session = new OrganSession(coalescer: new AnnouncementCoalescer(0.3, 2)) { Clock = () => now };
                session.OnAnnouncement = said.Add;
                session.OnUrgentAnnouncement = said.Add;
                var s = new Setting(p, indices);
                if (viaNrpn)
                {
                    var n = p.Nrpn!.Value;
                    foreach (var m in Nrpn.Messages(0, n.Msb, n.Lsb, p.RawMax, p.Length)) session.Receive(m.Bytes);
                }
                else if (p.IsText) session.Receive(XK7SysEx.DataSet(0, s, "Jazz"));
                else session.Receive(XK7SysEx.DataSet(0, s, p.RawMax));
                now += 1; session.Tick();
                count++;
                var start = s.SpokenName.Length > 6 ? s.SpokenName[..6] : s.SpokenName;
                if (said.Count != 1 || !(said[0].StartsWith(start, StringComparison.Ordinal)
                                         || new[] { "Fast", "Slow", "Stop" }.Contains(said[0]) || said[0].Contains("foot")))
                    silent.Add($"{p.Id} [{string.Join(",", indices)}]: {string.Join(" | ", said)}");
            }
        }
        return (count, silent);
    }

    [Fact]
    public void EverySettingArrivingAsSysExIsSaid()
    {
        var r = Check(false);
        Assert.Empty(r.Silent);
        Assert.True(r.Checked > 3000);
    }

    [Fact]
    public void EverySettingWithAnNrpnArrivingAsNrpnIsSaid()
    {
        var r = Check(true);
        Assert.Empty(r.Silent);
        Assert.True(r.Checked > 300);
    }
}
