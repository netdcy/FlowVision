//
//  CustomOutlineView.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation
import Cocoa

class CustomOutlineView: NSOutlineView, NSMenuDelegate {
    
    var curRightClickedPath = ""
    var curRightClickedIndex = -1
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        log("CustomOutlineView becomeFirstResponder")
        getViewController(self)!.publicVar.isOutlineViewFirstResponder=true
        return result
    }
    
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        log("CustomOutlineView resignFirstResponder")
        getViewController(self)!.publicVar.isOutlineViewFirstResponder=false
        return result
    }
    
    override func keyDown(with event: NSEvent) {
        // 不执行任何操作，从而忽略按键，避免字母定位与目录切换快捷键同时触发
        //super.keyDown(with: event)
        return
    }
    
    override func mouseDown(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        let locationInOutlineView = convert(locationInWindow, from: nil)
        let clickedRow = row(at: locationInOutlineView)
        
        // 检查是否在有效的区域内点击
        // 为了解决点击目录树后，在右边CollectionView中空白处快速右击左击，会出现目录树异常响应的问题
        // 且弹出重命名对话框时异常响应的问题
        if clickedRow >= 0 && getViewController(self)!.publicVar.isKeyEventEnabled {
            super.mouseDown(with: event)
        } else {
            // 如果点击区域无效，不执行默认的点击处理
            nextResponder?.mouseDown(with: event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }
    
    func menuDidClose(_ menu: NSMenu) {
        //curRightClickedPath = ""
        curRightClickedIndex = -1

        (self.delegate as? CustomOutlineViewManager)?.ifActWhenSelected=false
        let selectedRows = self.selectedRowIndexes
        self.reloadData()
        self.selectRowIndexes(selectedRows, byExtendingSelection: false)
        (self.delegate as? CustomOutlineViewManager)?.ifActWhenSelected=true
    }
    
    override func menu(for event: NSEvent) -> NSMenu? {
        
        let locationInView = self.convert(event.locationInWindow, from: nil)
        let clickedRow = self.row(at: locationInView)

        if clickedRow != -1 {
            //self.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            
            let item = self.item(atRow: clickedRow) as? TreeNode
            curRightClickedPath=item!.fullPath
            curRightClickedIndex=clickedRow
            
            (self.delegate as? CustomOutlineViewManager)?.ifActWhenSelected=false
            let selectedRows = self.selectedRowIndexes
            self.reloadData()
            self.selectRowIndexes(selectedRows, byExtendingSelection: false)
            (self.delegate as? CustomOutlineViewManager)?.ifActWhenSelected=true

            var canPasteOrMove=true
            let pasteboard = NSPasteboard.general
            let types = pasteboard.types ?? []
            if !types.contains(.fileURL) {
                canPasteOrMove=false
            }

            // 创建菜单
            let menu = NSMenu()
            menu.autoenablesItems = false
            
            let actionItemOpenInNewTab = menu.addItem(withTitle: NSLocalizedString("Open in New Tab", comment: "在新标签页中打开"), action: #selector(actOpenInNewTab), keyEquivalent: "")
            if isWindowNumMax() {
                actionItemOpenInNewTab.isEnabled=false
            }else{
                actionItemOpenInNewTab.isEnabled=true
            }
            
            menu.addItem(NSMenuItem.separator())
            
            menu.addItem(withTitle: NSLocalizedString("Show in Finder", comment: "在Finder中显示"), action: #selector(actShowInFinder), keyEquivalent: "")
            
            let actionItemGetInfo = menu.addItem(withTitle: NSLocalizedString("file-rightmenu-get-info", comment: "显示简介"), action: #selector(actGetInfo), keyEquivalent: "i")
            actionItemGetInfo.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())

            let actionItemSort = menu.addItem(withTitle: NSLocalizedString("Sort", comment: "排序"), action: nil, keyEquivalent: "")
            actionItemSort.keyEquivalentModifierMask = []
            
            let sortSubmenu = NSMenu()
            let sortTypes: [(SortType, String)] = [
                (.pathA, NSLocalizedString("sort-pathA", comment: "文件名")),
                (.pathZ, NSLocalizedString("sort-pathZ", comment: "文件名(倒序)")),
                (.createDateA, NSLocalizedString("sort-createDateA", comment: "创建日期")),
                (.createDateZ, NSLocalizedString("sort-createDateZ", comment: "创建日期(倒序)")),
                (.modDateA, NSLocalizedString("sort-modDateA", comment: "修改日期")),
                (.modDateZ, NSLocalizedString("sort-modDateZ", comment: "修改日期(倒序)")),
                (.addDateA, NSLocalizedString("sort-addDateA", comment: "添加日期")),
                (.addDateZ, NSLocalizedString("sort-addDateZ", comment: "添加日期(倒序)"))
            ]

            let currentDirTreeSortType = SortType(rawValue: Int(getViewController(self)!.publicVar.profile.getValue(forKey: "dirTreeSortType")) ?? 0)
            
            for (sortType, title) in sortTypes {
                let item = sortSubmenu.addItem(withTitle: title, action: #selector(actSortByType(_:)), keyEquivalent: "")
                item.representedObject = sortType
                if sortType == currentDirTreeSortType {
                    item.state = .on
                }
            }
            
            actionItemSort.submenu = sortSubmenu

            menu.addItem(NSMenuItem.separator())
            
            let actionItemDelete = menu.addItem(withTitle: NSLocalizedString("Move to Trash", comment: "移动到废纸篓"), action: #selector(actDelete), keyEquivalent: "\u{8}")
            actionItemDelete.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemRename = menu.addItem(withTitle: NSLocalizedString("Rename", comment: "重命名"), action: #selector(actRename), keyEquivalent: "r")
            actionItemRename.keyEquivalentModifierMask = []
            
            let actionItemCopy = menu.addItem(withTitle: NSLocalizedString("Copy", comment: "复制"), action: #selector(actCopy), keyEquivalent: "c")
            
            let actionItemCopyPath = menu.addItem(withTitle: NSLocalizedString("Copy Path", comment: "复制路径"), action: #selector(actCopyPath), keyEquivalent: "")
            
            let actionItemPaste = menu.addItem(withTitle: NSLocalizedString("Paste", comment: "粘贴"), action: #selector(actPaste), keyEquivalent: "v")
            actionItemPaste.isEnabled = canPasteOrMove
            
            let actionItemMove = menu.addItem(withTitle: NSLocalizedString("Move Here", comment: "移动到此"), action: #selector(actMove), keyEquivalent: "v")
            actionItemMove.keyEquivalentModifierMask = [.command,.option]
            actionItemMove.isEnabled = canPasteOrMove

            menu.addItem(NSMenuItem.separator())

            let actionItemOpenInTerminal = menu.addItem(withTitle: NSLocalizedString("Open in Terminal", comment: "在终端中打开"), action: #selector(actOpenInTerminal), keyEquivalent: "")
            
            menu.addItem(NSMenuItem.separator())

            let actionItemNewFolder = menu.addItem(withTitle: NSLocalizedString("New Folder", comment: "新建文件夹"), action: #selector(actNewFolder), keyEquivalent: "n")
            actionItemNewFolder.keyEquivalentModifierMask = [.command,.shift]
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemRefresh = menu.addItem(withTitle: NSLocalizedString("Refresh", comment: "刷新"), action: #selector(refreshAll), keyEquivalent: "r")
            actionItemRefresh.keyEquivalentModifierMask = [.command]

            // 可以将点击的对象传递给菜单项动作
            menu.items.forEach { item in
                item.representedObject = item
            }
            
            menu.delegate = self

            return menu
        }

        return nil
    }
    
    func getFirstSelectedUrl() -> URL? {
        let selectedIndexes = self.selectedRowIndexes
        for index in selectedIndexes {
            if let item = self.item(atRow: index) as? TreeNode {
                return URL(string: item.fullPath)
            }
        }
        return nil
    }
    
    @objc func refreshTreeView() {
        getViewController(self)?.refreshTreeView()
    }
    
    @objc func refreshAll() {
        getViewController(self)?.handleUserRefresh()
    }
    
    @objc func actOpenInNewTab() {
        guard let url=URL(string: curRightClickedPath) else{return}
        if let appDelegate=NSApplication.shared.delegate as? AppDelegate {
            _ = appDelegate.createNewWindow(url.absoluteString)
        }
    }

    @objc func actOpenInFinder() {
        guard let url=URL(string: curRightClickedPath) else{return}
        NSWorkspace.shared.open(url)
    }
    
    @objc func actShowInFinder() {
        guard let file=URL(string: curRightClickedPath) else{return}
//        let folderPath = (file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding! as NSString).deletingLastPathComponent
//        NSWorkspace.shared.selectFile(file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!, inFileViewerRootedAtPath: folderPath)
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
    
    @objc func actGetInfo(isByKeyboard: Bool = false) {
        var url: URL?
        if isByKeyboard {
            url = getFirstSelectedUrl()
        }else{
            url=URL(string: curRightClickedPath)
        }
        guard let url = url else {return}
        
        getViewController(self)?.handleGetInfo([url])
    }
    
    @objc func actRename(isByKeyboard: Bool = false) {
        var url: URL?
        if isByKeyboard {
            url = getFirstSelectedUrl()
        }else{
            url=URL(string: curRightClickedPath)
        }
        guard let url = url else {return}
        
        renameAlert(urls: [url])

        if curRightClickedIndex != self.selectedRowIndexes.first {
            refreshTreeView()
        }
    }
    
    @objc func actNewFolder() {
        guard let url=URL(string: curRightClickedPath) else{return}
        guard let viewController = getViewController(self) else{return}
        
        if viewController.handleNewFolder(targetURL: url).0 {
            if curRightClickedIndex != self.selectedRowIndexes.first {
                refreshTreeView()
            }
        }
    }
    
    @objc func actCopy(isByKeyboard: Bool = false) {
        var url: URL?
        if isByKeyboard {
            url = getFirstSelectedUrl()
        }else{
            url=URL(string: curRightClickedPath)
        }
        guard let url = url else {return}

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()  // 清除剪贴板现有内容

        var urls=[URL]()
        urls.append(url)
        // 将文件URL添加到剪贴板
        pasteboard.writeObjects(urls as [NSPasteboardWriting])
    }
    
    @objc func actDelete(isByKeyboard: Bool = false, isShowPrompt: Bool = true) {
        var url: URL?
        if isByKeyboard {
            url = getFirstSelectedUrl()
        }else{
            url=URL(string: curRightClickedPath)
        }
        guard let url = url else {return}
        
        let result = getViewController(self)?.handleDelete(fileUrls: [url], isShowPrompt: isByKeyboard && isShowPrompt)
        
        if result == true && curRightClickedIndex != self.selectedRowIndexes.first {
            refreshTreeView()
        }
    }
    
    @objc func actPaste() {
        guard let url=URL(string: curRightClickedPath) else{return}
        getViewController(self)?.handlePaste(targetURL: url)
        
        if curRightClickedIndex != self.selectedRowIndexes.first {
            refreshTreeView()
        }
    }
    
    @objc func actMove() {
        guard let url=URL(string: curRightClickedPath) else{return}
        getViewController(self)?.handleMove(targetURL: url)
        
        if curRightClickedIndex != self.selectedRowIndexes.first {
            refreshTreeView()
        }
    }

    @objc func actCopyPath() {
        guard let url=URL(string: curRightClickedPath) else{return}
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    @objc func actOpenInTerminal() {
        guard let url=URL(string: curRightClickedPath) else{return}
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", url.path]
        task.launch()
    }

    @objc func actSortByType(_ sender: NSMenuItem) {
        guard let sortType = sender.representedObject as? SortType else { return }
        getViewController(self)?.changeDirSortType(sortType: sortType)
    }
}
