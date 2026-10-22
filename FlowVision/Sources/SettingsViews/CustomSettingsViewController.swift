//
//  GeneralSettingsViewController.swift
//  FlowVision
//

import Cocoa
import Settings

final class CustomSettingsViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.custom
    let paneTitle = NSLocalizedString("View", comment: "查看")
    let toolbarItemIcon = NSImage(systemSymbolName: "gear", accessibilityDescription: "")!

    override var nibName: NSNib.Name? { "CustomSettingsViewController" }

    @IBOutlet weak var randomFolderThumbCheckbox: NSButton!
    @IBOutlet weak var thumbnailOfFolderUseStackingCheckbox: NSButton!
    @IBOutlet weak var loopBrowsingCheckbox: NSButton!
    @IBOutlet weak var clickEdgeToSwitchImageCheckbox: NSButton!
    @IBOutlet weak var scrollMouseWheelToZoomCheckbox: NSButton!
    @IBOutlet weak var useInternalPlayerCheckbox: NSButton!
    @IBOutlet weak var usePinyinSearchCheckbox: NSButton!
    @IBOutlet weak var usePinyinInitialSearchCheckbox: NSButton!
    @IBOutlet weak var keepFilterStateWhenSwitchFolderCheckbox: NSButton!
    @IBOutlet weak var excludeContainerView: ThumbnailExcludeView!
    
    @IBOutlet weak var radioGlass: NSButton!
    @IBOutlet weak var radioBlack: NSButton!
    @IBOutlet weak var radioFullscreen: NSButton!
    @IBOutlet weak var radioGlassForVideo: NSButton!
    @IBOutlet weak var radioBlackForVideo: NSButton!
    @IBOutlet weak var radioFullscreenForVideo: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        randomFolderThumbCheckbox.state = globalVar.randomFolderThumb ? .on : .off
        thumbnailOfFolderUseStackingCheckbox.state = globalVar.thumbnailOfFolderUseStacking ? .on : .off
        loopBrowsingCheckbox.state = globalVar.loopBrowsing ? .on : .off
        clickEdgeToSwitchImageCheckbox.state = globalVar.clickEdgeToSwitchImage ? .on : .off
        scrollMouseWheelToZoomCheckbox.state = globalVar.scrollMouseWheelToZoom ? .on : .off
        useInternalPlayerCheckbox.state = globalVar.useInternalPlayer ? .on : .off
        usePinyinSearchCheckbox.state = globalVar.usePinyinSearch ? .on : .off
        usePinyinInitialSearchCheckbox.state = globalVar.usePinyinInitialSearch ? .on : .off
        keepFilterStateWhenSwitchFolderCheckbox.state = globalVar.keepFilterStateWhenSwitchFolder ? .on : .off
        
        globalVar.useInternalPlayerCheckbox = self.useInternalPlayerCheckbox
        
        radioGlass.state = (!globalVar.blackBgAlways && !globalVar.blackBgInFullScreen) ? .on : .off
        radioBlack.state = globalVar.blackBgAlways ? .on : .off
        radioFullscreen.state = (!globalVar.blackBgAlways && globalVar.blackBgInFullScreen) ? .on : .off
        radioGlassForVideo.state = (!globalVar.blackBgAlwaysForVideo && !globalVar.blackBgInFullScreenForVideo) ? .on : .off
        radioBlackForVideo.state = globalVar.blackBgAlwaysForVideo ? .on : .off
        radioFullscreenForVideo.state = (!globalVar.blackBgAlwaysForVideo && globalVar.blackBgInFullScreenForVideo) ? .on : .off

        // MARK: RTL support
        if let container = radioGlass.superview {
            convertToLeadingLayoutForRTL(container)
        }
        if let container = radioGlassForVideo.superview {
            convertToLeadingLayoutForRTL(container)
        }
    }
    
    @IBAction func randomFolderThumbToggled(_ sender: NSButton) {
        globalVar.randomFolderThumb = (sender.state == .on)
        UserDefaults.standard.set(globalVar.randomFolderThumb, forKey: "randomFolderThumb")
    }
    
    @IBAction func thumbnailOfFolderUseStackingToggled(_ sender: NSButton) {
        globalVar.thumbnailOfFolderUseStacking = (sender.state == .on)
        UserDefaults.standard.set(globalVar.thumbnailOfFolderUseStacking, forKey: "thumbnailOfFolderUseStacking")
    }
    
    @IBAction func loopBrowsingToggled(_ sender: NSButton) {
        globalVar.loopBrowsing = (sender.state == .on)
        UserDefaults.standard.set(globalVar.loopBrowsing, forKey: "loopBrowsing")
    }

    @IBAction func clickEdgeToSwitchImageToggled(_ sender: NSButton) {
        globalVar.clickEdgeToSwitchImage = (sender.state == .on)
        UserDefaults.standard.set(globalVar.clickEdgeToSwitchImage, forKey: "clickEdgeToSwitchImage")
    }

    @IBAction func scrollMouseWheelToZoomToggled(_ sender: NSButton) {
        globalVar.scrollMouseWheelToZoom = (sender.state == .on)
        UserDefaults.standard.set(globalVar.scrollMouseWheelToZoom, forKey: "scrollMouseWheelToZoom")
    }

    @IBAction func useInternalPlayerToggled(_ sender: NSButton) {
        globalVar.useInternalPlayer = (sender.state == .on)
        UserDefaults.standard.set(globalVar.useInternalPlayer, forKey: "useInternalPlayer")
    }
    
    @IBAction func bgSettingToggled(_ sender: NSButton) {
        let tag = sender.tag
        if tag == 0 {
            globalVar.blackBgAlways = false
            globalVar.blackBgInFullScreen = false
        } else if tag == 1 {
            globalVar.blackBgAlways = true
            globalVar.blackBgInFullScreen = false
        } else if tag == 2 {
            globalVar.blackBgAlways = false
            globalVar.blackBgInFullScreen = true
        }
        UserDefaults.standard.set(globalVar.blackBgAlways, forKey: "blackBgAlways")
        UserDefaults.standard.set(globalVar.blackBgInFullScreen, forKey: "blackBgInFullScreen")
        if let appDelegate=NSApplication.shared.delegate as? AppDelegate {
            for windowController in appDelegate.windowControllers {
                if let viewController = windowController.contentViewController as? ViewController {
                    viewController.largeImageView.determineBlackBg()
                }
            }
        }
    }
    
    @IBAction func bgSettingForVideoToggled(_ sender: NSButton) {
        let tag = sender.tag
        if tag == 0 {
            globalVar.blackBgAlwaysForVideo = false
            globalVar.blackBgInFullScreenForVideo = false
        } else if tag == 1 {
            globalVar.blackBgAlwaysForVideo = true
            globalVar.blackBgInFullScreenForVideo = false
        } else if tag == 2 {
            globalVar.blackBgAlwaysForVideo = false
            globalVar.blackBgInFullScreenForVideo = true
        }
        UserDefaults.standard.set(globalVar.blackBgAlwaysForVideo, forKey: "blackBgAlwaysForVideo")
        UserDefaults.standard.set(globalVar.blackBgInFullScreenForVideo, forKey: "blackBgInFullScreenForVideo")
        if let appDelegate=NSApplication.shared.delegate as? AppDelegate {
            for windowController in appDelegate.windowControllers {
                if let viewController = windowController.contentViewController as? ViewController {
                    viewController.largeImageView.determineBlackBg()
                }
            }
        }
    }

    @IBAction func usePinyinSearchToggled(_ sender: NSButton) {
        globalVar.usePinyinSearch = (sender.state == .on)
        UserDefaults.standard.set(globalVar.usePinyinSearch, forKey: "usePinyinSearch")
    }

    @IBAction func usePinyinInitialSearchToggled(_ sender: NSButton) {
        globalVar.usePinyinInitialSearch = (sender.state == .on)
        UserDefaults.standard.set(globalVar.usePinyinInitialSearch, forKey: "usePinyinInitialSearch")
    }

    @IBAction func keepFilterStateWhenSwitchFolderToggled(_ sender: NSButton) {
        globalVar.keepFilterStateWhenSwitchFolder = (sender.state == .on)
        UserDefaults.standard.set(globalVar.keepFilterStateWhenSwitchFolder, forKey: "keepFilterStateWhenSwitchFolder")
    }
    
}

// MARK: - ThumbnailExcludeView

class ThumbnailExcludeView: NSView {

    private static let dragType = NSPasteboard.PasteboardType("com.flowvision.excludePathRow")

    private var paths: [String] = []
    private var tableView: NSTableView!

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 120)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        paths = globalVar.thumbnailExcludeList
        setupUI()
    }

    private func setupUI() {
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.draggingDestinationFeedbackStyle = .regular

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Path"))
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

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: editControl.topAnchor, constant: -4),

            editControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            editControl.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func editControlClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: addPath()
        case 1: removeSelected()
        default: break
        }
    }

    private func addPath() {
        guard let window else { return }
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = openPanel.url else { return }
            if !self.paths.contains(url.path) {
                self.paths.append(url.path)
                self.save()
                self.tableView.reloadData()
            }
        }
    }

    private func removeSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < paths.count else { return }
        paths.remove(at: row)
        save()
        tableView.reloadData()
        if !paths.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: min(row, paths.count - 1)), byExtendingSelection: false)
        }
    }

    private func save() {
        globalVar.thumbnailExcludeList = paths
        UserDefaults.standard.set(paths, forKey: "thumbnailExcludeList")
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension ThumbnailExcludeView: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { paths.count }

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
        let path = paths.remove(at: src)
        let dst = src < row ? row - 1 : row
        paths.insert(path, at: dst)
        save()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: dst), byExtendingSelection: false)
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("PathItem")
        let cell: NSTableCellView = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.lineBreakMode = .byTruncatingHead
            tf.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(tf)
            c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        cell.textField?.stringValue = paths[row]
        return cell
    }
}
