//
//  AutoScrollPlay.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func promptForScrollSpeed(completion: @escaping (CGFloat?) -> Void) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Set Scroll Speed", comment: "设置滚动速度")
        alert.informativeText = NSLocalizedString("Enter the scroll speed in pixels per second:", comment: "输入每秒滚动的像素数：")
        alert.alertStyle = .informational
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.stringValue = "60"
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let text = inputTextField.stringValue
            if let speed = Double(text), speed != 0 {
                completion(CGFloat(speed))
            } else {
                // Handle invalid input
                completion(nil)
            }
        } else {
            completion(nil)
        }
    }
    
    func startContinuousAutoScroll() {
        stopAutoScroll() // Stop any existing timer
        
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.performContinuousScroll()
        }
    }
    
    func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
    
    func performContinuousScroll() {
        guard let scrollView = collectionView.enclosingScrollView, !isAutoScrollPaused else { return }
        
        let currentOrigin = scrollView.contentView.bounds.origin
        let newY = max(0, min(currentOrigin.y + scrollSpeed / 60.0, collectionView.bounds.height - scrollView.contentSize.height))
        let newOrigin = NSPoint(x: currentOrigin.x, y: newY)
        
        scrollView.contentView.scroll(to: newOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        debounceSetLoadThumbPriority(interval: 1, ifNeedVisable: true)
    }
    
    func toggleAutoScroll() {
        if autoScrollTimer == nil {
            promptForScrollSpeed { [weak self] speed in
                guard let self = self, let speed = speed else {
                    return
                }
                self.scrollSpeed = speed
                self.isAutoScrollPaused = false
                self.startContinuousAutoScroll()
            }
        } else {
            stopAutoScroll()
        }
    }
    
//    func pauseAutoScroll() {
//        isAutoScrollPaused = true
//    }
//    
//    func resumeAutoScroll() {
//        isAutoScrollPaused = false
//    }
//    
//    func toggleAutoScrollPauseResume(_ sender: Any) {
//        if isAutoScrollPaused {
//            resumeAutoScroll()
//        } else {
//            pauseAutoScroll()
//        }
//    }

    func startAutoPlay() {
        guard !isAutoPlaying else {return}
        
        promptForAutoPlayInterval()
    }

    func stopAutoPlay() {
        guard isAutoPlaying else {return}
        
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
        isAutoPlaying = false
    }

    func toggleAutoPlay() {
        if isAutoPlaying {
            stopAutoPlay()
        } else {
            startAutoPlay()
        }
    }

    private func promptForAutoPlayInterval() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Set Auto Play Interval", comment: "设置自动播放间隔")
        alert.informativeText = NSLocalizedString("Enter the auto play interval in seconds:", comment: "请输入自动播放的间隔时间（秒）：")
        alert.alertStyle = .informational
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.stringValue = "2"
        alert.accessoryView = inputTextField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let text = inputTextField.stringValue as String?,
               let interval = TimeInterval(text), interval > 0 {
                autoPlayInterval = interval
                isAutoPlaying = true
                scheduleAutoPlay()
            } else {
                showAlert(message: NSLocalizedString("Invalid input, please enter a positive number", comment: "输入不合法，请输入一个正数"))
            }
        }
    }

    private func scheduleAutoPlay() {
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: autoPlayInterval, repeats: true) { [weak self] _ in
            self?.nextLargeImage()
        }
    }
}
