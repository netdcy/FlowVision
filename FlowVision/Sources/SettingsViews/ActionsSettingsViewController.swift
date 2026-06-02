//
//  ActionsSettingsViewController.swift
//  FlowVision
//
//  Two-column NSTableView. Each action shows one primary row + N extra rows,
//  one per additional bound chord. Primary row has [recorder][+][R]; extras
//  show [recorder][-]. Pending empty slots (from clicking +) live in the
//  controller until the user records into them.
//

import Settings
import Cocoa

private enum SettingsRow {
    case category(ShortcutCategory)
    /// `index` is the position within the action's chord list. Index 0 is the
    /// primary row (shows [+] and [R]); indices >= 1 are extra rows (show [-]).
    case actionSlot(ShortcutAction, index: Int)
}

final class ActionsSettingsViewController: NSViewController, SettingsPane,
                                           NSTableViewDataSource, NSTableViewDelegate,
                                           NSSearchFieldDelegate {
    let paneIdentifier = Settings.PaneIdentifier.actions
    let paneTitle = NSLocalizedString("Actions", comment: "操作（设置里的面板）")
    let toolbarItemIcon = NSImage(systemSymbolName: "keyboard.badge.ellipsis",
                                   accessibilityDescription: "")!

    override var nibName: NSNib.Name? { nil }

    // MARK: - Controls

    private let radioEnterKeyRename = NSButton(radioButtonWithTitle:
        NSLocalizedString("Rename", comment: ""), target: nil, action: nil)
    private let radioEnterKeyOpen   = NSButton(radioButtonWithTitle:
        NSLocalizedString("Open / Close", comment: ""), target: nil, action: nil)
    private let searchField = NSSearchField()
    private let tableView = NSTableView()

    private var rows: [SettingsRow] = []
    private var filterText = ""
    private var shortcutsObserver: NSObjectProtocol?

    /// Empty recorder rows the user added via [+] that haven't been filled yet.
    /// Keyed by action. Count = number of trailing empty slots beyond stored chords.
    private var pendingExtraSlots: [ShortcutAction: Int] = [:]

    private static let nameColumnId    = NSUserInterfaceItemIdentifier("name")
    private static let bindingColumnId = NSUserInterfaceItemIdentifier("binding")

    // MARK: - View

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 760))
        root.autoresizingMask = [.width, .height]
        preferredContentSize = NSSize(width: 500, height: 760)

        let enterLabel = NSTextField(labelWithString:
            NSLocalizedString("Enter Key:", comment: ""))
        enterLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

        radioEnterKeyRename.tag = 0
        radioEnterKeyOpen.tag   = 1
        radioEnterKeyRename.target = self
        radioEnterKeyRename.action = #selector(enterKeyToOpenToggled(_:))
        radioEnterKeyOpen.target   = self
        radioEnterKeyOpen.action   = #selector(enterKeyToOpenToggled(_:))

        let radioStack = NSStackView(views: [
            enterLabel, radioEnterKeyRename, radioEnterKeyOpen,
        ])
        radioStack.orientation = .horizontal
        radioStack.spacing = 12

        searchField.delegate = self
        searchField.placeholderString =
            NSLocalizedString("Search shortcuts…", comment: "")

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.allowsColumnReordering = false
        tableView.allowsColumnSelection = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.style = .inset
        tableView.floatsGroupRows = false
        tableView.headerView = nil

        let nameColumn = NSTableColumn(identifier: Self.nameColumnId)
        nameColumn.title = NSLocalizedString("Name", comment: "")
        nameColumn.minWidth = 120
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        tableView.addTableColumn(nameColumn)

        let bindingColumn = NSTableColumn(identifier: Self.bindingColumnId)
        bindingColumn.title = NSLocalizedString("Binding", comment: "")
        bindingColumn.minWidth = 220
        bindingColumn.width = 230
        bindingColumn.maxWidth = 280
        bindingColumn.resizingMask = [.userResizingMask]
        tableView.addTableColumn(bindingColumn)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let resetAllButton = NSButton(title:
            NSLocalizedString("Reset all to defaults", comment: ""),
            target: self, action: #selector(resetAllClicked(_:)))
        resetAllButton.bezelStyle = .rounded
        let bottomStack = NSStackView(views: [NSView(), resetAllButton])
        bottomStack.orientation = .horizontal
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        searchField.translatesAutoresizingMaskIntoConstraints = false
        let main = NSStackView(views: [radioStack, searchField, scroll, bottomStack])
        main.orientation = .vertical
        main.spacing = 12
        main.alignment = .leading
        main.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        main.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: root.topAnchor),
            main.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            main.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            searchField.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20),

            scroll.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 580),

            bottomStack.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 20),
            bottomStack.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        radioEnterKeyOpen.state   = globalVar.isEnterKeyToOpen ? .on  : .off
        radioEnterKeyRename.state = globalVar.isEnterKeyToOpen ? .off : .on

        convertToLeadingLayoutForRTL(view)

        rebuildRows()
        tableView.reloadData()

        shortcutsObserver = NotificationCenter.default.addObserver(
            forName: .shortcutsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            // A binding mutation can change the row count for an action.
            // Cheap, correct, and the table is small enough that a full
            // reload is fine.
            self?.rebuildRows()
            self?.tableView.reloadData()
        }
    }

    deinit {
        if let t = shortcutsObserver { NotificationCenter.default.removeObserver(t) }
    }

    // MARK: - Enter key + reset

    @objc func enterKeyToOpenToggled(_ sender: NSButton) {
        if sender.tag == 0 { globalVar.isEnterKeyToOpen = false }
        else if sender.tag == 1 { globalVar.isEnterKeyToOpen = true }
        UserDefaults.standard.set(globalVar.isEnterKeyToOpen, forKey: "isEnterKeyToOpen")
    }

    @objc func resetAllClicked(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Reset all shortcuts to defaults?", comment: "")
        alert.informativeText = NSLocalizedString(
            "This will discard all your custom keyboard shortcuts.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Reset", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            pendingExtraSlots.removeAll()
            ShortcutStore.shared.resetAll()
        }
    }

    fileprivate func resetRow(_ action: ShortcutAction) {
        pendingExtraSlots.removeValue(forKey: action)
        ShortcutStore.shared.reset(action)
    }

    fileprivate func addEmptySlot(_ action: ShortcutAction) {
        pendingExtraSlots[action, default: 0] += 1
        rebuildRows()
        tableView.reloadData()
    }

    fileprivate func removeSlot(_ action: ShortcutAction, at index: Int) {
        let stored = ShortcutStore.shared.chords(for: action).count
        if index < stored {
            ShortcutStore.shared.removeChord(at: index, for: action)
        } else {
            // Pending empty slot — pop one.
            if let n = pendingExtraSlots[action], n > 0 {
                pendingExtraSlots[action] = n - 1
                if pendingExtraSlots[action] == 0 {
                    pendingExtraSlots.removeValue(forKey: action)
                }
                rebuildRows()
                tableView.reloadData()
            }
        }
    }

    // MARK: - Recorder commit + conflict handling

    fileprivate func onRecordedChord(_ chord: KeyChord?,
                                      for action: ShortcutAction,
                                      at index: Int) {
        let stored = ShortcutStore.shared.chords(for: action)
        let isPendingSlot = index >= stored.count

        guard let chord else {
            // Clear: drop the slot. For a stored chord this removes the row.
            // For a pending empty slot it just decrements the counter.
            if isPendingSlot {
                removeSlot(action, at: index)
            } else {
                ShortcutStore.shared.setChord(nil, at: index, for: action)
            }
            return
        }

        // No-op when user re-records the same chord at the same slot.
        if !isPendingSlot && stored[index] == chord { return }

        // Reject any attempt to bind a chord that is the locked primary default
        // of another action (e.g. ⌘Q owned by quitApp). Locked primaries can't
        // be reassigned — would corrupt the locked action's UI state.
        if isLockedReservedDefault(chord, excluding: action) {
            showLockedReservedAlert(chord: chord)
            // Pending-slot path: the user opened an empty slot and the recorded
            // chord was rejected — drop the orphan slot so the table doesn't
            // accumulate stranded empty rows.
            if isPendingSlot { removeSlot(action, at: index) }
            rebuildRows()
            tableView.reloadData()
            return
        }

        // A duplicate is "blocking" only when both actions can fire in the same
        // runtime context. Cross-scope duplicates (e.g. browserOnly vs viewerOnly)
        // are harmless and commit silently.
        let blocking = (ShortcutStore.shared.reverseIndex[chord] ?? [])
            .filter { $0 != action && scopesOverlap($0.scope, action.scope) }
        let isSystemy = action.isSystemConventional || chord.isSystemReserved

        if !blocking.isEmpty {
            showConflictAlert(new: action, chord: chord, blocking: blocking,
                              at: index, isPendingSlot: isPendingSlot)
        } else if isSystemy {
            confirmSystemOverride(action: action, chord: chord,
                                   at: index, isPendingSlot: isPendingSlot)
        } else {
            commit(chord, action: action, at: index, isPendingSlot: isPendingSlot)
        }
    }

    private func isLockedReservedDefault(_ chord: KeyChord,
                                          excluding action: ShortcutAction) -> Bool {
        ShortcutAction.allCases.contains { other in
            other != action
                && other.hasLockedPrimary
                && other.defaultChords.first == chord
        }
    }

    private func showLockedReservedAlert(chord: KeyChord) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Reserved shortcut", comment: "")
        let fmt = NSLocalizedString("locked.reserved.body",
            value: "%@ is reserved by the system and cannot be reassigned.",
            comment: "%@ is chord glyphs")
        alert.informativeText = String(format: fmt, chord.displayString)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }

    private func scopesOverlap(_ a: ContextScope, _ b: ContextScope) -> Bool {
        a == .both || b == .both || a == b
    }

    private func commit(_ chord: KeyChord, action: ShortcutAction,
                        at index: Int, isPendingSlot: Bool) {
        if isPendingSlot {
            // Convert pending slot into a real stored chord.
            if let n = pendingExtraSlots[action], n > 0 {
                pendingExtraSlots[action] = n - 1
                if pendingExtraSlots[action] == 0 {
                    pendingExtraSlots.removeValue(forKey: action)
                }
            }
            ShortcutStore.shared.appendChord(chord, for: action)
        } else {
            ShortcutStore.shared.setChord(chord, at: index, for: action)
        }
    }

    private func showConflictAlert(new action: ShortcutAction, chord: KeyChord,
                                    blocking: [ShortcutAction],
                                    at index: Int, isPendingSlot: Bool) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Shortcut conflict", comment: "")
        let names = blocking.map { $0.displayName }.joined(separator: ", ")
        let fmt = NSLocalizedString("conflict.body",
            value: "%@ is already used by: %@.\nReassign?",
            comment: "%@ chord, %@ comma-separated names")
        alert.informativeText = String(format: fmt, chord.displayString, names)
        alert.addButton(withTitle: NSLocalizedString("Reassign", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            // Strip the conflicting chord from every blocker in one pass so the
            // table reloads once instead of N times.
            ShortcutStore.shared.batchRemove(chord: chord, from: blocking)
            commit(chord, action: action, at: index, isPendingSlot: isPendingSlot)
        } else {
            rebuildRows()
            tableView.reloadData()
        }
    }

    private func confirmSystemOverride(action: ShortcutAction, chord: KeyChord,
                                        at index: Int, isPendingSlot: Bool) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Override system-reserved shortcut?", comment: "")
        let fmt = NSLocalizedString("system.override.body",
            value: "%@ is conventionally used by macOS. Use it anyway?",
            comment: "")
        alert.informativeText = String(format: fmt, chord.displayString)
        alert.addButton(withTitle: NSLocalizedString("Use anyway", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            commit(chord, action: action, at: index, isPendingSlot: isPendingSlot)
        } else {
            rebuildRows()
            tableView.reloadData()
        }
    }

    // MARK: - Search

    func controlTextDidChange(_ obj: Notification) {
        filterText = searchField.stringValue.lowercased()
        rebuildRows()
        tableView.reloadData()
    }

    // MARK: - Row building

    private func slotCount(for action: ShortcutAction) -> Int {
        let stored = ShortcutStore.shared.chords(for: action).count
        let pending = pendingExtraSlots[action] ?? 0
        // Always show at least one row so the user can bind a chord for actions
        // with no current chords.
        return max(1, stored + pending)
    }

    private func rebuildRows() {
        var out: [SettingsRow] = []
        for cat in ShortcutCategory.allCases {
            let actions = ShortcutAction.allCases
                .filter { $0.category == cat }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                .filter { matchesFilter($0) }
            guard !actions.isEmpty else { continue }
            out.append(.category(cat))
            for action in actions {
                let count = slotCount(for: action)
                for i in 0..<count {
                    out.append(.actionSlot(action, index: i))
                }
            }
        }
        rows = out
    }

    private func matchesFilter(_ action: ShortcutAction) -> Bool {
        guard !filterText.isEmpty else { return true }
        if action.displayName.localizedCaseInsensitiveContains(filterText) { return true }
        if action.category.displayName.localizedCaseInsensitiveContains(filterText) { return true }
        return ShortcutStore.shared.chords(for: action).contains {
            $0.displayString.localizedCaseInsensitiveContains(filterText)
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .category = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .category = rows[row] { return 24 }
        return 28
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .category = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .category(let cat):
            if let col = tableColumn, col.identifier != Self.nameColumnId {
                return nil
            }
            let id = NSUserInterfaceItemIdentifier("CategoryCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
                let c = NSTableCellView()
                c.identifier = id
                let label = NSTextField(labelWithString: "")
                label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                label.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(label)
                c.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                    label.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor),
                ])
                return c
            }()
            cell.textField?.stringValue = cat.displayName
            return cell

        case .actionSlot(let action, let index):
            if tableColumn?.identifier == Self.nameColumnId {
                let id = NSUserInterfaceItemIdentifier("NameCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
                    let c = NSTableCellView()
                    c.identifier = id
                    let label = NSTextField(labelWithString: "")
                    label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    label.lineBreakMode = .byTruncatingTail
                    label.translatesAutoresizingMaskIntoConstraints = false
                    c.addSubview(label)
                    c.textField = label
                    NSLayoutConstraint.activate([
                        label.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8),
                        label.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                        label.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -4),
                    ])
                    return c
                }()
                // Only the primary slot (index 0) shows the action name.
                cell.textField?.stringValue = index == 0 ? action.displayName : ""
                return cell
            } else {
                let id = NSUserInterfaceItemIdentifier("BindingCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: self) as? BindingCell) ?? {
                    let c = BindingCell()
                    c.identifier = id
                    return c
                }()
                cell.configure(for: action, at: index, host: self)
                return cell
            }
        }
    }
}

// MARK: - Binding cell

private final class BindingCell: NSTableCellView {
    private let recorder = ShortcutRecorderView()
    private let plusButton  = NSButton(title: "+", target: nil, action: nil)
    private let minusButton = NSButton(title: "−", target: nil, action: nil)
    private let resetButton = NSButton(title: "↺", target: nil, action: nil)
    private let stack = NSStackView()
    private weak var host: ActionsSettingsViewController?
    private var action: ShortcutAction?
    private var index: Int = 0

    override init(frame: NSRect) {
        super.init(frame: frame)

        for b in [plusButton, minusButton, resetButton] {
            b.bezelStyle = .roundRect
            b.target = self
            b.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
        plusButton.action  = #selector(plusTapped)
        minusButton.action = #selector(minusTapped)
        resetButton.action = #selector(resetTapped)
        plusButton.toolTip  = NSLocalizedString("Add another shortcut", comment: "")
        minusButton.toolTip = NSLocalizedString("Remove this shortcut", comment: "")
        resetButton.toolTip = NSLocalizedString("Reset to default", comment: "")

        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .horizontal)
        addSubview(stack)
        // Add every button once at init; toggle `isHidden` per slot in configure.
        // NSStackView excludes hidden subviews from layout, so the visible buttons
        // shift left/right naturally.
        // Order keeps [-] at the same x as [+] (both immediately after recorder)
        // and [R] trails on the primary row only.
        stack.addArrangedSubview(recorder)
        stack.addArrangedSubview(plusButton)
        stack.addArrangedSubview(minusButton)
        stack.addArrangedSubview(resetButton)
        // Left-anchored so [recorder] and [+]/[-] sit at the same x position on
        // every row (primary vs extra).
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            recorder.widthAnchor.constraint(equalToConstant: 130),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func configure(for action: ShortcutAction, at index: Int,
                    host: ActionsSettingsViewController) {
        self.action = action
        self.index = index
        self.host = host

        let chords = ShortcutStore.shared.chords(for: action)
        let chordForSlot: KeyChord? = (index < chords.count) ? chords[index] : nil
        let isLockedPrimary = action.hasLockedPrimary && index == 0

        recorder.isEnabled = !isLockedPrimary
        recorder.toolTip = isLockedPrimary
            ? NSLocalizedString("This shortcut is system-locked. Use [+] to add alternates.",
                                comment: "locked recorder tooltip")
            : nil
        recorder.setChordSilent(chordForSlot)
        recorder.onChange = { [weak self, weak host] chord in
            guard let self, let host, let action = self.action else { return }
            host.onRecordedChord(chord, for: action, at: self.index)
        }

        // Toggle button visibility per slot.
        plusButton.isHidden  = index != 0
        resetButton.isHidden = index != 0
        minusButton.isHidden = index == 0
    }

    @objc private func plusTapped() {
        guard let action, let host else { return }
        host.addEmptySlot(action)
    }

    @objc private func minusTapped() {
        guard let action, let host else { return }
        host.removeSlot(action, at: index)
    }

    @objc private func resetTapped() {
        guard let action, let host else { return }
        host.resetRow(action)
    }
}
