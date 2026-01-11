//
//  WindowManagement.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func toggleOnTop(){
        if let window = self.view.window {
            var showText = ""
            if window.level == .floating {
                // 取消置顶
                // Unpin from top
                window.level = .normal
                showText = NSLocalizedString("Unpin Window from Top", comment: "取消置顶窗口")
            } else {
                // 置顶
                // Pin to top
                window.level = .floating
                showText = NSLocalizedString("Pin Window to Top", comment: "置顶窗口")
            }
            coreAreaView.showInfo(showText, timeOut: 1.0, cannotBeCleard: true)
            publicVar.updateToolbar()
        }
    }
    
    func adjustWindowMaximize(){
        if let window = view.window {
            if !window.isZoomed {
                window.zoom(nil)
                if publicVar.isInLargeView {
                    changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
                }
            }
        }
    }
    
    func adjustWindowSuitable(){
        if globalVar.portableMode {
            var zoomLockStore = publicVar.isZoomLocked
            publicVar.isZoomLocked = false
            adjustWindowPortable(firstShowThumb: false, animate: true, isToCenter: true)
            publicVar.isZoomLocked = zoomLockStore
            largeImageView.calcRatio(isShowPrompt: true)
        }else{
            adjustWindowToRatio(animate: true, isToCenter: true)
        }
    }
    
    func adjustWindowImageActual(refSize:NSSize? = nil, firstShowThumb: Bool = false, animate: Bool = true){
        // let zoomSize=largeImageView.customZoomSize()
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        var tmpSize=largeImageView.file.originalSize ?? NSSize(width: 800, height: 600)
        if refSize != nil {tmpSize=refSize!}
        tmpSize = NSSize(width: tmpSize.width/scale, height: tmpSize.height/scale)
        var zoomLockStore = publicVar.isZoomLocked
        publicVar.isZoomLocked = false
        adjustWindowTo(tmpSize, firstShowThumb: firstShowThumb, animate: animate, justAdjustWindowFrame: false, isToCenter: false)
        publicVar.isZoomLocked = zoomLockStore
        largeImageView.calcRatio(isShowPrompt: true)
    }
    
    func adjustWindowImageCurrent(){
        var zoomSize=largeImageView.imageView.frame.size
        if largeImageView.file.type == .video,
           let originalSize = largeImageView.file.originalSize {
            let rect = AVMakeRect(aspectRatio: originalSize, insideRect: largeImageView.frame)
            zoomSize = NSSize(width: round(rect.size.width), height: round(rect.size.height))
        }
        adjustWindowTo(zoomSize, firstShowThumb: false, animate: true, isToCenter: false)
    }
    
//    func adjustWindowImageMax() {
//        adjustWindowToImageRatio(refSize: largeImageView.imageView.image?.size, firstShowThumb: false, animate: true, refRatio: (1,1))
//    }

    func adjustWindowPortable(refSize:NSSize? = nil, firstShowThumb: Bool, animate: Bool, justAdjustWindowFrame: Bool = false, isToCenter: Bool = false) {
        if publicVar.isInLargeView {
            var scale = NSScreen.main?.backingScaleFactor ?? 1.0
            if publicVar.isZoomLocked,
               let zoomLock = publicVar.zoomLock {
                scale = scale / zoomLock
            }
            var tmpSize = largeImageView.file.originalSize
            if refSize != nil {tmpSize=refSize}
            if tmpSize == nil {tmpSize=NSSize(width: 400, height: 400)}
            tmpSize = NSSize(width: tmpSize!.width/scale, height: tmpSize!.height/scale)
            
            if publicVar.isLargeImageFitWindow && !publicVar.isZoomLocked {
                adjustWindowToImageRatio(refSize: tmpSize, firstShowThumb: firstShowThumb, animate: animate, justAdjustWindowFrame: justAdjustWindowFrame, isToCenter: isToCenter)
            }else{
                adjustWindowTo(tmpSize!, firstShowThumb: firstShowThumb, animate: false, justAdjustWindowFrame: justAdjustWindowFrame, isToCenter: isToCenter)
            }
        }else{
            adjustWindowToRatio(animate: animate, isToCenter: isToCenter)
        }
    }
    
    func togglePortableMode(){
        globalVar.portableMode.toggle()
        UserDefaults.standard.set(globalVar.portableMode, forKey: "portableMode")
        adjustWindowPortable(firstShowThumb: false, animate: true)
        if globalVar.portableMode {
            coreAreaView.showInfo(NSLocalizedString("Portable Mode: On", comment: "便携模式：开启"))
        }else{
            coreAreaView.showInfo(NSLocalizedString("Portable Mode: Off", comment: "便携模式：关闭"))
        }
    }
    
    func adjustWindowToCenter(animate: Bool = true) {
        if let window = view.window,
           let screen = window.screen {
            
            let visibleFrame = screen.visibleFrame
            
            // 获取当前窗口的尺寸
            // Get current window size
            let windowFrame = window.frame
            let newWindowSize = windowFrame.size
            
            // 计算新的窗口位置，使其居中
            // Calculate new window position to center it
            let newX = visibleFrame.origin.x + round((visibleFrame.width - newWindowSize.width) / 2)
            let newY = visibleFrame.origin.y + round((visibleFrame.height - newWindowSize.height) / 2)
            let newOrigin = NSPoint(x: newX, y: newY)
            
            // 设置窗口的新框架并居中显示
            // Set window's new frame and display centered
            let newFrame = NSRect(origin: newOrigin, size: newWindowSize)
            window.setFrame(newFrame, display: true, animate: animate)
        }
    }
    
    // ------------以下为调整窗口 间接接口-----------
    // ------------Below are indirect interfaces for adjusting window-----------
    
    func adjustWindowToRatio(animate: Bool, refRatio: (Double,Double)? = nil, isToCenter: Bool) {
        if let window = view.window {
            // 获取屏幕的可见区域
            // Get screen's visible area
            if let screen = window.screen {
                let visibleFrame = screen.visibleFrame
                let aspectRatio = screen.frame.width / screen.frame.height
                
                // 确定最大比例
                // Determine maximum ratio
                var ratioWidth: Double
                var ratioHeight: Double
                
                // mbp屏幕或者竖屏
                // MBP screen or portrait orientation
                if aspectRatio < 16.0/9.0 {
                    ratioWidth = globalVar.portableListWidthRatioHH
                    ratioHeight = globalVar.portableListHeightRatioHH
                }else{
                    ratioWidth = globalVar.portableListWidthRatio
                    ratioHeight = globalVar.portableListHeightRatio
                }
                
                if refRatio != nil {
                    ratioWidth = refRatio!.0
                    ratioHeight = refRatio!.1
                }
                
                // 计算目标窗口尺寸（可见区域的%）
                // Calculate target window size (% of visible area)
                let targetWidth = visibleFrame.width * ratioWidth
                let targetHeight = visibleFrame.height * ratioHeight
                
                // 计算窗口的边框尺寸（标题栏高度）
                // Calculate window border size (title bar height)
                let windowFrame = window.frame
                let contentRect = window.contentRect(forFrameRect: windowFrame)
                let titleBarHeight = windowFrame.height - contentRect.height
                
                // 计算新的内容区域尺寸
                // Calculate new content area size
                let newContentWidth = targetWidth
                let newContentHeight = targetHeight - titleBarHeight
                
                // 确保新的内容区域尺寸不小于最小窗口尺寸
                // Ensure new content area size is not less than minimum window size
                let minWindowSize = window.minSize
                let newContentSize = NSSize(width: max(newContentWidth, minWindowSize.width),
                                            height: max(newContentHeight, minWindowSize.height))
                
                // 计算新的窗口尺寸，包括标题栏
                // Calculate new window size, including title bar
                let newWindowSize = NSSize(width: newContentSize.width, height: newContentSize.height + titleBarHeight)
                
                let newOrigin: NSPoint
                
                if isToCenter {
                    // 计算新的窗口位置，使其居中
                    // Calculate new window position to center it
                    let newX = visibleFrame.origin.x + round((visibleFrame.width - newWindowSize.width) / 2)
                    let newY = visibleFrame.origin.y + round((visibleFrame.height - newWindowSize.height) / 2)
                    newOrigin = NSPoint(x: newX, y: newY)
                } else {
                    // 保持窗口的中心位置不变
                    // Keep window center position unchanged
                    let oldCenter = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
                    let newX = oldCenter.x - round(newWindowSize.width / 2)
                    let newY = oldCenter.y - round(newWindowSize.height / 2)
                    newOrigin = NSPoint(x: newX, y: newY)
                }
                
                // 设置窗口的新框架
                // Set window's new frame
                let newFrame = NSRect(origin: newOrigin, size: newWindowSize)
                window.setFrame(newFrame, display: true, animate: animate)
                
                // 重置图片大小位置
                // Reset image size and position
                if publicVar.isInLargeView {
                    changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
                }
            }
        }
    }
    
    func adjustWindowToImageRatio(refSize: NSSize?, firstShowThumb: Bool, animate: Bool, refRatio: (Double, Double)? = nil, justAdjustWindowFrame: Bool = false, isToCenter: Bool) {
        if let window = view.window,
           let screen = window.screen {
            
            let visibleFrame = screen.visibleFrame
            
            // 计算窗口的边框尺寸
            // Calculate window border size
            let windowFrame = window.frame
            let contentRect = window.contentRect(forFrameRect: windowFrame)
            let titleBarHeight = windowFrame.height - contentRect.height
            
            // 确定最大比例
            // Determine maximum ratio
            var ratioWidth = globalVar.portableImageWidthRatio
            var ratioHeight = globalVar.portableImageHeightRatio
            if let refRatio = refRatio {
                ratioWidth = refRatio.0
                ratioHeight = refRatio.1
            }
            
            // 计算可见区域的宽高，减去标题栏的高度
            // Calculate visible area width/height, subtract title bar height
            let maxWidth = (visibleFrame.width) * ratioWidth
            let maxHeight = (visibleFrame.height) * ratioHeight - titleBarHeight
            
            // 获取图像的宽高比
            // Get image aspect ratio
            let imageWidth = refSize?.width ?? 1
            let imageHeight = refSize?.height ?? 1
            let imageAspectRatio = imageWidth / imageHeight
            
            // 计算屏幕的宽高比
            // Calculate screen aspect ratio
            let screenAspectRatio = maxWidth / maxHeight
            
            // 计算缩放比例
            // Calculate scale factor
            var scaleFactor: CGFloat
            if imageAspectRatio > screenAspectRatio {
                // 图像宽高比更大，以宽度为基准缩放
                // Image aspect ratio is larger, scale based on width
                scaleFactor = maxWidth / imageWidth
            } else {
                // 图像宽高比更小，以高度为基准缩放
                // Image aspect ratio is smaller, scale based on height
                scaleFactor = maxHeight / imageHeight
            }
            
            // 计算新的图像尺寸
            // Calculate new image size
            var newWidth = imageWidth * scaleFactor
            var newHeight = imageHeight * scaleFactor
            
            // 如果新的宽度或高度超过了屏幕的可见区域，进行调整
            // If new width or height exceeds screen's visible area, adjust
            if newWidth > maxWidth {
                scaleFactor = maxWidth / imageWidth
                newWidth = maxWidth
                newHeight = imageHeight * scaleFactor
            }
            
            if newHeight > maxHeight {
                scaleFactor = maxHeight / imageHeight
                newHeight = maxHeight
                newWidth = imageWidth * scaleFactor
            }
            
            let newContentSize = NSSize(width: newWidth, height: newHeight)
            
            largeImageView.imageView.frame.size = newContentSize
            
            // 调整窗口的内容尺寸
            // Adjust window content size
            window.setContentSize(newContentSize)
            if !justAdjustWindowFrame{
                changeLargeImage(firstShowThumb: firstShowThumb, resetSize: true, triggeredByLongPress: true)
            }
            
            // 计算新的窗口尺寸，包括标题栏
            // Calculate new window size, including title bar
            let newWindowSize = NSSize(width: newContentSize.width, height: newContentSize.height + titleBarHeight)
            
            let newOrigin: NSPoint
            
            if isToCenter {
                // 计算新的窗口位置，使其居中
                // Calculate new window position to center it
                let newX = visibleFrame.origin.x + round((visibleFrame.width - newWindowSize.width) / 2)
                let newY = visibleFrame.origin.y + round((visibleFrame.height - newWindowSize.height) / 2)
                newOrigin = NSPoint(x: newX, y: newY)
            } else {
                // 保持窗口的中心位置不变
                // Keep window center position unchanged
                let oldCenter = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
                let newX = oldCenter.x - round(newWindowSize.width / 2)
                let newY = oldCenter.y - round(newWindowSize.height / 2)
                newOrigin = NSPoint(x: newX, y: newY)
            }
            
            // 设置窗口的新框架
            // Set window's new frame
            let newFrame = NSRect(origin: newOrigin, size: newWindowSize)
            window.setFrame(newFrame, display: true, animate: animate)
        }
    }
    
    func adjustWindowTo(_ zoomSize: CGSize, firstShowThumb: Bool, animate: Bool, justAdjustWindowFrame: Bool = false, isToCenter: Bool) {
        if let window = view.window,
           let screen = window.screen {
            
            let visibleFrame = screen.visibleFrame
            
            // 计算窗口的边框尺寸
            // Calculate window border size
            let windowFrame = window.frame
            let contentRect = window.contentRect(forFrameRect: windowFrame)
            let titleBarHeight = windowFrame.height - contentRect.height
            
            // 计算可见区域的宽高，减去标题栏的高度
            // Calculate visible area width/height, subtract title bar height
            let maxWidth = visibleFrame.width
            let maxHeight = visibleFrame.height - titleBarHeight
            
            // 计算图像的宽高比
            // Calculate image aspect ratio
            let imageAspectRatio = zoomSize.width / zoomSize.height
            
            // 计算屏幕的宽高比
            // Calculate screen aspect ratio
            let screenAspectRatio = maxWidth / maxHeight
            
            // 计算缩放比例
            // Calculate scale factor
            var scaleFactor: CGFloat
            if imageAspectRatio > screenAspectRatio {
                // 图像宽高比更大，以宽度为基准缩放
                // Image aspect ratio is larger, scale based on width
                scaleFactor = maxWidth / zoomSize.width
            } else {
                // 图像宽高比更小，以高度为基准缩放
                // Image aspect ratio is smaller, scale based on height
                scaleFactor = maxHeight / zoomSize.height
            }
            
            // 计算新的图像尺寸
            // Calculate new image size
            let newWidth = zoomSize.width * scaleFactor
            let newHeight = zoomSize.height * scaleFactor
            var newContentSize = NSSize(width: newWidth, height: newHeight)
            if newWidth > zoomSize.width {
                newContentSize = zoomSize
            }
            largeImageView.imageView.frame.size = newContentSize
            
            // 调整窗口的内容尺寸
            // Adjust window content size
            window.setContentSize(newContentSize)
            if !justAdjustWindowFrame{
                changeLargeImage(firstShowThumb: firstShowThumb, resetSize: true, triggeredByLongPress: false)
            }
            
            // 计算新的窗口尺寸，包括标题栏
            // Calculate new window size, including title bar
            let newWindowSize = NSSize(width: newContentSize.width, height: newContentSize.height + titleBarHeight)
            
            let newOrigin: NSPoint
            
            if isToCenter {
                // 计算新的窗口位置，使其居中
                // Calculate new window position to center it
                let newX = visibleFrame.origin.x + round((visibleFrame.width - newWindowSize.width) / 2)
                let newY = visibleFrame.origin.y + round((visibleFrame.height - newWindowSize.height) / 2)
                newOrigin = NSPoint(x: newX, y: newY)
            } else {
                // 保持窗口的中心位置不变
                // Keep window center position unchanged
                let oldCenter = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
                let newX = oldCenter.x - round(newWindowSize.width / 2)
                let newY = oldCenter.y - round(newWindowSize.height / 2)
                newOrigin = NSPoint(x: newX, y: newY)
            }
            
            // 设置窗口的新框架
            // Set window's new frame
            let newFrame = NSRect(origin: newOrigin, size: newWindowSize)
            window.setFrame(newFrame, display: true, animate: animate)
        }
    }

}
