namespace XK7D.Core.Tests;

static class H
{
    public static readonly ParameterDatabase Db = ParameterDatabase.Shared;

    public static byte[] Bytes(string hex) =>
        hex.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(b => Convert.ToByte(b, 16)).ToArray();

    public static string Hex(IEnumerable<byte> b) => string.Join(" ", b.Select(x => x.ToString("X2")));

    public static Address A(byte b0, byte b1, byte b2, byte b3, byte b4) => new(b0, b1, b2, b3, b4);

    public static Setting S(Address a) => Db.SettingAt(a) ?? throw new Exception($"no parameter at {a}");

    public static Parameter P(Address a) => S(a).Parameter;

    public static byte[] CC(IEnumerable<MidiMessage> m) => m.SelectMany(x => x.Bytes).ToArray();

    public static void Bytes(byte[] expected, byte[] actual) => Assert.Equal(Hex(expected), Hex(actual));
}

/// <summary>Collects what the session sends.</summary>
sealed class Capture : IMidiOutput
{
    public readonly List<byte[]> Sent = new();
    public Action<byte[]>? OnSend;
    public void Send(byte[] bytes) { Sent.Add(bytes); OnSend?.Invoke(bytes); }
}
