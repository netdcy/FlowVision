//
//  CustomSplitView.swift
//  FlowVision
//
//  Created by netdcy on 2024/6/12.
//

import Foundation
import Cocoa

class CustomSplitView: NSSplitView {
    
    private var middleMouseInitialLocation: NSPoint?
    
    override var dividerThickness: CGFloat {
        if getViewController(self)!.publicVar.isDirTreeHidden {
            return 0
        }else{
            return 10
        }
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
}
