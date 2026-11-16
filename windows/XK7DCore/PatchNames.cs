// Port of Sources/XK7DCore/PatchNames.swift.
namespace XK7D.Core;

/// <summary>Patch names: the factory table (pp. 172-173), reading names out of a Temporary dump, and
/// the spoken line. Factory patches can't be changed (p. 35); User patches can, so their names come
/// from the organ.</summary>
public static class PatchNames
{
    /// <summary>F00-F99, the UPPER Name column (the trailing "U" part marker left off).</summary>
    public static readonly IReadOnlyList<string> FactoryUpper = new[]
    {
        "Dr. L.S.",
        "Squabble",
        "Rock",
        "Classic Rock",
        "Booker",
        "Vx Reeds",
        "Strings Ens Farf",
        "Principal Chorus + Mixture",
        "Full Theatre",
        "Full Overdrive",
        "First 3 Overdrive",
        "Joe’s M-3",
        "Power Comp",
        "Power Solo 1",
        "Power Solo 2",
        "Kinda Brian",
        "Mark’s Foot Stmp",
        "Spencer Wood",
        "Jerry C.",
        "Solo & Comp",
        "Principal Chorus",
        "Stopped Flute Chorus",
        "Gamba Celeste",
        "Sesquialtera II",
        "Stopped Flute 16´ & 8´",
        "Diapason 8´ & 4´",
        "Bourdon 16´ & Prin 2´",
        "Flutes w/Trem",
        "Hautbois Solo",
        "Sforzando",
        "Tibia 8´",
        "Tibia 8´ & 4´",
        "Style D Trumpet 8´",
        "Oboe 8´ & Tibia 4´",
        "Tibias 16´ & 4´",
        "Brass Trumpet 8´",
        "Tibias, Strings & Voxes",
        "Tibia 16´ 8´ 2´ & Vox",
        "Full Tibias & Voxes",
        "Full Comb + Posthrn",
        "DB 8´ 4´",
        "DB 8´ 2´",
        "DB 8´ 1´",
        "DB 8´ 4´ 2´",
        "DB 16´ 8´",
        "DB 16´ 4´",
        "DB 16´ 8´ 2´",
        "DB 16´ 8´ 4´ & 2´",
        "DB 16´ 8´ 4´ 2´ & 1´",
        "DB Full Organ",
        "Sylvia",
        "Lady",
        "Yeh Yeh",
        "Season Time",
        "On a Clear Day",
        "Twee motten",
        "Toccata Live",
        "Je t’aime moi -+",
        "Early Bird",
        "Bluesette",
        "Vx Mellow",
        "Vx Bright",
        "Vx Mixture",
        "Farf Flute",
        "Farf Brass",
        "Farf Reeds",
        "Farf Strings",
        "Farf Full",
        "Ace Flute",
        "Ace Strings",
        "Summer Samba",
        "Pumping Compress",
        "Touch Wah",
        "Ring + Flanged Jazz",
        "California Girl",
        "Won’t Get Fooled",
        "[TAP] To Delay Time",
        "Drawbar Celesta",
        "Interference",
        "Talking Drawbars",
        "Cancel",
        "French Horn 8´",
        "Tibial 8´ & 2´",
        "Clarinet 8´",
        "Novel Solo 8´",
        "Theatre Solo 16´",
        "Oboe Horn 8´",
        "Full Tibias 16´",
        "Trumpet 8´",
        "Full Theatre Brass 16´",
        "Cancel",
        "Stopped Flute",
        "Dulciana",
        "French Horn",
        "Salicional",
        "Flutes 8´ & 4´",
        "Oboe Horn",
        "Swell Diapason",
        "Trumpet",
        "Full Swell",
    };

    /// <summary>F00-F99, the LOWER and PEDAL Name column (the trailing "L" left off).</summary>
    public static readonly IReadOnlyList<string> FactoryLower = new[]
    {
        "Dr. L.S.",
        "Squabble",
        "Rock",
        "Classic Rock",
        "Booker",
        "Vx Reeds",
        "Strings Ens Farf",
        "Principal Chorus + Mixture",
        "Full Theatre",
        "Full Overdrive",
        "First 3 Overdrive",
        "Joe’s M-3",
        "Power Comp",
        "Power Solo 1",
        "Power Solo 2",
        "Kinda Brian",
        "Mark’s Foot Stmp",
        "Spencer Wood",
        "Jerry C.",
        "Solo & Comp",
        "Principal Chorus",
        "Principal 4´ & 2´",
        "Flute Harmonique",
        "Gedeckt 8´",
        "Melodia 8´",
        "Diapason 8´ & 4´",
        "Principal 16´ & 8´",
        "Gedeckt 8´ w/Trem",
        "Diapason 8´",
        "Sforzando",
        "Clarinet 8´",
        "Diapason 8´",
        "Diapason & Vox",
        "Diapason & Clarinet",
        "Diapason & Flute",
        "Diapason & Oboe",
        "Diapason & Strings",
        "Diapason Flute & Vox",
        "Diapason 8 & 4 & Vox",
        "Full Accomp.",
        "DB 8´ 4´ 64",
        "DB 8´ 2´ 62",
        "DB 8´ 4´ 2⅔´",
        "DB 8´ & 4´ 84",
        "DB 8´ & 4´ 61",
        "DB 8´ & 4´ 65",
        "DB 8´ & 4´ 73",
        "DB 8´ & 4´ 87",
        "DB 8´ 4´ 2´",
        "DB Ensemble",
        "Sylvia",
        "Lady",
        "Yeh Yeh",
        "Season Time",
        "On a Clear Day",
        "Twee motten",
        "Toccata Live",
        "Je t’aime moi -+",
        "Early Bird",
        "Bluesette",
        "Vx Mellow",
        "Vx Bright",
        "Vx Mixture",
        "Farf Flute",
        "Farf Brass",
        "Farf Reeds",
        "Farf Strings",
        "Farf Full",
        "Ace Flute",
        "Ace Strings",
        "Summer Samba",
        "Pumping Compress",
        "Touch Wah",
        "Ring + Flanged Jazz",
        "California Girl",
        "Won’t Get Fooled",
        "[TAP] To Delay Time",
        "Drawbar Celesta",
        "Interference",
        "Talking Drawbars",
        "Cancel",
        "Cello 8´",
        "Dulciana 8´",
        "Vibraharp 8´",
        "Vox 8´ & Tibia 4´",
        "String Accomp. 8´",
        "Open Diapason 8´",
        "Full Accomp. 8´",
        "Tibia 8´",
        "Bombarde 16´",
        "Cancel",
        "Cello",
        "Flute & String",
        "Clarinet",
        "Diapason, Gamba & Flute",
        "Great, no reeds",
        "Open Diapason",
        "Full Great",
        "Tibia Clausa",
        "Full Great with 16´",
    };

    public static bool UsesUpperName(string part) => part == "Upper";

    public static string? FactoryName(string part, int? bank, int program)
    {
        if (bank != 1 || program < 0 || program >= 100) return null;
        return UsesUpperName(part) ? FactoryUpper[program] : FactoryLower[program];
    }

    /// <summary>A User patch or a Favorite: a stored patch whose name is worth looking up.</summary>
    public static bool IsLookupSlot(int? bank, int program) => program switch
    {
        >= 0 and <= 0x63 => bank == 0,
        >= 0x64 and <= 0x6D => true,
        _ => false,
    };

    /// <summary>A stored name tidied for speaking: runs of spaces become one, and a part marker set
    /// apart at the end ("  U", "  L") is left off.</summary>
    public static string Clean(string raw)
    {
        var s = raw.Replace("\0", " ", StringComparison.Ordinal);
        if (s.Length >= 3)
        {
            var tail = s[^3..];
            if (tail == "  U" || tail == "  L") s = s[..^1];
        }
        return string.Join(" ", s.Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>The name as it is said: a footage mark after a number (8\u00B4, 8' or 8\u2019) becomes "foot".</summary>
    public static string Spoken(string name)
    {
        var sb = new System.Text.StringBuilder();
        char? previous = null;
        foreach (var c in name)
        {
            if ((c == '\u00B4' || c == '\'' || c == '\u2019') && previous is { } p && ((p >= '0' && p <= '9') || p == '\u2154'))
                sb.Append(" foot");
            else if (c == '\u00B4')
                sb.Append(' ');
            else
                sb.Append(c);
            previous = c;
        }
        return sb.ToString();
    }

    /// <summary>"Upper: Dr. L.S., F00" with a name, "Upper: patch U05" without.</summary>
    public static string Announcement(string part, string description, string? name)
    {
        var slot = PatchSelect.Spoken(description);
        if (string.IsNullOrEmpty(name)) return $"{part}: {slot}";
        var shortSlot = slot.StartsWith("patch ", StringComparison.Ordinal) ? slot[6..] : slot;
        return $"{part}: {Spoken(name)}, {shortSlot}";
    }

    /// <summary>Finds the Upper and Lower names in a Temporary dump's data (see the Swift for the rule).</summary>
    public static (string Upper, string Lower)? FromTemporaryDump(IReadOnlyList<byte> data)
    {
        if (data.Count < 32) return null;
        static bool Printable(byte b) => b >= 0x20 && b <= 0x7E;
        static bool Letter(byte b) => (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A);
        static int Letters(IEnumerable<byte> s) => s.Count(Letter);
        static bool Wordy(IReadOnlyCollection<byte> s) => s.Count(b => Letter(b) || b == 0x20) * 2 >= s.Count;
        var run = 0;
        for (var i = 0; i < data.Count; i++)
        {
            run = Printable(data[i]) ? run + 1 : 0;
            if (run < 32) continue;
            var start = i - 31;
            var up = data.Skip(start).Take(16).ToArray();
            var lo = data.Skip(start + 16).Take(16).ToArray();
            if (Wordy(up) && Wordy(lo) && Math.Max(Letters(up), Letters(lo)) >= 2 && Letters(up) + Letters(lo) >= 3)
                return (Clean(System.Text.Encoding.ASCII.GetString(up)), Clean(System.Text.Encoding.ASCII.GetString(lo)));
        }
        return null;
    }
}
