import AppKit
import XK7DCore

func makeLabel(_ text: String, bold: Bool = false, wraps: Bool = false, selectable: Bool = false) -> NSTextField {
    let f = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
    if bold { f.font = .boldSystemFont(ofSize: NSFont.systemFontSize) }
    f.isSelectable = selectable
    if wraps { f.preferredMaxLayoutWidth = 520; f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
    return f
}

func makeButton(_ title: String, help: String, target: AnyObject?, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: target, action: action)
    b.bezelStyle = .rounded
    b.toolTip = help
    b.setAccessibilityHelp(help)
    return b
}

func describeManualSource(_ p: Parameter, setting: Setting) -> String {
    var s = "Manual page \(p.page): \(p.manualCategory), \(p.manualName). SysEx address \(setting.address)"
    if let n = p.nrpn, !p.hasIndices { s += String(format: ", NRPN %02X %02X", n.msb, n.lsb) }
    else if p.nrpn == nil { s += ", SysEx only (no NRPN)" }
    s += ", \(p.length == 16 ? "16 characters" : "\(p.length) data byte\(p.length == 1 ? "" : "s")")."
    if p.xk7Only { s += " Single-manual XK-7 only." }
    return s
}

/// A slider that steps one raw value per arrow key, speaks the organ's display value, and treats
/// "not heard yet" as a real state rather than pretending to know.
final class ParameterSlider: NSSlider {
    var parameter: Parameter!
    var known = false
    var onCommit: ((Int) -> Void)?

    var raw: Int {
        get { Int(doubleValue.rounded()) }
        set { doubleValue = Double(newValue); known = true; refreshDescription() }
    }

    func configure(_ p: Parameter, raw: Int?) {
        parameter = p
        minValue = Double(p.rawRange.lowerBound)
        maxValue = Double(p.rawRange.upperBound)
        isContinuous = true
        if let raw { self.raw = raw } else { doubleValue = minValue; known = false; refreshDescription() }
    }

    func refreshDescription() {
        let text = known ? parameter.spoken(raw) : "not heard yet"
        setAccessibilityValueDescription(text)
    }

    /// Called instead of sending when the value is unknown: any value we picked would be a guess,
    /// and the bottom of a range can be drastic on a real organ (0 rpm stops the Leslie horn).
    var onUnknownStep: (() -> Void)?

    private func step(_ delta: Int) {
        guard known else { onUnknownStep?(); return }
        let next = parameter.clamp(raw + delta)
        raw = next
        onCommit?(next)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 123, 125: step(-1)                      // left, down
        case 124, 126: step(1)                       // right, up
        case 116: step(max(1, (parameter.rawRange.count) / 10))   // page up
        case 121: step(-max(1, (parameter.rawRange.count) / 10))  // page down
        case 115: guard known else { onUnknownStep?(); return }; raw = parameter.rawRange.lowerBound; onCommit?(raw)   // home
        case 119: guard known else { onUnknownStep?(); return }; raw = parameter.rawRange.upperBound; onCommit?(raw)   // end
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool { step(1); return true }
    override func accessibilityPerformDecrement() -> Bool { step(-1); return true }
}
