//
//  CustomImageView.swift
//  FlowVision
//
//  Created by netdcy on 2024/6/4.
//

import Foundation
import Cocoa

class CustomImageView: NSImageView {
    
    var isFolder = false
    var url: URL? = nil

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource == nil {
            return .link
        } else if isFolder && sender.draggingSource is CustomCollectionView {
            return .copy
        } else {
            return .every
        }
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            sender.draggingPasteboard.clearContents()
        }
        
        if sender.draggingSource == nil {
            let pasteboard = sender.draggingPasteboard
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                getViewController(self)?.handleDraggedFiles(urls)
                return false
            }
            return false
        } else if isFolder && sender.draggingSource is CustomCollectionView {
            getViewController(self)?.handleMove(targetURL: url, pasteboard: sender.draggingPasteboard)
            //getViewController(self)?.refreshAll()
            return true
        } else {
            return false
        }
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

class BorderedImageView: CustomImageView {
    
    var isDrawBorder=false
    
    //发现会导致加载速度变慢，因此暂时不使用
//    override func draw(_ dirtyRect: NSRect) {
//        super.draw(dirtyRect)
//        
//        if isDrawBorder {
//            drawBorder(dirtyRect)
//        }
//    }
    
    func drawBorder(_ dirtyRect: NSRect) {
        // 确保图像存在
        guard let image = self.image else {
            return
        }
        
        // 设置边框颜色和宽度
        let borderColor = NSColor.gray
        let borderWidth: CGFloat = 2.0
        
        // 计算图像在视图中的绘制区域，考虑边框宽度
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
        drawRect = drawRect.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2)
        
        // 绘制图像
        //image.draw(in: drawRect)
        
        // 绘制边框
        borderColor.set()
        let borderPath = NSBezierPath(rect: drawRect)
        borderPath.lineWidth = borderWidth
        borderPath.stroke()
    }

}

class InterpolatedImageView: CustomImageView {
    //对于小图此方法可以提高质量
    //但只要override，即使不设置插值方法，也会导致巨大图像例如清明上河图100%显示时不够清晰，奇怪
    //因此暂时不使用
//    override func draw(_ dirtyRect: NSRect) {
//        NSGraphicsContext.current!.imageInterpolation = NSImageInterpolation.high
//        super.draw(dirtyRect)
//    }
}
