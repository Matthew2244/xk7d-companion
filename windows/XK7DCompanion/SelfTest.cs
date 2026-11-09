using System.Windows;
using System.Windows.Threading;
using XK7D.Core;

namespace XK7D.Companion;

/// <summary>The silent self-test (--self-test LOG): the Windows counterpart of the Mac's
/// XK7D_SELFTEST. No window is shown and nothing is spoken; what would have been said goes to the
/// log. Unlike the Mac's, it also checks its own results and exits 1 if a step didn't do what it
/// should, so CI can rely on the exit code.</summary>
static class SelfTest
{
    public static int Run(Application app, AppModel model, string logPath)
    {
        var log = new List<string>();
        void Write()
        {
            try { File.WriteAllText(logPath, string.Join("\n", log) + "\n"); } catch (Exception) { }
        }
        model.Announcer.SilentSink = text => { log.Add("ANNOUNCE " + text); Write(); };

        log.Add($"VERSION {Updates.Version}");
        var readers = Prism.Load() ? string.Join(", ", Prism.RunningReaders()) : "";
        log.Add(Prism.Load() ? $"SPEECH Prism loaded; screen readers running: {(readers.Length > 0 ? readers : "none")}"
                             : $"SPEECH Prism did not load: {Prism.LoadProblem}");
        log.Add(Updates.WinSparklePresent ? $"UPDATER WinSparkle present; installed copy: {(Updates.Installed ? "yes" : "no")}; feed {Updates.AppcastUrl}"
                                          : "UPDATER WinSparkle missing");
        if (Updates.Installed)
            log.Add(Updates.Start(() => { }) ? "UPDATER WinSparkle started (no automatic checks)" : "UPDATER WinSparkle didn't start");
        log.Add($"MIDI inputs {WinMidiConnection.InputNames().Count}, outputs {WinMidiConnection.OutputNames().Count}");
        // Build the main window without showing it, so a fault in the window's construction fails here.
        try { _ = new MainWindow(model); _ = new SimulatorWindow(model); _ = new SettingsWindow(model); log.Add("WINDOWS built"); }
        catch (Exception e) { log.Add($"WINDOWS failed: {e}"); }

        model.Choose(PortChoice.BuiltInSimulator, remember: false);
        log.Add("STATUS " + model.StatusText);
        Write();
        var db = model.Database;
        var organType = db.SettingAt(new Address(0, 0, 0, 0x10, 0x04))!;
        var steps = new (double At, Action Do)[]
        {
            (0.5, () => { model.Send(organType, 5); log.Add("SENT organ type Pipe"); }),
            (1.0, () => log.Add($"SIMULATOR organ type raw {model.Simulator?.Value(organType)?.ToString() ?? "nil"}; simulator received {model.Simulator?.Received.Count ?? -1} messages")),
            (1.2, () => { model.Simulator!.IndividualMode = IndividualMode.Sysex; SimulatorAction.LeslieHornSweep.Perform(model.Simulator, db, model.Settings, app.Dispatcher); }),
            (2.5, () => SimulatorAction.TogglePercussion.Perform(model.Simulator!, db, model.Settings, app.Dispatcher)),
            (3.2, () => SimulatorAction.NextPatch.Perform(model.Simulator!, db, model.Settings, app.Dispatcher)),
            (3.8, () => SimulatorAction.MoveDrawbar.Perform(model.Simulator!, db, model.Settings, app.Dispatcher)),
            (4.5, () => model.ReadFromOrgan(summary => { log.Add("READ " + summary); Write(); })),
            (8.0, () => { log.Add($"SELFTEST DONE {db.Parameters.Count} settings"); Finish(); }),
        };
        var exit = 1;
        void Finish()
        {
            var expected = new[]
            {
                ("SPEECH Prism loaded", "Prism (prism.dll) loads"),
                ("UPDATER WinSparkle present", "WinSparkle.dll is beside the app"),
                ("WINDOWS built", "the windows build"),
                ("SIMULATOR organ type raw 5", "a change made in the app reaches the simulator"),
                ("ANNOUNCE Leslie horn fast speed: ", "a turning knob is spoken"),
                ("ANNOUNCE Percussion on: ", "a switch is spoken"),
                ("ANNOUNCE Upper: patch U", "a patch change is spoken"),
                ("ANNOUNCE Upper 8 foot: ", "a drawbar is spoken"),
                ("READ The organ answered. Received 17 of 17 dump packets, all checks good", "Read from Organ"),
            };
            if (Updates.Installed) expected = expected.Append(("UPDATER WinSparkle started", "WinSparkle starts in an installed copy and takes the update key")).ToArray();
            var missing = expected.Where(e => !log.Any(l => l.StartsWith(e.Item1, StringComparison.Ordinal))).Select(e => e.Item2).ToList();
            // A knob sweep must be spoken once, not thirty times.
            var horn = log.Count(l => l.StartsWith("ANNOUNCE Leslie horn fast speed: ", StringComparison.Ordinal));
            if (horn != 1) missing.Add($"the knob sweep spoken once (it was spoken {horn} times)");
            log.Add(missing.Count == 0 ? "SELFTEST OK" : "SELFTEST FAILED: " + string.Join("; ", missing));
            Write();
            exit = missing.Count == 0 ? 0 : 1;
            Updates.Stop();
            model.Shutdown();
            app.Shutdown(exit);
        }
        var start = DateTime.Now;
        foreach (var (at, act) in steps)
        {
            var t = new DispatcherTimer(DispatcherPriority.Normal, app.Dispatcher) { Interval = TimeSpan.FromSeconds(at) };
            t.Tick += (_, _) => { t.Stop(); act(); Write(); };
            t.Start();
        }
        // Never hang: whatever happens, stop after 30 seconds.
        var guard = new DispatcherTimer(DispatcherPriority.Normal, app.Dispatcher) { Interval = TimeSpan.FromSeconds(30) };
        guard.Tick += (_, _) => { log.Add("SELFTEST FAILED: timed out"); Write(); app.Shutdown(1); };
        guard.Start();
        app.Run();
        return exit;
    }
}
