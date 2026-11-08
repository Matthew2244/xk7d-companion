// Read-only walk of an app's accessibility tree, for checking labels without touching the UI.
// Usage: swift tools/ax-inspect.swift <pid>
import ApplicationServices
import Foundation

let pid = pid_t(CommandLine.arguments[1])!
print("trusted:", AXIsProcessTrusted())
let app = AXUIElementCreateApplication(pid)

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ name: String) -> String {
    guard let v = attr(e, name) else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

let interactive: Set<String> = ["AXButton", "AXPopUpButton", "AXSlider", "AXTextField", "AXCheckBox", "AXOutline",
                                "AXTable", "AXSearchField", "AXIncrementor", "AXComboBox", "AXMenuButton", "AXRadioButton"]
var unlabeled: [String] = []
var count = 0
func walk(_ e: AXUIElement, _ depth: Int, _ maxDepth: Int) {
    count += 1
    let role = str(e, "AXRole")
    let sub = str(e, "AXSubrole")
    let title = str(e, "AXTitle")
    let desc = str(e, "AXDescription")
    let value = str(e, "AXValue")
    let vdesc = str(e, "AXValueDescription")
    let help = str(e, "AXHelp")
    let label = [title, desc].first { !$0.isEmpty } ?? ""
    let rowsSkip = role == "AXRow" || role == "AXCell"
    if !rowsSkip || depth < 6 {
        var line = String(repeating: "  ", count: depth) + role
        if !sub.isEmpty { line += "(\(sub))" }
        if !label.isEmpty { line += " label=\"\(label)\"" }
        if !value.isEmpty { line += " value=\"\(value.prefix(70))\"" }
        if !vdesc.isEmpty { line += " valueDesc=\"\(vdesc)\"" }
        if !help.isEmpty { line += " help=yes" }
        print(line)
    }
    let systemChrome: Set<String> = ["AXCloseButton", "AXMinimizeButton", "AXFullScreenButton", "AXZoomButton",
                                     "AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage"]
    if interactive.contains(role) && label.isEmpty && role != "AXTextField" && !systemChrome.contains(sub) {
        unlabeled.append("\(role) value=\(value.prefix(40))")
    }
    if role == "AXTextField" && label.isEmpty && str(e, "AXPlaceholderValue").isEmpty && (attr(e, "AXEditable") as? Bool ?? false) {
        unlabeled.append("editable AXTextField value=\(value.prefix(40))")
    }
    guard depth < maxDepth, let kids = attr(e, "AXChildren") as? [AXUIElement] else { return }
    for k in kids.prefix(role == "AXOutline" || role == "AXTable" ? 12 : 200) { walk(k, depth + 1, maxDepth) }
}
// Optional: perform AXIncrement on the first slider (acts on the app without moving focus).
func firstSlider(_ e: AXUIElement) -> AXUIElement? {
    if str(e, "AXRole") == "AXSlider" { return e }
    for k in (attr(e, "AXChildren") as? [AXUIElement] ?? []) { if let s = firstSlider(k) { return s } }
    return nil
}
if CommandLine.arguments.contains("--increment") {
    for w in attr(app, "AXWindows") as? [AXUIElement] ?? [] {
        if let s = firstSlider(w) {
            for _ in 0..<3 { AXUIElementPerformAction(s, "AXIncrement" as CFString) }
            print("after 3 x AXIncrement:", str(s, "AXValue"), str(s, "AXValueDescription"))
        }
    }
    exit(0)
}
let windows = attr(app, "AXWindows") as? [AXUIElement] ?? []
print("windows:", windows.count)
for w in windows { walk(w, 0, 14) }
if let barObj = attr(app, "AXMenuBar") { let bar = barObj as! AXUIElement
    print("--- menu bar")
    for top in (attr(bar, "AXChildren") as? [AXUIElement] ?? []) {
        let t = str(top, "AXTitle")
        guard let menu = (attr(top, "AXChildren") as? [AXUIElement])?.first else { continue }
        let items = (attr(menu, "AXChildren") as? [AXUIElement] ?? []).map { i -> String in
            let k = str(i, "AXMenuItemCmdChar")
            return str(i, "AXTitle") + (k.isEmpty ? "" : " [cmd \(k)]")
        }.filter { $0 != "" }
        print("\(t): \(items.joined(separator: "; "))")
    }
}
print("--- elements:", count, " unlabeled interactive:", unlabeled.count)
unlabeled.forEach { print("UNLABELED", $0) }
