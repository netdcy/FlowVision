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

                    let actionItemPaste = menu.addItem(withTitle: NSLocalizedString("Paste", comment: "粘贴"), action: #selector(actPaste), keyEquivalent: "v")
                    actionItemPaste.isEnabled = canPasteOrMove
                    
                    let actionItemMove = menu.addItem(withTitle: NSLocalizedString("Move Here", comment: "移动到此"), action: #selector(actMove), keyEquivalent: "v")
                    actionItemMove.keyEquivalentModifierMask = [.command,.option]
                    actionItemMove.isEnabled = canPasteOrMove

                    menu.addItem(NSMenuItem.separator())
                    
                    //let actionItemCopyPath = menu.addItem(withTitle: NSLocalizedString("Copy Path", comment: "复制路径"), action: #selector(actCopyPath), keyEquivalent: "")
                    
                    let actionItemOpenInTerminal = menu.addItem(withTitle: NSLocalizedString("Open in Terminal", comment: "在终端中打开"), action: #selector(actOpenInTerminal), keyEquivalent: "")
                    
                    menu.addItem(NSMenuItem.separator())
            
                    // 创建"新建"子菜单
                    let newMenu = NSMenu()
                    let newMenuItem = NSMenuItem(title: NSLocalizedString("New", comment: "新建"), action: nil, keyEquivalent: "")
                    newMenuItem.submenu = newMenu
                    
                    // 添加新建文件夹选项
                    let newFolderItem = newMenu.addItem(withTitle: NSLocalizedString("Folder", comment: "文件夹"), 
                                                       action: #selector(actNewFolder), 
                                                       keyEquivalent: "n")
                    newFolderItem.keyEquivalentModifierMask = [.command, .shift]

                    newMenu.addItem(NSMenuItem.separator())
                    
                    // 添加新建文本文件选项
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
        self.mouseDownLocation = nil // 重置按下位置
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
    @objc func actNewTextFile() {
        getViewController(self)?.handleNewTextFile()
    }
}
