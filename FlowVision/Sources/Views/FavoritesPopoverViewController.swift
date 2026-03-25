//
//  FavoritesPopoverViewController.swift
//  FlowVision
//

import Cocoa

private class FavoritesSeparatorCellView: NSTableCellView {
    let separatorLine = NSBox()
    let deleteButton = NSButton()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        separatorLine.boxType = .separator
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separatorLine)
        
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        deleteButton.isBordered = false
        deleteButton.setButtonType(.momentaryChange)
        deleteButton.contentTintColor = .tertiaryLabelColor
        addSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            separatorLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separatorLine.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            separatorLine.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
}

private class FavoritesCellView: NSTableCellView {
    let folderIconView = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    let pathLabel = NSTextField(labelWithString: "")
    let deleteButton = NSButton()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        folderIconView.translatesAutoresizingMaskIntoConstraints = false
        folderIconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(folderIconView)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isEditable = false
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.maximumNumberOfLines = 1
        addSubview(nameLabel)
        
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.isEditable = false
        pathLabel.isBezeled = false
        pathLabel.drawsBackground = false
        pathLabel.maximumNumberOfLines = 1
        addSubview(pathLabel)
        
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        deleteButton.isBordered = false
        deleteButton.setButtonType(.momentaryChange)
        deleteButton.contentTintColor = .tertiaryLabelColor
        addSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            folderIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            folderIconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            folderIconView.widthAnchor.constraint(equalToConstant: 28),
            folderIconView.heightAnchor.constraint(equalToConstant: 28),
            
            nameLabel.leadingAnchor.constraint(equalTo: folderIconView.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            pathLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
}

class FavoritesPopoverViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    static let separatorValue = "__SEPARATOR__"
    
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let addButton = NSButton()
    private let addSeparatorButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "")
    private static let dragType = NSPasteboard.PasteboardType("com.flowvision.favorites.row")
    private static let cellId = NSUserInterfaceItemIdentifier("FavoritesCellView")
    private static let separatorCellId = NSUserInterfaceItemIdentifier("FavoritesSeparatorCellView")
    
    weak var popover: NSPopover?
    var onNavigate: ((String) -> Void)?
    var onGetCurrentFolder: (() -> String?)?
    
    override func loadView() {
        self.view = NSView(frame: .zero)
        self.preferredContentSize = NSSize(width: 400, height: 600)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        updateAddButtonState()
        tableView.reloadData()
        updateEmptyState()
    }
    
    private func setupUI() {
        addButton.bezelStyle = .rounded
        addButton.title = " " + NSLocalizedString("Add Current Folder", comment: "添加当前文件夹")
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.target = self
        addButton.action = #selector(addCurrentFolder)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.focusRingType = .none
        view.addSubview(addButton)
        
        addSeparatorButton.bezelStyle = .rounded
        addSeparatorButton.title = " " + NSLocalizedString("Add Separator", comment: "添加分隔线")
        addSeparatorButton.image = NSImage(systemSymbolName: "line.horizontal.3", accessibilityDescription: nil)
        addSeparatorButton.imagePosition = .imageLeading
        addSeparatorButton.target = self
        addSeparatorButton.action = #selector(addSeparator)
        addSeparatorButton.translatesAutoresizingMaskIntoConstraints = false
        addSeparatorButton.focusRingType = .none
        view.addSubview(addSeparatorButton)
        
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FavoritesColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 48
        tableView.target = self
        tableView.action = #selector(tableViewClicked(_:))
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.draggingDestinationFeedbackStyle = .regular
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.backgroundColor = .clear
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        view.addSubview(scrollView)
        
        emptyLabel.stringValue = NSLocalizedString("empty-enclose", comment: "菜单当内容为空时显示的东西")
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        
        NSLayoutConstraint.activate([
            addButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            
            addSeparatorButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            addSeparatorButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            
            separator.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 40),
        ])
    }
    
    private func updateEmptyState() {
        emptyLabel.isHidden = !globalVar.myFavoritesArray.isEmpty
    }
    
    private func updateAddButtonState() {
        if let curFolder = onGetCurrentFolder?() {
            let isFavorited = globalVar.myFavoritesArray.contains(curFolder)
            if isFavorited {
                addButton.title = " " + NSLocalizedString("Remove Current Folder", comment: "移除当前文件夹")
                addButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil)
            } else {
                addButton.title = " " + NSLocalizedString("Add Current Folder", comment: "添加当前文件夹")
                addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            }
            addButton.isEnabled = true
        } else {
            addButton.title = " " + NSLocalizedString("Add Current Folder", comment: "添加当前文件夹")
            addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            addButton.isEnabled = false
        }
    }
    
    private func saveFavorites() {
        UserDefaults.standard.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
    }
    
    private func displayPath(for folderPath: String) -> String {
        var result = folderPath.replacingOccurrences(of: "file://", with: "")
        result = result.removingPercentEncoding ?? result
        result = result.replacingOccurrences(of: "/VirtualFinderTagsFolder", with: NSLocalizedString("Finder Tags", comment: "Finder标签"))
        if result.count > 1 && result.hasSuffix("/") {
            result = String(result.dropLast())
        }
        return result
    }
    
    private func folderName(for folderPath: String) -> String {
        let path = displayPath(for: folderPath)
        if path == "/" { return "/" }
        return (path as NSString).lastPathComponent
    }
    
    private func folderIcon(for folderPath: String) -> NSImage {
        if folderPath.contains("VirtualFinderTagsFolder") {
            return NSImage(systemSymbolName: "tag.fill", accessibilityDescription: nil)
                ?? NSImage(named: NSImage.folderName)!
        }
        var filePath = folderPath.replacingOccurrences(of: "file://", with: "")
        filePath = filePath.removingPercentEncoding ?? filePath
        let icon = NSWorkspace.shared.icon(forFile: filePath)
        icon.size = NSSize(width: 28, height: 28)
        return icon
    }
    
    // MARK: - Actions
    
    @objc private func addSeparator() {
        globalVar.myFavoritesArray.insert(Self.separatorValue, at: 0)
        saveFavorites()
        tableView.reloadData()
        updateEmptyState()
    }
    
    @objc private func addCurrentFolder() {
        guard let curFolder = onGetCurrentFolder?() else { return }
        if let index = globalVar.myFavoritesArray.firstIndex(of: curFolder) {
            globalVar.myFavoritesArray.remove(at: index)
        } else {
            globalVar.myFavoritesArray.insert(curFolder, at: 0)
        }
        saveFavorites()
        tableView.reloadData()
        updateEmptyState()
        updateAddButtonState()
    }
    
    @objc private func tableViewClicked(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0, row < globalVar.myFavoritesArray.count else { return }
        let folderPath = globalVar.myFavoritesArray[row]
        if folderPath == Self.separatorValue { return }
        onNavigate?(folderPath)
        popover?.close()
    }
    
    @objc private func deleteItem(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < globalVar.myFavoritesArray.count else { return }
        globalVar.myFavoritesArray.remove(at: row)
        saveFavorites()
        tableView.reloadData()
        updateEmptyState()
        updateAddButtonState()
    }
    
    // MARK: - NSTableViewDataSource
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return globalVar.myFavoritesArray.count
    }
    
    // MARK: - NSTableViewDelegate
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < globalVar.myFavoritesArray.count else { return nil }
        let folderPath = globalVar.myFavoritesArray[row]
        
        if folderPath == Self.separatorValue {
            let cellView: FavoritesSeparatorCellView
            if let existing = tableView.makeView(withIdentifier: Self.separatorCellId, owner: self) as? FavoritesSeparatorCellView {
                cellView = existing
            } else {
                cellView = FavoritesSeparatorCellView()
                cellView.identifier = Self.separatorCellId
            }
            cellView.deleteButton.tag = row
            cellView.deleteButton.target = self
            cellView.deleteButton.action = #selector(deleteItem(_:))
            return cellView
        }
        
        let cellView: FavoritesCellView
        if let existing = tableView.makeView(withIdentifier: Self.cellId, owner: self) as? FavoritesCellView {
            cellView = existing
        } else {
            cellView = FavoritesCellView()
            cellView.identifier = Self.cellId
        }
        
        cellView.folderIconView.image = folderIcon(for: folderPath)
        cellView.nameLabel.stringValue = folderName(for: folderPath)
        cellView.pathLabel.stringValue = displayPath(for: folderPath)
        cellView.deleteButton.tag = row
        cellView.deleteButton.target = self
        cellView.deleteButton.action = #selector(deleteItem(_:))
        cellView.toolTip = displayPath(for: folderPath)
        
        return cellView
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < globalVar.myFavoritesArray.count else { return 48 }
        return globalVar.myFavoritesArray[row] == Self.separatorValue ? 24 : 48
    }
    
    // MARK: - Drag & Drop
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.dragType)
        return item
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return []
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let items = info.draggingPasteboard.pasteboardItems,
              let item = items.first,
              let rowString = item.string(forType: Self.dragType),
              let sourceRow = Int(rowString) else { return false }
        
        let movedItem = globalVar.myFavoritesArray.remove(at: sourceRow)
        let destinationRow = sourceRow < row ? row - 1 : row
        globalVar.myFavoritesArray.insert(movedItem, at: destinationRow)
        saveFavorites()
        
        tableView.reloadData()
        return true
    }
}
