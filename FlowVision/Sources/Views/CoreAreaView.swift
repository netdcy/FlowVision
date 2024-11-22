//
//  CoreAreaView.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
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
    
    func showInfo(_ info: String, timeOut: Double = 1.0, cannotBeCleard: Bool = true) {
        infoView.showInfo(text: info, timeOut: timeOut)
        self.cannotBeCleard = cannotBeCleard
    }
    
    func hideInfo() {
        if !self.cannotBeCleard {
            infoView.hide()
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource == nil {
            return .link
        } else {
            return .every
        }
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if sender.draggingSource == nil {
            let pasteboard = sender.draggingPasteboard
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                getViewController(self)?.handleDraggedFiles(urls)
                return true
            }
            return false
        }else{
            return false
        }
        
    }
}
