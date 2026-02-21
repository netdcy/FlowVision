//
//  CustomImageView.swift
//  FlowVision
//

import Foundation
import Cocoa

class CustomImageView: NSImageView {
    
    var isFolder = false
    var url: URL? = nil

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let viewController = getViewController(self){
            if viewController.publicVar.isInLargeView {
                return .link
            }else if isFolder{
                return .copy
            }
        }
        return .every
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            sender.draggingPasteboard.clearContents()
        }
        
        if let viewController = getViewController(self){
            if viewController.publicVar.isInLargeView {
                let pasteboard = sender.draggingPasteboard
                if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                    getViewController(self)?.handleDraggedFiles(urls)
                    return true
                }
            }else if isFolder{
                getViewController(self)?.handleMove(targetURL: url, pasteboard: sender.draggingPasteboard)
                return true
            }else{
                if sender.draggingSource is CustomCollectionView {
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
    
    var center: CGPoint {
        get {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        set(newCenter) {
            var newFrame = frame
            newFrame.origin.x = newCenter.x - (newFrame.size.width / 2)
            newFrame.origin.y = newCenter.y - (newFrame.size.height / 2)
            frame = newFrame
        }
    }
}

class BorderedImageView: IntegerImageView {
    
    var isDrawBorder=false
    
    // 发现会导致加载速度变慢，因此暂时不使用
    // Found to cause slower loading speed, so temporarily not used
//    override func draw(_ dirtyRect: NSRect) {
//        super.draw(dirtyRect)
//        
//        if isDrawBorder {
//            drawBorder(dirtyRect)
//        }
//    }
    
    func drawBorder(_ dirtyRect: NSRect) {
        // 确保图像存在
        // Ensure image exists
        guard let image = self.image else {
            return
        }
        
        // 设置边框颜色和宽度
        // Set border color and width
        let borderColor = NSColor.gray
        let borderWidth: CGFloat = 2.0
        
        // 计算图像在视图中的绘制区域，考虑边框宽度
        // Calculate image drawing area in view, considering border width
        let imageSize = image.size
        let viewSize = self.bounds.size
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height
        
        var drawRect = NSRect.zero
        
        if imageAspect > viewAspect {
            drawRect.size.width = viewSize.width - 2 * borderWidth
            drawRect.size.height = drawRect.size.width / imageAspect
            drawRect.origin.y = (viewSize.height - drawRect.size.height) / 2
            drawRect.origin.x = borderWidth
        } else {
            drawRect.size.height = viewSize.height - 2 * borderWidth
            drawRect.size.width = drawRect.size.height * imageAspect
            drawRect.origin.x = (viewSize.width - drawRect.size.width) / 2
            drawRect.origin.y = borderWidth
        }
        
        // 平移绘制区域以确保边框不会被裁剪
        // Translate drawing area to ensure border won't be clipped
        drawRect = drawRect.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2)
        
        // 绘制图像
        // Draw image
        // image.draw(in: drawRect)
        
        // 绘制边框
        // Draw border
        borderColor.set()
        let borderPath = NSBezierPath(rect: drawRect)
        borderPath.lineWidth = borderWidth
        borderPath.stroke()
    }

}

class InterpolatedImageView: CustomImageView {
    // 对于小图此方法可以提高质量
    // For small images this method can improve quality
    // 但只要override，即使不设置插值方法，也会导致巨大图像例如清明上河图100%显示时不够清晰，奇怪
    // But just by overriding, even without setting interpolation method, it causes large images like "Along the River During the Qingming Festival" to be unclear at 100% display, strange
    // 因此暂时不使用
    // So temporarily not used
//    override func draw(_ dirtyRect: NSRect) {
//        NSGraphicsContext.current!.imageInterpolation = NSImageInterpolation.high
//        super.draw(dirtyRect)
//    }
}

class IntegerImageView: CustomImageView {
    // Use floating-point numbers to store the precise position and size
    private var internalOrigin: CGPoint = .zero
    private var internalSize: CGSize = .zero
    
    func getIntFrame () -> NSRect {
        return super.frame
    }

    // Override frame property
    override var frame: NSRect {
        get {
            // Return the frame with precise origin and size
            return NSRect(origin: internalOrigin, size: internalSize)
        }
        set {
            // Update internal floating-point origin and size
            internalOrigin = newValue.origin
            internalSize = newValue.size
            
            // Calculate rounded origin and size
            let newRoundedOrigin = CGPoint(x: round(newValue.origin.x), y: round(newValue.origin.y))
            let newRoundedSize = CGSize(width: round(newValue.size.width), height: round(newValue.size.height))
            
            // Only update the frame if it actually needs to change
            if super.frame.origin != newRoundedOrigin || super.frame.size != newRoundedSize {
                super.frame = NSRect(origin: newRoundedOrigin, size: newRoundedSize)
            }
        }
    }
}

class CustomThumbImageView: BorderedImageView {
    
}

class CustomLargeImageView: IntegerImageView {
    var isMirroredH: Bool = false
    
    override var image: NSImage? {
        get { return super.image }
        set {
            if isMirroredH, let img = newValue {
                super.image = img.flippedHorizontally()
            } else {
                super.image = newValue
            }
        }
    }
    
    // 对当前显示的图像执行翻转（翻转的翻转=还原，无需保存原图）
    // Flip the currently displayed image (flip of flip = restore, no need to save original)
    func updateMirror() {
        if let img = super.image {
            super.image = img.flippedHorizontally()
        }
    }
}
