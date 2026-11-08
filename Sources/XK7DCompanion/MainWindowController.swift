import AppKit
import XK7DCore

/// A row in the settings list: a category, or one parameter.
final class TreeNode {
    let title: String
    let parameter: Parameter?
    var children: [TreeNode]

    init(title: String, parameter: Parameter? = nil, children: [TreeNode] = []) {
        self.title = title
        self.parameter = parameter
        self.children = children
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    let model: AppModel
    private var fullTree: [TreeNode] = []
    private var shown: [TreeNode] = []
    private var nodeByID: [String: TreeNode] = [:]

    private let portPopup = NSPopUpButton()
    private let statusLabel = makeLabel("", wraps: true, selectable: true)
    private let speakCheckbox = NSButton(checkboxWithTitle: "Speak organ changes", target: nil, action: nil)
    let searchField = NSSearchField()
    let outline = NSOutlineView()
    private let detail = DetailView()
    private let historyTable = NSTableView()
    private var searchCountLabel = makeLabel("")

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.setFrameAutosaveName("MainWindow")
        window.minSize = NSSize(width: 820, height: 560)
        super.init(window: window)
        window.delegate = self
        buildTree()
        buildUI()
        detail.model = model
        refreshConnection()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(valuesChanged(_:)), name: .organValuesChanged, object: nil)
        nc.addObserver(self, selector: #selector(refreshConnection), name: .connectionChanged, object: nil)
        nc.addObserver(self, selector: #selector(historyChanged), name: .historyChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Tree

    private func buildTree() {
        var categories: [(String, [Parameter])] = []
        var index: [String: Int] = [:]
        for p in model.database.parameters {
            let title = p.section == .patch ? p.category : "\(p.section.rawValue): \(p.category)"
            if let i = index[title] { categories[i].1.append(p) } else { index[title] = categories.count; categories.append((title, [p])) }
        }
        fullTree = categories.map { title, params in
            let kids = params.map { p -> TreeNode in
                let n = TreeNode(title: p.name, parameter: p)
                nodeByID[p.id] = n
                return n
            }
            return TreeNode(title: title, children: kids)
        }
        shown = fullTree
    }

    func rowText(_ n: TreeNode) -> String {
        guard let p = n.parameter else {
            let count = n.children.count
            return "\(n.title), \(count) setting\(count == 1 ? "" : "s")"
        }
        if p.hasIndices {
            return "\(p.name): choose \(p.indices.map { $0.name.lowercased() }.joined(separator: " and "))"
        }
        let s = Setting(p)
        if p.isText { return "\(p.name): \(model.session.text(of: s).map { $0.isEmpty ? "blank" : $0 } ?? "not heard yet")" }
        return "\(p.name): \(model.session.value(of: s).map { p.display($0) } ?? "not heard yet")"
    }

    // MARK: Layout

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let organLabel = makeLabel("Organ:")
        portPopup.target = self
        portPopup.action = #selector(portChosen)
        portPopup.setAccessibilityLabel("Organ")
        portPopup.toolTip = "Choose the organ's USB MIDI port (it shows as XK-7 or similar), or the built-in simulator."
        portPopup.setAccessibilityHelp(portPopup.toolTip)

        let readButton = makeButton("Read from Organ", help: "Asks the organ to identify itself and send a memory dump. Command R.",
                                    target: NSApp.delegate, action: #selector(AppDelegate.readFromOrgan(_:)))
        let setupButton = makeButton("Set Up Organ for This App…", help: "Changes the organ's MIDI settings so it reports every change to this app. You choose which, and nothing is sent until you confirm.",
                                     target: NSApp.delegate, action: #selector(AppDelegate.setUpOrgan(_:)))
        speakCheckbox.target = self
        speakCheckbox.action = #selector(speakToggled)
        speakCheckbox.toolTip = "When on, changes made on the organ are spoken. Command Shift M turns this on and off."
        speakCheckbox.setAccessibilityHelp(speakCheckbox.toolTip)

        let top = NSStackView(views: [organLabel, portPopup, readButton, setupButton, speakCheckbox])
        top.orientation = .horizontal
        top.spacing = 10
        statusLabel.setAccessibilityLabel("Connection status")

        // Left: search and the list.
        searchField.placeholderString = "Search settings"
        searchField.setAccessibilityLabel("Search settings")
        searchField.toolTip = "Type any part of a setting's name, for example leslie horn or percussion. Press Return to go to the results. Command F comes here."
        searchField.setAccessibilityHelp(searchField.toolTip)
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("setting"))
        column.title = "Setting"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.rowSizeStyle = .default
        outline.setAccessibilityLabel("Settings")
        outline.toolTip = "Every setting the manual lists, by category. Each row shows its value. Press Tab to edit the selected setting."
        outline.setAccessibilityHelp(outline.toolTip)
        let outlineScroll = NSScrollView()
        outlineScroll.documentView = outline
        outlineScroll.hasVerticalScroller = true
        outlineScroll.borderType = .bezelBorder

        searchCountLabel.setAccessibilityLabel("Search results")
        let left = NSStackView(views: [searchField, searchCountLabel, outlineScroll])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 6
        outlineScroll.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        searchField.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true

        // Right: the selected setting.
        let detailScroll = NSScrollView()
        detailScroll.documentView = detail
        detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor).isActive = true

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(left)
        split.addArrangedSubview(detailScroll)
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        detailScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true

        // Bottom: history.
        let historyLabel = makeLabel("Recent announcements, newest first", bold: true)
        let hcol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        hcol.title = "Announcement"
        historyTable.addTableColumn(hcol)
        historyTable.headerView = nil
        historyTable.dataSource = self
        historyTable.delegate = self
        historyTable.setAccessibilityLabel("Recent announcements")
        historyTable.toolTip = "Everything the app has spoken, newest first, so you can read back anything you missed."
        let historyScroll = NSScrollView()
        historyScroll.documentView = historyTable
        historyScroll.hasVerticalScroller = true
        historyScroll.borderType = .bezelBorder

        let root = NSStackView(views: [top, statusLabel, split, historyLabel, historyScroll])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            split.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
            historyScroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
            historyScroll.heightAnchor.constraint(equalToConstant: 120),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
        ])
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        split.setHoldingPriority(.defaultLow + 1, forSubviewAt: 1)

        window?.autorecalculatesKeyViewLoop = true
        window?.initialFirstResponder = outline
    }

    // MARK: Actions

    @objc private func portChosen() {
        let choices = model.choices()
        let i = portPopup.indexOfSelectedItem
        guard i >= 0, i < choices.count else { return }
        model.choose(choices[i])
    }

    @objc private func speakToggled() {
        model.announcer.muted = speakCheckbox.state == .off
    }

    @objc func refreshConnection() {
        let choices = model.choices()
        portPopup.removeAllItems()
        portPopup.addItems(withTitles: choices.map(\.title))
        if let i = choices.firstIndex(of: model.choice) { portPopup.selectItem(at: i) }
        statusLabel.stringValue = model.statusText
        speakCheckbox.state = model.announcer.muted ? .off : .on
        let where_ = model.choice == .none ? "not connected" : model.choice.title
        window?.title = "\(AppIdentity.name) — \(where_)"
        detail.refreshValue()
    }

    @objc private func historyChanged() {
        historyTable.reloadData()
    }

    @objc private func valuesChanged(_ note: Notification) {
        var ids: [String] = []
        if let e = note.userInfo?["event"] as? OrganEvent {
            switch e {
            case .value(let s, _), .text(let s, _): ids = [s.parameter.id]
            case .drawbar(let part, let index, _):
                if let s = model.session.registrationSetting(part: part, index: index) { ids = [s.parameter.id] }
            default: return
            }
        }
        if ids.isEmpty {
            let visible = outline.rows(in: outline.visibleRect)
            if visible.length > 0 {
                outline.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                                   columnIndexes: [0])
            }
        } else {
            for id in ids { if let n = nodeByID[id] { outline.reloadItem(n) } }
            for id in ids {
                // Search results are separate nodes; refresh any that show this parameter.
                for n in shown where n.parameter?.id == id { outline.reloadItem(n) }
            }
        }
        // Only touch the editor when its own setting changed, so VoiceOver is not disturbed
        // while you are on a control.
        if let e = note.userInfo?["event"] as? OrganEvent, let shown = detail.shownAddress {
            switch e {
            case .value(let s, _), .text(let s, _): if s.address == shown { detail.refreshValue() }
            case .drawbar(let part, let index, _):
                if model.session.registrationSetting(part: part, index: index)?.address == shown { detail.refreshValue() }
            default: break
            }
        } else {
            detail.refreshValue()
        }
    }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    func focusList() {
        window?.makeFirstResponder(outline)
    }

    @objc private func searchChanged() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            shown = fullTree
            searchCountLabel.stringValue = ""
        } else {
            shown = model.database.search(q).map { TreeNode(title: $0.name, parameter: $0) }
            searchCountLabel.stringValue = shown.isEmpty ? "No settings match \(q)." :
                "\(shown.count) setting\(shown.count == 1 ? "" : "s") match \(q)."
        }
        outline.reloadData()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if control === searchField, sel == #selector(NSResponder.insertNewline(_:)) || sel == #selector(NSResponder.moveDown(_:)) {
            if !shown.isEmpty {
                window?.makeFirstResponder(outline)
                outline.selectRowIndexes([0], byExtendingSelection: false)
                outline.scrollRowToVisible(0)
            } else if !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                // Otherwise Return does nothing and says nothing.
                model.announcer.announce(searchCountLabel.stringValue, force: true)
            }
            return true
        }
        return false
    }

    /// Jump to a parameter by id (used by search and tests).
    func reveal(parameterID id: String) {
        guard let node = nodeByID[id], let parent = fullTree.first(where: { $0.children.contains { $0 === node } }) else { return }
        if shown.first !== fullTree.first { searchField.stringValue = ""; searchChanged() }
        outline.expandItem(parent)
        let row = outline.row(forItem: node)
        if row >= 0 {
            outline.selectRowIndexes([row], byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
    }

    // MARK: Outline data

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let n = item as? TreeNode else { return shown.count }
        return n.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let n = item as? TreeNode else { return shown[index] }
        return n.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? TreeNode)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? TreeNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let t = NSTextField(labelWithString: "")
            t.lineBreakMode = .byTruncatingTail
            t.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(t)
            c.textField = t
            NSLayoutConstraint.activate([
                t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                t.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        let text = rowText(n)
        cell.textField?.stringValue = text
        cell.textField?.font = n.parameter == nil ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        cell.toolTip = n.parameter.map { $0.help.isEmpty ? $0.name : $0.help }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let n = outline.item(atRow: outline.selectedRow) as? TreeNode
        detail.show(n?.parameter)
    }

    // MARK: History table

    func numberOfRows(in tableView: NSTableView) -> Int { model.history.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let t = NSTextField(labelWithString: model.history[row])
        t.lineBreakMode = .byTruncatingTail
        return t
    }

    /// Closing hides the window instead of quitting, so a stray Command W on stage doesn't stop
    /// the announcements.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        model.announcer.announce("Window hidden. Still listening.", force: true)
        return false
    }
}
