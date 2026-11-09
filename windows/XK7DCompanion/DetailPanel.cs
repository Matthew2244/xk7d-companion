// The Windows counterpart of Sources/XK7DCompanion/DetailView.swift: one setting, its index pickers,
// an editor for its value, and what the manual says about it.
using System.Media;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using XK7D.Core;

namespace XK7D.Companion;

public sealed class DetailPanel : StackPanel
{
    readonly AppModel model;
    Parameter? parameter;
    readonly List<ComboBox> indexBoxes = new();
    ComboBox? choiceBox;
    ValueSlider? slider;
    TextBlock? valueLabel;
    TextBox? typedBox;
    TextBox? nameBox;
    bool choiceHasPlaceholder;
    bool updating;

    public DetailPanel(AppModel model)
    {
        this.model = model;
        Margin = new Thickness(12, 8, 12, 12);
        Show(null);
    }

    Setting? CurrentSetting
    {
        get
        {
            if (parameter is not { } p) return null;
            var values = p.Indices.Select((d, i) => d.Options[Math.Max(indexBoxes[i].SelectedIndex, 0)].Raw).ToArray();
            return new Setting(p, values);
        }
    }

    /// <summary>The setting on show, if any (so the window only refreshes this pane when it changed).</summary>
    public Address? ShownAddress => CurrentSetting?.Address;
    public ValueSlider? Slider => slider;

    public void Show(Parameter? p)
    {
        parameter = p;
        Children.Clear();
        indexBoxes.Clear();
        choiceBox = null; slider = null; valueLabel = null; typedBox = null; nameBox = null; choiceHasPlaceholder = false;
        if (p is null)
        {
            Children.Add(Ui.Text("Select a setting in the list to see and change it.", wrap: true));
            return;
        }
        var title = Ui.Text(p.Name, bold: true, size: 17);
        AutomationProperties.SetHeadingLevel(title, AutomationHeadingLevel.Level2);
        Children.Add(title);
        var sectionName = p.Section switch { Section.Patch => "Patch setting", Section.Custom => "Custom set setting", _ => "System setting" };
        Children.Add(Ui.Text($"{sectionName}, {p.Category}.", wrap: true));

        foreach (var dim in p.Indices)
        {
            var box = new ComboBox { MinWidth = 200, IsEditable = false }.Named(dim.Name, $"Choose which {dim.Name.ToLowerInvariant()} to see and change.");
            foreach (var o in dim.Options) box.Items.Add(IndexDimension.Spoken(o.Label));
            box.SelectedIndex = 0;
            // VoiceOver/screen readers read the value control itself when you move to it; no extra speech here.
            box.SelectionChanged += (_, _) => RefreshValue();
            indexBoxes.Add(box);
            Children.Add(Ui.Row(Ui.LabelFor($"{dim.Name}:", box), box));
        }

        var help = EditorHelp(p);
        switch (p.Kind.Type)
        {
            case ValueType.Text:
            {
                var length = p.Kind.Length;
                nameBox = new TextBox { Width = 260, MaxLength = 64 }
                    .Named(p.Name, $"Type a new name, up to {length} plain letters, then press Enter or Send Name. {help}");
                nameBox.KeyDown += (_, e) => { if (e.Key == Key.Enter) { SendText(); e.Handled = true; } };
                var send = Ui.Button("Send Name", "Sends this name to the organ.", (_, _) => SendText());
                Children.Add(Ui.Row(Ui.LabelFor($"{p.Name}:", nameBox), nameBox, new TextBlock { Width = 8 }, send));
                break;
            }
            case ValueType.Choices:
            {
                choiceBox = new ComboBox { MinWidth = 240 }
                    .Named(p.Name, $"Choosing a value sends it to the organ straight away. Alt Down Arrow opens the list to look without sending. {help}");
                foreach (var o in p.Kind.Options) choiceBox.Items.Add(o.Label);
                choiceBox.SelectionChanged += (_, _) => ChoiceChanged();
                Children.Add(Ui.Row(Ui.LabelFor($"{p.Name}:", choiceBox), choiceBox));
                break;
            }
            default:
            {
                slider = new ValueSlider { Width = 300, VerticalAlignment = VerticalAlignment.Center }
                    .Named(p.Name, $"Arrow keys change the value by one step, Page Up and Page Down by ten percent, Home and End go to the ends. Each change is sent to the organ. {help}");
                slider.OnCommit = Commit;
                slider.OnUnknownStep = () => model.Announcer.Announce(
                    "Not heard yet, so nothing was sent. Type a value below, or change it on the organ so the app hears it.", force: true);
                slider.OnTyped = text =>
                {
                    if (p.RawValueFromTyped(text) is not { } raw) return false;
                    Commit(raw);
                    return true;
                };
                valueLabel = Ui.Text("");
                valueLabel.VerticalAlignment = VerticalAlignment.Center;
                valueLabel.Margin = new Thickness(10, 0, 0, 0);
                Children.Add(Ui.Row(Ui.LabelFor($"{p.Name}:", slider), slider, valueLabel));
                var example = TypedExample(p);
                typedBox = new TextBox { Width = 160 }
                    .Named($"Type a value for {p.Name}", $"Type a value the way the organ shows it, for example {example}, and press Enter to send it.");
                typedBox.KeyDown += (_, e) => { if (e.Key == Key.Enter) { TypedValue(); e.Handled = true; } };
                Children.Add(Ui.Row(Ui.LabelFor("Type a value:", typedBox), typedBox));
                break;
            }
        }

        var about = new List<string>();
        if (p.Help.Length > 0) about.Add(p.Help);
        about.Add($"Range: {RangeText(p)}.");
        if (p.Notes is { } notes) about.Add($"Manual note: {notes}");
        about.Add(DescribeManualSource(p, CurrentSetting!));
        Children.Add(Ui.Reading(string.Join(Environment.NewLine, about), $"About {p.Name}"));
        RefreshValue();
    }

    static string EditorHelp(Parameter p) => p.Help.Length == 0 ? $"Range: {RangeText(p)}." : p.Help;

    public static string RangeText(Parameter p) => p.Kind.Type switch
    {
        ValueType.Text => $"up to {p.Kind.Length} characters",
        ValueType.Choices => p.Kind.Options.Count <= 8
            ? string.Join(", ", p.Kind.Options.Select(o => o.Label))
            : $"{p.Kind.Options[0].Label} to {p.Kind.Options[^1].Label}, {p.Kind.Options.Count} choices",
        ValueType.Steps => $"{p.Kind.Low} to {p.Kind.High} in {p.RangeCount - 1} steps; the manual does not give the values in between",
        _ => $"{p.Display(p.RawMin)} to {p.Display(p.RawMax)}",
    };

    static string TypedExample(Parameter p) => p.Display((p.RawMin + p.RawMax) / 2);

    public static string DescribeManualSource(Parameter p, Setting setting)
    {
        var s = $"Manual page {p.Page}: {p.ManualCategory}, {p.ManualName}. SysEx address {setting.Address}";
        if (p.Nrpn is { } n && !p.HasIndices) s += $", NRPN {n.Msb:X2} {n.Lsb:X2}";
        else if (p.Nrpn is null) s += ", SysEx only (no NRPN)";
        s += ", " + (p.Length == 16 ? "16 characters" : $"{p.Length} data byte{(p.Length == 1 ? "" : "s")}") + ".";
        if (p.Xk7Only) s += " Single-manual XK-7 only.";
        return s;
    }

    /// <summary>Show what the session knows for the current setting.</summary>
    public void RefreshValue()
    {
        if (parameter is not { } p || CurrentSetting is not { } s) return;
        updating = true;
        try
        {
            if (p.IsText)
            {
                if (nameBox is { } box && !box.IsKeyboardFocusWithin)
                    box.Text = model.Session.TextOf(s) ?? "";
                return;
            }
            var raw = model.Session.ValueOf(s);
            if (choiceBox is { } cb)
            {
                var i = raw is { } r ? p.Kind.Options.ToList().FindIndex(o => o.Raw == r) : -1;
                if (i >= 0)
                {
                    if (choiceHasPlaceholder) { cb.Items.RemoveAt(0); choiceHasPlaceholder = false; }
                    if (cb.SelectedIndex != i) cb.SelectedIndex = i;
                }
                else if (!choiceHasPlaceholder)
                {
                    cb.Items.Insert(0, new ComboBoxItem { Content = "Not heard yet", IsEnabled = false });
                    cb.SelectedIndex = 0;
                    choiceHasPlaceholder = true;
                }
            }
            if (slider is { } sl)
            {
                sl.Configure(p, raw);
                if (valueLabel is { } vl) vl.Text = raw is { } v ? p.Display(v) : "Not heard yet";
            }
        }
        finally { updating = false; }
    }

    void ChoiceChanged()
    {
        if (updating || choiceBox is not { } cb || parameter is not { } p) return;
        var i = cb.SelectedIndex;
        if (choiceHasPlaceholder)
        {
            if (i == 0) return;
            // A real choice: the placeholder goes, quietly.
            updating = true;
            cb.Items.RemoveAt(0);
            choiceHasPlaceholder = false;
            i -= 1;
            cb.SelectedIndex = i;
            updating = false;
        }
        if (i < 0 || i >= p.Kind.Options.Count) return;
        Commit(p.Kind.Options[i].Raw);
    }

    void TypedValue()
    {
        if (parameter is not { } p || typedBox is not { } box) return;
        if (p.RawValueFromTyped(box.Text) is not { } raw)
        {
            SystemSounds.Beep.Play();
            model.Announcer.Announce($"Not a value for {p.Name}. Range {RangeText(p)}.", force: true);
            return;
        }
        Commit(raw);
        box.Text = "";
        // A screen reader says nothing when a text box is submitted, so confirm what was sent.
        if (CurrentSetting is { } s && model.IsConnected)
            model.Announcer.Announce($"{s.SpokenName}: {p.Spoken(p.Clamp(raw))}", force: true);
    }

    void SendText()
    {
        if (CurrentSetting is not { } s || nameBox is not { } box) return;
        var name = SwiftText.TrimWhitespace(box.Text);
        // An empty box is most likely an accidental Enter; sending it would blank the name.
        if (name.Length == 0)
        {
            model.Announcer.Announce("Type a name first. Nothing was sent.", force: true);
            return;
        }
        model.Send(s, name);
        if (model.IsConnected) model.Announcer.Announce($"{s.SpokenName} sent: {model.Session.TextOf(s) ?? name}", force: true);
    }

    void Commit(int raw)
    {
        if (CurrentSetting is not { } s) return;
        model.Send(s, s.Parameter.Clamp(raw));
        // Show what the session now holds: the new value, or, if nothing could be sent (no organ),
        // what was known before. A control must never show a value the organ wasn't sent.
        RefreshValue();
    }
}
