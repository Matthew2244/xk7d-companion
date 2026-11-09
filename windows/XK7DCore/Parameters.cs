// Port of Sources/XK7DCore/Parameters.swift. Keep the two in step: Tests/Vectors/core-vectors.json
// checks both give the same answers.
using System.Globalization;
using System.Reflection;
using System.Text.Json;

namespace XK7D.Core;

/// <summary>A five-byte SysEx address, as printed in the manual ("MSB to LSB").</summary>
public readonly struct Address : IEquatable<Address>, IComparable<Address>
{
    public readonly byte B0, B1, B2, B3, B4;

    public Address(byte b0, byte b1, byte b2, byte b3, byte b4) { B0 = b0; B1 = b1; B2 = b2; B3 = b3; B4 = b4; }

    public Address(IReadOnlyList<byte> b)
    {
        if (b.Count != 5) throw new ArgumentException("an XK-7 address is five bytes");
        B0 = b[0]; B1 = b[1]; B2 = b[2]; B3 = b[3]; B4 = b[4];
    }

    public byte[] Bytes => new[] { B0, B1, B2, B3, B4 };

    public byte this[int i] => i switch { 0 => B0, 1 => B1, 2 => B2, 3 => B3, 4 => B4, _ => throw new IndexOutOfRangeException() };

    public override string ToString() => $"{B0:X2} {B1:X2} {B2:X2} {B3:X2} {B4:X2}";

    public bool Equals(Address o) => B0 == o.B0 && B1 == o.B1 && B2 == o.B2 && B3 == o.B3 && B4 == o.B4;
    public override bool Equals(object? obj) => obj is Address a && Equals(a);
    public override int GetHashCode() => HashCode.Combine(B0, B1, B2, B3, B4);
    public static bool operator ==(Address a, Address b) => a.Equals(b);
    public static bool operator !=(Address a, Address b) => !a.Equals(b);

    public int CompareTo(Address o)
    {
        for (var i = 0; i < 5; i++)
        {
            var c = this[i].CompareTo(o[i]);
            if (c != 0) return c;
        }
        return 0;
    }
}

/// <summary>One named choice: a raw value and the label the organ shows.</summary>
public readonly record struct Option(int Raw, string Label);

public enum ValueType { Choices, Number, Steps, Note, Balance, Text }

/// <summary>How a parameter's raw value maps to what the organ's display shows.</summary>
public sealed class ValueKind
{
    public ValueType Type { get; init; }
    /// <summary>Choices: the named options.</summary>
    public IReadOnlyList<Option> Options { get; init; } = Array.Empty<Option>();
    public int Min { get; init; }
    public int Max { get; init; }
    /// <summary>Number: shown = origin + (raw - zero) * step.</summary>
    public int Zero { get; init; }
    public double Origin { get; init; }
    public double Step { get; init; }
    public int Decimals { get; init; }
    public string Unit { get; init; } = "";
    public bool Plus { get; init; }
    /// <summary>Number: names for special raw values, in raw order.</summary>
    public IReadOnlyList<Option> Special { get; init; } = Array.Empty<Option>();
    /// <summary>Steps: the labels of the two published end points.</summary>
    public string Low { get; init; } = "";
    public string High { get; init; } = "";
    /// <summary>Balance: centre raw value and labels.</summary>
    public int Center { get; init; }
    public string Left { get; init; } = "L%d";
    public string Right { get; init; } = "R%d";
    public string CenterLabel { get; init; } = "Center";
    /// <summary>Text: length in characters.</summary>
    public int Length { get; init; }

    public string? SpecialLabel(int raw)
    {
        foreach (var s in Special) if (s.Raw == raw) return s.Label;
        return null;
    }
}

public sealed class IndexDimension
{
    public string Name { get; }
    /// <summary>Which of the five address bytes carries this index.</summary>
    public int Position { get; }
    public IReadOnlyList<Option> Options { get; }

    public IndexDimension(string name, int position, IReadOnlyList<Option> options)
    {
        Name = name; Position = position; Options = options;
    }

    public string Label(int raw)
    {
        foreach (var o in Options) if (o.Raw == raw) return o.Label;
        return raw.ToString("X2", CultureInfo.InvariantCulture);
    }

    /// <summary>The label as read aloud and shown in pickers: "8 foot" rather than "8'".</summary>
    public string SpokenLabel(int raw) => Spoken(Label(raw));

    static readonly (string, string)[] FootSpoken =
    {
        ("5 1/3'", "5 and a third foot"), ("2 2/3'", "2 and two thirds foot"), ("1 3/5'", "1 and three fifths foot"),
        ("1 1/3'", "1 and a third foot"),
    };

    public static string Spoken(string label)
    {
        var s = label;
        foreach (var (a, b) in FootSpoken) s = s.Replace(a, b, StringComparison.Ordinal);
        s = s.Replace("'", " foot", StringComparison.Ordinal);
        if (s.StartsWith("#F", StringComparison.Ordinal)) s = s.Substring(1);          // foldback wheels: "F96"
        else if (s.StartsWith("#", StringComparison.Ordinal)) s = "number " + s.Substring(1);
        s = s.Replace("#", " sharp", StringComparison.Ordinal);
        return s;
    }

    /// <summary>Whether to say the index's name before its value.</summary>
    internal bool NamedInSpeech(string parameterName)
    {
        if (parameterName.ToLowerInvariant().Contains(Name.ToLowerInvariant(), StringComparison.Ordinal)) return false;
        return !new[] { "Footage", "Drawbar", "Key", "Formant", "Bank and key" }.Contains(Name);
    }
}

public enum Section { Patch, Custom, System }

public static class SectionInfo
{
    public static string Raw(this Section s) => s switch { Section.Patch => "Patch", Section.Custom => "Custom", _ => "System" };

    public static string Title(this Section s) => s switch
    {
        Section.Patch => "Patch settings",
        Section.Custom => "Custom sets (tone wheels, contacts, pipes, Leslie)",
        _ => "System settings",
    };
}

/// <summary>One row of the manual's MIDI tables, or a family of rows differing by an index.</summary>
public sealed class Parameter
{
    public required string Id { get; init; }
    public required Section Section { get; init; }
    public required string Category { get; init; }
    public required string ManualCategory { get; init; }
    public required string ManualName { get; init; }
    /// <summary>Plain-English name, front-loaded, used in announcements.</summary>
    public required string Name { get; init; }
    public required Address BaseAddress { get; init; }
    public (byte Msb, byte Lsb)? Nrpn { get; init; }
    /// <summary>Bytes of data: 1, 2 (two 7-bit bytes, MSB first) or 16 (text).</summary>
    public required int Length { get; init; }
    public required ValueKind Kind { get; init; }
    public int Page { get; init; }
    public string Help { get; init; } = "";
    public string? Notes { get; init; }
    public IReadOnlyList<IndexDimension> Indices { get; init; } = Array.Empty<IndexDimension>();
    public bool Xk7Only { get; init; }

    public bool IsText => Kind.Type == ValueType.Text;
    public bool HasIndices => Indices.Count > 0;

    public int RawMin => Kind.Type switch
    {
        ValueType.Choices => Kind.Options.Count == 0 ? 0 : Kind.Options.Min(o => o.Raw),
        ValueType.Text => 0,
        _ => Kind.Min,
    };

    public int RawMax => Kind.Type switch
    {
        ValueType.Choices => Kind.Options.Count == 0 ? 0 : Kind.Options.Max(o => o.Raw),
        ValueType.Text => 0,
        _ => Kind.Max,
    };

    /// <summary>The number of values from RawMin to RawMax.</summary>
    public int RangeCount => RawMax - RawMin + 1;

    /// <summary>The concrete address for a choice of index values (in the order of Indices).</summary>
    public Address AddressFor(IReadOnlyList<int> indexValues)
    {
        var b = BaseAddress.Bytes;
        for (var i = 0; i < Indices.Count && i < indexValues.Count; i++)
        {
            var d = Indices[i];
            b[d.Position] = unchecked((byte)(b[d.Position] + indexValues[i]));
        }
        return new Address(b);
    }

    /// <summary>Recover index values from a concrete address, or null if it is not one of ours.</summary>
    public int[]? IndexValues(Address address)
    {
        var positions = Indices.Select(d => d.Position).ToHashSet();
        for (var i = 0; i < 5; i++)
            if (!positions.Contains(i) && address[i] != BaseAddress[i]) return null;
        var output = new int[Indices.Count];
        for (var k = 0; k < Indices.Count; k++)
        {
            var d = Indices[k];
            var v = address[d.Position] - BaseAddress[d.Position];
            if (!d.Options.Any(o => o.Raw == v)) return null;
            output[k] = v;
        }
        return output;
    }
}

/// <summary>A parameter with its indices filled in: one real setting on the organ.</summary>
public sealed class Setting : IEquatable<Setting>
{
    public Parameter Parameter { get; }
    public IReadOnlyList<int> IndexValues { get; }

    public Setting(Parameter parameter, IReadOnlyList<int>? indexValues = null)
    {
        Parameter = parameter;
        IndexValues = indexValues ?? Array.Empty<int>();
    }

    public Address Address => Parameter.AddressFor(IndexValues);

    /// <summary>"Tone wheel level, tone wheel number 13" or just "Organ type".</summary>
    public string SpokenName
    {
        get
        {
            if (!Parameter.HasIndices) return Parameter.Name;
            var parts = new List<string>();
            for (var i = 0; i < Parameter.Indices.Count && i < IndexValues.Count; i++)
            {
                var dim = Parameter.Indices[i];
                var label = dim.SpokenLabel(IndexValues[i]);
                parts.Add(dim.NamedInSpeech(Parameter.Name) ? $"{dim.Name.ToLowerInvariant()} {label}" : label);
            }
            return Parameter.Name + ", " + string.Join(", ", parts);
        }
    }

    public bool Equals(Setting? o) => o is not null && Address == o.Address;
    public override bool Equals(object? obj) => obj is Setting s && Equals(s);
    public override int GetHashCode() => Address.GetHashCode();
}

public sealed class ParameterDatabaseException : Exception
{
    public ParameterDatabaseException(string message) : base("parameters.json could not be read: " + message) { }
}

/// <summary>The whole table from the manual, plus lookups by address, NRPN and name.</summary>
public sealed class ParameterDatabase
{
    public IReadOnlyList<Parameter> Parameters { get; }
    readonly Dictionary<Address, Parameter> byExactAddress = new();
    readonly List<Parameter> indexed = new();
    readonly Dictionary<int, Parameter> byNrpn = new();
    readonly Dictionary<string, Parameter> byId = new();

    static readonly Lazy<ParameterDatabase> shared = new(() =>
    {
        try { return LoadEmbedded(); }
        catch (Exception e)
        {
            LoadError = e.Message;
            return new ParameterDatabase(Array.Empty<Parameter>());
        }
    });

    /// <summary>The table compiled into the DLL. Never throws: if it can't be read (a broken build),
    /// this is an empty table and LoadError says why, so the app can explain instead of crashing.</summary>
    public static ParameterDatabase Shared => shared.Value;

    /// <summary>Set when Shared couldn't be read.</summary>
    public static string? LoadError { get; private set; }

    public static ParameterDatabase LoadEmbedded()
    {
        using var stream = typeof(ParameterDatabase).Assembly.GetManifestResourceStream("parameters.json")
            ?? throw new ParameterDatabaseException("the table isn't inside the program");
        using var reader = new StreamReader(stream);
        return FromJson(reader.ReadToEnd());
    }

    ParameterDatabase(IReadOnlyList<Parameter> parameters)
    {
        Parameters = parameters;
        foreach (var p in parameters)
        {
            byId[p.Id] = p;
            if (p.HasIndices) indexed.Add(p); else byExactAddress[p.BaseAddress] = p;
            if (p.Nrpn is { } n && !p.HasIndices) byNrpn[n.Msb << 8 | n.Lsb] = p;
        }
    }

    public static ParameterDatabase FromJson(string json)
    {
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("parameters", out var list) || list.ValueKind != JsonValueKind.Array)
            throw new ParameterDatabaseException("no parameter list");
        return new ParameterDatabase(list.EnumerateArray().Select(Parse).ToList());
    }

    public Parameter? ParameterById(string id) => byId.TryGetValue(id, out var p) ? p : null;

    /// <summary>The setting living at a SysEx address, if the manual defines one there.</summary>
    public Setting? SettingAt(Address address)
    {
        if (byExactAddress.TryGetValue(address, out var p)) return new Setting(p);
        foreach (var q in indexed)
            if (q.IndexValues(address) is { } v) return new Setting(q, v);
        return null;
    }

    /// <summary>The setting an NRPN number refers to. Indexed NRPNs (the Favorites tables) too.</summary>
    public Setting? SettingForNrpn(byte msb, byte lsb)
    {
        if (byNrpn.TryGetValue(msb << 8 | lsb, out var p)) return new Setting(p);
        var address = new Address(0, 0, 0, msb, lsb);
        foreach (var q in indexed)
            if (q.Nrpn is not null && q.IndexValues(address) is { } v) return new Setting(q, v);
        return null;
    }

    /// <summary>Search by any word in the friendly name, manual name or category. Every word must match.</summary>
    public IReadOnlyList<Parameter> Search(string query)
    {
        var words = query.ToLowerInvariant().Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0) return Parameters;
        return Parameters.Where(p =>
        {
            var hay = $"{p.Name} {p.ManualName} {p.Category} {p.ManualCategory} {p.Section.Raw()}".ToLowerInvariant();
            return words.All(w => hay.Contains(w, StringComparison.Ordinal));
        }).ToList();
    }

    // JSON

    static string Str(JsonElement d, string k)
    {
        if (d.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String) return v.GetString()!;
        throw new ParameterDatabaseException($"{k} in {(d.TryGetProperty("id", out var id) ? id.ToString() : "?")}");
    }

    static int Int(JsonElement d, string k, int fallback = 0)
    {
        if (!d.TryGetProperty(k, out var v) || v.ValueKind != JsonValueKind.Number) return fallback;
        return v.TryGetInt32(out var i) ? i : (int)v.GetDouble();
    }

    static double Dbl(JsonElement d, string k) =>
        d.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : 0;

    static string? OptStr(JsonElement d, string k) =>
        d.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    static List<Option> Options(JsonElement d, string k)
    {
        var output = new List<Option>();
        if (!d.TryGetProperty(k, out var list) || list.ValueKind != JsonValueKind.Array) return output;
        foreach (var pair in list.EnumerateArray())
        {
            if (pair.ValueKind != JsonValueKind.Array || pair.GetArrayLength() != 2) continue;
            var r = pair[0];
            var l = pair[1];
            if (r.ValueKind != JsonValueKind.Number || !r.TryGetInt32(out var raw) || l.ValueKind != JsonValueKind.String) continue;
            output.Add(new Option(raw, l.GetString()!));
        }
        return output;
    }

    static Parameter Parse(JsonElement d)
    {
        var idText = d.TryGetProperty("id", out var idv) ? idv.ToString() : "?";
        if (!d.TryGetProperty("address", out var addr) || addr.ValueKind != JsonValueKind.Array || addr.GetArrayLength() != 5
            || !d.TryGetProperty("length", out _) || !d.TryGetProperty("value", out var value)
            || value.ValueKind != JsonValueKind.Object)
            throw new ParameterDatabaseException($"parameter {idText}");
        var section = OptStr(d, "section") switch
        {
            "Patch" => Section.Patch,
            "Custom" => Section.Custom,
            "System" => Section.System,
            _ => throw new ParameterDatabaseException($"parameter {idText}"),
        };
        (byte, byte)? nrpn = null;
        if (d.TryGetProperty("nrpn", out var n) && n.ValueKind == JsonValueKind.Array && n.GetArrayLength() == 2)
            nrpn = ((byte)n[0].GetInt32(), (byte)n[1].GetInt32());
        var indices = new List<IndexDimension>();
        if (d.TryGetProperty("indices", out var ix) && ix.ValueKind == JsonValueKind.Array)
            foreach (var i in ix.EnumerateArray())
                indices.Add(new IndexDimension(OptStr(i, "name") ?? "Index", Int(i, "position", 4), Options(i, "options")));
        return new Parameter
        {
            Id = Str(d, "id"),
            Section = section,
            Category = Str(d, "category"),
            ManualCategory = Str(d, "manualCategory"),
            ManualName = Str(d, "manualName"),
            Name = Str(d, "name"),
            BaseAddress = new Address(addr.EnumerateArray().Select(b => (byte)b.GetInt32()).ToArray()),
            Nrpn = nrpn,
            Length = Int(d, "length"),
            Kind = Kind(value),
            Page = Int(d, "page"),
            Help = OptStr(d, "help") ?? "",
            Notes = OptStr(d, "notes"),
            Indices = indices,
            Xk7Only = d.TryGetProperty("xk7Only", out var x) && x.ValueKind == JsonValueKind.True,
        };
    }

    static ValueKind Kind(JsonElement v) => OptStr(v, "type") switch
    {
        "enum" => new ValueKind { Type = ValueType.Choices, Options = Options(v, "options") },
        "number" => new ValueKind
        {
            Type = ValueType.Number, Min = Int(v, "min"), Max = Int(v, "max"), Zero = Int(v, "zero"),
            Origin = Dbl(v, "origin"), Step = Dbl(v, "step"), Decimals = Int(v, "decimals"),
            Unit = OptStr(v, "unit") ?? "", Plus = v.TryGetProperty("plus", out var pl) && pl.ValueKind == JsonValueKind.True,
            Special = Options(v, "special").OrderBy(o => o.Raw).ToList(),
        },
        "steps" => new ValueKind { Type = ValueType.Steps, Min = Int(v, "min"), Max = Int(v, "max"), Low = OptStr(v, "low") ?? "", High = OptStr(v, "high") ?? "" },
        "note" => new ValueKind { Type = ValueType.Note, Min = Int(v, "min"), Max = Int(v, "max") },
        "pan" => new ValueKind
        {
            Type = ValueType.Balance, Min = Int(v, "min"), Max = Int(v, "max"), Center = Int(v, "center"),
            Left = OptStr(v, "left") ?? "L%d", Right = OptStr(v, "right") ?? "R%d", CenterLabel = OptStr(v, "centerLabel") ?? "Center",
        },
        "text" => new ValueKind { Type = ValueType.Text, Length = Int(v, "length") },
        var t => throw new ParameterDatabaseException($"value type {t ?? "?"}"),
    };
}
