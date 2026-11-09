// The Windows counterpart of Sources/XK7DCompanion/AppModel.swift: the same choices, sentences and
// rules, with WinMM in place of CoreMIDI and the simulator always in-process.
using System.Windows.Threading;
using XK7D.Core;

namespace XK7D.Companion;

/// <summary>Owns the session, the MIDI connection, the simulator and the announcer; the windows observe it.</summary>
public sealed class AppModel
{
    public ParameterDatabase Database { get; } = ParameterDatabase.Shared;
    public OrganSession Session { get; }
    public AppSettings Settings { get; }
    public Announcer Announcer { get; }
    readonly Dispatcher dispatcher;
    readonly WinMidiConnection connection;
    public PortChoice Choice { get; private set; } = PortChoice.NotConnected;
    public string StatusText { get; private set; } = "Not connected.";
    public List<string> History { get; } = new();
    public SimulatedOrgan? Simulator { get; private set; }
    LoopbackLink? loopback;
    readonly DispatcherTimer tickTimer, portTimer;
    DumpSnapshot? lastSnapshot;
    List<string> lastDeviceNames = new();

    public event Action? ConnectionChanged;
    /// <summary>A value changed: the event, or null when many may have.</summary>
    public event Action<OrganEvent?>? ValuesChanged;
    public event Action? HistoryChanged;
    public event Action? SimulatorChanged;

    public AppModel(AppSettings settings, Dispatcher dispatcher)
    {
        Settings = settings;
        this.dispatcher = dispatcher;
        Announcer = new Announcer(settings);
        var settle = settings.GetInt("settleMilliseconds") ?? 350;
        Session = new OrganSession(coalescer: new AnnouncementCoalescer(settle / 1000.0, 2.0));
        var a = new OrganAddressing();
        if (settings.GetInt("deviceID") is { } id) a.DeviceId = (byte)(id & 0x7F);
        if (settings.GetInt("upperChannel") is { } u) a.UpperChannel = u;
        if (settings.GetInt("lowerChannel") is { } l) a.LowerChannel = l;
        if (settings.GetInt("pedalChannel") is { } p) a.PedalChannel = p;
        Session.Addressing = a;

        Announcer.OnAnnounced = text =>
        {
            History.Insert(0, text);
            if (History.Count > 200) History.RemoveAt(History.Count - 1);
            HistoryChanged?.Invoke();
        };
        Session.OnAnnouncement = text => Announcer.Announce(text);
        Session.OnEvent = (e, _) => ValuesChanged?.Invoke(e);
        Session.OnChannelMismatch = channel =>
        {
            var mine = Session.Addressing.UpperChannel + 1;
            StatusText = $"The organ is sending its controls on channel {channel + 1}, but this app listens for them on channel {mine}. Set Upper channel to {channel + 1} in Settings (Control comma).";
            Announcer.Announce($"Channels don't match. The organ sends on channel {channel + 1}, the app listens on {mine}. Change Upper channel in Settings.", force: true);
            ConnectionChanged?.Invoke();
        };
        Session.OnDeviceIdLearned = learned =>
        {
            Settings.Set("deviceID", learned);
            ConnectionChanged?.Invoke();
        };

        connection = new WinMidiConnection(action => dispatcher.BeginInvoke(action));
        connection.OnReceive = bytes => Session.Receive(bytes);

        tickTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = TimeSpan.FromMilliseconds(50) };
        tickTimer.Tick += (_, _) => Session.Tick();
        tickTimer.Start();
        // WinMM has no notice when a device comes or goes, so look every two seconds.
        portTimer = new DispatcherTimer(DispatcherPriority.Background, dispatcher) { Interval = TimeSpan.FromSeconds(2) };
        portTimer.Tick += (_, _) => CheckPorts();
        lastDeviceNames = DeviceNames();
        portTimer.Start();
    }

    // Ports

    /// <summary>Real MIDI input ports by name, each once.</summary>
    public static List<string> DeviceNames() => WinMidiConnection.InputNames().Where(n => n.Length > 0).Distinct().ToList();

    public List<PortChoice> Choices() =>
        new List<PortChoice> { PortChoice.NotConnected }
            .Concat(DeviceNames().Select(n => (PortChoice)new PortChoice.Device(n)))
            .Append(PortChoice.BuiltInSimulator).ToList();

    /// <summary>At launch: the port used last time if present, else anything that looks like the
    /// organ, else the simulator if that was used last. A plugged-in organ beats a remembered simulator.</summary>
    public void ConnectAtLaunch()
    {
        var names = DeviceNames();
        var pick = PortPolicy.LaunchChoice(Settings.GetString("port"), names);
        if (pick is not PortChoice.None) { Choose(pick); return; }
        StatusText = names.Count == 0
            ? "No organ found. Connect the XK-7D by USB, or choose the built-in simulator from the Organ list."
            : "Choose your organ from the Organ list.";
        ConnectionChanged?.Invoke();
    }

    /// <summary>True while the chosen organ's port has gone (unplugged or turned off).</summary>
    public bool OrganMissing { get; private set; }

    void CheckPorts()
    {
        var names = DeviceNames();
        if (names.SequenceEqual(lastDeviceNames)) return;
        lastDeviceNames = names;
        PortsChanged(names);
    }

    void PortsChanged(List<string> names)
    {
        switch (PortPolicy.AfterPortsChanged(Choice, OrganMissing, Settings.GetString("port"), names))
        {
            case PortPolicy.Change.Lost lost:
                OrganMissing = true;
                connection.Disconnect();
                StatusText = $"{lost.Name} was disconnected. The app will connect again when it comes back.";
                Announcer.Announce("Organ disconnected", force: true);
                break;
            case PortPolicy.Change.Back back:
                Choose(new PortChoice.Device(back.Name));
                Announcer.Announce("Organ connected again", force: true);
                return;
            case PortPolicy.Change.Found found:
                Choose(new PortChoice.Device(found.Name));
                Announcer.Announce($"Organ connected: {found.Name}", force: true);
                return;
        }
        ConnectionChanged?.Invoke();
    }

    public void Choose(PortChoice c, bool remember = true)
    {
        connection.Disconnect();
        OrganMissing = false;
        Session.HoldUntilAnswered = false;
        Session.ResetConnection();
        loopback = null;
        Session.Output = null;
        Choice = c;
        switch (c)
        {
            case PortChoice.None:
                if (remember) Settings.Set("port", "none");
                StatusText = "Not connected.";
                break;
            case PortChoice.Simulator:
                if (remember) Settings.Set("port", "simulator");
                StartSimulator();
                break;
            case PortChoice.Device d:
                if (remember) Settings.Set("port", d.Name);
                try
                {
                    connection.Connect(d.Name);
                    Session.Output = connection;
                    StatusText = !connection.CanSend
                        ? $"Listening to {d.Name}. It has no MIDI output Windows could open, so changes can't be sent."
                        : $"Connected to {d.Name}. Checking that the organ answers.";
                    Session.ForgetAllValues();
                    Session.RequestIdentity();
                    ScheduleAnswerCheck(d.Name);
                }
                catch (Exception e)
                {
                    StatusText = $"Could not connect to {d.Name}. {e.Message}";
                    Announcer.Announce(StatusText, force: true);
                }
                break;
        }
        ConnectionChanged?.Invoke();
        ValuesChanged?.Invoke(null);
    }

    /// <summary>Windows has no virtual MIDI ports of its own, so the simulator is always in-process:
    /// the same session code talks to it, with the same messages, through a direct link.</summary>
    void StartSimulator()
    {
        var organ = Simulator ?? new SimulatedOrgan();
        organ.DeviceId = Session.Addressing.DeviceId;
        organ.UpperChannel = Session.Addressing.UpperChannel;
        organ.LowerChannel = Session.Addressing.LowerChannel;
        organ.PedalChannel = Session.Addressing.PedalChannel;
        organ.OnChange = _ => SimulatorChanged?.Invoke();
        Simulator = organ;
        Session.ForgetAllValues();
        loopback = new LoopbackLink(Session, organ, synchronous: false, post: a => dispatcher.BeginInvoke(a));
        StatusText = "Connected to the built-in simulator. This is not a real organ.";
    }

    void ScheduleAnswerCheck(string name)
    {
        var t = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = TimeSpan.FromSeconds(1.5) };
        t.Tick += (_, _) =>
        {
            t.Stop();
            if (Choice is not PortChoice.Device d || d.Name != name) return;
            StatusText = Session.OrganAnswered
                ? $"Connected to {name}. The organ answered (device ID {Session.Addressing.DeviceId})."
                : $"Connected to {name}, but the organ has not answered an identity request yet. Changes on the organ are still announced if it sends them.";
            ConnectionChanged?.Invoke();
        };
        t.Start();
    }

    /// <summary>What to say when something needs the organ and there isn't one.</summary>
    public string NotConnectedMessage => OrganMissing
        ? "The organ is disconnected, so nothing was sent. Check the USB cable and that the organ is on."
        : "Not connected. Choose the organ or the simulator first.";

    public bool IsConnected => Choice is not PortChoice.None && Session.Output is not null && !OrganMissing;

    // Values

    public void Send(Setting setting, int raw)
    {
        if (!IsConnected) { Announcer.Announce(NotConnectedMessage, force: true); return; }
        Session.Set(setting, raw);
        ValuesChanged?.Invoke(new OrganEvent.Value(setting, setting.Parameter.Clamp(raw)));
    }

    public void Send(Setting setting, string text)
    {
        if (!IsConnected) { Announcer.Announce(NotConnectedMessage, force: true); return; }
        Session.Set(setting, text);
        ValuesChanged?.Invoke(new OrganEvent.Text(setting, Session.TextOf(setting) ?? text));
    }

    public void RepeatLast() => Announcer.Announce(History.FirstOrDefault() ?? "Nothing has been announced yet.", force: true);

    // Read from organ

    /// <summary>Identity request, then a Temporary dump request. The manual does not publish the dump's
    /// layout, so values cannot be read out of it; the dump is kept as a snapshot file instead.</summary>
    public void ReadFromOrgan(Action<string> completion)
    {
        if (!IsConnected) { completion(NotConnectedMessage); return; }
        Session.RequestIdentity();
        Session.RequestDump(DumpType.Temporary);
        var lastCount = -1;
        var attempt = 0;
        var expected = XK7SysEx.TemporaryPackets + XK7SysEx.AdjustPackets;
        var t = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = TimeSpan.FromMilliseconds(250) };
        void Check()
        {
            var count = Session.CurrentDump?.Count ?? 0;
            if (count >= expected || (attempt > 6 && count == lastCount) || attempt > 40)
            {
                t.Stop();
                var snap = Session.FinishDump();
                if ((snap?.Count ?? 0) > 0) lastSnapshot = snap;
                completion(ReadSummary(snap, expected));
                return;
            }
            lastCount = count;
            attempt++;
        }
        t.Tick += (_, _) => Check();
        Check();
        if (attempt > 0) t.Start();
    }

    string ReadSummary(DumpSnapshot? snap, int expected)
    {
        var answered = Session.OrganAnswered ? "The organ answered. " : "No identity reply. ";
        if (snap is null || snap.Count == 0)
            return answered + "No memory dump arrived. Check the MIDI or USB connection. Settings still fill in as you change them on the organ.";
        var checks = snap.AllChecksumsOK ? "all checks good" : "some checks failed";
        return answered + $"Received {snap.Count} of {expected} dump packets, {checks}. The manual doesn't say what's inside a dump, so the app can't show those values yet. Save Organ Snapshot keeps it as a file. Settings fill in as you change them on the organ.";
    }

    public DumpSnapshot? Snapshot => lastSnapshot;

    // Organ setup

    public sealed record SetupStep(string Title, Setting Setting, int Raw, bool OnByDefault = true);

    public List<SetupStep> SetupSteps()
    {
        Setting S(byte b3, byte b4) => Database.SettingAt(new Address(0, 0, 0, b3, b4))!;
        return new()
        {
            new("Send every setting change as SysEx (Individual Parameters: SysEx). Needed to hear Leslie cabinet, custom and other SysEx-only settings.", S(0x0C, 0x03), 2),
            new("Send and receive program changes (Program Change: On), so patch changes are announced.", S(0x0C, 0x04), 1),
            new("Send and receive drawbar moves (Drawbar Registration: On), so drawbars are announced.", S(0x0C, 0x05), 1),
            new($"Change the organ's Upper send channel to {Session.Addressing.UpperChannel + 1}, to match this app (Tx Upper). Only needed if the app says the channels don't match. It also moves the organ's Upper notes, so other MIDI gear listening to the organ may need changing too. Usually it's easier to change Upper channel in this app's Settings instead.",
                S(0x0D, 0x00), Session.Addressing.UpperChannel, OnByDefault: false),
        };
    }

    // Simulator panel actions

    public void SimulatorAction(SimulatorAction action)
    {
        if (Simulator is not { } organ || Choice is not PortChoice.Simulator) return;
        action.Perform(organ, Database, Settings, dispatcher);
    }

    public void Shutdown()
    {
        tickTimer.Stop();
        portTimer.Stop();
        connection.Disconnect();
    }
}

/// <summary>Things the simulator window can do, as if someone touched the organ's panel.</summary>
public enum SimulatorAction { LeslieHornSweep, ToggleLeslieFast, TogglePercussion, MoveDrawbar, NextPatch, VibratoMode, RandomSetting }

public static class SimulatorActions
{
    static readonly Random random = new();

    public static string Title(this SimulatorAction a) => a switch
    {
        SimulatorAction.LeslieHornSweep => "Turn the Leslie horn fast speed knob",
        SimulatorAction.ToggleLeslieFast => "Press Leslie Fast",
        SimulatorAction.TogglePercussion => "Press Percussion On",
        SimulatorAction.MoveDrawbar => "Move the Upper 8 foot drawbar",
        SimulatorAction.NextPatch => "Recall the next User patch on Upper",
        SimulatorAction.VibratoMode => "Turn the vibrato and chorus knob",
        _ => "Change a random setting",
    };

    public static string Help(this SimulatorAction a) => a switch
    {
        SimulatorAction.LeslieHornSweep => "Sends about thirty quick changes, like turning a knob. Only the final value should be spoken. Needs Send changes as SysEx, because this setting has no NRPN.",
        SimulatorAction.ToggleLeslieFast => "Turns the Leslie Fast switch on or off.",
        SimulatorAction.TogglePercussion => "Turns percussion on or off.",
        SimulatorAction.MoveDrawbar => "Moves the Upper 8 foot drawbar to a new position, sent as a drawbar control change.",
        SimulatorAction.NextPatch => "Sends a bank select and program change for the next User patch on the Upper part.",
        SimulatorAction.VibratoMode => "Steps the vibrato and chorus knob to its next position.",
        _ => "Picks any setting from the manual's tables and changes it.",
    };

    public static void Perform(this SimulatorAction a, SimulatedOrgan organ, ParameterDatabase db, AppSettings settings, Dispatcher dispatcher)
    {
        Setting S(Address addr) => db.SettingAt(addr)!;
        void Toggle(Address addr) { var st = S(addr); organ.PanelChange(st, (organ.Value(st) ?? 0) == 0 ? 1 : 0); }
        switch (a)
        {
            case SimulatorAction.LeslieHornSweep:
            {
                var st = S(new Address(0x42, 0, 0, 0, 0));
                var current = organ.Value(st) ?? 141;
                var target = current > 200 ? random.Next(60, 161) : random.Next(220, 301);
                var values = organ.KnobSweep(st, target, 30);
                for (var i = 0; i < values.Count; i++)
                {
                    var v = values[i];
                    var t = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = TimeSpan.FromMilliseconds(1 + i * 25) };
                    t.Tick += (_, _) => { t.Stop(); organ.PanelChange(st, v); };
                    t.Start();
                }
                break;
            }
            case SimulatorAction.ToggleLeslieFast: Toggle(new Address(0, 0, 0, 0x12, 0x0A)); break;
            case SimulatorAction.TogglePercussion: Toggle(new Address(0, 0, 0, 0x11, 0x00)); break;
            case SimulatorAction.MoveDrawbar:
            {
                var st = S(new Address(0, 0, 1, 1, 2));
                var level = random.Next(0, 9);
                if (level == organ.Value(st)) level = (level + 3) % 9;
                organ.PanelChange(st, level);
                break;
            }
            case SimulatorAction.NextPatch:
            {
                var n = ((settings.GetInt("simulatorPatch") ?? 0) + 1) % 100;
                settings.Set("simulatorPatch", n);
                organ.SelectPatch("Upper", 0, n);
                break;
            }
            case SimulatorAction.VibratoMode:
            {
                var st = S(new Address(0, 0, 0, 0x12, 0x01));
                organ.PanelChange(st, ((organ.Value(st) ?? 0) + 1) % 6);
                break;
            }
            default:
            {
                // Leave the simulator's own MIDI settings alone, or it could stop talking to the app.
                var plain = db.Parameters.Where(p => !p.HasIndices && !p.IsText
                    && !new[] { "MIDI Common", "MIDI Channel", "USB MIDI" }.Contains(p.ManualCategory)).ToList();
                var p = plain[random.Next(plain.Count)];
                var raws = p.AllRawValues();
                organ.PanelChange(new Setting(p), raws[random.Next(raws.Count)]);
                break;
            }
        }
    }
}
