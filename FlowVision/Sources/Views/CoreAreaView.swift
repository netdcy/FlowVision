//
//  CoreAreaView.swift
//  FlowVision
//

import Foundation
import Cocoa

class CoreAreaView: NSView {
    
    var infoView: InfoView!
    var cannotBeCleard: Bool = true
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        infoView = InfoView(frame: .zero)
        infoView.setupView(fontSize: 20, fontWeight: .light, cornerRadius: 6.0, edge: (18,8))
        infoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoView)
        NSLayoutConstraint.activate([
            infoView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            infoView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    
    func showInfo(_ info: String, timeOut: Double = 1.0, duration: Double = INFO_VIEW_DURATION, cannotBeCleard: Bool = true) {
        infoView.showInfo(text: info, timeOut: timeOut, duration: duration)
        self.cannotBeCleard = cannotBeCleard
    }
    
    func hideInfo(force: Bool = false, duration: Double = INFO_VIEW_DURATION) {
        if !self.cannotBeCleard || force {
            infoView.hide(duration: duration)
        }
    }
    
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
                if let source = sender.draggingSource {
                    if source is CustomCollectionView && (source as? NSView)?.window == self.window {
                        return false
                    }
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
    
    override func otherMouseDown(with event: NSEvent) {
        // back
        if event.buttonNumber == 3 {
            if let viewController = getViewController(self) {
                if viewController.publicVar.isInLargeView{
                    viewController.previousLargeImage()
                }else{
                    viewController.handleHistoryBack()
                }
            }
        // forward
        } else if event.buttonNumber == 4 {
            if let viewController = getViewController(self) {
                if viewController.publicVar.isInLargeView{
                    viewController.nextLargeImage()
                }else{
                    viewController.handleHistoryForward()
                }
            }
        } else {
            super.otherMouseDown(with: event)
        }
    }
}
