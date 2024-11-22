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
    var lineWidth: CGFloat = 4.0     // 默认线条宽度
    var directionLabel: NSTextField!   // 方向提示文本字段
    var statusLabel: NSTextField!   // 状态提示文本字段
    var containerView: NSView!       // 容器视图
    
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
        let centerX = (self.bounds.width - containerWidth) / 2
        let centerY = (self.bounds.height - containerHeight) / 2
        
        // 设置容器视图的框架
        containerView.frame = CGRect(x: centerX, y: centerY, width: containerWidth, height: containerHeight)
        
        // 方向提示文本字段居中且位于视图中央
        directionLabel.frame = CGRect(x: 0, y: containerHeight - 40, width: labelWidth, height: 37)
        // 状态提示文本字段居中且位于方向提示文本字段下方
        statusLabel.frame = CGRect(x: 0, y: 0, width: labelWidth, height: 28)
    }
    
    private func setupContainerView() {
        containerView = NSView()
        containerView.wantsLayer = true
        containerView.isHidden = true
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
            return nil
        }
        return hitView
    }
    
    func _rightMouseDown(with event: NSEvent) {
        path = NSBezierPath()  // 开始一个新的绘图路径
        path?.lineWidth = lineWidth
        let location = convert(event.locationInWindow, from: nil)
        path?.move(to: location)
        super.rightMouseDown(with: event)  // 继续传递事件
    }
    
    func _rightMouseDragged(with event: NSEvent) {
        guard let path = path else { return }
        let location = convert(event.locationInWindow, from: nil)
        path.line(to: location)
        needsDisplay = true
        super.rightMouseDragged(with: event)  // 继续传递事件
    }
    
    func _rightMouseUp(with event: NSEvent) {
        path = nil  // 清除路径
        needsDisplay = true  // 需要重新绘制，以清除视图
        super.rightMouseUp(with: event)  // 继续传递事件
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        lineColor.setStroke()
        path?.stroke()  // 只绘制当前的路径
    }
}
