//
//  LargeImageView.swift
//  FlowVision
//
//  Created by netdcy on 2024/4/27.
//

import Foundation
import Cocoa

class LargeImageView: NSView {

    var imageView: InterpolatedImageView!
    var exifTextView: ExifTextView!
    var ratioView: InfoView!
    var infoView: InfoView!
    var file: FileModel = FileModel(path: "", ver: 0)
    private var lastDragLocation: CGPoint?
    private var hasZoomedByWheel: Bool = false
    var longPressZoomTimer: Timer?
    private var wheelZoomRegenTimer: Timer?
    private var initialPos: NSPoint? = nil
    
    private var initialScale: CGFloat = 1.0
    private var originalSize: CGSize?
    private let sensitivity: CGFloat = 1
    
    private var lastClickTime: TimeInterval = 0
    private var lastClickLocation: NSPoint = NSPoint.zero
    private let positionThreshold: CGFloat = 4.0 // 双击位置阈值，可以根据需要调整
    
    private var middleMouseInitialLocation: NSPoint?
    
    private var doNotPopRightMenu: Bool = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        imageView = InterpolatedImageView(frame: self.bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.animates=true
        self.addSubview(imageView)
        
        exifTextView = ExifTextView(frame: .zero)
        exifTextView.translatesAutoresizingMaskIntoConstraints = false
        exifTextView.isHidden=true
        addSubview(exifTextView)
        NSLayoutConstraint.activate([
            exifTextView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
            exifTextView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5)
        ])
        
        ratioView = InfoView(frame: .zero)
        ratioView.setupView(fontSize: 14, fontWeight: .regular, cornerRadius: 6.0, edge: (8,8))
        ratioView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ratioView)
        NSLayoutConstraint.activate([
            ratioView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -15),
            ratioView.topAnchor.constraint(equalTo: self.topAnchor, constant: 15)
        ])
        
        infoView = InfoView(frame: .zero)
        infoView.setupView(fontSize: 20, fontWeight: .light, cornerRadius: 6.0, edge: (18,8))
        infoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoView)
        NSLayoutConstraint.activate([
            infoView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            infoView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        
        let magnificationGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        self.addGestureRecognizer(magnificationGesture)
    }
    
    func updateTextItems(_ items: [(String, Any)]) {
        exifTextView.textItems = items
        exifTextView.invalidateIntrinsicContentSize()
    }
    
    func zoom(direction: Int = 0){
        //guard let originalSize = getViewController(self)?.getCurrentImageOriginalSizeInScreenScale() else { return }
        //let currentSize = imageView.bounds.size
//        var scale = 1.0
//        if direction == -1 {
//            scale = 0.8
//        }else if direction == +1 {
//            scale = 1.25
//        }
        //applyZoom(scale: scale, originalSize: currentSize, centerPoint: CGPoint(x: imageView.bounds.size.width/2, y: imageView.bounds.size.height/2))
        
        let zoomFactor: CGFloat = 1.25
        let locationInView = self.convert(NSPoint(x: self.frame.size.width / 2, y: self.frame.size.height / 2), from: nil)
        let locationInImageView = imageView.convert(locationInView, from: self)
        
        if direction > 0 {
            if isExceedZoomLimit(enlarge: true, width: imageView.frame.size.width, height: imageView.frame.size.height){
                return
            }
            hasZoomedByWheel=true
            
            imageView.frame.size.width *= zoomFactor
            imageView.frame.size.height *= zoomFactor
            imageView.frame.origin.x -= (locationInImageView.x * (zoomFactor - 1))
            imageView.frame.origin.y -= (locationInImageView.y * (zoomFactor - 1))
        } else if direction < 0 {
            if isExceedZoomLimit(enlarge: false, width: imageView.frame.size.width, height: imageView.frame.size.height){
                return
            }
            hasZoomedByWheel=true
            
            imageView.frame.size.width /= zoomFactor
            imageView.frame.size.height /= zoomFactor
            imageView.frame.origin.x += (locationInImageView.x * (1 - 1/zoomFactor))
            imageView.frame.origin.y += (locationInImageView.y * (1 - 1/zoomFactor))
        }
        
        //重新绘制图像
        getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false)
        
        showRatio()
    }
    
    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        let magnification = 1 + gesture.magnification * sensitivity
        
        switch gesture.state {
        case .began:
            initialScale = imageView.frame.width / imageView.bounds.width
            originalSize = imageView.bounds.size
        case .changed:
            if let originalSize = originalSize {
                let scale = initialScale * magnification
                applyZoom(scale: scale, originalSize: originalSize, centerPoint: gesture.location(in: imageView))
            }
        case .ended:
            initialScale *= magnification
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false)
        default:
            break
        }
        
        //缩放后防止意外滚动
        _ = getViewController(self)?.publicVar.timer.intervalSafe(name: "largeImageZoomForbidSwitch", second: -1)
    }
    
    private func applyZoom(scale: CGFloat, originalSize: CGSize, centerPoint: CGPoint) {
        let newWidth = originalSize.width * scale
        let newHeight = originalSize.height * scale
        
        if scale>1{
            if isExceedZoomLimit(enlarge: true, width: newWidth, height: newHeight){
                return
            }
        }else{
            if isExceedZoomLimit(enlarge: false, width: newWidth, height: newHeight){
                return
            }
        }
        
        
        let deltaWidth = newWidth - imageView.frame.width
        let deltaHeight = newHeight - imageView.frame.height
        
        let newOriginX = imageView.frame.origin.x - deltaWidth * (centerPoint.x / imageView.frame.width)
        let newOriginY = imageView.frame.origin.y - deltaHeight * (centerPoint.y / imageView.frame.height)
        
        imageView.frame = CGRect(x: newOriginX, y: newOriginY, width: newWidth, height: newHeight)
        
        showRatio()
    }
    
    func showRatio() {
        let ratio=String(Int(imageView.frame.size.width/customZoomSize().width*100))
        ratioView.showInfo(text: NSLocalizedString("zoom", comment: "缩放")+": "+ratio+"%")
    }
    
    func showInfo(_ info: String) {
        infoView.showInfo(text: info, timeOut: 1.0)
    }
    
    func customZoomSize() -> NSSize {
        // 返回您希望的缩放大小
        if let result=getViewController(self)?.getCurrentImageOriginalSizeInScreenScale(){
            return result
        }
        return NSSize(width: imageView.frame.width * 2, height: imageView.frame.height * 2)
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        getViewController(self)!.publicVar.isLeftMouseDown = true//临时按住左键也能缩放
        initialPos =  self.convert(event.locationInWindow, from: nil)
        lastDragLocation = initialPos
        doNotPopRightMenu = false
        
        // 设置定时器实现长按检测
        longPressZoomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.performLongPressZoom(at: event.locationInWindow)
        }
        
        // 检测双击
        let currentTime = event.timestamp
        let currentLocation = event.locationInWindow
        if currentTime - lastClickTime < NSEvent.doubleClickInterval &&
            distanceBetweenPoints(lastClickLocation, currentLocation) < positionThreshold {
            getViewController(self)?.closeLargeImage(0)
        }
        lastClickTime = currentTime
        lastClickLocation = currentLocation
    }

    private func performLongPressZoom(at point: NSPoint) {
        
        doNotPopRightMenu=true
        
        if !getViewController(self)!.publicVar.isInLargeView || !getViewController(self)!.publicVar.isInLargeViewAfterAnimate {
            //由于在大图状态下双击关闭又快速连击，会导致此处被异常调用，所以加以限制
            return
        }

        if !getViewController(self)!.publicVar.isRightMouseDown {
            let zoomSize=customZoomSize()
            let locationInView = self.convert(point, from: nil)
            let locationInImageView = imageView.convert(locationInView, from: self)
            
            let zoomFactorWidth = zoomSize.width / imageView.frame.width
            let zoomFactorHeight = zoomSize.height / imageView.frame.height
            
            // 计算新的图像尺寸和位置
            imageView.frame.size = zoomSize
            imageView.frame.origin.x -= (locationInImageView.x * (zoomFactorWidth - 1))
            imageView.frame.origin.y -= (locationInImageView.y * (zoomFactorHeight - 1))
            
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: true)
        }else{
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: true)
        }
        
        showRatio()
        
        //hasZoomed=true
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        getViewController(self)!.publicVar.isLeftMouseDown = false//临时按住左键也能缩放
        initialPos=nil
        longPressZoomTimer?.invalidate()
        longPressZoomTimer = nil
        wheelZoomRegenTimer?.invalidate()
        wheelZoomRegenTimer = nil
        
        if hasZoomedByWheel {
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false)
        }
        hasZoomedByWheel=false
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let lastLocation = lastDragLocation else { return }
        let newLocation = self.convert(event.locationInWindow, from: nil)
        if initialPos != nil{
            if abs(initialPos!.x-newLocation.x) + abs(initialPos!.y-newLocation.y) > 2 {
                longPressZoomTimer?.invalidate()
                longPressZoomTimer = nil
                doNotPopRightMenu = true
            }
        }
        
        let dx = newLocation.x - lastLocation.x
        let dy = newLocation.y - lastLocation.y

        imageView.frame.origin.x += dx
        imageView.frame.origin.y += dy

        lastDragLocation = newLocation
    }
    
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { // 检查是否按下了鼠标中键
            middleMouseInitialLocation = event.locationInWindow
        } else {
            super.otherMouseDown(with: event)
        }
    }
    
    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == 2, let middleMouseInitialLocation = middleMouseInitialLocation {
            let newLocation = event.locationInWindow
            let deltaX = newLocation.x - middleMouseInitialLocation.x
            let deltaY = newLocation.y - middleMouseInitialLocation.y
            
            if let window = self.window {
                var frame = window.frame
                frame.origin.x += deltaX
                frame.origin.y += deltaY
                window.setFrame(frame, display: true)
            }
        } else {
            super.otherMouseDragged(with: event)
        }
    }
    
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            middleMouseInitialLocation = nil
        } else {
            super.otherMouseUp(with: event)
        }
    }
    
    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        getViewController(self)!.publicVar.isRightMouseDown = true
        mouseDown(with: event)
        //super.rightMouseDown(with: event)  // 继续传递事件
    }

    override func rightMouseUp(with event: NSEvent) {
        getViewController(self)!.publicVar.isRightMouseDown = false
        mouseUp(with: event)
        
        if !doNotPopRightMenu{
            //弹出菜单
            let menu = NSMenu(title: "Custom Menu")
            menu.autoenablesItems = false
            
            let actionItemClose = menu.addItem(withTitle: NSLocalizedString("close", comment: "关闭"), action: #selector(actClose), keyEquivalent: " ")
            actionItemClose.keyEquivalentModifierMask = []
            
            let actionItemOpenInNewTab = menu.addItem(withTitle: NSLocalizedString("open-in-new-tab", comment: "在新标签页中打开"), action: #selector(actOpenInNewTab), keyEquivalent: "")
            if isWindowNumMax() {
                actionItemOpenInNewTab.isEnabled=false
            }else{
                actionItemOpenInNewTab.isEnabled=true
            }
            
            menu.addItem(NSMenuItem.separator())
            
            if URL(string: file.path)!.hasDirectoryPath == false {
                addOpenWithSubMenu(to: menu, for: URL(string: file.path)!)
            }
            
            menu.addItem(withTitle: NSLocalizedString("show-in-finder", comment: "在Finder中显示"), action: #selector(actShowInFinder), keyEquivalent: "")
            
            let actionItemRename = menu.addItem(withTitle: NSLocalizedString("rename", comment: "重命名"), action: #selector(actRename), keyEquivalent: "\r")
            actionItemRename.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemDelete = menu.addItem(withTitle: NSLocalizedString("move-to-trash", comment: "移动到废纸篓"), action: #selector(actDelete), keyEquivalent: "\u{8}")
            actionItemDelete.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemCopy = menu.addItem(withTitle: NSLocalizedString("copy", comment: "复制"), action: #selector(actCopy), keyEquivalent: "c")
            
            let actionItemShare = menu.addItem(withTitle: NSLocalizedString("Share...", comment: "共享..."), action: #selector(actShare(_:)), keyEquivalent: "")
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemCopyToDownload = menu.addItem(withTitle: NSLocalizedString("copy-to-download", comment: "复制到\"下载\"文件夹"), action: #selector(actCopyToDownload), keyEquivalent: "n")
            actionItemCopyToDownload.keyEquivalentModifierMask = []
            
            let actionItemMoveToDownload = menu.addItem(withTitle: NSLocalizedString("move-to-download", comment: "移动到\"下载\"文件夹"), action: #selector(actMoveToDownload), keyEquivalent: "m")
            actionItemMoveToDownload.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemShowExif = menu.addItem(withTitle: NSLocalizedString("show-exif", comment: "显示Exif信息"), action: #selector(actShowExif), keyEquivalent: "i")
            actionItemShowExif.keyEquivalentModifierMask = []
            actionItemShowExif.state = getViewController(self)!.publicVar.isShowExif ? .on : .off
            
            let actionItemQRCode = menu.addItem(withTitle: NSLocalizedString("recognize-QRCode", comment: "识别二维码"), action: #selector(actQRCode), keyEquivalent: "")
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemRotateR = menu.addItem(withTitle: NSLocalizedString("rotate-clockwise", comment: "顺时针旋转"), action: #selector(actRotateR), keyEquivalent: "e")
            actionItemRotateR.keyEquivalentModifierMask = []
            
            let actionItemRotateL = menu.addItem(withTitle: NSLocalizedString("rotate-counterclockwise", comment: "逆时针旋转"), action: #selector(actRotateL), keyEquivalent: "q")
            actionItemRotateL.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemRefresh = menu.addItem(withTitle: NSLocalizedString("refresh", comment: "刷新"), action: #selector(actRefresh), keyEquivalent: "r")
            actionItemRefresh.keyEquivalentModifierMask = []
            
            menu.items.forEach { $0.target = self }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        
        //super.rightMouseDragged(with: event)  // 继续传递事件
    }
    
    override func scrollWheel(with event: NSEvent) {
        //保证鼠标在图像上才缩放
        //guard imageView.frame.contains(event.locationInWindow) else { return }

        if getViewController(self)!.publicVar.isRightMouseDown || getViewController(self)!.publicVar.isLeftMouseDown {
            
            //注意：触控板按下右键的同时会触发deltaY为0的滚动事件
            if abs(event.deltaY) > 0 {
                longPressZoomTimer?.invalidate()
                longPressZoomTimer = nil
                doNotPopRightMenu=true
            }
            
            do {
                wheelZoomRegenTimer?.invalidate()
                wheelZoomRegenTimer = nil
                wheelZoomRegenTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    guard let self=self else{return}
                    getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false)
                    self.hasZoomedByWheel=false
                }
            }

            let zoomFactor: CGFloat = 1.1
            let locationInView = self.convert(event.locationInWindow, from: nil)
            let locationInImageView = imageView.convert(locationInView, from: self)
            
            if event.deltaY > 0 {
                if isExceedZoomLimit(enlarge: true, width: imageView.frame.size.width, height: imageView.frame.size.height){
                    return
                }
                hasZoomedByWheel=true
                
                imageView.frame.size.width *= zoomFactor
                imageView.frame.size.height *= zoomFactor
                imageView.frame.origin.x -= (locationInImageView.x * (zoomFactor - 1))
                imageView.frame.origin.y -= (locationInImageView.y * (zoomFactor - 1))
            } else if event.deltaY < 0 {
                if isExceedZoomLimit(enlarge: false, width: imageView.frame.size.width, height: imageView.frame.size.height){
                    return
                }
                hasZoomedByWheel=true
                
                imageView.frame.size.width /= zoomFactor
                imageView.frame.size.height /= zoomFactor
                imageView.frame.origin.x += (locationInImageView.x * (1 - 1/zoomFactor))
                imageView.frame.origin.y += (locationInImageView.y * (1 - 1/zoomFactor))
            }
            //log(imageView.frame.size,imageView.frame.origin)
            
            showRatio()
        }
    }
    
    func isExceedZoomLimit(enlarge: Bool, width: Double, height: Double) -> Bool {
        guard let originalSize = getViewController(self)?.getCurrentImageOriginalSizeInScreenScale() else { return false }
        
//        if enlarge && width>originalSize.width && (min(width,height) > 20000) {
//            return true
//        }
//        if !enlarge && width<originalSize.width && (max(width,height) < 200) {
//            return true
//        }
        
        if enlarge && width>originalSize.width*8 {
            return true
        }
        if !enlarge && width<originalSize.width/2 && (max(width,height) < 200)  {
            return true
        }
        
        return false
    }
    
    func addOpenWithSubMenu(to menu: NSMenu, for fileUrl: URL) {
        let openWithMenu = NSMenu(title: "openWith")
        let openWithMenuItem = NSMenuItem(title: NSLocalizedString("open-with", comment: "打开方式"), action: nil, keyEquivalent: "")
        openWithMenuItem.submenu = openWithMenu
        
        // 获取可以打开文件的应用程序列表
        let cfFileUrl = fileUrl as CFURL
        let appURLs = LSCopyApplicationURLsForURL(cfFileUrl, .all)?.takeRetainedValue() as? [URL] ?? []
        
        for appURL in appURLs {
            let appName = FileManager.default.displayName(atPath: appURL.path)
            let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            let appMenuItem = NSMenuItem(title: appName.replacingOccurrences(of: ".app", with: " "), action: #selector(openFileWithApp(_:)), keyEquivalent: "")
            appMenuItem.representedObject = appURL
            appMenuItem.target = self
            appMenuItem.image = appIcon
            appMenuItem.image?.size = NSSize(width: 16, height: 16)  // Optionally resize the icon if needed
            openWithMenu.addItem(appMenuItem)
        }
        
        // 添加到主菜单
        menu.addItem(openWithMenuItem)
    }
    
    @objc func openFileWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL, let fileUrl = URL(string: file.path)
            else { return }
        
        NSWorkspace.shared.open([fileUrl], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: { (app, error) in
            if let error = error {
                log("Error opening file: \(error.localizedDescription)")
            } else if let app = app {
                log("Application \(app.localizedName ?? "Unknown") opened")
            }
        })
    }
    
    @objc func actOpenInNewTab() {
        if let appDelegate=NSApplication.shared.delegate as? AppDelegate {
            globalVar.isLaunchFromFile=true
            if let windowController = appDelegate.createNewWindow(file.path) {
                appDelegate.openImageInTargetWindow(file.path, windowController: windowController)
            }
        }
    }
    
    @objc func actShowInFinder() {
        let folderPath = (file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding! as NSString).deletingLastPathComponent
        // 使用NSWorkspace的实例来显示文件
        NSWorkspace.shared.selectFile(file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!, inFileViewerRootedAtPath: folderPath)
    }
    @objc func actRename() {
        renameAlert(url: URL(string: file.path)!);
    }
    
    @objc func actCopy() {
        getViewController(self)?.handleCopy()
    }
    
    @objc func actCopyToDownload() {
        getViewController(self)?.handleCopyToDownload()
    }
    
    @objc func actMoveToDownload() {
        getViewController(self)?.handleMoveToDownload()
    }

    @objc func actDelete() {
        getViewController(self)?.handleDelete()
    }
    
    @objc func actRefresh() {
        file.rotate = 0
        getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false)
    }
    
    @objc func actShowExif() {
        getViewController(self)!.publicVar.isShowExif.toggle()
        //exifTextView.isHidden = !getViewController(self)!.publicVar.isShowExif
    }
    
    @objc func actQRCode() {
        if let image=file.image,
           let qrCodes = recognizeQRCode(from: image) {
            let text=qrCodes.joined(separator: "\n")
            showInformationCopy(title: NSLocalizedString("qrcode-recog-result", comment: "二维码识别结果"), message: text)
        } else {
            showAlert(message: NSLocalizedString("qrcode-recog-fail", comment: "未能识别到二维码"))
        }
    }
    
    @objc func actRotateR() {
        file.rotate = (file.rotate+1)%4
        getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false)
    }
    
    @objc func actRotateL() {
        file.rotate = (file.rotate+3)%4
        getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false)
    }
    
    @objc func actClose() {
        getViewController(self)?.closeLargeImage(0)
    }
    
    @objc func actShare(_ sender: NSMenuItem) {
        guard let fileUrl = URL(string: file.path) else { return }
        let sharingServicePicker = NSSharingServicePicker(items: [fileUrl])
        let centerPoint = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
        let rect = NSRect(origin: NSPoint(x: centerPoint.x - 5, y: centerPoint.y - 5), size: NSSize(width: 10, height: 10))
        sharingServicePicker.show(relativeTo: rect, of: self, preferredEdge: .maxX)
    }
}


class ExifTextView: NSView {

    var textItems: [(String, Any)] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !textItems.isEmpty else { return }

        let backgroundColor = NSColor.black.withAlphaComponent(0.5)
        backgroundColor.setFill()

        let padding: CGFloat = 10
        let rect = NSInsetRect(self.bounds, padding, padding)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        path.fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle
        ]

        let keyAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle
        ]

        var yOffset: CGFloat = rect.origin.y + rect.height - padding

        let keyMaxWidth = textItems.map { $0.0.size(withAttributes: keyAttributes).width }.max() ?? 0

        for (key, value) in textItems {
            if key == "-" {
                // 绘制分割线
                let lineRect = NSRect(x: rect.origin.x + padding, y: yOffset - 7, width: rect.width - padding * 2, height: 1)
                NSColor.white.setFill()
                lineRect.fill()
                yOffset -= 14 // 分割线高度 + 间距
                continue
            }

            let keyString = NSString(string: key)
            let valueString = NSString(string: String(describing: value))
            
            let keySize = keyString.size(withAttributes: keyAttributes)
            let valueSize = valueString.size(withAttributes: attributes)

            let keyX = rect.origin.x + padding
            let valueX = keyX + keyMaxWidth + 10

            keyString.draw(at: CGPoint(x: keyX, y: yOffset - keySize.height), withAttributes: keyAttributes)
            valueString.draw(at: CGPoint(x: valueX, y: yOffset - valueSize.height), withAttributes: attributes)

            yOffset -= max(keySize.height, valueSize.height) + 5
        }
    }

    override var intrinsicContentSize: NSSize {
        let padding: CGFloat = 10
        let keyMaxWidth = textItems.map { $0.0.size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: 14)]).width }.max() ?? 0
        let valueMaxWidth = textItems.map { String(describing: $0.1).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width }.max() ?? 0

        let lineHeight = "Sample".size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).height
        var numLines = CGFloat(textItems.count) + 1
        var additionalHeight: CGFloat = 0
        
        for (key, _) in textItems {
            if key == "-" {
                additionalHeight += 18 // 分割线高度 + 间距
                numLines -= 1 // 分割线不算在内
            }
        }

        let height = numLines * lineHeight + (numLines - 1) * 5 + padding * 2 + additionalHeight
        let width = keyMaxWidth + valueMaxWidth + 35 + padding * 2

        return NSSize(width: width, height: height)
    }
}

class InfoView: NSView {

    private var label: NSTextField!
    private var hideTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        //setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        //setupView()
    }
    
    func setupView(fontSize: Double = 14, fontWeight: NSFont.Weight = .regular, cornerRadius: Double = 5.0, edge: (Double,Double) = (8,8)) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = cornerRadius
        
        label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        addSubview(label)
        
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: edge.0),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -edge.0),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: edge.1),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -edge.1)
        ])
        
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0
    }
    
    func showInfo(text: String, timeOut: Double = 2.0) {
        // Update text
        label.stringValue = text

        // Invalidate previous timer
        hideTimer?.invalidate()
        
        // Show the view with fade-in animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 1.0
        })
        
        // Set a timer to hide the view after xx seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: timeOut, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
    
    private var isAnimating = false
    
    func hide() {
        // Check if the view is already hidden or currently animating
        guard !isAnimating, self.alphaValue != 0.0 else { return }
        
        isAnimating = true
        // Hide the view with fade-out animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0.0
        }) {
            // Animation completion handler
            self.isAnimating = false
        }
    }
}
