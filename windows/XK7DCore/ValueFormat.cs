// Port of Sources/XK7DCore/ValueFormat.swift. Tests/Vectors/core-vectors.json checks every value of
// every setting, and what typing gives, against the Swift core.
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace XK7D.Core;

/// <summary>Note names the way the XK-7 display writes them: octave first, so note 60 is "3C".</summary>
public static class NoteName
{
    static readonly string[] Names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };

    public static string Display(int note) => $"{note / 12 - 2}{Names[((note % 12) + 12) % 12]}";

    /// <summary>For speech: "C sharp 3" reads better than "3C#".</summary>
    public static string Spoken(int note)
    {
        var n = Names[((note % 12) + 12) % 12].Replace("#", " sharp", StringComparison.Ordinal);
        return $"{n} {note / 12 - 2}";
    }
}

/// <summary>The few pieces of Swift's string handling the core relies on, reproduced exactly, so
/// typed values parse the same on both systems.</summary>
public static class SwiftText
{
    /// <summary>CharacterSet.whitespaces: Unicode Zs and tab.</summary>
    public static bool IsWhitespace(char c) => c == '\t' || CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;

    /// <summary>CharacterSet.whitespacesAndNewlines.</summary>
    public static bool IsWhitespaceOrNewline(char c) =>
        IsWhitespace(c) || c is '\n' or '\v' or '\f' or '\r' or '\u0085' or '\u2028' or '\u2029';

    /// <summary>CharacterSet.letters: Unicode L* and M*.</summary>
    public static bool IsLetter(char c) => CharUnicodeInfo.GetUnicodeCategory(c) switch
    {
        UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
            or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter or UnicodeCategory.NonSpacingMark
            or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark => true,
        _ => false,
    };

    public static string Trim(string s, Func<char, bool> set)
    {
        var a = 0;
        var b = s.Length;
        while (a < b && set(s[a])) a++;
        while (b > a && set(s[b - 1])) b--;
        return s.Substring(a, b - a);
    }

    public static string TrimWhitespace(string s) => Trim(s, IsWhitespace);

    /// <summary>Swift's Int("..."): an optional sign and ASCII digits, nothing else.</summary>
    public static int? ParseInt(string s)
    {
        if (s.Length == 0) return null;
        var i = s[0] is '+' or '-' ? 1 : 0;
        if (i == s.Length) return null;
        for (var k = i; k < s.Length; k++) if (s[k] < '0' || s[k] > '9') return null;
        return int.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var v) ? v : null;
    }

    /// <summary>Foundation's Scanner(string:).scanDouble(): skips leading whitespace and newlines,
    /// then reads the longest number at the start (sign, digits, a "." fraction, an exponent),
    /// ignoring whatever follows. Any Unicode decimal digit counts as a digit.</summary>
    public static double? ScanDouble(string s)
    {
        var i = 0;
        while (i < s.Length && IsWhitespaceOrNewline(s[i])) i++;
        var sb = new StringBuilder();
        if (i < s.Length && s[i] is '+' or '-') { if (s[i] == '-') sb.Append('-'); i++; }
        var digits = 0;
        while (i < s.Length && char.IsDigit(s[i])) { sb.Append(Digit(s[i])); i++; digits++; }
        if (i < s.Length && s[i] == '.')
        {
            var j = i + 1;
            var frac = new StringBuilder();
            while (j < s.Length && char.IsDigit(s[j])) { frac.Append(Digit(s[j])); j++; }
            if (digits > 0 || frac.Length > 0)
            {
                sb.Append('.').Append(frac);
                digits += frac.Length;
                i = j;
            }
        }
        if (digits == 0) return null;
        if (i < s.Length && s[i] is 'e' or 'E')
        {
            var j = i + 1;
            var exp = new StringBuilder("e");
            if (j < s.Length && s[j] is '+' or '-') { exp.Append(s[j]); j++; }
            var expDigits = 0;
            while (j < s.Length && char.IsDigit(s[j])) { exp.Append(Digit(s[j])); j++; expDigits++; }
            if (expDigits > 0) sb.Append(exp);
        }
        return double.Parse(sb.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture);
    }

    static char Digit(char c) => (char)('0' + (int)char.GetNumericValue(c));

    /// <summary>Swift's Double.rounded(): halves away from zero.</summary>
    public static double Round(double d) => Math.Round(d, MidpointRounding.AwayFromZero);
}

public static class ValueFormat
{
    /// <summary>The value as the organ's display would show it.</summary>
    public static string Display(this Parameter p, int raw)
    {
        var k = p.Kind;
        switch (k.Type)
        {
            case ValueType.Choices:
                foreach (var o in k.Options) if (o.Raw == raw) return o.Label;
                return $"Unknown value {raw}";
            case ValueType.Number:
            {
                if (k.SpecialLabel(raw) is { } s) return s;
                var v = k.Origin + (raw - k.Zero) * k.Step;
                var text = v.ToString("F" + k.Decimals.ToString(CultureInfo.InvariantCulture), CultureInfo.InvariantCulture);
                if (text.StartsWith('-') && double.Parse(text, CultureInfo.InvariantCulture) == 0) text = text.Substring(1);
                if (k.Plus && v > 0) text = "+" + text;
                return k.Unit.Length == 0 ? text : $"{text} {UnitText(k.Unit, v)}";
            }
            case ValueType.Steps:
                if (raw == k.Min) return k.Low;
                if (raw == k.Max) return k.High;
                return $"step {raw - k.Min} of {k.Max - k.Min}";
            case ValueType.Note:
                return NoteName.Display(raw);
            case ValueType.Balance:
                if (raw == k.Center) return k.CenterLabel;
                if (raw < k.Center) return k.Left.Replace("%d", (k.Center - raw).ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal);
                return k.Right.Replace("%d", (raw - k.Center).ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal);
            default:
                return "";
        }
    }

    /// <summary>The same value phrased for speech, where the display's shorthand would be misread.</summary>
    public static string Spoken(this Parameter p, int raw)
    {
        var k = p.Kind;
        switch (k.Type)
        {
            case ValueType.Note:
                return NoteName.Spoken(raw);
            case ValueType.Balance:
            {
                if (raw == k.Center) return k.CenterLabel;
                var d = p.Display(raw);
                if (d.StartsWith('L')) return $"left {k.Center - raw}";
                if (d.StartsWith('R')) return $"right {raw - k.Center}";
                if (d.StartsWith('D')) return $"dry {k.Center - raw}";
                if (d.EndsWith('V')) return $"vibrato {raw - k.Center}";
                return d;
            }
            default:
                return p.Display(raw).Replace("-inf", "minus infinity", StringComparison.Ordinal)
                    .Replace("A#", "A sharp", StringComparison.Ordinal);
        }
    }

    static string UnitText(string unit, double value)
    {
        if (Math.Abs(value) == 1)
        {
            switch (unit)
            {
                case "octaves": return "octave";
                case "semitones": return "semitone";
                case "cents": return "cent";
            }
        }
        return unit;
    }

    /// <summary>Every raw value, in order, for controls that step through them.</summary>
    public static IReadOnlyList<int> AllRawValues(this Parameter p) =>
        p.Kind.Type == ValueType.Choices ? p.Kind.Options.Select(o => o.Raw).ToList()
                                         : Enumerable.Range(p.RawMin, p.RangeCount).ToList();

    public static int Clamp(this Parameter p, int raw) => Math.Min(Math.Max(raw, p.RawMin), p.RawMax);

    /// <summary>A typed number as a whole number, or null when it's far outside any range.</summary>
    static int? Whole(double d) => double.IsFinite(d) && Math.Abs(d) < 1_000_000_000 ? (int)d : null;

    static bool InRange(int raw, int lo, int hi) => raw >= lo && raw <= hi;

    static readonly Regex NotePattern = new(@"^(-?\d)([a-g]#?)$|^([a-g]#?)(-?\d)$", RegexOptions.CultureInvariant);
    static readonly string[] NoteNames = { "c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b" };

    /// <summary>Turn what the user typed into a raw value, using the same mapping the display uses:
    /// "340 rpm", "+2", "-12.1 dB", "Random", "off", "3C" or "C3", "L10", "center", "step 12".</summary>
    public static int? RawValueFromTyped(this Parameter p, string text)
    {
        var t = SwiftText.TrimWhitespace(text).ToLowerInvariant();
        if (t.Length == 0) return null;
        static double? Number(string s) => SwiftText.ScanDouble(s.Replace("+", "", StringComparison.Ordinal));
        var k = p.Kind;
        switch (k.Type)
        {
            case ValueType.Steps:
            {
                if (t == k.Low.ToLowerInvariant()) return k.Min;
                if (t == k.High.ToLowerInvariant()) return k.Max;
                var n = Number(SwiftText.TrimWhitespace(t.Replace("step", "", StringComparison.Ordinal)));
                if (n is not { } nv || Whole(nv) is not { } whole) return null;
                var raw = k.Min + whole;
                return InRange(raw, k.Min, k.Max) ? raw : null;
            }
            case ValueType.Note:
            {
                if (SwiftText.ParseInt(t) is { } direct && InRange(direct, k.Min, k.Max)) return direct;
                var compact = t.Replace(" sharp", "#", StringComparison.Ordinal).Replace(" ", "", StringComparison.Ordinal);
                var m = NotePattern.Match(compact);
                if (!m.Success) return null;
                string? G(int i) => m.Groups[i].Success ? m.Groups[i].Value : null;
                var octaveText = G(1) ?? G(4) ?? "";
                var name = G(2) ?? G(3);
                if (SwiftText.ParseInt(octaveText) is not { } octave || name is null) return null;
                var idx = Array.IndexOf(NoteNames, name);
                if (idx < 0) return null;
                var raw = (octave + 2) * 12 + idx;
                return InRange(raw, k.Min, k.Max) ? raw : null;
            }
            case ValueType.Balance:
            {
                if (t == k.CenterLabel.ToLowerInvariant() || t == "center" || t == "centre" || t == "c") return k.Center;
                int? raw = null;
                var stripped = SwiftText.Trim(t, c => SwiftText.IsLetter(c) || SwiftText.IsWhitespace(c));
                if ((t.StartsWith('l') || t.StartsWith("left", StringComparison.Ordinal) || t.StartsWith('d')
                     || t.StartsWith("dry", StringComparison.Ordinal)) && Number(stripped) is { } a && Whole(a) is { } wa)
                    raw = k.Center - wa;
                else if ((t.StartsWith('r') || t.StartsWith("right", StringComparison.Ordinal) || t.EndsWith('v')
                          || t.StartsWith("vib", StringComparison.Ordinal)) && Number(stripped) is { } b && Whole(b) is { } wb)
                    raw = k.Center + wb;
                else if (Number(t) is { } c && Whole(c) is { } wc)
                    raw = k.Center + wc;
                return raw is { } r && InRange(r, k.Min, k.Max) ? r : null;
            }
            case ValueType.Number:
            {
                // Named values ("Random", "Off", "-inf", "Mono"): the whole word, or the start of it.
                var hasLetters = t.Any(SwiftText.IsLetter);
                foreach (var s in k.Special)
                {
                    var label = s.Label.ToLowerInvariant();
                    if (label == t || (hasLetters && label.StartsWith(t, StringComparison.Ordinal))) return s.Raw;
                }
                var numeric = t.Replace("\u00B1", "", StringComparison.Ordinal).Replace("+", "", StringComparison.Ordinal);
                if (SwiftText.ScanDouble(numeric) is not { } v || Whole(SwiftText.Round((v - k.Origin) / k.Step)) is not { } steps)
                    return null;
                var raw = steps + k.Zero;
                if (InRange(raw, k.Min, k.Max) && k.SpecialLabel(raw) is null) return raw;
                // A named value that is also a number, like "0 rpm" for a stopped rotor.
                foreach (var s in k.Special)
                    if (SwiftText.ScanDouble(s.Label) == v) return s.Raw;
                return null;
            }
            default:
                return null;
        }
    }
}

/// <summary>Text values: the organ uses 7-bit ASCII, padded to 16 characters.</summary>
public static class TextCodec
{
    /// <summary>Typographic quotes and dashes become their plain ASCII forms.</summary>
    public static string Plain(string s)
    {
        var t = s;
        foreach (var (a, b) in new[] { ("\u2018", "'"), ("\u2019", "'"), ("\u201C", "\""), ("\u201D", "\""),
                                       ("\u2013", "-"), ("\u2014", "-"), ("\u00A0", " ") })
            t = t.Replace(a, b, StringComparison.Ordinal);
        return t;
    }

    public static byte[] Encode(string s, int length = 16)
    {
        var bytes = new List<byte>();
        foreach (var r in Plain(s).EnumerateRunes())
            bytes.Add(r.Value < 0x80 && r.Value >= 0x20 ? (byte)r.Value : (byte)'?');
        if (bytes.Count > length) bytes = bytes.Take(length).ToList();
        while (bytes.Count < length) bytes.Add(0x20);
        return bytes.ToArray();
    }

    public static string Decode(IEnumerable<byte> bytes)
    {
        var chars = bytes.Select(b => b >= 0x20 && b < 0x7F ? (char)b : ' ').ToArray();
        return SwiftText.TrimWhitespace(new string(chars));
    }
}
