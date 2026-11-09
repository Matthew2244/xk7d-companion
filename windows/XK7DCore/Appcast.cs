using System.Xml.Linq;

namespace XK7D.Core;

/// <summary>Reading a Sparkle update list (appcast), for the app's own quiet check. Kept here, with
/// no user interface, so it is tested on every system.</summary>
public static class Appcast
{
    static readonly XNamespace SparkleNs = "http://www.andymatuschak.org/xml-namespaces/sparkle";

    /// <summary>The highest sparkle:version among the list's items. Items marked for another
    /// system (sparkle:os) are skipped. Null for a list with no versions.</summary>
    public static string? NewestIn(string xml)
    {
        var doc = XDocument.Parse(xml);
        string? best = null;
        foreach (var item in doc.Descendants("item"))
        {
            var enclosure = item.Element("enclosure");
            var os = enclosure?.Attribute(SparkleNs + "os")?.Value;
            if (os is not null && os != "windows") continue;
            var v = item.Element(SparkleNs + "version")?.Value ?? enclosure?.Attribute(SparkleNs + "version")?.Value;
            if (string.IsNullOrWhiteSpace(v)) continue;
            if (best is null || Compare(v, best) > 0) best = v.Trim();
        }
        return best;
    }

    /// <summary>Compares dotted version numbers: 1.10.0 is newer than 1.9.2, and 1.1 equals 1.1.0.</summary>
    public static int Compare(string a, string b)
    {
        static int[] Parts(string v) => v.Trim().TrimStart('v').Split('.')
            .Select(p => int.TryParse(new string(p.TakeWhile(char.IsAsciiDigit).ToArray()), out var n) ? n : 0).ToArray();
        var x = Parts(a);
        var y = Parts(b);
        for (var i = 0; i < Math.Max(x.Length, y.Length); i++)
        {
            var c = (i < x.Length ? x[i] : 0).CompareTo(i < y.Length ? y[i] : 0);
            if (c != 0) return c;
        }
        return 0;
    }
}
