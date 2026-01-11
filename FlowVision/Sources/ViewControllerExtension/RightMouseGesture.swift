//
//  RightMouseGesture.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    enum RightMouseGestureState {
        case none, oneDirection(RightMouseGestureDirection), twoDirections(RightMouseGestureDirection, RightMouseGestureDirection)
    }

    func analyzeGesture(doAction: Bool) {
        if directionHistory.count > 0 {
//            drawingView?.containerView.isHidden=false
            
            if drawingView?.containerView.isHidden == true {
                drawingView?.containerView.isHidden = false
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    drawingView?.containerView.animator().alphaValue = 1
                }, completionHandler: {
                })
            }
        }
        
        if directionHistory.count == 1 {
            handleSingleDirectionGesture(directionHistory.first!, doAction: doAction)
        } else if directionHistory.count == 2 {
            // 可以在这里扩展更复杂的手势分析
            // Can extend more complex gesture analysis here
            handleMultiDirectionGesture(directionHistory, doAction: doAction)
        } else {
            drawingView?.statusLabel.stringValue=""
        }
        
        
        if !doAction {
            var status=[String]()
            for direction in directionHistory{
                switch direction {
                case .right:
                    status.append("arrow.right.square.fill")
                case .left:
                    status.append("arrow.left.square.fill")
                case .up:
                    status.append("arrow.up.square.fill")
                case .down:
                    status.append("arrow.down.square.fill")
                default:
                    break
                }
            }
            drawingView?.directionLabel.attributedStringValue=attributedStringWithSymbols(status)
        }else{
            drawingView?.directionLabel.attributedStringValue=attributedStringWithSymbols([])
            drawingView?.statusLabel.stringValue=""
        }
    }

    func handleMultiDirectionGesture(_ directions: [RightMouseGestureDirection], doAction: Bool) {
        if directions.count == 2 {
            // log("Detected two-direction gesture: \(directions[0]) then \(directions[1])")
            handleTwoDirectionsGesture(directions[0],directions[1], doAction: doAction)
        }
    }

    func handleSingleDirectionGesture(_ direction: RightMouseGestureDirection, doAction: Bool) {
        switch direction {
        case .right:
            // log("Gesture: ➡️")
            if doAction {switchDirByDirection(direction: .right, stackDeep: 0);gestureTriggeredSwitch=true}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-folder", comment: "下一个目录")}
        case .left:
            // log("Gesture: ⬅️")
            if doAction {switchDirByDirection(direction: .left, stackDeep: 0);gestureTriggeredSwitch=true}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-folder", comment: "上一个目录")}
        case .up:
            // log("Gesture: ⬆️")
            if doAction {switchDirByDirection(direction: .up, stackDeep: 0);gestureTriggeredSwitch=true}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("parent-folder", comment: "上级目录")}
        case .down:
            // log("Gesture: ⬇️")
            if doAction {switchDirByDirection(direction: .down, stackDeep: 0);gestureTriggeredSwitch=true}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("back-folder", comment: "返回历史目录")}
        default:
            break
        }
    }

    func handleTwoDirectionsGesture(_ first: RightMouseGestureDirection, _ second: RightMouseGestureDirection, doAction: Bool) {
        switch (first, second) {
        case (.up, .right):
            // log("Gesture: ⬆️ ➡️")
            // if doAction {switchDirByDirection(direction: .up_right, stackDeep: 0);gestureTriggeredSwitch=true}
            // else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-sibling-of-parent", comment: "上级的平级下一个目录")}
            if doAction {switchDirByDirection(direction: .down_right, stackDeep: 0);gestureTriggeredSwitch=true}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-sibling", comment: "平级的下一个目录")}
        case (.up, .left):
            // log("Gesture: ⬆️ ⬅️")
            // if doAction {switchDirByDirection(direction: .up_left, stackDeep: 0);gestureTriggeredSwitch=true}
            // else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-sibling-of-parent", comment: "上级的平级上一个目录")}
            if doAction {switchDirByDirection(direction: .down_left, stackDeep: 0);gestureTriggeredSwitch=true}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-sibling", comment: "平级的上一个目录")}
        case (.down, .right):
            // log("Gesture: ⬇️ ➡️")
//            if doAction {switchDirByDirection(direction: .down_right, stackDeep: 0);gestureTriggeredSwitch=true}
//            else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-sibling", comment: "平级的下一个目录")}
            if doAction {self.view.window?.performClose(nil)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("Close Tab", comment: "关闭标签页")}
//        case (.down, .left):
//            // log("Gesture: ⬇️ ⬅️")
//            if doAction {switchDirByDirection(direction: .down_left, stackDeep: 0);gestureTriggeredSwitch=true}
//            else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-sibling", comment: "平级的上一个目录")}
        default:
            drawingView?.statusLabel.stringValue=""
            break
        }
    }
}
