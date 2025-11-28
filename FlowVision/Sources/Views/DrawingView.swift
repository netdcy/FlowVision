//
//  DrawingView.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation
import Cocoa

class DrawingView: NSView {
    private var path: NSBezierPath?
    var lineColor: NSColor = NSColor.controlAccentColor  // 默认线条颜色
    // Default line color
    var lineWidth: CGFloat = 4.0     // 默认线条宽度
    // Default line width
    var directionLabel: NSTextField!   // 方向提示文本字段
    // Direction hint text field
    var statusLabel: NSTextField!   // 状态提示文本字段
    // Status hint text field
    var containerView: NSView!       // 容器视图
    // Container view
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupContainerView()
        setupLabel()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContainerView()
        setupLabel()
    }
    
    override func layout() {
        super.layout()
        let labelWidth: CGFloat = 240
        let containerWidth: CGFloat = labelWidth
        let containerHeight: CGFloat = 70 // 根据两个文本字段的高度调整容器高度
        // Adjust container height based on height of two text fields
        let centerX = (self.bounds.width - containerWidth) / 2
        let centerY = (self.bounds.height - containerHeight) / 2
        
        // 设置容器视图的框架
        // Set container view frame
        containerView.frame = CGRect(x: centerX, y: centerY, width: containerWidth, height: containerHeight)
        
        // 方向提示文本字段居中且位于视图中央
        // Direction hint text field centered and positioned at view center
        directionLabel.frame = CGRect(x: 0, y: containerHeight - 40, width: labelWidth, height: 37)
        // 状态提示文本字段居中且位于方向提示文本字段下方
        // Status hint text field centered and positioned below direction hint text field
        statusLabel.frame = CGRect(x: 0, y: 0, width: labelWidth, height: 28)
    }
    
    private func setupContainerView() {
        containerView = NSView()
        containerView.wantsLayer = true
        containerView.isHidden = true
        containerView.alphaValue = 0
        containerView.layer?.backgroundColor = hexToNSColor(hex: "#000000",alpha: 0.45).cgColor
        containerView.layer?.cornerRadius = 6.0
        containerView.layer?.masksToBounds = true
        
        addSubview(containerView)
    }
    
    private func setupLabel() {
        directionLabel = NSTextField(frame: CGRect(x: 0, y: 0, width: self.bounds.width, height: 30))
        directionLabel.stringValue = ""
        directionLabel.backgroundColor = hexToNSColor(alpha: 0.0)
        directionLabel.isBordered = false
        directionLabel.isEditable = false
        directionLabel.alignment = .center
        directionLabel.font = NSFont.systemFont(ofSize: 29, weight: .regular)
        directionLabel.textColor = hexToNSColor(hex: "#FFFFFF",alpha: 0.9)
        //directionLabel.isHidden = true
        directionLabel.wantsLayer = true
        containerView.addSubview(directionLabel)
        
        statusLabel = NSTextField(frame: CGRect(x: 0, y: 0, width: self.bounds.width, height: 20))
        statusLabel.stringValue = ""
        statusLabel.backgroundColor = hexToNSColor(alpha: 0.0)
        statusLabel.isBordered = false
        statusLabel.isEditable = false
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        statusLabel.textColor = hexToNSColor(hex: "#FFFFFF",alpha: 0.9)
        //statusLabel.isHidden = true
        statusLabel.wantsLayer = true
        containerView.addSubview(statusLabel)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        if hitView == self {
            // 如果点击的是DrawingView，但不需要处理事件，则返回nil，让事件传递到下面的视图
            // If DrawingView is clicked but doesn't need to handle event, return nil to pass event to view below
            return nil
        }
        return hitView
    }
    
    func _rightMouseDown(with event: NSEvent) {
        path = NSBezierPath()  // 开始一个新的绘图路径
        // Start a new drawing path
        path?.lineWidth = lineWidth
        let location = convert(event.locationInWindow, from: nil)
        path?.move(to: location)
        super.rightMouseDown(with: event)  // 继续传递事件
        // Continue passing event
    }
    
    func _rightMouseDragged(with event: NSEvent) {
        guard let path = path else { return }
        let location = convert(event.locationInWindow, from: nil)
        path.line(to: location)
        needsDisplay = true
        super.rightMouseDragged(with: event)  // 继续传递事件
        // Continue passing event
    }
    
    func _rightMouseUp(with event: NSEvent) {
        path = nil  // 清除路径
        // Clear path
        needsDisplay = true  // 需要重新绘制，以清除视图
        // Need to redraw to clear view
        super.rightMouseUp(with: event)  // 继续传递事件
        // Continue passing event
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        lineColor.setStroke()
        path?.stroke()  // 只绘制当前的路径
        // Only draw current path
    }
}
