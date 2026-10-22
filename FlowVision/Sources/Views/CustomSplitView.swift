//
//  CustomSplitView.swift
//  FlowVision
//

import Foundation
import Cocoa

class CustomSplitView: NSSplitView {

    private var middleMouseInitialLocation: NSPoint?
    private var didFlipForRTL = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // RTL布局时交换子视图顺序，使目录树显示在右侧
        // Flip subview order under RTL so the sidebar appears on the right
        if !didFlipForRTL && userInterfaceLayoutDirection == .rightToLeft && subviews.count == 2 {
            didFlipForRTL = true
            let first = subviews[0]
            let second = subviews[1]
            subviews = [second, first]
        }
    }
    
    override var dividerThickness: CGFloat {
        guard let viewController = getViewController(self) else { return 0 }
        if viewController.publicVar.profile.isDirTreeHidden {
            return 0
        }else{
            if #available(macOS 26.0, *), SDK_VERSION >= 26 {
                return 0
            }else{
                return 1
            }
        }
    }
    
    override func otherMouseDown(with event: NSEvent) {
        // 检查是否按下了鼠标中键
        // Check if middle mouse button is pressed
        if event.buttonNumber == 2 {
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
            globalVar.isInMiddleMouseDrag = true
        } else {
            super.otherMouseDragged(with: event)
        }
    }
    
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            middleMouseInitialLocation = nil
            globalVar.isInMiddleMouseDrag = false
        } else {
            super.otherMouseUp(with: event)
        }
    }
}
