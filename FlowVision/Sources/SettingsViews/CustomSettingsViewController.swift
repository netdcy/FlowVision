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
    let paneTitle = NSLocalizedString("View", comment: "查看")
    let toolbarItemIcon = NSImage(systemSymbolName: "gear", accessibilityDescription: "")!

    override var nibName: NSNib.Name? { "CustomSettingsViewController" }

    @IBOutlet weak var randomFolderThumbCheckbox: NSButton!
    @IBOutlet weak var loopBrowsingCheckbox: NSButton!
    @IBOutlet weak var usePinyinSearchCheckbox: NSButton!
    @IBOutlet weak var usePinyinInitialSearchCheckbox: NSButton!
    @IBOutlet weak var excludeListView: NSOutlineView!
    @IBOutlet weak var excludeContainerView: NSView!
    @IBOutlet weak var refViewForExcludeListView: NSView!
    @IBOutlet weak var excludeListEditControl: NSSegmentedControl!
    
    @IBOutlet weak var radioGlass: NSButton!
    @IBOutlet weak var radioBlack: NSButton!
    @IBOutlet weak var radioFullscreen: NSButton!
    @IBOutlet weak var radioGlassForVideo: NSButton!
    @IBOutlet weak var radioBlackForVideo: NSButton!
    @IBOutlet weak var radioFullscreenForVideo: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        randomFolderThumbCheckbox.state = globalVar.randomFolderThumb ? .on : .off
        loopBrowsingCheckbox.state = globalVar.loopBrowsing ? .on : .off
        usePinyinSearchCheckbox.state = globalVar.usePinyinSearch ? .on : .off
        usePinyinInitialSearchCheckbox.state = globalVar.usePinyinInitialSearch ? .on : .off
        
        radioGlass.state = !globalVar.blackBgAlways ? .on : .off
        radioBlack.state = globalVar.blackBgAlways ? .on : .off
        radioFullscreen.state = globalVar.blackBgInFullScreen ? .on : .off
        radioGlassForVideo.state = !globalVar.blackBgAlwaysForVideo ? .on : .off
        radioBlackForVideo.state = globalVar.blackBgAlwaysForVideo ? .on : .off
        radioFullscreenForVideo.state = globalVar.blackBgInFullScreenForVideo ? .on : .off

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
        
        // 设置增减图标
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
        getMainViewController()?.largeImageView.determineBlackBg()
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
        getMainViewController()?.largeImageView.determineBlackBg()
    }

    @IBAction func usePinyinSearchToggled(_ sender: NSButton) {
        globalVar.usePinyinSearch = (sender.state == .on)
        UserDefaults.standard.set(globalVar.usePinyinSearch, forKey: "usePinyinSearch")
    }

    @IBAction func usePinyinInitialSearchToggled(_ sender: NSButton) {
        globalVar.usePinyinInitialSearch = (sender.state == .on)
        UserDefaults.standard.set(globalVar.usePinyinInitialSearch, forKey: "usePinyinInitialSearch")
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
                    if !globalVar.thumbnailExcludeList.contains(url.path) {
                        globalVar.thumbnailExcludeList.append(url.path)
                    }
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
