//
//  CustomEffectView.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/17.
//

import Foundation
import Cocoa

class CustomEffectView: NSVisualEffectView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let viewController = getViewController(self){
            if viewController.publicVar.isInLargeView {
                return .link
            }
        }
        return .every
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let viewController = getViewController(self) {
            if viewController.publicVar.isInLargeView {
                let pasteboard = sender.draggingPasteboard
                if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                    getViewController(self)?.handleDraggedFiles(urls)
                    return true
                }
            }else{
                if sender.draggingSource is CustomCollectionView {
                    return false
                }
                if let curFolderUrl = URL(string: viewController.fileDB.curFolder){
                    viewController.handleMove(targetURL: curFolderUrl, pasteboard: sender.draggingPasteboard)
                    if sender.draggingSource is CustomOutlineView {
                        viewController.refreshTreeView()
                    }
                    return true
                }
            }
        }
        return false
    }
    
}
