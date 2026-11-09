// Launches XK7DCompanion.exe --ui-test (silent, on the simulator, settings in a scratch folder) and
// checks it through UI Automation, the interface screen readers use. Exits 1 on any failure.
// What this proves: what UI Automation (and, through its bridge, MSAA) exposes. It does not prove
// how NVDA, JAWS or Narrator speak it; that needs a person.
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using XK7D.Core;

var exe = args.Length > 0 ? args[0] : throw new ArgumentException("usage: UiaCheck path\\to\\XK7DCompanion.exe");
var failures = new List<string>();
void Check(bool ok, string what) { Console.WriteLine((ok ? "ok    " : "FAIL  ") + what); if (!ok) failures.Add(what); }

var testDir = Path.Combine(Path.GetTempPath(), "xk7d-uia-" + Guid.NewGuid().ToString("N")[..8]);
Directory.CreateDirectory(testDir);
var psi = new ProcessStartInfo(exe, "--ui-test") { UseShellExecute = false };
psi.Environment["XK7D_TEST_DIR"] = testDir;
var proc = Process.Start(psi)!;
try
{
    var main = Wait(() => Windows(proc.Id).FirstOrDefault(w => w.Current.Name.StartsWith("XK-7D Companion -", StringComparison.Ordinal)), 40)
               ?? throw new Exception("the main window never appeared");
    Check(main.Current.Name == "XK-7D Companion - Built-in simulator (not a real organ)", $"main window title: {main.Current.Name}");
    Wait(() => Windows(proc.Id).Count >= 3 ? true : (bool?)null, 15);

    // 1. Every control a person can reach has a name.
    var interactive = new HashSet<ControlType>
    {
        ControlType.Button, ControlType.CheckBox, ControlType.ComboBox, ControlType.Edit, ControlType.Slider,
        ControlType.Tree, ControlType.TreeItem, ControlType.List, ControlType.ListItem, ControlType.MenuItem,
        ControlType.RadioButton, ControlType.Hyperlink, ControlType.Spinner, ControlType.Tab, ControlType.TabItem,
    };
    var counts = new Dictionary<string, int>();
    var unnamed = new List<string>();
    foreach (var w in Windows(proc.Id))
    {
        Console.WriteLine($"window: {w.Current.Name}");
        Walk(w, e =>
        {
            var ct = e.Current.ControlType;
            if (!interactive.Contains(ct)) return;
            counts[ct.ProgrammaticName] = counts.GetValueOrDefault(ct.ProgrammaticName) + 1;
            if (string.IsNullOrWhiteSpace(e.Current.Name))
                unnamed.Add($"{ct.ProgrammaticName} (class {e.Current.ClassName}, id '{e.Current.AutomationId}') in {w.Current.Name}");
        });
    }
    foreach (var (k, v) in counts.OrderBy(k => k.Key)) Console.WriteLine($"      {v,4} {k}");
    Check(unnamed.Count == 0, $"every reachable control has a name ({counts.Values.Sum()} checked)" + (unnamed.Count > 0 ? ": " + string.Join("; ", unnamed.Take(15)) : ""));
    Check(counts.GetValueOrDefault("ControlType.TreeItem") >= 20, "the settings list shows its categories");
    Check(counts.GetValueOrDefault("ControlType.MenuItem") >= 6, "the menu bar is there");

    var db = ParameterDatabase.Shared;
    var fast = db.SettingAt(new Address(0x42, 0, 0, 0, 0))!;
    var slow = db.SettingAt(new Address(0x42, 0, 0, 0, 1))!;

    // 2. Search, and choose a result.
    var search = Find(main, "Search settings", ControlType.Edit);
    ((ValuePattern)search.GetCurrentPattern(ValuePattern.Pattern)).SetValue("leslie horn fast speed");
    var result = Wait(() => Descendants(Find(main, "Settings", ControlType.Tree), ControlType.TreeItem)
        .FirstOrDefault(i => i.Current.Name.StartsWith("Leslie horn fast speed:", StringComparison.Ordinal)), 10);
    Check(result is not null, "search finds Leslie horn fast speed");
    Check(result?.Current.Name == "Leslie horn fast speed: not heard yet", $"its row reads \"{result?.Current.Name}\"");
    ((SelectionItemPattern)result!.GetCurrentPattern(SelectionItemPattern.Pattern)).Select();

    // 3. The slider reads the organ's display value, not a number or a percentage.
    var slider = Wait(() => TryFind(main, "Leslie horn fast speed", ControlType.Slider), 10) ?? throw new Exception("no slider for Leslie horn fast speed");
    Check(slider.TryGetCurrentPattern(ValuePattern.Pattern, out var vp), "the slider offers the Value pattern");
    Check(!slider.TryGetCurrentPattern(RangeValuePattern.Pattern, out _), "the slider offers no RangeValue pattern (NVDA would read a percentage)");
    var value = (ValuePattern)vp;
    Check(value.Current.Value == "not heard yet", $"before the organ reports it, the slider reads \"{value.Current.Value}\"");
    var msaa = Msaa(slider);
    Check(msaa == ("Leslie horn fast speed", "not heard yet"), $"MSAA (what JAWS and older readers use) reads name \"{msaa.Name}\", value \"{msaa.Value}\"");
    var help = slider.Current.HelpText;
    Check(help.Contains("Arrow keys", StringComparison.Ordinal), "the slider has help text");

    // 4. Refusing to guess: a step from "not heard yet" sends nothing and says why.
    var simulator = Windows(proc.Id).First(w => w.Current.Name == "XK-7D Simulator (not a real organ)");
    var log = Find(simulator, "Simulator log", ControlType.List);
    int LogCount() => Descendants(log, ControlType.ListItem).Count;
    var before = LogCount();
    Focus(main, slider);
    Key(VK_UP);
    Thread.Sleep(700);
    Check(value.Current.Value == "not heard yet", $"Up Arrow on an unknown value changes nothing (reads \"{value.Current.Value}\")");
    Check(LogCount() == before, "and nothing was sent to the simulator");
    var historyList = Find(main, "Recent announcements", ControlType.List);
    Check(Descendants(historyList, ControlType.ListItem).FirstOrDefault()?.Current.Name.StartsWith("Not heard yet, so nothing was sent", StringComparison.Ordinal) == true,
          "and the app says why");

    // 5. A typed value (through UI Automation's Value pattern, as a screen reader can set it) is sent.
    value.SetValue("340 rpm");
    Thread.Sleep(700);
    Check(value.Current.Value == "340 rpm", $"typing 340 rpm: the slider reads \"{value.Current.Value}\"");
    var expected = Hex(XK7SysEx.DataSet(0, fast, 141));
    Check(Descendants(log, ControlType.ListItem).Any(i => i.Current.Name == expected), $"the simulator received {expected}");

    // 6. The keyboard steps by one and by a tenth, sending each.
    Focus(main, slider);
    Key(VK_UP);
    Thread.Sleep(700);
    Check(value.Current.Value == fast.Parameter.Spoken(142), $"Up Arrow: \"{value.Current.Value}\" (expected \"{fast.Parameter.Spoken(142)}\")");
    Key(VK_PRIOR);
    Thread.Sleep(700);
    var tenth = Math.Max(1, fast.Parameter.RangeCount / 10);
    Check(value.Current.Value == fast.Parameter.Spoken(142 + tenth), $"Page Up: \"{value.Current.Value}\"");
    Key(VK_HOME);
    Thread.Sleep(700);
    Check(value.Current.Value == fast.Parameter.Spoken(fast.Parameter.RawMin), $"Home: \"{value.Current.Value}\"");
    Check(Descendants(log, ControlType.ListItem).Any(i => i.Current.Name == Hex(XK7SysEx.DataSet(0, fast, fast.Parameter.RawMin))),
          "and Home's value reached the simulator");

    // 7. The list row follows.
    ((ValuePattern)search.GetCurrentPattern(ValuePattern.Pattern)).SetValue("leslie horn fast speed");
    var row = Wait(() => Descendants(Find(main, "Settings", ControlType.Tree), ControlType.TreeItem)
        .FirstOrDefault(i => i.Current.Name.StartsWith("Leslie horn fast speed:", StringComparison.Ordinal)), 10);
    Check(row?.Current.Name == $"Leslie horn fast speed: {fast.Parameter.Display(fast.Parameter.RawMin)}", $"the row now reads \"{row?.Current.Name}\"");

    // 8. A typed value that isn't one is refused.
    ((ValuePattern)search.GetCurrentPattern(ValuePattern.Pattern)).SetValue("leslie horn slow speed");
    var slowRow = Wait(() => Descendants(Find(main, "Settings", ControlType.Tree), ControlType.TreeItem)
        .FirstOrDefault(i => i.Current.Name.StartsWith("Leslie horn slow speed:", StringComparison.Ordinal)), 10)!;
    ((SelectionItemPattern)slowRow.GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
    var slowSlider = Wait(() => TryFind(main, "Leslie horn slow speed", ControlType.Slider), 10)!;
    var refused = false;
    try { ((ValuePattern)slowSlider.GetCurrentPattern(ValuePattern.Pattern)).SetValue("9999 rpm"); } catch (ArgumentException) { refused = true; }
    Check(refused, "a value outside the range is refused");
    Check(Find(main, $"Type a value for {slow.Parameter.Name}", ControlType.Edit) is not null, "the typed-value box is named for its setting");

    // 9. Close: the process ends cleanly.
    ((WindowPattern)main.GetCurrentPattern(WindowPattern.Pattern)).Close();
    Check(proc.WaitForExit(15000), "closing the main window quits the app");
    Check(proc.HasExited && proc.ExitCode == 0, $"exit code {(proc.HasExited ? proc.ExitCode : -1)}");
}
catch (Exception e)
{
    Check(false, "unexpected: " + e);
}
finally
{
    if (!proc.HasExited) proc.Kill();
}
Console.WriteLine(failures.Count == 0 ? "UIA CHECK OK" : $"UIA CHECK FAILED ({failures.Count})");
return failures.Count == 0 ? 0 : 1;

static string Hex(byte[] b) => string.Join(" ", b.Select(x => x.ToString("X2")));

static List<AutomationElement> Windows(int pid) =>
    AutomationElement.RootElement.FindAll(TreeScope.Children, new PropertyCondition(AutomationElement.ProcessIdProperty, pid))
        .Cast<AutomationElement>().ToList();

static List<AutomationElement> Descendants(AutomationElement root, ControlType type) =>
    root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, type)).Cast<AutomationElement>().ToList();

static AutomationElement? TryFind(AutomationElement root, string name, ControlType type) =>
    root.FindFirst(TreeScope.Descendants, new AndCondition(
        new PropertyCondition(AutomationElement.NameProperty, name), new PropertyCondition(AutomationElement.ControlTypeProperty, type)));

static AutomationElement Find(AutomationElement root, string name, ControlType type) =>
    TryFind(root, name, type) ?? throw new Exception($"no {type.ProgrammaticName} named \"{name}\"");

static void Walk(AutomationElement e, Action<AutomationElement> visit)
{
    visit(e);
    var walker = TreeWalker.ControlViewWalker;
    for (var c = walker.GetFirstChild(e); c is not null; c = walker.GetNextSibling(c)) Walk(c, visit);
}

static T? Wait<T>(Func<T?> get, double seconds)
{
    var end = DateTime.Now.AddSeconds(seconds);
    while (true)
    {
        try { if (get() is { } v) return v; } catch (Exception) when (DateTime.Now < end) { }
        if (DateTime.Now >= end) return default;
        Thread.Sleep(200);
    }
}

/// <summary>Name and value through MSAA (oleacc), the older interface JAWS still leans on, at the
/// middle of the element's rectangle.</summary>
static (string? Name, string? Value) Msaa(AutomationElement e)
{
    try
    {
        var r = e.Current.BoundingRectangle;
        var pt = new POINT { X = (int)(r.Left + r.Width / 2), Y = (int)(r.Top + r.Height / 2) };
        if (AccessibleObjectFromPoint(pt, out var acc, out var child) != 0 || acc is null) return (null, null);
        return (acc.get_accName(child), acc.get_accValue(child));
    }
    catch (Exception ex) { return ("error: " + ex.Message, null); }
}

static void Focus(AutomationElement window, AutomationElement e)
{
    try { ((WindowPattern)window.GetCurrentPattern(WindowPattern.Pattern)).SetWindowVisualState(WindowVisualState.Normal); } catch (Exception) { }
    SetForegroundWindow(new IntPtr(window.Current.NativeWindowHandle));
    e.SetFocus();
    Thread.Sleep(300);
}

static void Key(ushort vk)
{
    var inputs = new[]
    {
        new INPUT { type = 1, u = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = 0 } } },
        new INPUT { type = 1, u = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = 2 } } },
    };
    SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
}

[DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
[DllImport("oleacc.dll")] static extern int AccessibleObjectFromPoint(POINT pt, [MarshalAs(UnmanagedType.Interface)] out Accessibility.IAccessible acc, out object child);
[DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);

partial class Program
{
    const ushort VK_UP = 0x26, VK_PRIOR = 0x21, VK_HOME = 0x24;
}

[StructLayout(LayoutKind.Sequential)]
struct POINT { public int X, Y; }

[StructLayout(LayoutKind.Sequential)]
struct INPUT { public uint type; public InputUnion u; }

[StructLayout(LayoutKind.Explicit)]
struct InputUnion
{
    [FieldOffset(0)] public MOUSEINPUT mi;
    [FieldOffset(0)] public KEYBDINPUT ki;
}

[StructLayout(LayoutKind.Sequential)]
struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

[StructLayout(LayoutKind.Sequential)]
struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
