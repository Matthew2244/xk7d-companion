using System.Net.Http;
using System.Runtime.InteropServices;
using XK7D.Core;

namespace XK7D.Companion;

/// <summary>App updates on Windows through WinSparkle, Sparkle's Windows twin (as Wavelength does).
/// Every installer is signed with the same kind of EdDSA key as the Mac app's updates, kept on
/// Matthew's Mac; WinSparkle checks the signature against the public key below before running it.
/// WinSparkle installs by running the new installer, so only an installed copy (an uninstaller
/// beside it) uses it. WinSparkle never checks by itself here: the app looks every few hours and
/// says one sentence; Help, Check for Updates opens WinSparkle's window.</summary>
public static class Updates
{
    const string ReleaseFeed = "https://github.com/Matthew2244/xk7d-companion/releases/latest/download/appcast-windows.xml";
    /// <summary>The same public key as the Mac app's SUPublicEDKey (scripts/build-app.sh).</summary>
    const string ReleaseKey = "Tb6TgfdA4Ju4L+xy8wj3w8wCcrofZGJDQf0sZELmQb4=";

    /// <summary>A test build (windows/build.ps1 -TestFeed -TestKey) carries its own feed and key, so CI
    /// can rehearse a real update with a throwaway key. Release builds carry neither.</summary>
    static string? Metadata(string key) => typeof(Updates).Assembly
        .GetCustomAttributes(typeof(System.Reflection.AssemblyMetadataAttribute), false)
        .OfType<System.Reflection.AssemblyMetadataAttribute>().FirstOrDefault(a => a.Key == key)?.Value is { Length: > 0 } v ? v : null;

    public static bool IsTestBuild => Metadata("XK7DTestFeed") is not null;
    public static string AppcastUrl => Metadata("XK7DTestFeed") ?? ReleaseFeed;
    public static string PublicKey => Metadata("XK7DTestKey") ?? ReleaseKey;
    public static readonly TimeSpan CheckEvery = TimeSpan.FromHours(4);
    public static readonly TimeSpan FirstCheckAfter = TimeSpan.FromSeconds(15);

    const string Dll = "WinSparkle.dll";
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int CanShutdown();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void ShutdownRequest();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void win_sparkle_set_appcast_url([MarshalAs(UnmanagedType.LPStr)] string url);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int win_sparkle_set_eddsa_public_key([MarshalAs(UnmanagedType.LPStr)] string key);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    static extern void win_sparkle_set_app_details(string company, string app, string version);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void win_sparkle_set_automatic_check_for_updates(int on);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void win_sparkle_set_can_shutdown_callback(CanShutdown cb);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void win_sparkle_set_shutdown_request_callback(ShutdownRequest cb);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void win_sparkle_init();
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void win_sparkle_check_update_with_ui();
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void win_sparkle_check_update_with_ui_and_install();
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void win_sparkle_cleanup();

    static CanShutdown? canShutdown;
    static ShutdownRequest? shutdownRequest;
    static bool started;

    public static string Version => typeof(Updates).Assembly
        .GetCustomAttributes(typeof(System.Reflection.AssemblyInformationalVersionAttribute), false)
        .OfType<System.Reflection.AssemblyInformationalVersionAttribute>().FirstOrDefault()?.InformationalVersion.Split('+')[0]
        ?? "0.0.0";

    /// <summary>True for a copy put there by the installer (it has an uninstaller beside it).</summary>
    public static bool Installed => Directory.EnumerateFiles(AppContext.BaseDirectory, "unins*.exe").Any();

    public static bool WinSparklePresent => File.Exists(Path.Combine(AppContext.BaseDirectory, Dll));

    /// <summary>Start WinSparkle for an installed copy, without any automatic checks.
    /// quit closes the app when WinSparkle is ready to run the new installer.</summary>
    public static bool Start(Action quit)
    {
        if (started) return true;
        if (!Installed || !WinSparklePresent) return false;
        try
        {
            canShutdown = () => 1;
            shutdownRequest = () => quit();
            win_sparkle_set_appcast_url(AppcastUrl);
            if (win_sparkle_set_eddsa_public_key(PublicKey) != 1) return false;
            win_sparkle_set_app_details("Matthew Whitaker", "XK-7D Companion", Version);
            win_sparkle_set_can_shutdown_callback(canShutdown);
            win_sparkle_set_shutdown_request_callback(shutdownRequest);
            // The app does the looking and says so; WinSparkle's window comes only when asked.
            win_sparkle_set_automatic_check_for_updates(0);
            win_sparkle_init();
            started = true;
        }
        catch (Exception)
        {
            started = false;
        }
        return started;
    }

    /// <summary>Help, Check for Updates: WinSparkle's own window takes it from here.</summary>
    public static bool CheckWithWindow()
    {
        if (!started) return false;
        try { win_sparkle_check_update_with_ui(); return true; } catch (Exception) { return false; }
    }

    /// <summary>The update rehearsal (test builds only): check, download, verify and install with no
    /// questions, the way CI proves an update really installs.</summary>
    public static bool Rehearse()
    {
        if (!started || !IsTestBuild) return false;
        try { win_sparkle_check_update_with_ui_and_install(); return true; } catch (Exception) { return false; }
    }

    public static void Stop()
    {
        if (!started) return;
        try { win_sparkle_cleanup(); } catch (Exception) { }
        started = false;
    }

    /// <summary>The newest version the update list offers, or null when it can't be read.
    /// One small request to GitHub; nothing sent but the request.</summary>
    public static async Task<string?> LatestVersionAsync(string? url = null)
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd($"XK7DCompanion/{Version}");
            var xml = await http.GetStringAsync(url ?? AppcastUrl);
            return Appcast.NewestIn(xml);
        }
        catch (Exception)
        {
            return null;
        }
    }
}
