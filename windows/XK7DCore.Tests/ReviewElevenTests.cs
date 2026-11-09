// Port of Tests/XK7DCoreTests/ReviewElevenTests.swift.

namespace XK7D.Core.Tests;

/// <summary>Tests for the 1.1.1 review: what an editor may step from, and when a change can really be sent.
/// Ported from Tests/XK7DCoreTests/ReviewElevenTests.swift.</summary>
public class HoldsTests
{
    static readonly ParameterDatabase Db = ParameterDatabase.Shared;

    [Fact]
    public void ChoicesHoldOnlyTheirOwnValues()
    {
        var organType = Db.SettingAt(new Address(0, 0, 0, 0x10, 0x04))!.Parameter;
        Assert.All(Enumerable.Range(0, 6), r => Assert.True(organType.Holds(r)));
        Assert.False(organType.Holds(6));
        Assert.False(organType.Holds(-1));
    }

    [Fact]
    public void NumbersHoldTheirRange()
    {
        var fast = Db.SettingAt(new Address(0x42, 0, 0, 0, 0))!.Parameter;
        Assert.True(fast.Holds(fast.RawMin));
        Assert.True(fast.Holds(fast.RawMax));
        Assert.False(fast.Holds(fast.RawMin - 1));
        Assert.False(fast.Holds(fast.RawMax + 1));
    }

    [Fact]
    public void EveryListedValueIsHeld()
    {
        foreach (var p in Db.Parameters.Where(p => !p.IsText))
            Assert.True(p.AllRawValues().All(p.Holds), p.Id);
    }
}

public class CannotSendTests
{
    static PortChoice Dev(string n) => new PortChoice.Device(n);

    [Fact]
    public void WhenAChangeCanBeSent()
    {
        Assert.Null(PortPolicy.CannotSend(Dev("XK-7D"), hasOutput: true, missing: false, canSend: true));
        Assert.Null(PortPolicy.CannotSend(PortChoice.BuiltInSimulator, hasOutput: true, missing: false, canSend: true));
    }

    [Fact]
    public void NothingChosenOrNothingOpen()
    {
        Assert.Equal("Not connected. Choose the organ or the simulator first.",
            PortPolicy.CannotSend(PortChoice.NotConnected, hasOutput: false, missing: false, canSend: true));
        // A port that wouldn't open (another program had it) leaves nothing to send to.
        Assert.Equal("Not connected. Choose the organ or the simulator first.",
            PortPolicy.CannotSend(Dev("XK-7D"), hasOutput: false, missing: false, canSend: true));
    }

    [Fact]
    public void UnpluggedSaysSo() =>
        Assert.Equal("The organ is disconnected, so nothing was sent. Check the USB cable and that the organ is on.",
            PortPolicy.CannotSend(Dev("XK-7D"), hasOutput: true, missing: true, canSend: true));

    /// <summary>Listening only: before 1.1.1 the app said "sent" while the change went nowhere.</summary>
    [Fact]
    public void AListenOnlyPortCantClaimASend() =>
        Assert.Equal("The app can listen to this MIDI port but can't send to it, so nothing was sent. Choose the organ again, or check that no other program is using it.",
            PortPolicy.CannotSend(Dev("XK-7D"), hasOutput: true, missing: false, canSend: false));
}
