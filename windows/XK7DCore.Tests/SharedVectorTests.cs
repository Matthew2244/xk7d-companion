// Checks the C# core against Tests/Vectors/core-vectors.json, the answers the Swift core gives
// (written and kept current by Tests/XK7DCoreTests/SharedVectorTests.swift).
using System.Text.Json;
using static XK7D.Core.Tests.H;

namespace XK7D.Core.Tests;

public class SharedVectorTests
{
    static readonly JsonElement V = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "core-vectors.json"))).RootElement;

    static int? N(JsonElement e) => e.ValueKind == JsonValueKind.Null ? null : e.GetInt32();
    static string Str(JsonElement e) => e.GetString()!;
    static int[] Ints(JsonElement e) => e.EnumerateArray().Select(x => x.GetInt32()).ToArray();

    static Address Addr(string hex) => new(Bytes(hex));

    [Fact]
    public void EveryValueOfEverySettingDisplaysAndSpeaksTheSame()
    {
        var count = 0;
        var mismatches = new List<string>();
        foreach (var o in V.GetProperty("parameters").EnumerateArray())
        {
            var p = Db.ParameterById(Str(o.GetProperty("id")))!;
            Assert.Equal(o.GetProperty("length").GetInt32(), p.Length);
            Assert.Equal(Str(o.GetProperty("address")), p.BaseAddress.ToString());
            if (!o.TryGetProperty("values", out var values)) { Assert.True(p.IsText, p.Id); continue; }
            Assert.Equal(Ints(o.GetProperty("rawRange")), new[] { p.RawMin, p.RawMax });
            var raws = p.AllRawValues();
            Assert.Equal(values.GetArrayLength(), raws.Count);
            var i = 0;
            foreach (var v in values.EnumerateArray())
            {
                var raw = v[0].GetInt32();
                Assert.Equal(raw, raws[i++]);
                if (p.Display(raw) != Str(v[1])) mismatches.Add($"{p.Id} {raw} display C# '{p.Display(raw)}' Swift '{Str(v[1])}'");
                if (p.Spoken(raw) != Str(v[2])) mismatches.Add($"{p.Id} {raw} spoken C# '{p.Spoken(raw)}' Swift '{Str(v[2])}'");
                count++;
            }
            var clampIn = new[] { p.RawMin - 1, p.RawMax + 1, -100000, 100000 };
            Assert.Equal(Ints(o.GetProperty("clamp")), clampIn.Select(p.Clamp));
        }
        Assert.Empty(mismatches.Take(20));
        Assert.Equal(40522, count);
    }

    [Fact]
    public void TypingGivesTheSameRawValue()
    {
        var inputs = V.GetProperty("typedInputs").EnumerateArray().Select(Str).ToArray();
        var count = 0;
        var mismatches = new List<string>();
        foreach (var o in V.GetProperty("parameters").EnumerateArray())
        {
            var p = Db.ParameterById(Str(o.GetProperty("id")))!;
            if (!o.TryGetProperty("typedDisplay", out var td)) continue;
            var raws = p.AllRawValues();
            var tsp = o.GetProperty("typedSpoken");
            for (var i = 0; i < raws.Count; i++)
            {
                var d = p.Display(raws[i]);
                var sp = p.Spoken(raws[i]);
                if (p.RawValueFromTyped(d) != N(td[i])) mismatches.Add($"{p.Id} typed '{d}': C# {p.RawValueFromTyped(d)} Swift {N(td[i])}");
                if (p.RawValueFromTyped(sp) != N(tsp[i])) mismatches.Add($"{p.Id} typed '{sp}': C# {p.RawValueFromTyped(sp)} Swift {N(tsp[i])}");
                count += 2;
            }
            var other = o.GetProperty("typedOther");
            for (var i = 0; i < inputs.Length; i++)
            {
                if (p.RawValueFromTyped(inputs[i]) != N(other[i]))
                    mismatches.Add($"{p.Id} typed '{inputs[i]}': C# {p.RawValueFromTyped(inputs[i])} Swift {N(other[i])}");
                count++;
            }
        }
        Assert.Empty(mismatches.Take(20));
        Assert.True(count > 80000, $"only {count} checked");
    }

    [Fact]
    public void SettingsLookUpNameAndEncodeTheSame()
    {
        var count = 0;
        foreach (var o in V.GetProperty("settings").EnumerateArray())
        {
            var p = Db.ParameterById(Str(o[0]))!;
            var iv = Ints(o[1]);
            var s = new Setting(p, iv);
            Assert.Equal(Str(o[2]), s.Address.ToString());
            var found = Db.SettingAt(s.Address)!;
            Assert.Equal(p.Id, found.Parameter.Id);
            Assert.Equal(iv, found.IndexValues);
            Assert.Equal(Str(o[3]), s.SpokenName);
            var message = p.IsText
                ? XK7SysEx.DataSet(0x10, s, "Jimmy’s “Ballad” – Café")
                : XK7SysEx.DataSet(0x10, s, p.RawMax);
            Assert.Equal(Str(o[4]), Hex(message));
            if (o[5].ValueKind != JsonValueKind.Null || s.Address.B4 < 0x7F)
            {
                var b = s.Address.Bytes;
                b[4]++;
                var next = Db.SettingAt(new Address(b));
                if (o[5].ValueKind == JsonValueKind.Null) Assert.Null(next);
                else
                {
                    Assert.Equal(Str(o[5][0]), next?.Parameter.Id);
                    Assert.Equal(Ints(o[5][1]), next!.IndexValues);
                }
            }
            count++;
        }
        Assert.Equal(3919, count);
    }

    [Fact]
    public void EveryNrpnNumberResolvesTheSame()
    {
        var expected = V.GetProperty("nrpn").EnumerateArray()
            .ToDictionary(o => (o[0].GetInt32(), o[1].GetInt32()), o => o);
        var resolved = 0;
        for (var msb = 0; msb < 128; msb++)
        {
            for (var lsb = 0; lsb < 128; lsb++)
            {
                var s = Db.SettingForNrpn((byte)msb, (byte)lsb);
                if (!expected.TryGetValue((msb, lsb), out var o)) { Assert.Null(s); continue; }
                Assert.NotNull(s);
                Assert.Equal(Str(o[2]), s!.Parameter.Id);
                Assert.Equal(Ints(o[3]), s.IndexValues);
                Assert.Equal(Str(o[4]), Hex(CC(Nrpn.Messages(2, (byte)msb, (byte)lsb, s.Parameter.RawMax, s.Parameter.Length))));
                resolved++;
            }
        }
        Assert.Equal(expected.Count, resolved);
    }

    [Fact]
    public void PatchNamesNotesDrawbarsAndTextMatch()
    {
        foreach (var o in V.GetProperty("patches").EnumerateArray())
        {
            var bank = o[0].GetInt32();
            var names = o[1].EnumerateArray().Select(Str).ToArray();
            var spoken = o[2].EnumerateArray().Select(Str).ToArray();
            for (var program = 0; program < 128; program++)
            {
                var d = PatchSelect.Describe(bank < 0 ? null : bank, program);
                Assert.Equal(names[program], d);
                Assert.Equal(spoken[program], PatchSelect.Spoken(d));
            }
        }
        var notes = V.GetProperty("notes");
        for (var n = 0; n < 128; n++)
        {
            Assert.Equal(Str(notes[n][0]), NoteName.Display(n));
            Assert.Equal(Str(notes[n][1]), NoteName.Spoken(n));
        }
        Assert.Equal(Ints(V.GetProperty("drawbarLevels")), Enumerable.Range(0, 128).Select(DrawbarCC.Level));
        Assert.Equal(Ints(V.GetProperty("drawbarValues")), Enumerable.Range(0, 9).Select(DrawbarCC.Value));
        foreach (var t in V.GetProperty("texts").EnumerateArray())
        {
            var input = Str(t[0]);
            Assert.Equal(Str(t[1]), Hex(TextCodec.Encode(input)));
            Assert.Equal(Str(t[2]), TextCodec.Decode(TextCodec.Encode(input)));
        }
    }

    /// <summary>Not in the shared file (too many to list): every address of every indexed family, all
    /// 671,144 of them, looks back up to itself.</summary>
    [Fact]
    public void EveryAddressOfEveryFamilyLooksBackUpToItself()
    {
        var total = 0;
        foreach (var p in Db.Parameters)
        {
            var combos = new List<int[]> { Array.Empty<int>() };
            foreach (var d in p.Indices)
                combos = combos.SelectMany(c => d.Options.Select(o => c.Append(o.Raw).ToArray())).ToList();
            foreach (var iv in combos)
            {
                var s = new Setting(p, iv);
                var back = p.HasIndices ? (p.IndexValues(s.Address) is { } v ? v : null) : Array.Empty<int>();
                Assert.NotNull(back);
                Assert.Equal(iv, back);
                total++;
            }
        }
        Assert.Equal(671144, total);
    }
}
