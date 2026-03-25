//
//  CustomCollectionView.swift
//  FlowVision
//

import Foundation
import Cocoa

class CustomCollectionView: NSCollectionView {

    private var mouseDownLocation: NSPoint? = nil
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        log("CustomCollectionView becomeFirstResponder")
        
        getViewController(self)!.publicVar.isCollectionViewFirstResponder=true
        
        let selectedIndexPaths = self.selectionIndexPaths
        for indexPath in selectedIndexPaths{
            if let item = self.item(at: indexPath) as? CustomCollectionViewItem{
                item.selectedColor()
            }
        }
        
        return result
    }
    
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        log("CustomCollectionView resignFirstResponder")
        
        getViewController(self)!.publicVar.isCollectionViewFirstResponder=false
        
        let selectedIndexPaths = self.selectionIndexPaths
        for indexPath in selectedIndexPaths{
            if let item = self.item(at: indexPath) as? CustomCollectionViewItem{
                item.selectedColor()
            }
        }
        
        return result
    }

    override func keyDown(with event: NSEvent) {
        // 不执行任何操作，从而忽略按键
        // Do nothing to ignore key press
        // super.keyDown(with: event)
        return
    }
    
    override func rightMouseDown(with event: NSEvent) {
        getViewController(self)!.publicVar.isColllectionViewItemRightClicked=false
        self.window?.makeFirstResponder(self)
        self.mouseDownLocation = event.locationInWindow
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        let mouseUpLocation = event.locationInWindow
        
        if let mouseDownLocation = self.mouseDownLocation {
            
            if !getViewController(self)!.publicVar.isColllectionViewItemRightClicked {
                // 允许的最大移动距离
                // Maximum allowed movement distance
                let maxDistance: CGFloat = 5.0
                let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)
                
                // 鼠标移动距离在允许范围内，弹出菜单
                // If mouse movement is within allowed range, show context menu
                if distance <= maxDistance {
                    
                    deselectAll(nil)
                    
                    var canPasteOrMove=true
                    let pasteboard = NSPasteboard.general
                    let types = pasteboard.types ?? []
                    if !types.contains(.fileURL) {
                        canPasteOrMove=false
                    }

                    let curFolder = getViewController(self)!.fileDB.curFolder
                    let isVirtualFinderTagsFolder = curFolder.hasPrefix("file:///VirtualFinderTagsFolder")
                    
                    // 弹出菜单
                    // Show context menu
                    let menu = NSMenu(title: "Custom Menu")
                    menu.autoenablesItems = false
                    
                    let actionItemOpenInFinder = menu.addItem(withTitle: NSLocalizedString("Open in Finder", comment: "在Finder中打开"), action: #selector(actOpenInFinder), keyEquivalent: "")
                    actionItemOpenInFinder.isEnabled = !isVirtualFinderTagsFolder
                    
                    menu.addItem(NSMenuItem.separator())

                    let actionItemPaste = menu.addItem(withTitle: NSLocalizedString("Paste", comment: "粘贴"), action: #selector(actPaste), keyEquivalent: "v")
                    actionItemPaste.isEnabled = canPasteOrMove && !isVirtualFinderTagsFolder
                    
                    let actionItemMove = menu.addItem(withTitle: NSLocalizedString("Move Here", comment: "移动到此"), action: #selector(actMove), keyEquivalent: "v")
                    actionItemMove.keyEquivalentModifierMask = [.command,.option]
                    actionItemMove.isEnabled = canPasteOrMove && !isVirtualFinderTagsFolder

                    menu.addItem(NSMenuItem.separator())

                    let filterMenu = NSMenu()
                    let filterMenuItem = NSMenuItem(title: NSLocalizedString("Filter by Finder Tag", comment: "按Finder标签筛选"), action: nil, keyEquivalent: "")
                    filterMenuItem.submenu = filterMenu

                    let currentFilters = getViewController(self)?.publicVar.finderTagFilters ?? []

                    for (i, tag) in FinderTag.all.enumerated() {
                        let item = filterMenu.addItem(withTitle: NSLocalizedString(tag.name, comment: ""), action: #selector(actFilterByFinderTag(_:)), keyEquivalent: (i + 1 <= 9) ? "\(i + 1)" : "")
                        item.keyEquivalentModifierMask = [.command, .shift]
                        item.representedObject = tag.name
                        if currentFilters.contains(tag.name) {
                            item.state = .on
                        }
                        item.image = tag.dotImage
                    }

                    filterMenu.addItem(NSMenuItem.separator())

                    let isAndMode = getViewController(self)?.publicVar.isFinderTagFilterModeAnd ?? false
                    let matchAnyItem = filterMenu.addItem(withTitle: NSLocalizedString("Match Any (OR)", comment: "匹配任一 (OR)"), action: #selector(actSetFinderTagFilterModeOr), keyEquivalent: "")
                    matchAnyItem.state = isAndMode ? .off : .on
                    let matchAllItem = filterMenu.addItem(withTitle: NSLocalizedString("Match All (AND)", comment: "匹配全部 (AND)"), action: #selector(actSetFinderTagFilterModeAnd), keyEquivalent: "")
                    matchAllItem.state = isAndMode ? .on : .off

                    filterMenu.addItem(NSMenuItem.separator())

                    let reverseFilterItem = filterMenu.addItem(withTitle: NSLocalizedString("Reverse Filter", comment: "反转筛选"), action: #selector(actReverseFinderTagFilter), keyEquivalent: "")
                    reverseFilterItem.state = getViewController(self)?.publicVar.isFinderTagFilterReversed ?? false ? .on : .off

                    filterMenu.addItem(NSMenuItem.separator())

                    let showAllItem = filterMenu.addItem(withTitle: NSLocalizedString("Show All", comment: "显示全部"), action: #selector(actClearFinderTagFilter), keyEquivalent: "")
                    if currentFilters.isEmpty {
                        showAllItem.state = .on
                    }

                    filterMenu.addItem(NSMenuItem.separator())
                    filterMenu.addItem(withTitle: NSLocalizedString("Learn More...", comment: "了解更多..."), action: #selector(actTagLearnMore), keyEquivalent: "")

                    menu.addItem(filterMenuItem)

                    // 根据评级筛选
                    let ratingMenu = NSMenu()
                    let ratingMenuItem = NSMenuItem(title: NSLocalizedString("Filter by Rating", comment: "按评级筛选"), action: nil, keyEquivalent: "")
                    ratingMenuItem.submenu = ratingMenu

                    let currentRatingFilters = getViewController(self)?.publicVar.ratingFilters ?? []

                    for rating in (1...5).reversed() {
                        let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
                        let title = "\(stars)  (\(rating))"
                        let item = ratingMenu.addItem(withTitle: title, action: #selector(actFilterByRating(_:)), keyEquivalent: "\(rating)")
                        item.keyEquivalentModifierMask = [.control, .shift]
                        item.representedObject = rating
                        if currentRatingFilters.contains(rating) {
                            item.state = .on
                        }
                    }

                    let noRatingItem = ratingMenu.addItem(withTitle: NSLocalizedString("No Rating", comment: "无评级"), action: #selector(actFilterByRating(_:)), keyEquivalent: "0")
                    noRatingItem.keyEquivalentModifierMask = [.control, .shift]
                    noRatingItem.representedObject = 0
                    if currentRatingFilters.contains(0) {
                        noRatingItem.state = .on
                    }

                    ratingMenu.addItem(NSMenuItem.separator())

                    let reverseRatingFilterItem = ratingMenu.addItem(withTitle: NSLocalizedString("Reverse Filter", comment: "反转筛选"), action: #selector(actReverseRatingFilter), keyEquivalent: "")
                    reverseRatingFilterItem.state = getViewController(self)?.publicVar.isRatingFilterReversed ?? false ? .on : .off

                    ratingMenu.addItem(NSMenuItem.separator())

                    let showAllRatingItem = ratingMenu.addItem(withTitle: NSLocalizedString("Show All", comment: "显示全部"), action: #selector(actClearRatingFilter), keyEquivalent: "")
                    if currentRatingFilters.isEmpty {
                        showAllRatingItem.state = .on
                    }

                    ratingMenu.addItem(NSMenuItem.separator())
                    ratingMenu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(actRatingReadme), keyEquivalent: "")

                    menu.addItem(ratingMenuItem)

                    menu.addItem(NSMenuItem.separator())
                    
                    // let actionItemCopyPath = menu.addItem(withTitle: NSLocalizedString("Copy Path", comment: "复制路径"), action: #selector(actCopyPath), keyEquivalent: "")
                    
                    let actionItemOpenInTerminal = menu.addItem(withTitle: NSLocalizedString("Open in Terminal", comment: "在终端中打开"), action: #selector(actOpenInTerminal), keyEquivalent: "")
                    actionItemOpenInTerminal.isEnabled = !isVirtualFinderTagsFolder
                    
                    menu.addItem(NSMenuItem.separator())
            
                    // 创建"新建"子菜单
                    // Create "New" submenu
                    let newMenu = NSMenu()
                    let newMenuItem = NSMenuItem(title: NSLocalizedString("New", comment: "新建"), action: nil, keyEquivalent: "")
                    newMenuItem.submenu = newMenu
                    newMenuItem.isEnabled = !isVirtualFinderTagsFolder
                    
                    // 添加新建文件夹选项
                    // Add new folder option
                    let newFolderItem = newMenu.addItem(withTitle: NSLocalizedString("Folder", comment: "文件夹"), 
                                                       action: #selector(actNewFolder), 
                                                       keyEquivalent: "n")
                    newFolderItem.keyEquivalentModifierMask = [.command, .shift]

                    newMenu.addItem(NSMenuItem.separator())
                    
                    // 添加新建文本文件选项
                    // Add new text file option
                    let newTextFileItem = newMenu.addItem(withTitle: NSLocalizedString("Text File", comment: "文本文件"), 
                                                        action: #selector(actNewTextFile), 
                                                        keyEquivalent: "")
                    
                    menu.addItem(newMenuItem)

                    menu.addItem(NSMenuItem.separator())

                    let actionItemRefresh = menu.addItem(withTitle: NSLocalizedString("Refresh", comment: "刷新"), action: #selector(actRefresh), keyEquivalent: "r")
                    actionItemRefresh.keyEquivalentModifierMask = [.command]
                    
                    menu.items.forEach { $0.target = self }
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                }
            }
        }
        // 重置按下位置
        // Reset mouse down location
        self.mouseDownLocation = nil
        super.rightMouseUp(with: event)
    }
    
    @objc func actOpenInFinder() {
        if let folderURL=getViewController(self)?.fileDB.curFolder {
            NSWorkspace.shared.open(URL(string: folderURL)!)
        }
    }
    
    @objc func actNewFolder() {
        getViewController(self)?.handleNewFolder()
    }
    
    @objc func actPaste() {
        getViewController(self)?.handlePaste()
    }
    
    @objc func actMove() {
        getViewController(self)?.handleMove()
    }
    
    @objc func actRefresh() {
        getViewController(self)?.handleUserRefresh()
    }

    @objc func actCopyPath() {
        guard let folderURL=getViewController(self)?.fileDB.curFolder else{return}
        guard let url=URL(string: folderURL) else{return}
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    @objc func actOpenInTerminal() {
        guard let folderURL=getViewController(self)?.fileDB.curFolder else{return}
        guard let url=URL(string: folderURL) else{return}
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", url.path]
        task.launch()
    }

    // 添加新建文本文件的动作处理方法
    // Add action handler method for new text file
    @objc func actNewTextFile() {
        getViewController(self)?.handleNewTextFile()
    }

    @objc func actFilterByFinderTag(_ sender: NSMenuItem) {
        guard let tagName = sender.representedObject as? String else { return }
        getViewController(self)?.toggleFinderTagFilter(tagName)
    }

    @objc func actClearFinderTagFilter() {
        getViewController(self)?.publicVar.isFinderTagFilterReversed = false
        getViewController(self)?.publicVar.isFinderTagFilterModeAnd = false
        getViewController(self)?.publicVar.finderTagFilters.removeAll()
        getViewController(self)?.toggleFinderTagFilter(nil)
    }

    @objc func actReverseFinderTagFilter() {
        getViewController(self)?.toggleFinderTagFilterReversed()
    }

    @objc func actSetFinderTagFilterModeAnd() {
        getViewController(self)?.publicVar.isFinderTagFilterModeAnd = true
        getViewController(self)?.refreshCollectionView(needLoadThumbPriority: true)
    }

    @objc func actSetFinderTagFilterModeOr() {
        getViewController(self)?.publicVar.isFinderTagFilterModeAnd = false
        getViewController(self)?.refreshCollectionView(needLoadThumbPriority: true)
    }

    @objc func actTagLearnMore() {
        getViewController(self)?.handleTagLearnMore()
    }

    @objc func actFilterByRating(_ sender: NSMenuItem) {
        guard let rating = sender.representedObject as? Int else { return }
        getViewController(self)?.toggleRatingFilter(rating)
    }

    @objc func actClearRatingFilter() {
        getViewController(self)?.publicVar.isRatingFilterReversed = false
        getViewController(self)?.publicVar.ratingFilters.removeAll()
        getViewController(self)?.toggleRatingFilter(nil)
    }

    @objc func actReverseRatingFilter() {
        getViewController(self)?.toggleRatingFilterReversed()
    }

    @objc func actRatingReadme() {
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("rating-info", comment: "对于评级的说明..."))
    }
}
