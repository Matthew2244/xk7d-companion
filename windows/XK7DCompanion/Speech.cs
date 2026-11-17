using System.Runtime.InteropServices;
using System.Text;

namespace XK7D.Companion;

/// <summary>Speech through Prism (prism.dll, MPL-2.0, from the prismatoid package, the same library
/// Wavelength uses): NVDA and JAWS directly, several other screen readers, and UI Automation
/// notifications for Narrator. Its OneCore and SAPI backends are the "Windows voice". Every call is
/// guarded: speech failing must never stop the app.</summary>
public static class Prism
{
    const string Dll = "prism.dll";

    public const ulong Nvda = 0x89CC19C5C4AC1A56, Jaws = 0xAC3D60E9BD84B53E, Zdsr = 0x3D93C56C9E7F2A2E,
        SystemAccess = 0x8380F2A37B2C3EB6, ZoomText = 0xAE439D62DC7B1479, SenseReader = 0xED4760890B55C2F2,
        PcTalker = 0x344B951962E3B835, BoyPcReader = 0x285ABA1C16F3300F, Uia = 0x6238F019DB678F8E,
        OneCore = 0x6797D32F0D994CB4, Sapi = 0x1D6DF72422CEEE66;

    const ulong SupportedAtRuntime = 1UL << 0, SupportsOutput = 1UL << 5;
    const int Ok = 0, AlreadyInitialized = 15;

    /// <summary>Screen readers Prism talks to directly, in the order Wavelength tries them.</summary>
    public static readonly (ulong Id, string Name)[] Readers =
    {
        (Nvda, "NVDA"), (Jaws, "JAWS"), (Zdsr, "ZDSR"), (SystemAccess, "System Access"), (ZoomText, "ZoomText"),
        (SenseReader, "Sense Reader"), (PcTalker, "PC-Talker"), (BoyPcReader, "Boy PC Reader"),
    };

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr prism_init(IntPtr cfg);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
    static extern bool prism_registry_exists(IntPtr ctx, ulong id);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr prism_registry_acquire(IntPtr ctx, ulong id);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_initialize(IntPtr b);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern ulong prism_backend_get_features(IntPtr b);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    static extern int prism_backend_speak(IntPtr b, byte[] text, [MarshalAs(UnmanagedType.I1)] bool interrupt);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    static extern int prism_backend_output(IntPtr b, byte[] text, [MarshalAs(UnmanagedType.I1)] bool interrupt);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void prism_backend_free(IntPtr b);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_get_rate(IntPtr b, out float rate);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_set_rate(IntPtr b, float rate);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_get_volume(IntPtr b, out float volume);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_set_volume(IntPtr b, float volume);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_count_voices(IntPtr b, out UIntPtr count);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_get_voice_name(IntPtr b, UIntPtr index, out IntPtr name);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_set_voice(IntPtr b, UIntPtr index);

    /// <summary>The Windows voice's settings: a voice by name (null for Windows' default), a speed
    /// (0 = Windows' own, 1 slow, 2 normal, 3 fast, 4 very fast) and a loudness in percent. Speed and
    /// loudness are applied relative to what the voice reports at first, since Prism doesn't document
    /// its ranges.</summary>
    public static (string? Voice, int Speed, int Volume) VoiceConfig { get; private set; } = (null, 0, 100);
    static int voiceConfigVersion = 1;
    static readonly Dictionary<ulong, (float Rate, float Volume, int Version)> voiceState = new();

    public static void SetVoiceConfig(string? voice, int speed, int volume)
    {
        VoiceConfig = (string.IsNullOrEmpty(voice) ? null : voice, speed, Math.Clamp(volume, 25, 100));
        voiceConfigVersion++;
    }

    static void ApplyVoiceConfig(ulong id, IntPtr b)
    {
        try
        {
            if (!voiceState.TryGetValue(id, out var st))
            {
                prism_backend_get_rate(b, out var r0);
                prism_backend_get_volume(b, out var v0);
                st = (r0, v0, 0);
            }
            if (st.Version == voiceConfigVersion) return;
            var (voice, speed, volume) = VoiceConfig;
            if (voice is not null && VoiceNames(b).IndexOf(voice) is var i and >= 0) prism_backend_set_voice(b, (UIntPtr)i);
            var factor = speed switch { 1 => 0.8f, 3 => 1.25f, 4 => 1.5f, _ => 1f };
            var rate = st.Rate * factor;
            if (st.Rate <= 1f) rate = Math.Clamp(rate, 0f, 1f);
            prism_backend_set_rate(b, rate);
            prism_backend_set_volume(b, st.Volume * volume / 100f);
            voiceState[id] = (st.Rate, st.Volume, voiceConfigVersion);
        }
        catch (Exception) { }
    }

    static List<string> VoiceNames(IntPtr b)
    {
        var names = new List<string>();
        try
        {
            if (prism_backend_count_voices(b, out var count) != Ok) return names;
            for (ulong i = 0; i < count.ToUInt64(); i++)
                names.Add(prism_backend_get_voice_name(b, (UIntPtr)i, out var p) == Ok && p != IntPtr.Zero
                    ? Marshal.PtrToStringUTF8(p) ?? "" : "");
        }
        catch (Exception) { }
        return names;
    }

    /// <summary>The Windows voices to choose from, for Settings.</summary>
    public static List<string> WindowsVoices()
    {
        if (!Load()) return new List<string>();
        foreach (var id in new[] { OneCore, Sapi })
        {
            if (kept.TryGetValue(id, out var k)) return VoiceNames(k).Where(n => n.Length > 0).Distinct().ToList();
            IntPtr b = IntPtr.Zero;
            try
            {
                if (!prism_registry_exists(context, id)) continue;
                b = prism_registry_acquire(context, id);
                if (b == IntPtr.Zero) continue;
                var init = prism_backend_initialize(b);
                if (init != Ok && init != AlreadyInitialized) continue;
                kept[id] = b;
                b = IntPtr.Zero;
                return VoiceNames(kept[id]).Where(n => n.Length > 0).Distinct().ToList();
            }
            catch (Exception) { }
            finally { if (b != IntPtr.Zero) { try { prism_backend_free(b); } catch (Exception) { } } }
        }
        return new List<string>();
    }

    static IntPtr context;
    static bool failed;
    public static string? LoadProblem { get; private set; }

    /// <summary>Load Prism. False (and LoadProblem says why) if prism.dll is missing or won't start.</summary>
    public static bool Load()
    {
        if (context != IntPtr.Zero) return true;
        if (failed) return false;
        try
        {
            context = prism_init(IntPtr.Zero);
            if (context == IntPtr.Zero) { failed = true; LoadProblem = "Prism did not start"; }
        }
        catch (Exception e)
        {
            failed = true;
            LoadProblem = e.Message;
        }
        return context != IntPtr.Zero;
    }

    /// <summary>Voice backends kept between announcements. A voice (OneCore, SAPI) plays its audio
    /// after speak returns; freeing the backend straight away can cut it off, so these stay open,
    /// as Wavelength keeps its own. Screen readers are asked afresh each time, since one can be
    /// started or quit at any moment.</summary>
    static readonly Dictionary<ulong, IntPtr> kept = new();

    /// <summary>The first of these backends that is running and takes the text. Returns its name, or null.</summary>
    static string? Try((ulong Id, string Name)[] backends, string text, bool interrupt, bool needRunning, bool keep = false)
    {
        if (!Load()) return null;
        var utf8 = Encoding.UTF8.GetBytes(text + "\0");
        foreach (var (id, name) in backends)
        {
            IntPtr b = IntPtr.Zero;
            var reused = keep && kept.TryGetValue(id, out b);
            try
            {
                if (!reused)
                {
                    if (!prism_registry_exists(context, id)) continue;
                    b = prism_registry_acquire(context, id);
                    if (b == IntPtr.Zero) continue;
                    var init = prism_backend_initialize(b);           // fails for a reader that isn't running
                    if (init != Ok && init != AlreadyInitialized) continue;
                }
                if (keep) ApplyVoiceConfig(id, b);
                var features = prism_backend_get_features(b);
                if (needRunning && (features & SupportedAtRuntime) == 0) continue;
                var r = (features & SupportsOutput) != 0
                    ? prism_backend_output(b, utf8, interrupt)     // speech and braille
                    : prism_backend_speak(b, utf8, interrupt);
                if (r == Ok)
                {
                    if (keep) { kept[id] = b; b = IntPtr.Zero; }   // stays open, still speaking
                    return name;
                }
            }
            catch (Exception)
            {
                // This reader hiccuped (restarting, say): try the next.
            }
            finally
            {
                if (b != IntPtr.Zero)
                {
                    if (reused) kept.Remove(id);
                    try { prism_backend_free(b); } catch (Exception) { }
                }
            }
        }
        return null;
    }

    /// <summary>Through a running screen reader (NVDA, JAWS and the others Prism knows). Null if none is running.</summary>
    public static string? ToScreenReader(string text, bool interrupt) => Try(Readers, text, interrupt, needRunning: true);

    /// <summary>As a UI Automation notification, which Narrator (and some others) speak.</summary>
    public static string? ToUiAutomation(string text, bool interrupt) =>
        Try(new[] { (Uia, "Narrator") }, text, interrupt, needRunning: false);

    /// <summary>The Windows voice: OneCore, or SAPI where OneCore isn't there.</summary>
    public static string? ToWindowsVoice(string text, bool interrupt) =>
        Try(new[] { (OneCore, "Windows voice"), (Sapi, "Windows voice (SAPI)") }, text, interrupt, needRunning: false, keep: true);

    /// <summary>Which screen readers Prism finds running now, for the self-test and About.</summary>
    public static List<string> RunningReaders()
    {
        var found = new List<string>();
        if (!Load()) return found;
        foreach (var (id, name) in Readers)
        {
            IntPtr b = IntPtr.Zero;
            try
            {
                if (!prism_registry_exists(context, id)) continue;
                b = prism_registry_acquire(context, id);
                if (b == IntPtr.Zero) continue;
                var init = prism_backend_initialize(b);
                if ((init == Ok || init == AlreadyInitialized) && (prism_backend_get_features(b) & SupportedAtRuntime) != 0)
                    found.Add(name);
            }
            catch (Exception) { }
            finally
            {
                if (b != IntPtr.Zero) { try { prism_backend_free(b); } catch (Exception) { } }
            }
        }
        return found;
    }
}

/// <summary>Speaks announcements through the screen reader when one is running, or the Windows
/// voice otherwise. The Windows counterpart of the Mac's Announcer.</summary>
public sealed class Announcer
{
    public enum Method { Automatic, ScreenReader, WindowsVoice }

    public static string Title(Method m) => m switch
    {
        Method.Automatic => "Automatic (the screen reader when one is running, otherwise the Windows voice)",
        Method.ScreenReader => "Screen reader only",
        _ => "The Windows voice",
    };

    readonly AppSettings settings;
    public Announcer(AppSettings settings) { this.settings = settings; PushVoice(); }

    public Method SpeakWith
    {
        get => settings.GetString("announceMethod") switch
        {
            "screenReader" => Method.ScreenReader,
            "windowsVoice" => Method.WindowsVoice,
            _ => Method.Automatic,
        };
        set => settings.Set("announceMethod", value switch
        {
            Method.ScreenReader => "screenReader",
            Method.WindowsVoice => "windowsVoice",
            _ => "automatic",
        });
    }

    public bool Muted
    {
        get => settings.GetBool("announcementsMuted");
        set => settings.Set("announcementsMuted", value);
    }

    /// <summary>The Windows voice by name, or null for Windows' default (Settings, Time and language, Speech).</summary>
    public string? VoiceName
    {
        get => settings.GetString("windowsVoiceName") is { Length: > 0 } v ? v : null;
        set { settings.Set("windowsVoiceName", value ?? ""); PushVoice(); }
    }

    public static readonly string[] SpeedTitles = { "Windows speed", "Slow", "Normal", "Fast", "Very fast" };
    /// <summary>0 = Windows' own speed, 1 slow, 2 normal, 3 fast, 4 very fast.</summary>
    public int Speed
    {
        get => Math.Clamp(settings.GetInt("windowsVoiceSpeed") ?? 0, 0, 4);
        set { settings.Set("windowsVoiceSpeed", Math.Clamp(value, 0, 4)); PushVoice(); }
    }

    /// <summary>Loudness of the Windows voice, 25 to 100 percent.</summary>
    public int VolumePercent
    {
        get => Math.Clamp(settings.GetInt("windowsVoiceVolume") ?? 100, 25, 100);
        set { settings.Set("windowsVoiceVolume", Math.Clamp(value, 25, 100)); PushVoice(); }
    }

    public void PushVoice() => Prism.SetVoiceConfig(VoiceName, Speed, VolumePercent);

    /// <summary>Say a sample in the Windows voice with the chosen settings.</summary>
    public void Sample()
    {
        PushVoice();
        Prism.ToWindowsVoice("Upper: Dr. L.S., F00", true);
    }

    /// <summary>Test and self-test hook: when set, nothing is spoken; text goes here instead.</summary>
    public Action<string>? SilentSink { get; set; }
    /// <summary>Every announcement, for the history list.</summary>
    public Action<string>? OnAnnounced { get; set; }
    /// <summary>What spoke the last announcement ("NVDA", "Windows voice"), for Help and the self-test.</summary>
    public string? LastVoice { get; private set; }

    /// <summary>force speaks even when muted (for things the person asked for, like Repeat Last).
    /// polite lets the screen reader finish what it is saying first. historyText is what the history
    /// list and Repeat Last keep, when it differs from what is said (a value said alone keeps its
    /// setting's name there).</summary>
    public void Announce(string text, bool force = false, bool polite = false, string? historyText = null)
    {
        OnAnnounced?.Invoke(historyText ?? text);
        if (SilentSink is { } sink) { sink(text); return; }
        if (Muted && !force) return;
        if (string.IsNullOrWhiteSpace(text)) return;
        var interrupt = !polite;
        LastVoice = SpeakWith switch
        {
            Method.ScreenReader => Prism.ToScreenReader(text, interrupt) ?? Prism.ToUiAutomation(text, interrupt),
            Method.WindowsVoice => Prism.ToWindowsVoice(text, interrupt),
            _ => Prism.ToScreenReader(text, interrupt)
                 ?? (Native.ScreenReaderFlag() ? Prism.ToUiAutomation(text, interrupt) : Prism.ToWindowsVoice(text, interrupt)),
        };
    }
}

static class Native
{
    const uint SPI_GETSCREENREADER = 0x0046;

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool SystemParametersInfo(uint action, uint param, out int value, uint winIni);

    /// <summary>Windows' own "a screen reader is running" flag, which Narrator and others set.</summary>
    public static bool ScreenReaderFlag()
    {
        try { return SystemParametersInfo(SPI_GETSCREENREADER, 0, out var on, 0) && on != 0; }
        catch (Exception) { return false; }
    }
}
