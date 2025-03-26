//
//  GeneralSettingsViewController.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/22.
//

import Cocoa
import Settings

final class CustomSettingsViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.custom
    let paneTitle = NSLocalizedString("Custom", comment: "自定义")
    let toolbarItemIcon = NSImage(systemSymbolName: "gear", accessibilityDescription: "")!

    override var nibName: NSNib.Name? { "CustomSettingsViewController" }

    @IBOutlet weak var randomFolderThumbCheckbox: NSButton!
    @IBOutlet weak var loopBrowsingCheckbox: NSButton!
    @IBOutlet weak var blackBgInFullScreenCheckbox: NSButton!
    @IBOutlet weak var excludeListView: NSOutlineView!
    @IBOutlet weak var excludeContainerView: NSView!
    @IBOutlet weak var refViewForExcludeListView: NSView!
    @IBOutlet weak var excludeListEditControl: NSSegmentedControl!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        randomFolderThumbCheckbox.state = globalVar.randomFolderThumb ? .on : .off
        loopBrowsingCheckbox.state = globalVar.loopBrowsing ? .on : .off
        blackBgInFullScreenCheckbox.state = globalVar.blackBgInFullScreen ? .on : .off
        
        // 设置 OutlineView
        excludeListView.dataSource = self
        excludeListView.delegate = self

        // 根据refViewForExcludeListView的x、y设置excludeListView的x、y
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let refFrameInWindow = refViewForExcludeListView.convert(refViewForExcludeListView.bounds, to: nil)
            let newY = refFrameInWindow.origin.y - excludeContainerView.frame.height + refViewForExcludeListView.frame.height
            excludeContainerView.frame = NSRect(x: refFrameInWindow.origin.x, y: newY, width: 300, height: 125)
        }
        
        // 设置分段图标
        if let plusImage = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Item") {
            excludeListEditControl.setImage(plusImage, forSegment: 0)
        }
        
        if let minusImage = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove Item") {
            excludeListEditControl.setImage(minusImage, forSegment: 1)
        }
        
        // 已在AppDelegate中加载数据
        excludeListView.reloadData()
    }
    
    @IBAction func randomFolderThumbToggled(_ sender: NSButton) {
        globalVar.randomFolderThumb = (sender.state == .on)
        UserDefaults.standard.set(globalVar.randomFolderThumb, forKey: "randomFolderThumb")
    }
    
    @IBAction func loopBrowsingToggled(_ sender: NSButton) {
        globalVar.loopBrowsing = (sender.state == .on)
        UserDefaults.standard.set(globalVar.loopBrowsing, forKey: "loopBrowsing")
    }

    @IBAction func blackBgInFullScreenToggled(_ sender: NSButton) {
        globalVar.blackBgInFullScreen = (sender.state == .on)
        UserDefaults.standard.set(globalVar.blackBgInFullScreen, forKey: "blackBgInFullScreen")
    }
    
    @IBAction func segmentedControlValueChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: // 增加
            let openPanel = NSOpenPanel()
            openPanel.canChooseDirectories = true
            openPanel.canChooseFiles = false
            openPanel.allowsMultipleSelection = false
            
            openPanel.beginSheetModal(for: self.view.window!) { [weak self] response in
                guard let self = self else { return }
                if response == .OK, let url = openPanel.url {
                    globalVar.thumbnailExcludeList.append(url.path)
                    excludeListView.reloadData()
                    UserDefaults.standard.set(globalVar.thumbnailExcludeList, forKey: "thumbnailExcludeList")
                }
            }
        case 1: // 删除
            let selectedRow = excludeListView.selectedRow
            if selectedRow >= 0 && selectedRow < globalVar.thumbnailExcludeList.count {
                globalVar.thumbnailExcludeList.remove(at: selectedRow)
                excludeListView.reloadData()
                UserDefaults.standard.set(globalVar.thumbnailExcludeList, forKey: "thumbnailExcludeList")
            }
        default:
            break
        }
    }
}

// MARK: - NSOutlineViewDataSource
extension CustomSettingsViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        return item == nil ? globalVar.thumbnailExcludeList.count : 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return globalVar.thumbnailExcludeList[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
}

// MARK: - NSOutlineViewDelegate
extension CustomSettingsViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("PathCell")
        
        guard let cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView else {
            let cell = NSTableCellView()
            cell.identifier = cellIdentifier
            let textField = NSTextField(labelWithString: "")
            cell.addSubview(textField)
            cell.textField = textField
            return cell
        }
        
        if let path = item as? String {
            cell.textField?.stringValue = path
        }
        
        return cell
    }
}
