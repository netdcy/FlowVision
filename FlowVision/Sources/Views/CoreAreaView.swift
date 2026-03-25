//
//  CoreAreaView.swift
//  FlowVision
//

import Foundation
import Cocoa

class CoreAreaView: NSView {
    
    var infoView: InfoView!
    var cannotBeCleard: Bool = true
    
    private var scanProgressView: NSView?
    private var scanProgressLabel: NSTextField?
    var onScanCancel: (() -> Void)?
    
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
    
    // MARK: - Scan Progress Overlay
    
    func showScanProgress(_ message: String) {
        if scanProgressView == nil {
            setupScanProgressView()
        }
        scanProgressLabel?.stringValue = message
        
        guard let overlay = scanProgressView, overlay.isHidden else { return }
        overlay.isHidden = false
        overlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            overlay.animator().alphaValue = 1.0
        }
    }
    
    func hideScanProgress(delayed: Double = 0) {
        guard let overlay = scanProgressView, !overlay.isHidden else { return }
        let hide = { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                overlay.animator().alphaValue = 0
            }) {
                overlay.isHidden = true
                overlay.removeFromSuperview()
                self?.scanProgressView = nil
                self?.scanProgressLabel = nil
            }
        }
        if delayed > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delayed) { hide() }
        } else {
            hide()
        }
    }
    
    private func setupScanProgressView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.82).cgColor
        container.layer?.cornerRadius = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let cancelBtn = ClickableLabel(title: NSLocalizedString("Cancel", comment: "取消")) { [weak self] in
            self?.onScanCancel?()
            self?.hideScanProgress()
        }
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        container.addSubview(cancelBtn)
        addSubview(container)
        
        NSLayoutConstraint.activate([
            container.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -16),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            cancelBtn.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            cancelBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            cancelBtn.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            cancelBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        
        container.isHidden = true
        scanProgressView = container
        scanProgressLabel = label
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
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
                    let pasteboard = sender.draggingPasteboard
                    if viewController.handleFilePromiseDrop(targetURL: curFolderUrl, pasteboard: pasteboard) {
                        return true
                    }
                    viewController.handleMove(targetURL: curFolderUrl, pasteboard: pasteboard)
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
