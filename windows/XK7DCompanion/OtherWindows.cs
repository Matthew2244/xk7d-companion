// The Windows counterparts of OtherWindows.swift (simulator, settings) and the Set Up Organ sheet.
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using XK7D.Core;

namespace XK7D.Companion;

/// <summary>Set Up Organ for This App: four changes with checkboxes. Nothing is sent until Send to Organ.</summary>
public sealed class SetupDialog : Window
{
    readonly List<CheckBox> boxes = new();
    public IEnumerable<bool> Chosen => boxes.Select(b => b.IsChecked == true);

    public SetupDialog(List<AppModel.SetupStep> steps)
    {
        Title = "Set up the organ to report changes to this app";
        Width = 600;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var panel = new StackPanel { Margin = new Thickness(16) };
        var intro = Ui.Reading("Tick what to change, then choose Send to Organ. Nothing is sent until you do. These are System settings: to keep them after the organ is turned off, record the System settings on the organ (manual page 142).",
            "About these changes");
        panel.Children.Add(intro);
        foreach (var s in steps)
        {
            var box = new CheckBox
            {
                Content = new TextBlock { Text = s.Title, TextWrapping = TextWrapping.Wrap, MaxWidth = 540 },
                IsChecked = s.OnByDefault,
                Margin = new Thickness(0, 6, 0, 6),
            }.Named(s.Title);
            boxes.Add(box);
            panel.Children.Add(box);
        }
        var send = new Button { Content = "_Send to Organ", IsDefault = true, Padding = new Thickness(12, 3, 12, 3), Margin = new Thickness(0, 0, 8, 0) }
            .Named("Send to Organ", "Sends the ticked changes to the organ.");
        send.Click += (_, _) => DialogResult = true;
        var cancel = new Button { Content = "Cancel", IsCancel = true, Padding = new Thickness(12, 3, 12, 3) }.Named("Cancel", "Closes this without sending anything.");
        var buttons = Ui.Row(send, cancel);
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        buttons.Margin = new Thickness(0, 12, 0, 0);
        panel.Children.Add(buttons);
        Content = panel;
        // The explanation first, so a screen reader reads it; Tab goes on to the choices.
        Loaded += (_, _) => intro.Focus();
    }
}

/// <summary>The simulator's own window: clearly labelled, with panel actions and a log of what it received.</summary>
public sealed class SimulatorWindow : Window
{
    readonly AppModel model;
    readonly ComboBox modeBox;
    readonly TextBox stateBox;
    readonly ListBox logList;
    readonly List<Button> actionButtons = new();
    bool updating;

    public SimulatorWindow(AppModel model)
    {
        this.model = model;
        Title = "XK-7D Simulator (not a real organ)";
        Width = 640; Height = 600;
        var root = new DockPanel { Margin = new Thickness(14) };
        var top = new StackPanel();
        top.Children.Add(Ui.Reading("This is a pretend XK-7D built into the app, for trying things out without the organ. Its buttons act as if someone touched the organ's panel. Changes made in the main window are stored here, just as the organ would store them.",
            "About the simulator"));
        modeBox = new ComboBox { MinWidth = 360 }.Named("Simulator sends changes as", "How the simulated organ reports panel changes. This is the organ's Individual Parameters setting.");
        foreach (var t in new[] { "Off", "NRPN (what the organ's MIDI templates set)", "SysEx (every setting, including Leslie cabinet and custom)" })
            modeBox.Items.Add(t);
        modeBox.SelectionChanged += (_, _) =>
        {
            if (updating || model.Simulator is not { } organ || modeBox.SelectedIndex < 0) return;
            organ.IndividualMode = (IndividualMode)modeBox.SelectedIndex;
        };
        top.Children.Add(Ui.Row(Ui.LabelFor("Send changes as:", modeBox), modeBox));
        foreach (var action in Enum.GetValues<SimulatorAction>())
        {
            var b = Ui.Button(action.Title(), action.Help(), (_, _) => { model.SimulatorAction(action); Refresh(); });
            b.HorizontalAlignment = HorizontalAlignment.Left;
            b.Margin = new Thickness(0, 3, 0, 3);
            actionButtons.Add(b);
            top.Children.Add(b);
        }
        stateBox = Ui.Reading("", "Simulator state");
        top.Children.Add(stateBox);
        logList = new ListBox { FontFamily = new System.Windows.Media.FontFamily("Consolas") }
            .Named("Simulator log", "What the simulator received from the app, newest first.");
        top.Children.Add(Ui.LabelFor("What the simulator received from the app, newest first", logList));
        DockPanel.SetDock(top, Dock.Top);
        root.Children.Add(top);
        root.Children.Add(logList);
        Content = root;
        model.SimulatorChanged += Refresh;
        model.ConnectionChanged += Refresh;
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { Hide(); e.Handled = true; } };
        Closing += (_, e) => { if (!Program.Quitting) { e.Cancel = true; Hide(); } };
        Refresh();
    }

    public void Refresh()
    {
        var active = model.Choice is PortChoice.Simulator;
        updating = true;
        if (model.Simulator is { } organ)
        {
            modeBox.SelectedIndex = (int)organ.IndividualMode;
            stateBox.Text = active
                ? $"The app is connected to this simulator. Device ID {organ.DeviceId}. It has received {organ.Received.Count} messages."
                : "The app is not connected to the simulator. Choose Built-in simulator from the Organ list in the main window to use it.";
            logList.ItemsSource = organ.Received.TakeLast(200).Reverse().Select(m => string.Join(" ", m.Select(b => b.ToString("X2")))).ToList();
        }
        else
        {
            stateBox.Text = "The simulator is not running. Choose Built-in simulator from the Organ list in the main window to start it.";
            logList.ItemsSource = null;
        }
        updating = false;
        modeBox.IsEnabled = active;
        foreach (var b in actionButtons) b.IsEnabled = active;
    }
}

/// <summary>Settings: how to speak, how long to wait, and MIDI addressing. Changes take effect at once.</summary>
public sealed class SettingsWindow : Window
{
    readonly AppModel model;
    readonly ComboBox methodBox, settleBox, deviceBox;
    readonly List<ComboBox> channelBoxes = new();
    bool updating;
    static readonly int[] SettleChoices = Enumerable.Range(0, 39).Select(i => 100 + i * 50).ToArray();

    public SettingsWindow(AppModel model)
    {
        this.model = model;
        Title = "XK-7D Companion Settings";
        Width = 620;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(Ui.Text("Announcements", bold: true));
        methodBox = new ComboBox { MinWidth = 420 }.Named("Speak with", "How announcements are spoken. Automatic uses the screen reader when one is running: NVDA, JAWS and others directly, Narrator through UI Automation. Otherwise the Windows voice.");
        foreach (var m in Enum.GetValues<Announcer.Method>()) methodBox.Items.Add(Announcer.Title(m));
        methodBox.SelectionChanged += (_, _) => Changed();
        panel.Children.Add(Ui.Row(Ui.LabelFor("Speak with:", methodBox), methodBox));
        settleBox = new ComboBox { MinWidth = 100 }.Named("Wait before speaking, milliseconds", "How long a knob must stop moving before its value is spoken. Shorter is quicker, longer is quieter.");
        foreach (var ms in SettleChoices) settleBox.Items.Add(ms.ToString());
        settleBox.SelectionChanged += (_, _) => Changed();
        panel.Children.Add(Ui.Row(Ui.LabelFor("Wait before speaking, milliseconds:", settleBox), settleBox));
        panel.Children.Add(Ui.Text("MIDI", bold: true));
        deviceBox = new ComboBox { MinWidth = 100 }.Named("Organ device ID", "The organ's Device ID, MENU, SYSTEM, MIDI, SYS EX page. The app learns it when the organ answers.");
        for (var i = 0; i < 128; i++) deviceBox.Items.Add(i.ToString());
        deviceBox.SelectionChanged += (_, _) => Changed();
        panel.Children.Add(Ui.Row(Ui.LabelFor("Organ device ID:", deviceBox), deviceBox));
        foreach (var part in new[] { "Upper", "Lower", "Pedal" })
        {
            var box = new ComboBox { MinWidth = 140 }.Named($"{part} channel",
                $"The organ's {part} MIDI channel. The Basic template uses Upper 1, Lower 2, Pedal 3. NRPN and drawbars travel on the Upper channel.");
            for (var c = 1; c <= 16; c++) box.Items.Add($"Channel {c}");
            box.SelectionChanged += (_, _) => Changed();
            channelBoxes.Add(box);
            panel.Children.Add(Ui.Row(Ui.LabelFor($"{part} channel:", box), box));
        }
        panel.Children.Add(Ui.Text("Changes here take effect at once.", wrap: true));
        var close = new Button { Content = "Close", IsCancel = true, Padding = new Thickness(12, 3, 12, 3), HorizontalAlignment = HorizontalAlignment.Right }
            .Named("Close", "Closes Settings. Changes are already saved.");
        close.Click += (_, _) => Hide();
        panel.Children.Add(close);
        Content = panel;
        Closing += (_, e) => { if (!Program.Quitting) { e.Cancel = true; Hide(); } };
        model.ConnectionChanged += DeviceIdMayHaveChanged;
        Reload();
    }

    /// <summary>Read the current values each time it opens, so a Device ID learned from the organ
    /// since then is never shown stale and written back over the learned one.</summary>
    public void Reload()
    {
        updating = true;
        methodBox.SelectedIndex = (int)model.Announcer.SpeakWith;
        var settle = (int)Math.Round(model.Session.Coalescer.Settle * 1000);
        settleBox.SelectedIndex = Array.IndexOf(SettleChoices, SettleChoices.MinBy(c => Math.Abs(c - settle)));
        var a = model.Session.Addressing;
        deviceBox.SelectedIndex = a.DeviceId;
        channelBoxes[0].SelectedIndex = a.UpperChannel;
        channelBoxes[1].SelectedIndex = a.LowerChannel;
        channelBoxes[2].SelectedIndex = a.PedalChannel;
        updating = false;
    }

    void DeviceIdMayHaveChanged()
    {
        if (deviceBox.IsKeyboardFocusWithin && deviceBox.IsDropDownOpen) return;
        updating = true;
        deviceBox.SelectedIndex = model.Session.Addressing.DeviceId;
        updating = false;
    }

    void Changed()
    {
        if (updating) return;
        model.Announcer.SpeakWith = (Announcer.Method)Math.Max(methodBox.SelectedIndex, 0);
        var settle = SettleChoices[Math.Max(settleBox.SelectedIndex, 0)];
        model.Session.Coalescer.Settle = settle / 1000.0;
        model.Settings.Set("settleMilliseconds", settle);
        var dev = Math.Clamp(deviceBox.SelectedIndex, 0, 127);
        model.Session.Addressing.DeviceId = (byte)dev;
        model.Settings.Set("deviceID", dev);
        var chans = channelBoxes.Select(b => Math.Max(b.SelectedIndex, 0)).ToArray();
        model.Session.Addressing.UpperChannel = chans[0];
        model.Session.Addressing.LowerChannel = chans[1];
        model.Session.Addressing.PedalChannel = chans[2];
        model.Settings.Set("upperChannel", chans[0]);
        model.Settings.Set("lowerChannel", chans[1]);
        model.Settings.Set("pedalChannel", chans[2]);
        if (model.Simulator is { } sim)
        {
            sim.UpperChannel = chans[0]; sim.LowerChannel = chans[1]; sim.PedalChannel = chans[2];
        }
    }
}
