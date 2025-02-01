//
//  CustomCollectionView.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
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
        //super.keyDown(with: event)
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
                let maxDistance: CGFloat = 5.0 // 允许的最大移动距离
                let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)
                
                // 鼠标移动距离在允许范围内，弹出菜单
                if distance <= maxDistance {
                    
                    deselectAll(nil)
                    
                    var canPasteOrMove=true
                    let pasteboard = NSPasteboard.general
                    let types = pasteboard.types ?? []
                    if !types.contains(.fileURL) {
                        canPasteOrMove=false
                    }
                    
                    //弹出菜单
                    let menu = NSMenu(title: "Custom Menu")
                    menu.autoenablesItems = false
                    
                    menu.addItem(withTitle: NSLocalizedString("Open in Finder", comment: "在Finder中打开"), action: #selector(actOpenInFinder), keyEquivalent: "")
                    
                    menu.addItem(NSMenuItem.separator())
                    
                    // 定义排序项
                    do{
                        let sortTypes: [(SortType, String)] = [
                            (.pathA, NSLocalizedString("sort-pathA", comment: "文件名")),
                            (.pathZ, NSLocalizedString("sort-pathZ", comment: "文件名(倒序)")),
                            (.sizeA, NSLocalizedString("sort-sizeA", comment: "大小")),
                            (.sizeZ, NSLocalizedString("sort-sizeZ", comment: "大小(倒序)")),
                            (.extA, NSLocalizedString("sort-extA", comment: "文件类型")),
                            (.extZ, NSLocalizedString("sort-extZ", comment: "文件类型(倒序)")),
                            (.createDateA, NSLocalizedString("sort-createDateA", comment: "创建日期")),
                            (.createDateZ, NSLocalizedString("sort-createDateZ", comment: "创建日期(倒序)")),
                            (.modDateA, NSLocalizedString("sort-modDateA", comment: "修改日期")),
                            (.modDateZ, NSLocalizedString("sort-modDateZ", comment: "修改日期(倒序)")),
                            (.addDateA, NSLocalizedString("sort-addDateA", comment: "添加日期")),
                            (.addDateZ, NSLocalizedString("sort-addDateZ", comment: "添加日期(倒序)")),
                            (.random, NSLocalizedString("sort-random", comment: "随机"))
                        ]

                        let sortMenuItem = NSMenuItem(title: NSLocalizedString("Sort By", comment: "排序方式"), action: nil, keyEquivalent: "")
                        let sortSubMenu = NSMenu()
                        
                        let folderFirstItem = NSMenuItem(title: NSLocalizedString("Sort Folders First", comment: "文件夹优先排序"), action: #selector(sortFolderFirst(_:)), keyEquivalent: "")
                        folderFirstItem.state = (getViewController(self)?.publicVar.profile.isSortFolderFirst == false) ? .off : .on
                        sortSubMenu.addItem(folderFirstItem)
                        
                        let useFullPathItem = NSMenuItem(title: NSLocalizedString("Sort Using Full Path In Recursive Mode", comment: "在递归模式下使用完整路径排序"), action: #selector(sortUseFullPath(_:)), keyEquivalent: "")
                        useFullPathItem.state = (getViewController(self)?.publicVar.profile.isSortUseFullPath == false) ? .off : .on
                        sortSubMenu.addItem(useFullPathItem)
                        
                        sortSubMenu.addItem(NSMenuItem.separator())
                        
                        for (sortType, title) in sortTypes {
                            let menuItem = NSMenuItem(title: title, action: #selector(sortItems(_:)), keyEquivalent: "")
                            menuItem.target = self
                            menuItem.representedObject = sortType
                            let curSortType=getViewController(self)?.publicVar.profile.sortType
                            menuItem.state = curSortType == sortType ? .on : .off
                            sortSubMenu.addItem(menuItem)
                        }
                        sortMenuItem.submenu = sortSubMenu
                        menu.addItem(sortMenuItem)
                    }
                    
                    menu.addItem(NSMenuItem.separator())

                    let actionItemPaste = menu.addItem(withTitle: NSLocalizedString("Paste", comment: "粘贴"), action: #selector(actPaste), keyEquivalent: "v")
                    actionItemPaste.isEnabled = canPasteOrMove
                    
                    let actionItemMove = menu.addItem(withTitle: NSLocalizedString("Move Here", comment: "移动到此"), action: #selector(actMove), keyEquivalent: "v")
                    actionItemMove.keyEquivalentModifierMask = [.command,.option]
                    actionItemMove.isEnabled = canPasteOrMove

                    menu.addItem(NSMenuItem.separator())
                    
                    let actionItemNewFolder = menu.addItem(withTitle: NSLocalizedString("New Folder", comment: "新建文件夹"), action: #selector(actNewFolder), keyEquivalent: "n")
                    actionItemNewFolder.keyEquivalentModifierMask = [.command,.shift]
                    
                    menu.addItem(NSMenuItem.separator())

                    // 复制路径
                    //let actionItemCopyPath = menu.addItem(withTitle: NSLocalizedString("Copy Path", comment: "复制路径"), action: #selector(actCopyPath), keyEquivalent: "")
            
                    // 在终端中打开
                    let actionItemOpenInTerminal = menu.addItem(withTitle: NSLocalizedString("Open in Terminal", comment: "在终端中打开"), action: #selector(actOpenInTerminal), keyEquivalent: "")
            
                    menu.addItem(NSMenuItem.separator())
                    
                    let actionItemRefresh = menu.addItem(withTitle: NSLocalizedString("Refresh", comment: "刷新"), action: #selector(actRefresh), keyEquivalent: "r")
                    actionItemRefresh.keyEquivalentModifierMask = []
                    
                    menu.items.forEach { $0.target = self }
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                }
            }
        }
        self.mouseDownLocation = nil // 重置按下位置
        super.rightMouseUp(with: event)
    }
    
    @objc func actOpenInFinder() {
        if let folderURL=getViewController(self)?.fileDB.curFolder {
            NSWorkspace.shared.open(URL(string: folderURL)!)
        }
    }
    
    @objc func sortItems(_ sender: NSMenuItem) {
        guard let viewController = getViewController(self) else {return}
        guard let sortType = sender.representedObject as? SortType else { return }
        getViewController(self)?.changeSortType(sortType: sortType, isSortFolderFirst: viewController.publicVar.profile.isSortFolderFirst, isSortUseFullPath: viewController.publicVar.profile.isSortUseFullPath)
    }
    
    @objc func sortFolderFirst(_ sender: NSMenuItem) {
        guard let viewController = getViewController(self) else {return}
        viewController.publicVar.profile.isSortFolderFirst.toggle()
        viewController.changeSortType(sortType: viewController.publicVar.profile.sortType, isSortFolderFirst: viewController.publicVar.profile.isSortFolderFirst, isSortUseFullPath: viewController.publicVar.profile.isSortUseFullPath)
    }

    @objc func sortUseFullPath(_ sender: NSMenuItem) {
        guard let viewController = getViewController(self) else {return}
        viewController.publicVar.profile.isSortUseFullPath.toggle()
        viewController.changeSortType(sortType: viewController.publicVar.profile.sortType, isSortFolderFirst: viewController.publicVar.profile.isSortFolderFirst, isSortUseFullPath: viewController.publicVar.profile.isSortUseFullPath)
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
        LargeImageProcessor.clearCache()
        ThumbImageProcessor.clearCache()
        getViewController(self)?.refreshAll([.all])
        DispatchQueue.main.async { [weak self] in
            guard let self=self else {return}
            getViewController(self)?.setLoadThumbPriority(ifNeedVisable: true)
        }
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
}
