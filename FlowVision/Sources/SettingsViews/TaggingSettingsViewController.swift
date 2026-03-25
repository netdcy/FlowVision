//
//  DemoSettingsViewController.swift
//  FlowVision
//

import Settings
import Cocoa

final class TaggingSettingsViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.tagging
    let paneTitle = NSLocalizedString("Tagging", comment: "标签（设置里的面板）")
    let toolbarItemIcon = NSImage(systemSymbolName: "tag", accessibilityDescription: "")!

    override var nibName: NSNib.Name? { "TaggingSettingsViewController" }
    
    @IBOutlet weak var customTagView: CustomTagView!
    @IBOutlet weak var learnMoreButton: LearnMoreClickableLabel!
    @IBOutlet weak var enableEnhancedIndexCheckbox: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        enableEnhancedIndexCheckbox.state = globalVar.enhancedIndexEnabled ? .on : .off
        learnMoreButton.onClick = { [weak self] in
            getAnyViewController()?.handleTagLearnMore()
        }
    }

    @IBAction func enableEnhancedIndexToggled(_ sender: NSButton) {
        globalVar.enhancedIndexEnabled = (sender.state == .on)
        UserDefaults.standard.set(globalVar.enhancedIndexEnabled, forKey: "enhancedIndexEnabled")
        if globalVar.enhancedIndexEnabled {
            EnhancedIndex.initialize()
        }
    }

}

// MARK: - CustomTagView

class CustomTagView: NSView {
    
    static let userDefaultsKey = "customLabels"
    private static let dragType = NSPasteboard.PasteboardType("com.flowvision.customTagRow")
    
    fileprivate var tags: [(name: String, colorIndex: Int?)] = []
    private var tableView: NSTableView!
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 215)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        loadTags()
        setupUI()
    }
    
    private func loadTags() {
        tags = FinderTag.customLabels
    }
    
    fileprivate func applyAndSave() {
        FinderTag.customLabels = tags
        let encoded: [[String: Any]] = tags.map { tag in
            var d: [String: Any] = ["name": tag.name]
            if let c = tag.colorIndex { d["colorIndex"] = c }
            return d
        }
        UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.draggingDestinationFeedbackStyle = .regular
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Tag"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        
        let plusImage = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add") ?? NSImage()
        let minusImage = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove") ?? NSImage()
        let editControl = NSSegmentedControl(images: [plusImage, minusImage], trackingMode: .momentary, target: self, action: #selector(editControlClicked(_:)))
        editControl.setWidth(24, forSegment: 0)
        editControl.setWidth(24, forSegment: 1)
        editControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editControl)
        
        let resetBtn = NSButton(title: NSLocalizedString("Reset", comment: "重置"), target: self, action: #selector(resetTags))
        resetBtn.bezelStyle = .rounded
        //resetBtn.controlSize = .small
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resetBtn)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: editControl.topAnchor, constant: -4),
            
            editControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            editControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            resetBtn.trailingAnchor.constraint(equalTo: trailingAnchor),
            resetBtn.centerYAnchor.constraint(equalTo: editControl.centerYAnchor),
        ])
    }
    
    @objc private func editControlClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: addTag()
        case 1: removeSelected()
        default: break
        }
    }
    
    // MARK: - Actions
    
    private func addTag() {
        let base = NSLocalizedString("New Tag", comment: "新标签")
        var name = base
        var i = 1
        while tags.contains(where: { $0.name == name }) { i += 1; name = "\(base) \(i)" }
        tags.append((name, nil))
        applyAndSave()
        tableView.reloadData()
        let row = tags.count - 1
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let cell = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TagItemCellView {
                self.window?.makeFirstResponder(cell.nameField)
                cell.nameField.selectText(nil)
            }
        }
    }
    
    private func removeSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < tags.count else { return }
        tags.remove(at: row)
        applyAndSave()
        tableView.reloadData()
        if !tags.isEmpty {
            tableView.selectRowIndexes(
                IndexSet(integer: min(row, tags.count - 1)),
                byExtendingSelection: false
            )
        }
    }
    
    @objc private func resetTags() {
        tags = FinderTag.systemColorLabels.map { ($0.name, $0.colorIndex) }
        applyAndSave()
        tableView.reloadData()
    }
    
    // MARK: - Color Menu
    
    fileprivate func showColorMenu(for row: Int, relativeTo button: NSView) {
        guard row >= 0, row < tags.count else { return }
        let menu = NSMenu()
        // 0=None, 1=Gray, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Red, 7=Orange
        let colorIndices: [Int?] = [6, 7, 5, 2, 4, 3, 1, nil]
        for ci in colorIndices {
            let title: String
            let color: NSColor
            if let ci, ci > 0, ci < FILE_LABELS.count, ci < FILE_LABEL_COLORS.count {
                title = FILE_LABELS[ci]
                color = FILE_LABEL_COLORS[ci]
            } else {
                title = NSLocalizedString("No Color", comment: "无颜色")
                color = FinderTag.defaultLabelColor
            }
            let item = NSMenuItem(title: title, action: #selector(colorPicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = ci ?? -1
            item.representedObject = row
            item.image = FinderTag.makeDotImageWithBorder(for: color)
            if tags[row].colorIndex == ci { item.state = .on }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
    
    @objc private func colorPicked(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int,
              row >= 0, row < tags.count else { return }
        tags[row].colorIndex = sender.tag == -1 ? nil : sender.tag
        applyAndSave()
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension CustomTagView: NSTableViewDataSource, NSTableViewDelegate {
    
    func numberOfRows(in tableView: NSTableView) -> Int { tags.count }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("TagItem")
        let cell: TagItemCellView = tableView.makeView(withIdentifier: id, owner: nil) as? TagItemCellView
            ?? { let c = TagItemCellView(); c.identifier = id; return c }()
        cell.configure(tag: tags[row], row: row, owner: self)
        return cell
    }
    
    // MARK: Drag & Drop
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.dragType)
        return item
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        op == .above ? .move : []
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let str = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.dragType),
              let src = Int(str) else { return false }
        let tag = tags.remove(at: src)
        let dst = src < row ? row - 1 : row
        tags.insert(tag, at: dst)
        applyAndSave()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: dst), byExtendingSelection: false)
        return true
    }
}

// MARK: - TagItemCellView

fileprivate class TagItemCellView: NSTableCellView, NSTextFieldDelegate {
    
    let colorButton = NSButton()
    let nameField = NSTextField()
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private weak var owner: CustomTagView?
    private var previousName = ""
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupSubviews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }
    
    private func setupSubviews() {
        colorButton.isBordered = false
        colorButton.imagePosition = .imageOnly
        colorButton.imageScaling = .scaleNone
        colorButton.target = self
        colorButton.action = #selector(colorTapped)
        colorButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(colorButton)
        
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.isEditable = true
        nameField.focusRingType = .none
        nameField.font = .systemFont(ofSize: 13)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameField)
        self.textField = nameField
        
        shortcutLabel.font = .systemFont(ofSize: 12)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shortcutLabel)
        
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        deleteButton.contentTintColor = .tertiaryLabelColor
        deleteButton.imagePosition = .imageOnly
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isHidden = true
        addSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            colorButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            colorButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorButton.widthAnchor.constraint(equalToConstant: 18),
            colorButton.heightAnchor.constraint(equalToConstant: 18),
            
            nameField.leadingAnchor.constraint(equalTo: colorButton.trailingAnchor, constant: 4),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.trailingAnchor.constraint(equalTo: shortcutLabel.leadingAnchor, constant: -4),
            
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -2),
            
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 16),
            deleteButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }
    
    func configure(tag: (name: String, colorIndex: Int?), row: Int, owner: CustomTagView) {
        self.owner = owner
        previousName = tag.name
        nameField.stringValue = tag.name
        deleteButton.isHidden = true
        shortcutLabel.stringValue = row < 9 ? "⌘\(row + 1)" : ""
        
        let dotColor: NSColor
        if let ci = tag.colorIndex, ci > 0, ci < FILE_LABEL_COLORS.count {
            dotColor = FILE_LABEL_COLORS[ci]
        } else {
            dotColor = FinderTag.defaultLabelColor
        }
        colorButton.image = FinderTag.makeDotImageWithBorder(for: dotColor)
    }
    
    private var enclosingTableView: NSTableView? {
        var v: NSView? = superview
        while let s = v {
            if let tv = s as? NSTableView { return tv }
            v = s.superview
        }
        return nil
    }
    
    private var currentRow: Int {
        enclosingTableView?.row(for: self) ?? -1
    }
    
    @objc private func colorTapped() {
        let row = currentRow
        guard row >= 0 else { return }
        owner?.showColorMenu(for: row, relativeTo: colorButton)
    }
    
    @objc private func deleteTapped() {
        let row = currentRow
        guard let owner, row >= 0, row < owner.tags.count else { return }
        owner.tags.remove(at: row)
        owner.applyAndSave()
        enclosingTableView?.reloadData()
    }
    
    private static let forbiddenCharacters = CharacterSet(charactersIn: "/:\\,\n\r\t\0")
    
    func controlTextDidEndEditing(_ obj: Notification) {
        let row = currentRow
        guard let owner, row >= 0, row < owner.tags.count else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.rangeOfCharacter(from: Self.forbiddenCharacters) != nil {
            nameField.stringValue = previousName
            if !name.isEmpty {
                NSSound.beep()
            }
            return
        }
        owner.tags[row].name = name
        previousName = name
        owner.applyAndSave()
    }
    
    override func mouseEntered(with event: NSEvent) {
        deleteButton.isHidden = false
    }
    
    override func mouseExited(with event: NSEvent) {
        deleteButton.isHidden = true
    }
}

// MARK: - ClickableLabel

class LearnMoreClickableLabel: NSTextField {
    var onClick: (() -> Void)?
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
