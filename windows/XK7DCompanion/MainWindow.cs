// The Windows counterpart of MainWindowController.swift and the menus in AppDelegate.swift.
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using XK7D.Core;

namespace XK7D.Companion;

public sealed class MainWindow : Window
{
    readonly AppModel model;
    readonly ComboBox portBox;
    readonly TextBox statusBox;
    readonly CheckBox speakBox;
    readonly TextBox searchBox;
    readonly TextBlock searchCount;
    readonly TreeView tree;
    readonly DetailPanel detail;
    readonly ListBox history;
    readonly MenuItem muteItem, snapshotItem, disconnectItem;
    readonly List<(string Title, List<Parameter> Parameters)> categories = new();
    readonly Dictionary<string, List<TreeViewItem>> rowsById = new();
    readonly HashSet<TreeViewItem> staleRows = new();
    bool updatingPorts;

    public Action? ShowSimulator { get; set; }
    public Action? ShowSettings { get; set; }
    public Action? CheckForUpdates { get; set; }
    public bool Quitting { get; set; }

    public static readonly RoutedUICommand FindCmd = Cmd("Find Setting", Key.F, ModifierKeys.Control);
    public static readonly RoutedUICommand ListCmd = Cmd("Go to Settings List", Key.L, ModifierKeys.Control);
    public static readonly RoutedUICommand ReadCmd = Cmd("Read from Organ", Key.R, ModifierKeys.Control);
    public static readonly RoutedUICommand SetupCmd = Cmd("Set Up Organ for This App...", Key.U, ModifierKeys.Control | ModifierKeys.Shift);
    public static readonly RoutedUICommand MuteCmd = Cmd("Mute Announcements", Key.M, ModifierKeys.Control | ModifierKeys.Shift);
    public static readonly RoutedUICommand RepeatCmd = Cmd("Repeat Last Announcement", Key.L, ModifierKeys.Control | ModifierKeys.Shift);
    public static readonly RoutedUICommand MainCmd = Cmd("Main Window", Key.D1, ModifierKeys.Control);
    public static readonly RoutedUICommand SimulatorCmd = Cmd("Simulator", Key.D2, ModifierKeys.Control);
    public static readonly RoutedUICommand MinimizeCmd = Cmd("Minimize Window", Key.W, ModifierKeys.Control);
    public static readonly RoutedUICommand SaveCmd = Cmd("Save Organ Snapshot...", Key.S, ModifierKeys.Control);
    public static readonly RoutedUICommand SettingsCmd = Cmd("Settings...", Key.OemComma, ModifierKeys.Control);
    public static readonly RoutedUICommand HelpCmd = Cmd("XK-7D Companion Help", Key.F1, ModifierKeys.None);
    public static readonly RoutedUICommand UpdatesCmd = Cmd("Check for Updates...", Key.U, ModifierKeys.Control);

    static RoutedUICommand Cmd(string text, Key key, ModifierKeys mods) =>
        new(text, text.Replace(" ", "").Replace(".", ""), typeof(MainWindow), new InputGestureCollection { new KeyGesture(key, mods) });

    public MainWindow(AppModel model)
    {
        this.model = model;
        Title = "XK-7D Companion";
        Width = 1060; Height = 720; MinWidth = 820; MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        // Menus: every command reachable from the keyboard, each key with one meaning.
        var menu = new Menu();
        var file = new MenuItem { Header = "_File" };
        snapshotItem = Item(SaveCmd);
        file.Items.Add(snapshotItem);
        file.Items.Add(Item(SettingsCmd, "Ctrl+Comma"));
        file.Items.Add(new Separator());
        file.Items.Add(Item(MinimizeCmd));
        var exit = new MenuItem { Header = "E_xit", InputGestureText = "Alt+F4" };
        exit.Click += (_, _) => Close();
        file.Items.Add(exit);
        var edit = new MenuItem { Header = "_Edit" };
        edit.Items.Add(new MenuItem { Command = ApplicationCommands.Cut });
        edit.Items.Add(new MenuItem { Command = ApplicationCommands.Copy });
        edit.Items.Add(new MenuItem { Command = ApplicationCommands.Paste });
        edit.Items.Add(new MenuItem { Command = ApplicationCommands.SelectAll });
        edit.Items.Add(new Separator());
        edit.Items.Add(Item(FindCmd));
        edit.Items.Add(Item(ListCmd));
        var organ = new MenuItem { Header = "_Organ" };
        organ.Items.Add(Item(ReadCmd));
        organ.Items.Add(Item(SetupCmd));
        organ.Items.Add(new Separator());
        var useSim = new MenuItem { Header = "Use the Built-in _Simulator" };
        useSim.Click += (_, _) => { model.Choose(PortChoice.BuiltInSimulator); ShowSimulator?.Invoke(); };
        organ.Items.Add(useSim);
        disconnectItem = new MenuItem { Header = "_Disconnect" };
        disconnectItem.Click += (_, _) => model.Choose(PortChoice.NotConnected);
        organ.Items.Add(disconnectItem);
        var speech = new MenuItem { Header = "_Announcements" };
        muteItem = Item(MuteCmd);
        speech.Items.Add(muteItem);
        speech.Items.Add(Item(RepeatCmd));
        var window = new MenuItem { Header = "_Window" };
        window.Items.Add(Item(MainCmd));
        window.Items.Add(Item(SimulatorCmd));
        var help = new MenuItem { Header = "_Help" };
        help.Items.Add(Item(HelpCmd));
        help.Items.Add(Item(UpdatesCmd));
        var about = new MenuItem { Header = "_About XK-7D Companion" };
        about.Click += (_, _) => ShowAbout();
        help.Items.Add(about);
        foreach (var m in new[] { file, edit, organ, speech, window, help }) menu.Items.Add(m);
        organ.SubmenuOpened += (_, _) => disconnectItem.IsEnabled = model.Choice is not PortChoice.None;
        file.SubmenuOpened += (_, _) => snapshotItem.IsEnabled = model.Snapshot is not null;
        speech.SubmenuOpened += (_, _) => muteItem.Header = model.Announcer.Muted ? "Unmute Announcements" : "Mute Announcements";

        Bind(FindCmd, FocusSearch);
        Bind(ListCmd, FocusList);
        Bind(ReadCmd, ReadFromOrgan);
        Bind(SetupCmd, SetUpOrgan);
        Bind(MuteCmd, ToggleMute);
        Bind(RepeatCmd, model.RepeatLast);
        Bind(MainCmd, ShowMain);
        Bind(SimulatorCmd, () => ShowSimulator?.Invoke());
        Bind(MinimizeCmd, MinimizeKeepListening);
        Bind(SaveCmd, SaveSnapshot);
        Bind(SettingsCmd, () => ShowSettings?.Invoke());
        Bind(HelpCmd, ShowHelp);
        Bind(UpdatesCmd, () => CheckForUpdates?.Invoke());

        // Top: organ choice and the two organ actions.
        portBox = new ComboBox { MinWidth = 280 }.Named("Organ", "Choose the organ's USB MIDI port (it shows as XK-7 or similar), or the built-in simulator.");
        portBox.SelectionChanged += (_, _) => PortChosen();
        var readButton = Ui.Button("Read from Organ", "Asks the organ to identify itself and send a memory dump. Control R.", (_, _) => ReadFromOrgan());
        var setupButton = Ui.Button("Set Up Organ for This App...", "Changes the organ's MIDI settings so it reports every change to this app. You choose which, and nothing is sent until you confirm.", (_, _) => SetUpOrgan());
        speakBox = new CheckBox { Content = "Speak organ changes", VerticalAlignment = VerticalAlignment.Center }
            .Named("Speak organ changes", "When on, changes made on the organ are spoken. Control Shift M turns this on and off.");
        speakBox.Click += (_, _) => model.Announcer.Muted = speakBox.IsChecked != true;
        var top = Ui.Row(Ui.LabelFor("Organ:", portBox), portBox, new TextBlock { Width = 10 }, readButton, setupButton, speakBox);
        statusBox = Ui.Reading("", "Connection status");

        // Left: search and the list.
        searchBox = new TextBox().Named("Search settings", "Type any part of a setting's name, for example leslie horn or percussion. Press Enter or Down Arrow to go to the results. Control F comes here.");
        searchBox.TextChanged += (_, _) => SearchChanged();
        searchBox.PreviewKeyDown += SearchKey;
        searchCount = Ui.Text("");
        AutomationProperties.SetName(searchCount, "Search results");
        AutomationProperties.SetLiveSetting(searchCount, AutomationLiveSetting.Polite);
        tree = new TreeView().Named("Settings", "Every setting the manual lists, by category. Each row shows its value. Press Tab to edit the selected setting.");
        VirtualizingPanel.SetIsVirtualizing(tree, false);
        tree.SelectedItemChanged += (_, _) => detail!.Show((tree.SelectedItem as TreeViewItem)?.Tag as Parameter);
        var left = new DockPanel { Margin = new Thickness(0, 0, 8, 0) };
        var searchRow = new StackPanel();
        searchRow.Children.Add(Ui.LabelFor("_Search settings:", searchBox));
        searchRow.Children.Add(searchBox);
        searchRow.Children.Add(searchCount);
        DockPanel.SetDock(searchRow, Dock.Top);
        left.Children.Add(searchRow);
        left.Children.Add(tree);

        // Right: the selected setting.
        detail = new DetailPanel(model);
        var detailScroll = new ScrollViewer { Content = detail, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false };

        var split = new Grid();
        split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 340 });
        split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.2, GridUnitType.Star), MinWidth = 380 });
        Grid.SetColumn(left, 0);
        Grid.SetColumn(detailScroll, 1);
        split.Children.Add(left);
        split.Children.Add(detailScroll);

        // Bottom: history.
        history = new ListBox { Height = 120 }.Named("Recent announcements", "Everything the app has spoken, newest first, so you can read back anything you missed.");
        var historyPanel = new StackPanel();
        historyPanel.Children.Add(Ui.LabelFor("_Recent announcements, newest first", history));
        historyPanel.Children.Add(history);

        var root = new DockPanel { Margin = new Thickness(14, 0, 14, 12) };
        DockPanel.SetDock(top, Dock.Top);
        DockPanel.SetDock(statusBox, Dock.Top);
        DockPanel.SetDock(historyPanel, Dock.Bottom);
        root.Children.Add(top);
        root.Children.Add(statusBox);
        root.Children.Add(historyPanel);
        root.Children.Add(split);
        var outer = new DockPanel();
        DockPanel.SetDock(menu, Dock.Top);
        outer.Children.Add(menu);
        outer.Children.Add(root);
        Content = outer;

        BuildTree();
        model.ConnectionChanged += RefreshConnection;
        model.HistoryChanged += () => { history.ItemsSource = null; history.ItemsSource = model.History; };
        model.ValuesChanged += ValuesChanged;
        RefreshConnection();
        Loaded += (_, _) => FocusList();
    }

    MenuItem Item(RoutedUICommand c, string? gesture = null)
    {
        var m = new MenuItem { Command = c, Header = c.Text };
        if (gesture is not null) m.InputGestureText = gesture;
        return m;
    }

    void Bind(RoutedUICommand c, Action a) =>
        CommandBindings.Add(new CommandBinding(c, (_, e) => { a(); e.Handled = true; }));

    // Tree

    void BuildTree()
    {
        var index = new Dictionary<string, int>();
        foreach (var p in model.Database.Parameters)
        {
            var title = p.Section == Section.Patch ? p.Category : $"{p.Section.Raw()}: {p.Category}";
            if (index.TryGetValue(title, out var i)) categories[i].Parameters.Add(p);
            else { index[title] = categories.Count; categories.Add((title, new List<Parameter> { p })); }
        }
        ShowFullTree();
    }

    void ShowFullTree()
    {
        rowsById.Clear();
        staleRows.Clear();
        tree.Items.Clear();
        foreach (var (title, ps) in categories)
        {
            var cat = new Row { Header = $"{title}, {ps.Count} setting{(ps.Count == 1 ? "" : "s")}" };
            cat.FontWeight = FontWeights.Bold;
            foreach (var p in ps) cat.Items.Add(RowFor(p));
            tree.Items.Add(cat);
        }
    }

    TreeViewItem RowFor(Parameter p)
    {
        var item = new Row { Tag = p, Header = RowText(p), FontWeight = FontWeights.Normal, ToolTip = p.Help.Length == 0 ? p.Name : p.Help };
        if (!rowsById.TryGetValue(p.Id, out var list)) rowsById[p.Id] = list = new List<TreeViewItem>();
        list.Add(item);
        // A row whose value changed while it had the focus is updated when the focus moves on, so the
        // screen reader isn't made to read the row again on top of the announcement.
        item.LostKeyboardFocus += (_, _) => { if (staleRows.Remove(item)) item.Header = RowText(p); };
        return item;
    }

    string RowText(Parameter p)
    {
        if (p.HasIndices) return $"{p.Name}: choose {string.Join(" and ", p.Indices.Select(d => d.Name.ToLowerInvariant()))}";
        var s = new Setting(p);
        if (p.IsText) return $"{p.Name}: {(model.Session.TextOf(s) is { } t ? (t.Length == 0 ? "blank" : t) : "not heard yet")}";
        return $"{p.Name}: {(model.Session.ValueOf(s) is { } v ? p.Display(v) : "not heard yet")}";
    }

    void RefreshRows(string id)
    {
        if (!rowsById.TryGetValue(id, out var rows)) return;
        foreach (var item in rows)
        {
            if (item.IsKeyboardFocused) { staleRows.Add(item); continue; }
            item.Header = RowText((Parameter)item.Tag);
        }
    }

    void ValuesChanged(OrganEvent? e)
    {
        string? id = e switch
        {
            OrganEvent.Value v => v.Setting.Parameter.Id,
            OrganEvent.Text t => t.Setting.Parameter.Id,
            OrganEvent.Drawbar d => model.Session.RegistrationSetting(d.Part, d.Index)?.Parameter.Id,
            null => null,
            _ => "",
        };
        if (id == "") return;
        if (id is null) { foreach (var key in rowsById.Keys.ToList()) RefreshRows(key); }
        else RefreshRows(id);
        // Only touch the editor when its own setting changed, so the screen reader is not disturbed
        // while you are on a control.
        var shown = detail.ShownAddress;
        if (e is null) { detail.RefreshValue(); return; }
        var changed = e switch
        {
            OrganEvent.Value v => v.Setting.Address,
            OrganEvent.Text t => t.Setting.Address,
            OrganEvent.Drawbar d => model.Session.RegistrationSetting(d.Part, d.Index)?.Address,
            _ => null,
        };
        if (shown is { } a && changed == a) detail.RefreshValue();
    }

    // Search

    void SearchChanged()
    {
        var q = searchBox.Text.Trim();
        if (q.Length == 0)
        {
            searchCount.Text = "";
            ShowFullTree();
            return;
        }
        var found = model.Database.Search(q);
        rowsById.Clear();
        staleRows.Clear();
        tree.Items.Clear();
        foreach (var p in found) tree.Items.Add(RowFor(p));
        searchCount.Text = found.Count == 0 ? $"No settings match {q}." : $"{found.Count} setting{(found.Count == 1 ? "" : "s")} match {q}.";
    }

    void SearchKey(object sender, KeyEventArgs e)
    {
        if (e.Key is not (Key.Enter or Key.Down)) return;
        e.Handled = true;
        if (searchBox.Text.Trim().Length > 0 && tree.Items.Count > 0 && tree.Items[0] is TreeViewItem first)
        {
            first.IsSelected = true;
            first.Focus();
            first.BringIntoView();
        }
        else if (searchBox.Text.Trim().Length > 0)
        {
            // Otherwise Enter does nothing and says nothing.
            model.Announcer.Announce(searchCount.Text, force: true);
        }
        else
        {
            FocusList();
        }
    }

    public void FocusSearch()
    {
        ShowMain();
        searchBox.Focus();
        searchBox.SelectAll();
    }

    public void FocusList()
    {
        ShowMain();
        var item = tree.SelectedItem as TreeViewItem ?? tree.Items.OfType<TreeViewItem>().FirstOrDefault();
        if (item is null) { tree.Focus(); return; }
        item.IsSelected = true;
        item.Focus();
    }

    /// <summary>Jump to a parameter by id (used by the UI test and XK7D_SHOW).</summary>
    public void Reveal(string id)
    {
        if (searchBox.Text.Length > 0) searchBox.Text = "";
        foreach (TreeViewItem cat in tree.Items)
        {
            foreach (TreeViewItem item in cat.Items)
            {
                if (item.Tag is Parameter p && p.Id == id)
                {
                    cat.IsExpanded = true;
                    item.IsSelected = true;
                    item.BringIntoView();
                    return;
                }
            }
        }
    }

    public DetailPanel Detail => detail;

    // Connection

    public void RefreshConnection()
    {
        updatingPorts = true;
        var choices = model.Choices();
        portBox.Items.Clear();
        foreach (var c in choices) portBox.Items.Add(c.Title);
        portBox.SelectedIndex = Math.Max(0, choices.FindIndex(c => c == model.Choice));
        updatingPorts = false;
        statusBox.Text = model.StatusText;
        speakBox.IsChecked = !model.Announcer.Muted;
        Title = $"XK-7D Companion - {(model.Choice is PortChoice.None ? "not connected" : model.Choice.Title)}";
        detail.RefreshValue();
    }

    void PortChosen()
    {
        if (updatingPorts) return;
        var choices = model.Choices();
        var i = portBox.SelectedIndex;
        if (i < 0 || i >= choices.Count || choices[i] == model.Choice) return;
        model.Choose(choices[i]);
    }

    // Commands

    public void ShowMain()
    {
        if (!IsVisible) Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    /// <summary>Control W: out of the way, still listening. Windows' close (Alt F4) quits, as there.</summary>
    void MinimizeKeepListening()
    {
        WindowState = WindowState.Minimized;
        model.Announcer.Announce("Window minimized. Still listening.", force: true);
    }

    void ToggleMute()
    {
        model.Announcer.Muted = !model.Announcer.Muted;
        // Say so even when muting: silence is not confirmation.
        model.Announcer.Announce(model.Announcer.Muted ? "Announcements muted" : "Announcements on", force: true);
        RefreshConnection();
    }

    void ReadFromOrgan()
    {
        model.Announcer.Announce("Reading from the organ", force: true);
        model.ReadFromOrgan(summary =>
        {
            var parts = summary.Split(". ");
            model.Announcer.Announce(string.Join(". ", parts.Take(2)), force: true);
            Modal.Message(this, summary, "Read from Organ");
        });
    }

    void SetUpOrgan()
    {
        if (!model.IsConnected) { model.Announcer.Announce(model.NotConnectedMessage, force: true); return; }
        ShowMain();
        var steps = model.SetupSteps();
        var dialog = new SetupDialog(steps) { Owner = this };
        if (Modal.Show(dialog) != true) return;
        var sent = 0;
        foreach (var (step, on) in steps.Zip(dialog.Chosen))
        {
            if (!on) continue;
            model.Send(step.Setting, step.Raw);
            sent++;
        }
        model.Announcer.Announce(sent == 0 ? "Nothing sent." : $"Sent {sent} setting{(sent == 1 ? "" : "s")} to the organ.", force: true);
    }

    void SaveSnapshot()
    {
        if (model.Snapshot is not { } snap) { model.Announcer.Announce("There's no organ snapshot yet. Read from Organ first.", force: true); return; }
        ShowMain();
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Title = "Save Organ Snapshot",
            Filter = "MIDI System Exclusive (*.syx)|*.syx",
            FileName = $"XK-7D snapshot {snap.Started:yyyy-MM-dd HHmm}.syx",
        };
        bool? ok;
        try { ok = Modal.Run(() => dialog.ShowDialog(this)); } catch (Exception) { ok = false; }
        if (ok != true) return;
        try
        {
            File.WriteAllBytes(dialog.FileName, snap.SyxData);
            model.Announcer.Announce("Snapshot saved.", force: true);
        }
        catch (Exception e)
        {
            model.Announcer.Announce($"Could not save the snapshot: {e.Message}", force: true);
        }
    }

    void ShowAbout()
    {
        var reader = string.Join(", ", Prism.RunningReaders());
        Modal.Message(this,
            $"Version {Updates.Version}. An accessible companion for the Hammond XK-7D: it speaks changes made on the organ and lets you see and change every setting the manual's MIDI tables list. Not made by or affiliated with Hammond. {model.Database.Parameters.Count} settings from the Owner's Manual V1.10." +
            (reader.Length > 0 ? $" Speaking through {reader}." : ""),
            "About XK-7D Companion");
    }

    void ShowHelp()
    {
        Modal.Message(this, string.Join(Environment.NewLine + Environment.NewLine, new[]
        {
            "Choose your organ in the Organ list (it shows as XK-7 or similar over USB), or the built-in simulator.",
            "Changes you make on the organ are spoken, name first. A knob that is turning is spoken once it stops.",
            "Browse or search every setting in the list. Each row shows its value; \"not heard yet\" means the organ has not reported it. Press Tab to reach the editor; changes are sent at once.",
            "Keys: Control F search, Control L the settings list, Control R read from organ, Control Shift U set up the organ, Control Shift M mute, Control Shift L repeat the last announcement, Control S save the last organ snapshot, Control 1 this window, Control 2 the simulator, Control comma settings, Control U check for updates, F1 this help.",
            "To hear every setting, use Organ, Set Up Organ for This App, which sets the organ to send changes as SysEx. Loading one of the organ's MIDI templates puts that back to NRPN, so run Set Up Organ again afterwards.",
            "If the organ is unplugged or turned off, the app says so, and connects again by itself when the organ comes back. If another program has the organ's MIDI port open, close it first.",
            "Control W minimizes this window. The app keeps listening and speaking organ changes. Alt F4 quits.",
        }), "XK-7D Companion Help");
    }
}
