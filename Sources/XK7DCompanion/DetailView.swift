import AppKit
import XK7DCore

/// The right-hand pane: one setting, its index pickers, an editor for its value, and what the
/// manual says about it.
final class DetailView: NSView {
    weak var model: AppModel?
    private let stack = NSStackView()
    private var parameter: Parameter?
    private var indexPopups: [NSPopUpButton] = []
    private var choicePopup: NSPopUpButton?
    private var slider: ParameterSlider?
    private var valueLabel: NSTextField?
    private var typedField: NSTextField?
    private var textField: NSTextField?
    private var choiceHasPlaceholder = false

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(false)
        show(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var setting: Setting? {
        guard let p = parameter else { return nil }
        let values = zip(p.indices, indexPopups).map { dim, popup in dim.options[max(popup.indexOfSelectedItem, 0)].raw }
        return Setting(p, indexValues: values)
    }

    func show(_ p: Parameter?) {
        parameter = p
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        indexPopups = []; choicePopup = nil; slider = nil; valueLabel = nil; typedField = nil; textField = nil
        guard let p else {
            stack.addArrangedSubview(makeLabel("Select a setting in the list to see and change it.", wraps: true))
            return
        }
        let title = makeLabel(p.name, bold: true)
        title.font = .boldSystemFont(ofSize: 17)
        title.setAccessibilityRole(.staticText)
        stack.addArrangedSubview(title)
        let sectionName = p.section == .patch ? "Patch setting" : (p.section == .custom ? "Custom set setting" : "System setting")
        stack.addArrangedSubview(makeLabel("\(sectionName), \(p.category).", wraps: true))

        for dim in p.indices {
            let label = makeLabel("\(dim.name):")
            let popup = NSPopUpButton()
            popup.addItems(withTitles: dim.options.map { IndexDimension.spoken($0.label) })
            popup.target = self
            popup.action = #selector(indexChanged)
            popup.setAccessibilityLabel(dim.name)
            popup.toolTip = "Choose which \(dim.name.lowercased()) to see and change."
            popup.setAccessibilityHelp(popup.toolTip)
            indexPopups.append(popup)
            stack.addArrangedSubview(row([label, popup]))
        }

        let help = editorHelp(p)
        switch p.kind {
        case .text(let length):
            let field = NSTextField(string: "")
            field.placeholderString = "Up to \(length) letters"
            field.setAccessibilityLabel(p.name)
            field.toolTip = "Type a new name, up to \(length) plain letters, then press Return or Send Name. \(help)"
            field.setAccessibilityHelp(field.toolTip)
            field.target = self
            field.action = #selector(sendText)
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
            textField = field
            let send = makeButton("Send Name", help: "Sends this name to the organ.", target: self, action: #selector(sendText))
            stack.addArrangedSubview(row([makeLabel("\(p.name):"), field, send]))
        case .choices(let options):
            let popup = NSPopUpButton()
            popup.target = self
            popup.action = #selector(choiceChanged)
            popup.addItems(withTitles: options.map(\.label))
            popup.setAccessibilityLabel(p.name)
            popup.toolTip = "Choosing a value sends it to the organ straight away. \(help)"
            popup.setAccessibilityHelp(popup.toolTip)
            choicePopup = popup
            stack.addArrangedSubview(row([makeLabel("\(p.name):"), popup]))
        default:
            let s = ParameterSlider()
            s.setAccessibilityLabel(p.name)
            s.toolTip = "Arrow keys change the value by one step, Page Up and Page Down by ten percent, Home and End go to the ends. Each change is sent to the organ. \(help)"
            s.setAccessibilityHelp(s.toolTip)
            s.onCommit = { [weak self] raw in self?.commit(raw) }
            s.onUnknownStep = { [weak self] in
                self?.model?.announcer.announce("Not heard yet, so nothing was sent. Type a value below, or change it on the organ so the app hears it.", force: true)
            }
            s.target = self
            s.action = #selector(sliderMoved)
            s.widthAnchor.constraint(equalToConstant: 300).isActive = true
            slider = s
            let vl = makeLabel("")
            vl.setAccessibilityLabel("Current value")
            valueLabel = vl
            stack.addArrangedSubview(row([makeLabel("\(p.name):"), s, vl]))
            do {
                let typed = NSTextField(string: "")
                typed.placeholderString = typedPlaceholder(p)
                typed.setAccessibilityLabel("Type a value for \(p.name)")
                typed.toolTip = "Type a value the way the organ shows it, for example \(typedPlaceholder(p)), and press Return to send it."
                typed.setAccessibilityHelp(typed.toolTip)
                typed.target = self
                typed.action = #selector(typedValue)
                typed.widthAnchor.constraint(equalToConstant: 140).isActive = true
                typedField = typed
                stack.addArrangedSubview(row([makeLabel("Type a value:"), typed]))
            }
        }

        if !p.help.isEmpty { stack.addArrangedSubview(makeLabel(p.help, wraps: true)) }
        stack.addArrangedSubview(makeLabel("Range: \(rangeText(p)).", wraps: true))
        if let notes = p.notes {
            let n = makeLabel("Manual note: \(notes)", wraps: true, selectable: true)
            n.setAccessibilityLabel("Note about this setting")
            stack.addArrangedSubview(n)
        }
        let source = makeLabel(describeManualSource(p, setting: setting!), wraps: true, selectable: true)
        source.textColor = .secondaryLabelColor
        stack.addArrangedSubview(source)
        refreshValue()
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.spacing = 8
        return r
    }

    private func editorHelp(_ p: Parameter) -> String {
        p.help.isEmpty ? "Range: \(rangeText(p))." : p.help
    }

    private func rangeText(_ p: Parameter) -> String {
        switch p.kind {
        case .text(let n): return "up to \(n) characters"
        case .choices(let o): return o.count <= 8 ? o.map(\.label).joined(separator: ", ") : "\(o.first!.label) to \(o.last!.label), \(o.count) choices"
        case .steps(_, _, let low, let high):
            return "\(low) to \(high) in \(p.rawRange.count - 1) steps; the manual does not give the values in between"
        default: return "\(p.display(p.rawRange.lowerBound)) to \(p.display(p.rawRange.upperBound))"
        }
    }

    private func typedPlaceholder(_ p: Parameter) -> String {
        let mid = (p.rawRange.lowerBound + p.rawRange.upperBound) / 2
        return p.display(mid)
    }

    /// The setting on show, if any (so the window only refreshes this pane when it changed).
    var shownAddress: Address? { setting?.address }

    /// Show what the session knows for the current setting.
    func refreshValue() {
        guard let p = parameter, let s = setting, let model else { return }
        if p.isText {
            if let field = textField, field.currentEditor() == nil {
                field.stringValue = model.session.text(of: s) ?? ""
                field.placeholderString = model.session.text(of: s) == nil ? "Not heard yet; up to 16 letters" : "Up to 16 letters"
            }
            return
        }
        let raw = model.session.value(of: s)
        if let popup = choicePopup, case .choices(let options) = p.kind {
            if let raw, let i = options.firstIndex(where: { $0.raw == raw }) {
                if choiceHasPlaceholder { popup.removeItem(at: 0); choiceHasPlaceholder = false }
                if popup.indexOfSelectedItem != i { popup.selectItem(at: i) }
            } else if !choiceHasPlaceholder {
                popup.insertItem(withTitle: "Not heard yet", at: 0)
                popup.item(at: 0)?.isEnabled = false
                popup.selectItem(at: 0)
                choiceHasPlaceholder = true
            }
        }
        if let slider {
            slider.configure(p, raw: raw)
            valueLabel?.stringValue = raw.map { p.display($0) } ?? "Not heard yet"
        }
    }

    // MARK: Actions

    @objc private func indexChanged() {
        // VoiceOver reads the value control itself when you move to it; no extra speech here.
        refreshValue()
    }

    @objc private func choiceChanged() {
        guard let popup = choicePopup, let p = parameter, case .choices(let options) = p.kind else { return }
        var i = popup.indexOfSelectedItem
        if choiceHasPlaceholder { i -= 1 }
        guard i >= 0, i < options.count else { return }
        commit(options[i].raw)
    }

    @objc private func sliderMoved() {
        guard let slider else { return }
        slider.known = true
        slider.refreshDescription()
        commit(slider.raw)
    }

    @objc private func typedValue() {
        guard let p = parameter, let field = typedField else { return }
        guard let raw = parse(field.stringValue, for: p) else {
            NSSound.beep()
            model?.announcer.announce("Not a value for \(p.name). Range \(rangeText(p)).", force: true)
            return
        }
        commit(raw)
        field.stringValue = ""
        // VoiceOver says nothing when a text field is submitted, so confirm what was sent.
        if let s = setting, model?.isConnected == true {
            model?.announcer.announce("\(s.spokenName): \(p.spoken(s.parameter.clamp(raw)))", force: true)
        }
    }

    @objc private func sendText() {
        guard let s = setting, let field = textField, let model else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        // An empty field is most likely an accidental Return; sending it would blank the name.
        guard !name.isEmpty else {
            model.announcer.announce("Type a name first. Nothing was sent.", force: true)
            return
        }
        model.send(s, text: name)
        if model.isConnected { model.announcer.announce("\(s.spokenName) sent: \(model.session.text(of: s) ?? name)", force: true) }
    }

    private func commit(_ raw: Int) {
        guard let s = setting else { return }
        model?.send(s, raw: s.parameter.clamp(raw))
        valueLabel?.stringValue = s.parameter.display(s.parameter.clamp(raw))
        slider?.refreshDescription()
    }

    func parse(_ text: String, for p: Parameter) -> Int? { p.rawValue(fromTyped: text) }
}
