//
//  CoreAreaView.swift
//  FlowVision
//

import Foundation
import Cocoa

class CoreAreaView: NSView {
    
    var infoView: InfoView!
    var cannotBeCleard: Bool = true
    
    // 拖拽悬停时的高亮，分屏后用来指示文件会落进哪个窗格
    // Hover highlight during a drag, it shows which pane the files will land in
    private var dropHighlightView: PaneDropHighlightView!
    
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
        dropHighlightView = PaneDropHighlightView(frame: bounds)
        dropHighlightView.autoresizingMask = [.width, .height]
        dropHighlightView.isHidden = true
        addSubview(dropHighlightView)

        infoView = InfoView(frame: .zero)
        infoView.setupView(fontSize: 20, fontWeight: .light, cornerRadius: 6.0, edge: (18,8))
        infoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoView)
        NSLayoutConstraint.activate([
            infoView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            infoView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    
    private func setDropHighlight(_ highlighted: Bool) {
        guard dropHighlightView.isHidden == highlighted else { return }
        dropHighlightView.isHidden = !highlighted
        if highlighted, subviews.last !== dropHighlightView {
            dropHighlightView.removeFromSuperview()
            addSubview(dropHighlightView)
        }
    }
    
    // 拖拽源是否就是本窗格自己的缩略图区域
    // Whether the drag started in this very pane's thumbnail area
    private func isDragFromThisPane(_ sender: NSDraggingInfo) -> Bool {
        guard let sourceView = sender.draggingSource as? CustomCollectionView else { return false }
        guard let viewController = getViewController(self) else { return false }
        return sourceView === viewController.collectionView
    }
    
    func showInfo(_ info: String, timeOut: Double = 1.0, duration: Double = INFO_VIEW_DURATION, cannotBeCleard: Bool) {
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
        // 把文件拖回它自己所在的窗格没有意义，直接拒绝，让光标显示"不可放下"
        // Dropping files back into the pane they came from is a no-op, refuse it so the cursor says "no drop"
        if isDragFromThisPane(sender) {
            return []
        }
        if let viewController = getViewController(self){
            if viewController.publicVar.isInLargeView {
                return .link
            }
        }
        // 分屏时高亮本窗格，让用户看清文件会落到哪边
        // Highlight this pane when split so it is obvious where the files will land
        if getViewController(self)?.isInSplitLayout == true {
            setDropHighlight(true)
        }
        return .every
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isDragFromThisPane(sender) {
            return []
        }
        if let viewController = getViewController(self), viewController.publicVar.isInLargeView {
            return .link
        }
        return .every
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlight(false)
    }
    
    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDropHighlight(false)
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropHighlight(false)
        if let viewController = getViewController(self) {
            if viewController.publicVar.isInLargeView {
                let pasteboard = sender.draggingPasteboard
                if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                    viewController.handleDraggedFiles(urls)
                    return true
                }
            }else{
                // 只拒绝来自本窗格自身的拖拽。分屏后同一个窗口里有多个窗格，
                // 按窗口判断会把窗格之间的拖放一并挡掉
                // Only refuse drags coming from this pane itself. A split window holds several panes,
                // so judging by window would block pane to pane drops as well
                if isDragFromThisPane(sender) {
                    return false
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

// 拖拽悬停时画在窗格上的边框，不接收鼠标事件
// Border drawn over a pane while a drag hovers it, never takes mouse events
class PaneDropHighlightView: NSView {
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    override var isOpaque: Bool {
        return false
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 4
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.stroke()
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        bounds.fill()
    }
}
