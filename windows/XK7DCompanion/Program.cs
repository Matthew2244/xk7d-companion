using System.Windows;
using System.Windows.Threading;
using XK7D.Core;

namespace XK7D.Companion;

/// <summary>Starts the app. Modes:
///   (none)                  the app
///   --self-test LOG         no window, no speech: a scripted session against the simulator, written
///                           to LOG; exits 0 when every step did what it should (like the Mac's XK7D_SELFTEST)
///   --ui-test               the real windows on the simulator, silent, for the UI Automation check in CI
/// XK7D_TEST_DIR keeps settings in that folder, so tests never touch a person's own.</summary>
public static class Program
{
    public static bool Quitting { get; set; }
    static string? updateNotice, updateVersion;
    static Mutex? single;

    [STAThread]
    public static int Main(string[] args)
    {
        var selfTestLog = args.Length >= 2 && args[0] == "--self-test" ? args[1] : null;
        var uiTest = args.Contains("--ui-test");
        var rehearsal = args.Contains("--update-rehearsal") && Updates.IsTestBuild;
        var app = new Application { ShutdownMode = selfTestLog is null ? ShutdownMode.OnMainWindowClose : ShutdownMode.OnExplicitShutdown };

        var problem = ParameterDatabase.LoadError ?? (ParameterDatabase.Shared.Parameters.Count == 0 ? "the table is empty" : null);
        if (problem is not null)
        {
            if (selfTestLog is not null) { File.WriteAllText(selfTestLog, $"FAILED settings table: {problem}\n"); return 2; }
            MessageBox.Show($"The app's list of organ settings couldn't be read, so it can't work. Please download it again from github.com/Matthew2244/xk7d-companion. Details: {problem}",
                "XK-7D Companion can't start", MessageBoxButton.OK, MessageBoxImage.Error);
            return 2;
        }

        if (selfTestLog is null && !uiTest && !rehearsal)
        {
            // Two copies would fight over the organ's MIDI port.
            single = new Mutex(true, @"Local\XK7DCompanion", out var first);
            if (!first)
            {
                MessageBox.Show("XK-7D Companion is already open. Look for it in the taskbar, or press Alt Tab.", "XK-7D Companion");
                return 0;
            }
        }

        var settings = new AppSettings { Persist = selfTestLog is null && !uiTest && !rehearsal };
        var model = new AppModel(settings, app.Dispatcher);
        if (selfTestLog is not null) return SelfTest.Run(app, model, selfTestLog);

        if (uiTest || rehearsal || Environment.GetEnvironmentVariable("XK7D_SILENT") is not null) model.Announcer.SilentSink = _ => { };
        var main = new MainWindow(model);
        var simulator = new SimulatorWindow(model);
        var settingsWindow = new SettingsWindow(model);
        main.ShowSimulator = () => { simulator.Show(); simulator.Activate(); };
        main.ShowSettings = () => { settingsWindow.Reload(); settingsWindow.Show(); settingsWindow.Activate(); };
        main.CheckForUpdates = () =>
        {
            if (Updates.CheckWithWindow())
            {
                // WinSparkle's window shows what's new; the quiet look won't announce this version again.
                if (updateVersion is not null) { settings.Set("toldUpdateVersion", updateVersion); updateNotice = null; }
            }
            else
            {
                model.Announcer.Announce("Updates come through the installer. Download the latest from github.com/Matthew2244/xk7d-companion.", force: true);
            }
        };
        main.Closing += (_, _) => Quitting = true;
        app.MainWindow = main;
        app.Exit += (_, _) => { Quitting = true; Updates.Stop(); model.Shutdown(); };
        main.Show();

        if (rehearsal)
        {
            // CI's update rehearsal: WinSparkle checks the test feed, verifies the signature, closes
            // this app and runs the newer installer. Never in a release build (Updates.IsTestBuild).
            if (!Updates.Start(() => app.Dispatcher.BeginInvoke(() => { Quitting = true; app.Shutdown(); })) || !Updates.Rehearse())
                return 3;
        }
        else if (uiTest)
        {
            model.Choose(PortChoice.BuiltInSimulator, remember: false);
            simulator.Show();
            settingsWindow.Show();
            main.Activate();
            if (Environment.GetEnvironmentVariable("XK7D_SHOW") is { } show && show.Split(':') is [_, var id, ..]) main.Reveal(id);
        }
        else
        {
            model.ConnectAtLaunch();
            StartUpdates(app, model, settings, main);
        }
        return app.Run();
    }

    /// <summary>WinSparkle for the window (installed copies), and the app's own quiet look every few hours.</summary>
    static void StartUpdates(Application app, AppModel model, AppSettings settings, MainWindow main)
    {
        Updates.Start(() => app.Dispatcher.BeginInvoke(() => { Quitting = true; app.Shutdown(); }));
        async void Look()
        {
            var latest = await Updates.LatestVersionAsync();
            if (latest is null || Appcast.Compare(latest, Updates.Version) <= 0) return;
            if (settings.GetString("toldUpdateVersion") == latest) return;
            updateVersion = latest;
            updateNotice = $"XK-7D Companion {latest} is out. Help, Check for Updates shows what's new and installs it.";
        }
        var first = new DispatcherTimer { Interval = Updates.FirstCheckAfter };
        first.Tick += (_, _) => { first.Stop(); Look(); };
        first.Start();
        var every = new DispatcherTimer { Interval = Updates.CheckEvery };
        every.Tick += (_, _) => Look();
        every.Start();
        // Say it once, only when this app is in front, no dialog is open and announcements aren't
        // muted: never over a question someone is answering, never into another app.
        var deliver = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        deliver.Tick += (_, _) =>
        {
            if (updateNotice is null || updateVersion is null || Modal.Open > 0 || model.Announcer.Muted) return;
            if (!app.Windows.Cast<Window>().Any(w => w.IsActive)) return;
            settings.Set("toldUpdateVersion", updateVersion);
            model.Announcer.Announce(updateNotice, polite: true);
            updateNotice = null;
        };
        deliver.Start();
    }
}
