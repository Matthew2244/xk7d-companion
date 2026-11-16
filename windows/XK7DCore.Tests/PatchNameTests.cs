// Port of Tests/XK7DCoreTests/PatchNameTests.swift.
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class PatchNameTests
{
    readonly OrganSession session;
    double now = 100;
    readonly List<string> spoken = new();
    readonly List<string> notes = new();
    readonly Capture output = new();
    List<byte[]> Sent => output.Sent;

    public PatchNameTests()
    {
        session = new OrganSession(coalescer: new AnnouncementCoalescer(0.3, 2));
        session.Clock = () => now;
        session.OnAnnouncement = spoken.Add;
        session.OnNameNote = notes.Add;
        session.Output = output;
    }

    void Run(double seconds)
    {
        for (var i = 0; i < (int)Math.Round(seconds / 0.05); i++) { now += 0.05; session.Tick(); }
    }

    static readonly string DumpRequestHex = "F0 55 00 10 26 12 07 F7";
    int DumpRequests => Sent.Count(m => Hex(m) == DumpRequestHex);

    static List<byte[]> Dump(string upper, string lower, int offset = 40)
    {
        var stream = new byte[64 * 6];
        var names = TextCodec.Encode(upper, 16).Concat(TextCodec.Encode(lower, 16)).ToArray();
        for (var i = 0; i < names.Length; i++) stream[offset + i] = names[i];
        var output = new List<byte[]>();
        for (var n = 0; n < 6; n++) output.Add(XK7SysEx.DataPacket(0, 0x07, n, stream.Skip(n * 64).Take(64).ToArray()));
        for (var n = 0; n < 11; n++) output.Add(XK7SysEx.DataPacket(0, 0x08, n, new byte[64]));
        return output;
    }

    void SelectUser(byte program, byte channel = 0) =>
        session.Receive(new byte[] { (byte)(0xB0 | channel), 0x00, 0x00, (byte)(0xB0 | channel), 0x20, 0x00, (byte)(0xC0 | channel), program });

    void Feed(List<byte[]> packets) { foreach (var p in packets) session.Receive(p); }

    [Fact]
    public void FactoryTableHasEveryPatch()
    {
        Assert.Equal(100, PatchNames.FactoryUpper.Count);
        Assert.Equal(100, PatchNames.FactoryLower.Count);
        Assert.Equal("Dr. L.S.", PatchNames.FactoryUpper[0]);
        Assert.Equal("Kinda Brian", PatchNames.FactoryUpper[15]);
        Assert.Equal("Principal 4´ & 2´", PatchNames.FactoryLower[21]);
        Assert.Equal("Full Swell", PatchNames.FactoryUpper[99]);
        Assert.Equal("Full Great with 16´", PatchNames.FactoryLower[99]);
    }

    [Fact]
    public void FactoryPatchSaidByNameAtOnceWithoutAsking()
    {
        session.Receive(Bytes("B1 00 01 B1 20 00 C1 15"));
        Run(0.4);
        Assert.Equal(new[] { "Lower: Principal 4 foot & 2 foot, F21" }, spoken);
        Assert.Equal(0, DumpRequests);
        session.Receive(Bytes("B2 00 01 C2 16"));
        Run(0.4);
        Assert.Equal("Pedal: Flute Harmonique, F22", spoken[^1]);
    }

    [Fact]
    public void UserPatchNameFromTheDump()
    {
        SelectUser(5);
        Run(0.2);
        Assert.Equal(1, DumpRequests);
        Assert.Empty(spoken);
        Feed(Dump("Jazz Lead", "Walking Bass"));
        Run(0.5);
        Assert.Equal(new[] { "Upper: Jazz Lead, U05" }, spoken);
        Assert.Equal(OrganSession.NameDumpStates.Works, session.NameDumpState);
        Assert.Equal(17, Sent.Count(m => m.Length > 5 && m[5] == 0x14));
        Assert.Null(session.CurrentDump);
        Assert.Equal("Jazz Lead", session.PatchNameCache["Upper|patch U05"]);
    }

    [Fact]
    public void LowerTakesTheLowerName()
    {
        SelectUser(9, 1);
        Run(0.2);
        Feed(Dump("Jazz Lead", "Walking Bass"));
        Run(0.5);
        Assert.Equal(new[] { "Lower: Walking Bass, U09" }, spoken);
    }

    [Fact]
    public void NameSentByTheOrganIsUsedAndNotSaidTwice()
    {
        SelectUser(5);
        Run(0.05);
        session.Receive(XK7SysEx.DataSet(0, S(A(0, 0, 0x10, 0, 0)), "Gospel"));
        Run(0.6);
        Assert.Equal(new[] { "Upper: Gospel, U05" }, spoken);
        Assert.Equal(0, DumpRequests);
    }

    [Fact]
    public void OrganThatDoesNotAnswerFallsBackThenStopsAsking()
    {
        SelectUser(5);
        Run(1.0);
        Assert.Equal(new[] { "Upper: patch U05" }, spoken);
        SelectUser(6);
        Run(1.0);
        Assert.Equal("Upper: patch U06", spoken[^1]);
        Assert.Equal(OrganSession.NameDumpStates.GaveUp, session.NameDumpState);
        Assert.Equal(2, DumpRequests);
        SelectUser(7);
        Run(0.4);
        Assert.Equal("Upper: patch U07", spoken[^1]);
        Assert.Equal(2, DumpRequests);
        Assert.Contains(notes, n => n.Contains("Stopped asking"));
    }

    [Fact]
    public void DumpWithoutNamesFallsBack()
    {
        SelectUser(5);
        Run(0.2);
        Feed(Dump("", ""));
        Run(0.4);
        Assert.Equal(new[] { "Upper: patch U05" }, spoken);
    }

    [Fact]
    public void NameLearnedEarlierIsUsedWhenTheOrganIsQuiet()
    {
        session.AskOrganForPatchNames = false;
        SelectUser(5);
        session.Receive(XK7SysEx.DataSet(0, S(A(0, 0, 0x10, 0, 0)), "Gospel"));
        Run(0.5);
        SelectUser(6);
        Run(0.5);
        SelectUser(5);
        Run(0.5);
        Assert.Equal(new[] { "Upper: Gospel, U05", "Upper: patch U06", "Upper: Gospel, U05" }, spoken);
        Assert.Equal(0, DumpRequests);
    }

    [Fact]
    public void RenamingTheCurrentPatchUpdatesWhatIsRemembered()
    {
        session.AskOrganForPatchNames = false;
        SelectUser(5);
        Run(0.5);
        session.Set(S(A(0, 0, 0x10, 0, 0)), "Sunday");
        SelectUser(6);
        Run(0.5);
        SelectUser(5);
        Run(0.5);
        Assert.Equal("Upper: Sunday, U05", spoken[^1]);
    }

    [Fact]
    public void QuickChangesAskOnceAndSayTheLast()
    {
        for (byte p = 1; p <= 5; p++) { SelectUser(p); Run(0.05); }
        Run(0.15);
        Assert.Equal(1, DumpRequests);
        Feed(Dump("Five", "x"));
        Run(0.5);
        Assert.Equal(new[] { "Upper: Five, U05" }, spoken);
    }

    [Fact]
    public void AnswerForAnOlderPatchIsNotUsed()
    {
        SelectUser(5);
        Run(0.2);
        Assert.Equal(1, DumpRequests);
        SelectUser(6);
        Feed(Dump("Old Name", "x"));
        Run(0.25);
        Assert.Equal(2, DumpRequests);
        Feed(Dump("New Name", "x"));
        Run(0.5);
        Assert.Equal(new[] { "Upper: New Name, U06" }, spoken);
    }

    [Fact]
    public void FavoriteIsLookedUpAndAdjustIsNot()
    {
        session.Receive(Bytes("B0 00 65 C0 69"));
        Run(0.2);
        Assert.Equal(1, DumpRequests);
        Feed(Dump("Ballad", "x"));
        Run(0.5);
        Assert.Equal(new[] { "Upper: Ballad, Favorite C sharp-F" }, spoken);
        session.Receive(Bytes("C0 7F"));
        Run(0.4);
        Assert.Equal("Upper: Adjust B", spoken[^1]);
        Assert.Equal(1, DumpRequests);
    }

    [Fact]
    public void ReadFromOrganStillGetsItsOwnDump()
    {
        SelectUser(5);
        Run(0.2);
        session.RequestDump(DumpType.Temporary);
        Feed(Dump("Jazz Lead", "x"));
        Assert.Equal(17, session.CurrentDump?.Count);
        Run(1.2);
        Assert.Equal(new[] { "Upper: patch U05" }, spoken);
    }

    [Fact]
    public void FromTemporaryDump()
    {
        static byte[] Stream(byte[] bytes, int offset)
        {
            var s = new byte[200];
            for (var i = 0; i < bytes.Length; i++) s[offset + i] = bytes[i];
            return s;
        }
        var names = TextCodec.Encode("Dr. L.S.       U").Concat(TextCodec.Encode("Dr. L.S.       L")).ToArray();
        var found = PatchNames.FromTemporaryDump(Stream(names, 17));
        Assert.Equal("Dr. L.S.", found?.Upper);
        Assert.Equal("Dr. L.S.", found?.Lower);
        Assert.Null(PatchNames.FromTemporaryDump(Stream(Enumerable.Repeat((byte)0x40, 40).ToArray(), 0)));
        Assert.Null(PatchNames.FromTemporaryDump(Stream(TextCodec.Encode("Jazz"), 0)));
        Assert.Null(PatchNames.FromTemporaryDump(Array.Empty<byte>()));
    }

    [Fact]
    public void SpokenNames()
    {
        Assert.Equal("Stopped Flute 16 foot & 8 foot", PatchNames.Spoken("Stopped Flute 16´ & 8´"));
        Assert.Equal("DB 8 foot 4 foot 2⅔ foot", PatchNames.Spoken("DB 8´ 4´ 2⅔´"));
        Assert.Equal("Tibia 8 foot & 4 foot", PatchNames.Spoken("Tibia 8' & 4'"));
        Assert.Equal("Joe's M-3", PatchNames.Spoken("Joe's M-3"));
        Assert.Equal("Upper: patch U05", PatchNames.Announcement("Upper", "patch U05", null));
        Assert.Equal("Upper: patch U05", PatchNames.Announcement("Upper", "patch U05", ""));
        Assert.Equal("Jazz Lead", PatchNames.Clean("  Jazz    Lead  "));
    }
}
