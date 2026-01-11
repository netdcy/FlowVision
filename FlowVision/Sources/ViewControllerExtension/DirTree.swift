//
//  DirTree.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    private func findItemsToExpand(outlineView: NSOutlineView, targetPaths: [String], currentPath: [String], currentItem: Any?, itemsToExpand: inout Set<AnyHashable>) {
        guard !targetPaths.isEmpty else { return }
        
        outlineView.expandItem(currentItem)
        
        let childrenCount = outlineView.numberOfChildren(ofItem: currentItem)
        for index in 0..<childrenCount {
            if let item = outlineView.child(index, ofItem: currentItem),
               let itemObject = (item as? TreeNode)
            {
                let itemName = itemObject.name
                let newPath = currentPath + [itemName]
                
                if targetPaths.starts(with: newPath) {
                    _=itemsToExpand.insert(itemObject)
                    findItemsToExpand(outlineView: outlineView, targetPaths: targetPaths, currentPath: newPath, currentItem: item, itemsToExpand: &itemsToExpand)
                }
            }
        }
    }
    
    private func adjustExpansion(outlineView: NSOutlineView, parentItem: Any?, itemsToExpand: Set<AnyHashable>, doCollapse: Bool) {
        let childrenCount = outlineView.numberOfChildren(ofItem: parentItem)
        for index in 0..<childrenCount {
            if let item = outlineView.child(index, ofItem: parentItem),
               let itemObject = (item as? TreeNode) {
                if itemsToExpand.contains(itemObject) {
                    outlineView.expandItem(item)
                } else {
                    if doCollapse{
                        outlineView.collapseItem(item, collapseChildren: true)
                    }
                }
                adjustExpansion(outlineView: outlineView, parentItem: item, itemsToExpand: itemsToExpand, doCollapse: doCollapse)
            }
        }
    }
    
    private func selectFinalItem(outlineView: NSOutlineView, targetPaths: [String]) {
        var currentItem: Any? = nil
        for path in targetPaths {
            let count = outlineView.numberOfChildren(ofItem: currentItem)
            var found = false
            for index in 0..<count {
                if let item = outlineView.child(index, ofItem: currentItem),
                   let itemObject = (item as? TreeNode),
                   itemObject.name == path {
                    currentItem = item
                    found = true
                    break
                }
            }
            if !found {
                outlineViewManager.ifActWhenSelected=false
                outlineView.selectRowIndexes([], byExtendingSelection: false)
                outlineViewManager.ifActWhenSelected=true
                return
            }
        }
        if let finalItem = currentItem, let rowIndex = outlineView.row(forItem: finalItem) as Int? {
            outlineViewManager.ifActWhenSelected=false
            outlineView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
            outlineView.scrollRowToVisible(rowIndex)
            outlineViewManager.ifActWhenSelected=true
        }
    }
    
    func treeReLocate(path: String, doCollapse: Bool, expandLast: Bool) {
        var path=path
        var isInExternal=false
        
        // 注：由于此函数获取的是volumeIsInternal属性为false的真外部卷，对于第二块硬盘、分区会没有，因此不再使用
        // Note: This function retrieves true external volumes where volumeIsInternal is false, which won't include second hard drives or partitions, so it's no longer used.
//        let externalVolumes=VolumeManager.shared.getExternalVolumes()
//        for exUrl in externalVolumes {
//            if path.hasPrefix(exUrl.absoluteString) {
//                path=exUrl.lastPathComponent+"/"+path.replacingOccurrences(of: exUrl.absoluteString, with: "")
//                isInExternal=true
//                break
//            }
//        }

        if let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
            for exUrl in urls {
                if exUrl.absoluteString == "file:///" {continue}
                if path.hasPrefix(exUrl.absoluteString) {
                    path=exUrl.lastPathComponent+"/"+path.replacingOccurrences(of: exUrl.absoluteString, with: "")
                    isInExternal=true
                    break
                }
            }
        }

        var targetPaths = path.replacingOccurrences(of: rootFolder, with: "").removingPercentEncoding!.components(separatedBy: "/")
        targetPaths.removeLast()
        log("Locate:",targetPaths)
        
        // 额外插入一层用来定位
        // Insert an additional layer for positioning
        if treeRootFolder == "root" && !isInExternal {
            targetPaths.insert(ROOT_NAME, at: 0)
        }
        
        // 标签
        // Tags
        if path.contains("VirtualTagFolder") {
            targetPaths = ["Tag " + URL(string: path)!.lastPathComponent]
        }
        
        if targetPaths.isEmpty {
            outlineView.deselectAll(nil)
        }else{
            let last=targetPaths.last!
            if !expandLast {targetPaths.removeLast()}
            
            // 用于记录应当展开的项
            var itemsToExpand = Set<AnyHashable>()
            
            // 找到应该展开的项
            findItemsToExpand(outlineView: outlineView, targetPaths: targetPaths, currentPath: [], currentItem: nil, itemsToExpand: &itemsToExpand)
            
            // 展开找到的项，并折叠不在路径上的项
            adjustExpansion(outlineView: outlineView, parentItem: nil, itemsToExpand: itemsToExpand, doCollapse: doCollapse)
            
            if !expandLast {targetPaths.append(last)}
            // 选择最后一项
            selectFinalItem(outlineView: outlineView, targetPaths: targetPaths)
        }
    }
}
