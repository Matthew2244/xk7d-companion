using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Input;
using XK7D.Core;

namespace XK7D.Companion;

static class Ui
{
    /// <summary>Gives a control the name a screen reader reads, and help text (also its tooltip).</summary>
    public static T Named<T>(this T e, string name, string? help = null) where T : FrameworkElement
    {
        AutomationProperties.SetName(e, name);
        if (help is not null)
        {
            AutomationProperties.SetHelpText(e, help);
            e.ToolTip = help;
        }
        return e;
    }

    public static TextBlock Text(string s, bool bold = false, bool wrap = false, double size = 0)
    {
        var t = new TextBlock { Text = s, Margin = new Thickness(0, 2, 0, 2) };
        if (bold) t.FontWeight = FontWeights.Bold;
        if (wrap) t.TextWrapping = TextWrapping.Wrap;
        if (size > 0) t.FontSize = size;
        return t;
    }

    /// <summary>Text a screen reader user can Tab to and read line by line: a read-only text box.</summary>
    public static TextBox Reading(string text, string name) => new TextBox
    {
        Text = text,
        IsReadOnly = true,
        IsReadOnlyCaretVisible = true,
        TextWrapping = TextWrapping.Wrap,
        AcceptsReturn = true,
        BorderThickness = new Thickness(0),
        Background = System.Windows.Media.Brushes.Transparent,
        Margin = new Thickness(0, 4, 0, 4),
    }.Named(name);

    public static Label LabelFor(string text, UIElement target) => new Label { Content = text, Target = target, Padding = new Thickness(0, 4, 6, 4) };

    public static StackPanel Row(params UIElement[] children)
    {
        var p = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 3, 0, 3) };
        foreach (var c in children) p.Children.Add(c);
        return p;
    }

    public static Button Button(string title, string help, RoutedEventHandler click)
    {
        var b = new Button { Content = title, Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(0, 0, 8, 0) }.Named(title.Replace("_", ""), help);
        b.Click += click;
        return b;
    }
}

/// <summary>Counts open dialogs, so the update news is never said over a question someone is answering.</summary>
static class Modal
{
    public static int Open { get; private set; }

    public static bool? Show(Window dialog)
    {
        Open++;
        try { return dialog.ShowDialog(); } finally { Open--; }
    }

    public static bool? Run(Func<bool?> show)
    {
        Open++;
        try { return show(); } finally { Open--; }
    }

    public static MessageBoxResult Message(Window? owner, string text, string title,
        MessageBoxButton buttons = MessageBoxButton.OK, MessageBoxImage icon = MessageBoxImage.None)
    {
        Open++;
        try
        {
            return owner is { IsVisible: true }
                ? MessageBox.Show(owner, text, title, buttons, icon)
                : MessageBox.Show(text, title, buttons, icon);
        }
        finally { Open--; }
    }
}

/// <summary>A slider that steps one raw value per arrow key and reads the organ's display value
/// ("340 rpm", not "141"), treating "not heard yet" as a real state rather than pretending to know.
/// The Windows counterpart of the Mac's ParameterSlider.
///
/// Its automation peer offers the Value pattern only, holding that text. It deliberately offers no
/// RangeValue pattern: NVDA reads a RangeValue slider as a percentage, which would hide the value.</summary>
public sealed class ValueSlider : Slider
{
    public Parameter? Parameter { get; private set; }
    public bool Known { get; private set; }
    /// <summary>A value the person chose: send it.</summary>
    public Action<int>? OnCommit { get; set; }
    /// <summary>Called instead of sending when the value is unknown: any value picked would be a
    /// guess, and the bottom of a range can be drastic on a real organ (0 rpm stops the Leslie horn).</summary>
    public Action? OnUnknownStep { get; set; }
    /// <summary>Text typed through UI Automation's Value pattern; returns false if it isn't a value.</summary>
    public Func<string, bool>? OnTyped { get; set; }
    bool quiet;

    public ValueSlider()
    {
        IsSnapToTickEnabled = true;
        TickFrequency = 1;
        SmallChange = 1;
        Focusable = true;
        IsTabStop = true;
    }

    public int Raw => (int)Math.Round(Value);

    public string ValueText => Known && Parameter is { } p ? p.Spoken(Raw) : "not heard yet";

    /// <summary>Show what the session knows, without sending anything.</summary>
    public void Configure(Parameter p, int? raw)
    {
        var old = ValueText;
        quiet = true;
        Parameter = p;
        Minimum = p.RawMin;
        Maximum = p.RawMax;
        LargeChange = Math.Max(1, p.RangeCount / 10);
        if (raw is { } r) { Value = r; Known = true; }
        else { Value = p.RawMin; Known = false; }
        quiet = false;
        RaiseValueText(old);
    }

    void RaiseValueText(string old)
    {
        if (UIElementAutomationPeer.FromElement(this) is ValueSliderPeer peer && old != ValueText)
            peer.RaisePropertyChangedEvent(ValuePatternIdentifiers.ValueProperty, old, ValueText);
    }

    void Set(int raw, bool alwaysAnnounce)
    {
        var old = ValueText;
        quiet = true;
        Value = raw;
        Known = true;
        quiet = false;
        OnCommit?.Invoke(raw);
        // At an end the value doesn't move; say it again so a key press is never met with silence.
        if (alwaysAnnounce && UIElementAutomationPeer.FromElement(this) is ValueSliderPeer peer)
            peer.RaisePropertyChangedEvent(ValuePatternIdentifiers.ValueProperty, old == ValueText ? "" : old, ValueText);
    }

    void Step(int delta)
    {
        if (Parameter is null) return;
        if (!Known) { OnUnknownStep?.Invoke(); return; }
        Set(Parameter.Clamp(Raw + delta), true);
    }

    void Jump(int raw)
    {
        if (Parameter is null) return;
        if (!Known) { OnUnknownStep?.Invoke(); return; }
        Set(raw, true);
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (Parameter is null || Keyboard.Modifiers != ModifierKeys.None) { base.OnPreviewKeyDown(e); return; }
        var tenth = Math.Max(1, Parameter.RangeCount / 10);
        switch (e.Key)
        {
            case Key.Left: case Key.Down: Step(-1); break;
            case Key.Right: case Key.Up: Step(1); break;
            case Key.PageUp: Step(tenth); break;
            case Key.PageDown: Step(-tenth); break;
            case Key.Home: Jump(Parameter.RawMin); break;
            case Key.End: Jump(Parameter.RawMax); break;
            default: base.OnPreviewKeyDown(e); return;
        }
        e.Handled = true;
    }

    /// <summary>A mouse drag (a sighted helper, say) also sends.</summary>
    protected override void OnValueChanged(double oldValue, double newValue)
    {
        base.OnValueChanged(oldValue, newValue);
        if (quiet || Parameter is null) return;
        var old = Known && Parameter is { } p ? p.Spoken((int)Math.Round(oldValue)) : "not heard yet";
        Known = true;
        OnCommit?.Invoke(Raw);
        RaiseValueText(old);
    }

    protected override AutomationPeer OnCreateAutomationPeer() => new ValueSliderPeer(this);

    internal bool AcceptTyped(string text) => OnTyped?.Invoke(text) ?? false;
}

public sealed class ValueSliderPeer : FrameworkElementAutomationPeer, IValueProvider
{
    readonly ValueSlider slider;
    public ValueSliderPeer(ValueSlider owner) : base(owner) { slider = owner; }

    protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Slider;
    protected override string GetClassNameCore() => "Slider";
    protected override bool IsContentElementCore() => true;
    protected override bool IsControlElementCore() => true;
    protected override bool IsKeyboardFocusableCore() => true;
    /// <summary>The thumb and the track's repeat buttons are drawing, not separate controls.</summary>
    protected override List<AutomationPeer>? GetChildrenCore() => null;

    public override object? GetPattern(PatternInterface patternInterface) =>
        patternInterface == PatternInterface.Value ? this : base.GetPattern(patternInterface);

    public string Value => slider.ValueText;
    public bool IsReadOnly => !slider.IsEnabled;

    public void SetValue(string value)
    {
        if (!slider.IsEnabled) throw new ElementNotEnabledException();
        if (!slider.AcceptTyped(value)) throw new ArgumentException("Not a value for this setting.");
    }
}

/// <summary>A row of the settings list. Its template's expand toggle is drawing for the mouse; the
/// row itself expands and collapses (Right and Left Arrow), so the toggle is left out of what screen
/// readers see, where it would be an unnamed button inside every category.</summary>
public sealed class Row : TreeViewItem
{
    protected override AutomationPeer OnCreateAutomationPeer() => new RowPeer(this);
}

public sealed class RowPeer : TreeViewItemAutomationPeer
{
    public RowPeer(Row owner) : base(owner) { }

    protected override List<AutomationPeer>? GetChildrenCore() =>
        base.GetChildrenCore()?.Where(p => !(p is FrameworkElementAutomationPeer f
            && f.Owner is System.Windows.Controls.Primitives.ToggleButton { Name: "Expander" })).ToList();
}
