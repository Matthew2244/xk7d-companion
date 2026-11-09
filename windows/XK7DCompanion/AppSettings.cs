using System.Text.Json;
using System.Text.Json.Nodes;

namespace XK7D.Companion;

/// <summary>The app's own settings, the Windows counterpart of the Mac's UserDefaults, with the same
/// key names. Kept in %APPDATA%\XK-7D Companion\settings.json, or in XK7D_TEST_DIR for tests so a
/// test never touches a real person's settings.</summary>
public sealed class AppSettings
{
    readonly string path;
    readonly JsonObject data;
    /// <summary>When false (self-test), nothing is written.</summary>
    public bool Persist { get; set; } = true;

    public AppSettings()
    {
        var dir = Environment.GetEnvironmentVariable("XK7D_TEST_DIR") is { Length: > 0 } test
            ? test
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "XK-7D Companion");
        path = Path.Combine(dir, "settings.json");
        data = Load(path);
    }

    public static string Folder => Environment.GetEnvironmentVariable("XK7D_TEST_DIR") is { Length: > 0 } test
        ? test
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "XK-7D Companion");

    static JsonObject Load(string path)
    {
        try
        {
            if (File.Exists(path) && JsonNode.Parse(File.ReadAllText(path)) is JsonObject o) return o;
        }
        catch (Exception)
        {
            // A damaged settings file is set aside, never fatal: the app starts with defaults.
            try { File.Move(path, path + ".unreadable-" + DateTime.Now.ToString("yyyyMMddHHmmss"), true); } catch (Exception) { }
        }
        return new JsonObject();
    }

    public bool Has(string key) => data.ContainsKey(key);

    public string? GetString(string key) => data[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    public int? GetInt(string key) => data[key] is JsonValue v && v.TryGetValue<int>(out var i) ? i : null;

    public bool GetBool(string key) => data[key] is JsonValue v && v.TryGetValue<bool>(out var b) && b;

    public void Set(string key, string? value) { data[key] = value; Save(); }
    public void Set(string key, int value) { data[key] = value; Save(); }
    public void Set(string key, bool value) { data[key] = value; Save(); }
    public void Remove(string key) { data.Remove(key); Save(); }

    void Save()
    {
        if (!Persist) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            // Written beside, then moved over, so a crash mid-write never leaves half a file.
            var tmp = path + ".new";
            File.WriteAllText(tmp, data.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(tmp, path, true);
        }
        catch (Exception)
        {
            // Settings that can't be saved (a full or read-only disk) must never stop the app.
        }
    }
}
