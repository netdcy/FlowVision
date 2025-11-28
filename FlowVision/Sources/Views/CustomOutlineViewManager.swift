//
//  TreeOutlineViewManager.swift
//  FlowVision
//
//  Created by netdcy on 2024/4/21.
//

import Foundation
import Cocoa

class CustomOutlineViewManager: NSObject {
    var fileDB: DatabaseModel
    var treeViewData: TreeViewModel
    var ifActWhenSelected = true
    weak var outlineView: NSOutlineView?
    
    init(fileDB: DatabaseModel, treeViewData: TreeViewModel, outlineView: NSOutlineView) {
        self.fileDB = fileDB
        self.treeViewData = treeViewData
        self.outlineView = outlineView
    }
}

extension CustomOutlineViewManager: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let treeNode = item as? TreeNode else {
            return treeViewData.root?.children?.count ?? 0
        }
        return treeNode.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let treeNode = item as? TreeNode else {
            return treeViewData.root?.children?[index] ?? ""
        }
        return treeNode.children?[index] ?? ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let treeNode = item as? TreeNode else {
            return false
        }
        if (treeNode.children?.count ?? 0) > 0 {
            return true
        }
        if treeNode.hasChild {
            return true
        }
        return false
    }
    func outlineViewItemWillExpand(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] as? TreeNode {
            // 在这里执行你的代码
            log("TreeData expand: \(item.fullPath)")
            treeViewData.expand(node: item, isLookSub: true)
        }
    }

}
extension CustomOutlineViewManager: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let treeNode = item as? TreeNode else { return nil }
        let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("DataCell"), owner: self) as! CustomTableCellView
        view.textField?.stringValue = treeNode.name
        
        let folderIcon = NSImage(named: NSImage.folderName)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        //folderIcon?.isTemplate = true // 设置为模板
        //view.imageView?.contentTintColor = NSColor.red // 将图标颜色设置为红色
        view.imageView?.image = folderIcon
        //view?.imageView?.image = NSImage(named: NSImage.folderName)
        
//        let backgroundView = NSView()
//        backgroundView.wantsLayer = true
//        backgroundView.layer?.backgroundColor = NSColor.lightGray.cgColor
//        view.addSubview(backgroundView, positioned: .below, relativeTo: view.textField)
//
//        // 确保背景视图填充整个cell
//        backgroundView.frame = view.bounds
//        backgroundView.autoresizingMask = [.width, .height]
        
        return view
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }
        
        let selectedIndex = outlineView.selectedRow
        if selectedIndex != -1, let item = outlineView.item(atRow: selectedIndex) as? TreeNode {
            // 这里调用你的函数，例如:
            itemSelected(item)
        }
    }
    
    func itemSelected(_ item: TreeNode) {
        if ifActWhenSelected {
            //log("Selected item: \(item.name)")
            //fileDB.lock()
            //let lastFolderPath = fileDB.curFolder
            //fileDB.curFolder = item.fullPath
            //log(fileDB.curFolder)
            //fileDB.unlock()
            //getViewController(self)!.publicVar.folderStepStack.insert(lastFolderPath, at: 0)
            getViewController(outlineView!)?.switchDirByDirection(direction: .zero, dest: item.fullPath, doCollapse: false, expandLast: false, skip: false, stackDeep: 0)
        }
        
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        return CustomTableRowView()
    }
    
    func outlineViewItemDidExpand(_ notification: Notification) {
        adjustColumnWidth()
        
        // 重新选中之前选中的项
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        if let item = notification.userInfo?["NSObject"] as? TreeNode,
           let children = item.children {
            for child in children {
                if child.fullPath == curFolder {
                    if let row = outlineView?.row(forItem: child),
                       row != -1 {
                        ifActWhenSelected=false
                        outlineView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        ifActWhenSelected=true
                        break
                    }
                }
            }
        }
        
    }
    
    func outlineViewItemDidCollapse(_ notification: Notification) {
        adjustColumnWidth()
    }
    
    func adjustColumnWidth() {
        guard let outlineView = outlineView else { return }
        
        DispatchQueue.main.async {

            let columnIndex = 0 // 指定你需要调整的列的索引
            // Specify the index of the column you need to adjust
            let column = outlineView.tableColumns[columnIndex]
            var maxWidth: CGFloat = 10
            
            // 遍历所有可见行
            // Iterate through all visible rows
            for i in 0..<outlineView.numberOfRows {
                // 获取每行对应列的单元格内容
                // Get cell content for each row's corresponding column
                if let item = outlineView.item(atRow: i) as? TreeNode {
                    // 计算这个单元格内容的宽度
                    // Calculate width of this cell content
                    let content = item.name
                    let attributes = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
                    let size = (content as NSString).size(withAttributes: attributes)
                    
                    // 获取当前行的层级，并计算缩进
                    // Get current row's level and calculate indentation
                    let level = outlineView.level(forRow: i)
                    let indentation = outlineView.indentationPerLevel * CGFloat(level)
                    
                    // 更新最大宽度
                    // Update maximum width
                    maxWidth = max(maxWidth, size.width + indentation + 30)  // 再留一点边距
                    // Leave some margin
                }
            }
            
            column.width = maxWidth
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        return .move
    }
    
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let outlineItem = item as? TreeNode else { return false }

        if let targetUrl = URL(string: outlineItem.fullPath) {
            let pasteboard = info.draggingPasteboard
            if let data = pasteboard.data(forType: .fileURL),
               let pasteboardUrl = URL(dataRepresentation: data, relativeTo: nil),
               pasteboardUrl == targetUrl {
                // URLs are identical, do not perform the move
                return false
            }
            
            getViewController(outlineView)?.handleMove(targetURL: targetUrl, pasteboard: pasteboard)
            getViewController(outlineView)?.refreshTreeView()
            return true
        }
        
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let outlineItem = item as? TreeNode else { return nil }
        
        let pasteboardItem = NSPasteboardItem()

        if let url=URL(string: outlineItem.fullPath) {
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
        }
        
        return pasteboardItem
    }
    
}

class CustomTableCellView: NSTableCellView {
    
//    override var backgroundStyle: NSView.BackgroundStyle {
//        didSet {
//            imageView?.contentTintColor = backgroundStyle == .emphasized ? NSColor.black : NSColor.green
//            // 检查是否处于选中状态
//            switch backgroundStyle {
//            case .emphasized: // 选中状态
//                textField?.textColor = NSColor.green
//                // 如果需要，还可以在这里修改imageView的contentTintColor
//            default: // 非选中状态
//                textField?.textColor = NSColor.red
//                // 根据需要恢复imageView的contentTintColor
//            }
//        }
//    }
}

class CustomTableRowView: NSTableRowView {

    override func drawSelection(in dirtyRect: NSRect) {
        if self.selectionHighlightStyle != .none {
            let selectionRect = NSInsetRect(self.bounds, 8, 1.5)//边距
            // Margin
            let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)//圆角半径
            // Corner radius
            
            // 自定义选中状态下的背景色
            // Customize background color in selected state
            let theme=NSApp.effectiveAppearance.name
            
            // 检查是否是第一响应者
            // Check if it's the first responder
            if let window = self.window, let firstResponder = window.firstResponder as? NSView, (firstResponder === self || self.isDescendant(of: firstResponder)) {
                if theme == .darkAqua {
                    // 暗模式下的颜色
                    // Color in dark mode
                    NSColor.controlAccentColor.setFill()
                } else {
                    // 光模式下的颜色
                    // Color in light mode
                    NSColor.controlAccentColor.setFill()
                }
            }else{
                NSColor.systemGray.setFill()
            }
            
            selectionPath.fill()
        }
    }

    // 为了更好的视觉效果，可能还需要重写背景色绘制方法
    // For better visual effect, may need to override background color drawing method
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        // 自定义非选中状态下的背景色
        // Customize background color in non-selected state
        let theme=NSApp.effectiveAppearance.name
        
        if theme == .darkAqua {
            // 暗模式下的颜色
            // Color in dark mode
            //hexToNSColor(hex: "#333333").setFill()
            NSColor(named: NSColor.Name("OutlineViewBgColor"))?.setFill()
        }else {
            // 光模式下的颜色
            // Color in light mode
            //hexToNSColor(hex: "#F4F5F5").setFill()
            NSColor(named: NSColor.Name("OutlineViewBgColor"))?.setFill()
        }

        __NSRectFillUsingOperation(dirtyRect, .sourceOver)
        
        let selectionRect = NSInsetRect(self.bounds, 9, 2.5) // 边距
        // Margin
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4) // 圆角半径
        // Corner radius
        // 获取当前 row 的 index
        // Get current row's index
        if let tableView = self.superview as? NSTableView {
            let rowIndex = tableView.row(for: self)
            if rowIndex == getViewController(self)?.outlineView.curRightClickedIndex {
                NSColor.controlAccentColor.setStroke() // 设置边框颜色
                // Set border color
                selectionPath.lineWidth = 2.0 // 设置边框宽度
                // Set border width
                selectionPath.stroke() // 绘制边框
                // Draw border
            }
        }
    }
}
