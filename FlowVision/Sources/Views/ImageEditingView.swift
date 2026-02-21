//
//  ImageEditingView.swift
//  FlowVision
//

import Foundation
import Cocoa

// MARK: - 编辑工具类型
// MARK: - Edit tool types
enum EditingTool {
    case pen           // 画笔
    case highlighter   // 荧光笔
    case eraser        // 橡皮擦
    case arrow         // 箭头
    case rectangle     // 矩形
    case ellipse       // 椭圆
    case text          // 文字
}

// MARK: - 绘制路径模型（使用归一化坐标 0-1）
// MARK: - Drawing path model (using normalized coordinates 0-1)
class DrawingPath {
    // 归一化的点数组（相对于画布的 0-1 坐标）
    // Normalized points array (relative to canvas 0-1 coordinates)
    var normalizedPoints: [NSPoint]
    var color: NSColor
    // 归一化的线宽（相对于画布宽度）
    // Normalized line width (relative to canvas width)
    var normalizedLineWidth: CGFloat
    var tool: EditingTool
    var isHighlighter: Bool
    
    init(normalizedPoints: [NSPoint], color: NSColor, normalizedLineWidth: CGFloat, tool: EditingTool, isHighlighter: Bool = false) {
        self.normalizedPoints = normalizedPoints
        self.color = color
        self.normalizedLineWidth = normalizedLineWidth
        self.tool = tool
        self.isHighlighter = isHighlighter
    }
    
    /// 根据给定尺寸生成实际路径
    /// Generate actual path based on given size
    func generatePath(for size: NSSize) -> NSBezierPath {
        let path = NSBezierPath()
        guard !normalizedPoints.isEmpty else { return path }
        
        let scaledPoints = normalizedPoints.map { point in
            NSPoint(x: point.x * size.width, y: point.y * size.height)
        }
        
        switch tool {
        case .pen, .highlighter:
            path.move(to: scaledPoints[0])
            for i in 1..<scaledPoints.count {
                path.line(to: scaledPoints[i])
            }
        case .arrow:
            if scaledPoints.count >= 2 {
                let start = scaledPoints[0]
                let end = scaledPoints[1]
                path.move(to: start)
                path.line(to: end)
                
                // 箭头头部
                // Arrow head
                let angle = atan2(end.y - start.y, end.x - start.x)
                let arrowLength: CGFloat = 15 * (size.width / 500) // 缩放箭头大小
                let arrowAngle: CGFloat = .pi / 6
                
                let arrowPoint1 = NSPoint(x: end.x - arrowLength * cos(angle - arrowAngle),
                                           y: end.y - arrowLength * sin(angle - arrowAngle))
                let arrowPoint2 = NSPoint(x: end.x - arrowLength * cos(angle + arrowAngle),
                                           y: end.y - arrowLength * sin(angle + arrowAngle))
                
                path.move(to: end)
                path.line(to: arrowPoint1)
                path.move(to: end)
                path.line(to: arrowPoint2)
            }
        case .rectangle:
            if scaledPoints.count >= 2 {
                let start = scaledPoints[0]
                let end = scaledPoints[1]
                let rect = NSRect(x: min(start.x, end.x),
                                  y: min(start.y, end.y),
                                  width: abs(end.x - start.x),
                                  height: abs(end.y - start.y))
                path.appendRect(rect)
            }
        case .ellipse:
            if scaledPoints.count >= 2 {
                let start = scaledPoints[0]
                let end = scaledPoints[1]
                let rect = NSRect(x: min(start.x, end.x),
                                  y: min(start.y, end.y),
                                  width: abs(end.x - start.x),
                                  height: abs(end.y - start.y))
                path.appendOval(in: rect)
            }
        default:
            break
        }
        
        return path
    }
    
    /// 获取实际线宽
    /// Get actual line width
    func getLineWidth(for size: NSSize) -> CGFloat {
        return normalizedLineWidth * size.width
    }
}

// MARK: - 图片编辑画布视图
// MARK: - Image editing canvas view
class ImageEditingCanvasView: NSView {
    
    // 绘制历史（使用归一化坐标）
    // Drawing history (using normalized coordinates)
    private var drawingPaths: [DrawingPath] = []
    private var undoStack: [[DrawingPath]] = []
    private var redoStack: [[DrawingPath]] = []
    
    // 当前绘制中的点（屏幕坐标）
    // Current drawing points (screen coordinates)
    private var currentPoints: [NSPoint] = []
    
    // 当前工具设置
    // Current tool settings
    var currentTool: EditingTool = .pen
    var currentColor: NSColor = .red
    var currentLineWidth: CGFloat = 4.0
    
    // 形状绘制辅助
    // Shape drawing helper
    private var shapeStartPoint: NSPoint?
    private var shapeEndPoint: NSPoint?
    
    // 累计旋转角度（0, 1, 2, 3 对应 0°, 90°, 180°, 270°）
    // Accumulated rotation angle (0, 1, 2, 3 corresponds to 0°, 90°, 180°, 270°)
    private var totalRotation: Int = 0
    
    // 回调
    // Callbacks
    var onDrawingChanged: (() -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    /// 将屏幕坐标转换为归一化坐标
    /// Convert screen coordinates to normalized coordinates
    private func normalizePoint(_ point: NSPoint) -> NSPoint {
        guard bounds.width > 0 && bounds.height > 0 else { return .zero }
        return NSPoint(x: point.x / bounds.width, y: point.y / bounds.height)
    }
    
    /// 将归一化坐标转换为屏幕坐标
    /// Convert normalized coordinates to screen coordinates
    private func denormalizePoint(_ point: NSPoint) -> NSPoint {
        return NSPoint(x: point.x * bounds.width, y: point.y * bounds.height)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let currentSize = bounds.size
        
        // 绘制所有历史路径
        // Draw all history paths
        for drawingPath in drawingPaths {
            if drawingPath.isHighlighter {
                drawingPath.color.withAlphaComponent(0.4).setStroke()
            } else {
                drawingPath.color.setStroke()
            }
            let path = drawingPath.generatePath(for: currentSize)
            path.lineWidth = drawingPath.getLineWidth(for: currentSize)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        
        // 绘制当前路径（实时）
        // Draw current path (real-time)
        if !currentPoints.isEmpty {
            if currentTool == .highlighter {
                currentColor.withAlphaComponent(0.4).setStroke()
            } else {
                currentColor.setStroke()
            }
            
            let path = NSBezierPath()
            path.move(to: currentPoints[0])
            for i in 1..<currentPoints.count {
                path.line(to: currentPoints[i])
            }
            path.lineWidth = currentLineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        
        // 绘制当前形状预览
        // Draw current shape preview
        if let start = shapeStartPoint, let end = shapeEndPoint {
            currentColor.setStroke()
            let path = createShapePath(from: start, to: end, tool: currentTool)
            path.lineWidth = currentLineWidth
            path.stroke()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        switch currentTool {
        case .pen, .highlighter:
            currentPoints = [location]
        case .eraser:
            eraseAt(point: location)
        case .arrow, .rectangle, .ellipse:
            shapeStartPoint = location
            shapeEndPoint = location
        case .text:
            break
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        switch currentTool {
        case .pen, .highlighter:
            currentPoints.append(location)
            needsDisplay = true
        case .eraser:
            eraseAt(point: location)
        case .arrow, .rectangle, .ellipse:
            shapeEndPoint = location
            needsDisplay = true
        case .text:
            break
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        // 保存撤销状态
        // Save undo state
        saveUndoState()
        
        switch currentTool {
        case .pen, .highlighter:
            if !currentPoints.isEmpty {
                // 转换为归一化坐标
                // Convert to normalized coordinates
                let normalizedPoints = currentPoints.map { normalizePoint($0) }
                let normalizedLineWidth = currentLineWidth / bounds.width
                
                let drawingPath = DrawingPath(normalizedPoints: normalizedPoints,
                                              color: currentColor,
                                              normalizedLineWidth: normalizedLineWidth,
                                              tool: currentTool,
                                              isHighlighter: currentTool == .highlighter)
                drawingPaths.append(drawingPath)
            }
            currentPoints = []
        case .eraser:
            break
        case .arrow, .rectangle, .ellipse:
            if let start = shapeStartPoint {
                let normalizedStart = normalizePoint(start)
                let normalizedEnd = normalizePoint(location)
                let normalizedLineWidth = currentLineWidth / bounds.width
                
                let drawingPath = DrawingPath(normalizedPoints: [normalizedStart, normalizedEnd],
                                              color: currentColor,
                                              normalizedLineWidth: normalizedLineWidth,
                                              tool: currentTool)
                drawingPaths.append(drawingPath)
            }
            shapeStartPoint = nil
            shapeEndPoint = nil
        case .text:
            break
        }
        
        redoStack.removeAll()
        needsDisplay = true
        onDrawingChanged?()
    }
    
    // 创建形状路径（用于实时预览）
    // Create shape path (for real-time preview)
    private func createShapePath(from start: NSPoint, to end: NSPoint, tool: EditingTool) -> NSBezierPath {
        let path = NSBezierPath()
        
        switch tool {
        case .arrow:
            path.move(to: start)
            path.line(to: end)
            
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 15
            let arrowAngle: CGFloat = .pi / 6
            
            let arrowPoint1 = NSPoint(x: end.x - arrowLength * cos(angle - arrowAngle),
                                       y: end.y - arrowLength * sin(angle - arrowAngle))
            let arrowPoint2 = NSPoint(x: end.x - arrowLength * cos(angle + arrowAngle),
                                       y: end.y - arrowLength * sin(angle + arrowAngle))
            
            path.move(to: end)
            path.line(to: arrowPoint1)
            path.move(to: end)
            path.line(to: arrowPoint2)
        case .rectangle:
            let rect = NSRect(x: min(start.x, end.x),
                              y: min(start.y, end.y),
                              width: abs(end.x - start.x),
                              height: abs(end.y - start.y))
            path.appendRect(rect)
        case .ellipse:
            let rect = NSRect(x: min(start.x, end.x),
                              y: min(start.y, end.y),
                              width: abs(end.x - start.x),
                              height: abs(end.y - start.y))
            path.appendOval(in: rect)
        default:
            break
        }
        
        return path
    }
    
    // 橡皮擦功能
    // Eraser function
    private func eraseAt(point: NSPoint) {
        let normalizedPoint = normalizePoint(point)
        let eraseRadius: CGFloat = (currentLineWidth * 2) / bounds.width
        
        drawingPaths.removeAll { drawingPath in
            // 检查是否有任何点在擦除范围内
            // Check if any point is within eraser range
            for normalizedPt in drawingPath.normalizedPoints {
                let dx = normalizedPt.x - normalizedPoint.x
                let dy = normalizedPt.y - normalizedPoint.y
                if sqrt(dx*dx + dy*dy) < eraseRadius {
                    return true
                }
            }
            return false
        }
        needsDisplay = true
    }
    
    // 撤销/重做功能
    // Undo/Redo functions
    private func saveUndoState() {
        undoStack.append(drawingPaths.map { drawing in
            DrawingPath(normalizedPoints: drawing.normalizedPoints,
                       color: drawing.color,
                       normalizedLineWidth: drawing.normalizedLineWidth,
                       tool: drawing.tool,
                       isHighlighter: drawing.isHighlighter)
        })
        // 限制撤销栈大小
        // Limit undo stack size
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }
    
    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(drawingPaths)
        drawingPaths = undoStack.removeLast()
        needsDisplay = true
        onDrawingChanged?()
    }
    
    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(drawingPaths)
        drawingPaths = redoStack.removeLast()
        needsDisplay = true
        onDrawingChanged?()
    }
    
    func clearAll() {
        saveUndoState()
        drawingPaths.removeAll()
        redoStack.removeAll()
        needsDisplay = true
        onDrawingChanged?()
    }
    
    /// 顺时针旋转90度
    /// Rotate clockwise 90 degrees
    func rotateClockwise() {
        totalRotation = (totalRotation + 1) % 4
        
        // 旋转所有绘制路径的归一化坐标
        // Rotate all drawing paths' normalized coordinates
        for drawingPath in drawingPaths {
            drawingPath.normalizedPoints = drawingPath.normalizedPoints.map { point in
                // 顺时针90度：(x, y) -> (y, 1-x)
                // Clockwise 90 degrees: (x, y) -> (y, 1-x)
                return NSPoint(x: point.y, y: 1 - point.x)
            }
        }
        
        // 同时旋转撤销栈和重做栈中的坐标
        // Also rotate coordinates in undo and redo stacks
        rotateStackClockwise(&undoStack)
        rotateStackClockwise(&redoStack)
        
        needsDisplay = true
        onDrawingChanged?()
    }
    
    /// 逆时针旋转90度
    /// Rotate counterclockwise 90 degrees
    func rotateCounterclockwise() {
        totalRotation = (totalRotation + 3) % 4
        
        // 旋转所有绘制路径的归一化坐标
        // Rotate all drawing paths' normalized coordinates
        for drawingPath in drawingPaths {
            drawingPath.normalizedPoints = drawingPath.normalizedPoints.map { point in
                // 逆时针90度：(x, y) -> (1-y, x)
                // Counterclockwise 90 degrees: (x, y) -> (1-y, x)
                return NSPoint(x: 1 - point.y, y: point.x)
            }
        }
        
        // 同时旋转撤销栈和重做栈中的坐标
        // Also rotate coordinates in undo and redo stacks
        rotateStackCounterclockwise(&undoStack)
        rotateStackCounterclockwise(&redoStack)
        
        needsDisplay = true
        onDrawingChanged?()
    }
    
    /// 顺时针旋转栈中所有路径的坐标
    /// Rotate all paths' coordinates in stack clockwise
    private func rotateStackClockwise(_ stack: inout [[DrawingPath]]) {
        for i in 0..<stack.count {
            for drawingPath in stack[i] {
                drawingPath.normalizedPoints = drawingPath.normalizedPoints.map { point in
                    return NSPoint(x: point.y, y: 1 - point.x)
                }
            }
        }
    }
    
    /// 逆时针旋转栈中所有路径的坐标
    /// Rotate all paths' coordinates in stack counterclockwise
    private func rotateStackCounterclockwise(_ stack: inout [[DrawingPath]]) {
        for i in 0..<stack.count {
            for drawingPath in stack[i] {
                drawingPath.normalizedPoints = drawingPath.normalizedPoints.map { point in
                    return NSPoint(x: 1 - point.y, y: point.x)
                }
            }
        }
    }
    
    var canUndo: Bool {
        return !undoStack.isEmpty
    }
    
    var canRedo: Bool {
        return !redoStack.isEmpty
    }
    
    var hasDrawings: Bool {
        return !drawingPaths.isEmpty
    }
    
    // 获取绘制内容的图像（按指定尺寸）
    // Get image of drawn content (at specified size)
    func getDrawingImage(targetSize: NSSize? = nil) -> NSImage? {
        let size = targetSize ?? bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        
        for drawingPath in drawingPaths {
            if drawingPath.isHighlighter {
                drawingPath.color.withAlphaComponent(0.4).setStroke()
            } else {
                drawingPath.color.setStroke()
            }
            let path = drawingPath.generatePath(for: size)
            path.lineWidth = drawingPath.getLineWidth(for: size)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        
        image.unlockFocus()
        return image
    }
}

// MARK: - 编辑工具栏视图
// MARK: - Edit toolbar view
class ImageEditingToolbarView: NSView {
    
    // 工具按钮
    // Tool buttons
    private var penButton: NSButton!
    private var highlighterButton: NSButton!
    private var eraserButton: NSButton!
    private var arrowButton: NSButton!
    private var rectangleButton: NSButton!
    private var ellipseButton: NSButton!
    
    // 颜色选择器
    // Color picker
    private var colorWell: NSColorWell!
    
    // 线宽滑块
    // Line width slider
    private var lineWidthSlider: NSSlider!
    private var lineWidthLabel: NSTextField!
    
    // 操作按钮
    // Action buttons
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var clearButton: NSButton!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!
    
    // 回调
    // Callbacks
    var onToolChanged: ((EditingTool) -> Void)?
    var onColorChanged: ((NSColor) -> Void)?
    var onLineWidthChanged: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onClear: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    
    private var currentTool: EditingTool = .pen
    private var toolButtons: [NSButton] = []
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        layer?.cornerRadius = 10
        
        setupToolButtons()
        setupColorPicker()
        setupLineWidthSlider()
        setupActionButtons()
        layoutSubviews()
    }
    
    private func setupToolButtons() {
        // 创建工具按钮
        // Create tool buttons
        penButton = createToolButton(imageName: "pencil.tip", tooltip: NSLocalizedString("Pen", comment: "画笔"))
        highlighterButton = createToolButton(imageName: "highlighter", tooltip: NSLocalizedString("Highlighter", comment: "荧光笔"))
        eraserButton = createToolButton(imageName: "eraser", tooltip: NSLocalizedString("Eraser", comment: "橡皮擦"))
        arrowButton = createToolButton(imageName: "arrow.up.right", tooltip: NSLocalizedString("Arrow", comment: "箭头"))
        rectangleButton = createToolButton(imageName: "rectangle", tooltip: NSLocalizedString("Rectangle", comment: "矩形"))
        ellipseButton = createToolButton(imageName: "circle", tooltip: NSLocalizedString("Ellipse", comment: "椭圆"))
        
        toolButtons = [penButton, highlighterButton, eraserButton, arrowButton, rectangleButton, ellipseButton]
        
        penButton.target = self
        penButton.action = #selector(selectPen)
        highlighterButton.target = self
        highlighterButton.action = #selector(selectHighlighter)
        eraserButton.target = self
        eraserButton.action = #selector(selectEraser)
        arrowButton.target = self
        arrowButton.action = #selector(selectArrow)
        rectangleButton.target = self
        rectangleButton.action = #selector(selectRectangle)
        ellipseButton.target = self
        ellipseButton.action = #selector(selectEllipse)
        
        // 默认选中画笔
        // Default select pen
        updateToolSelection(penButton)
    }
    
    private func createToolButton(imageName: String, tooltip: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.toolTip = tooltip
        
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: tooltip) {
            button.image = image
            button.imageScaling = .scaleProportionallyUpOrDown
        }
        button.contentTintColor = .white
        
        addSubview(button)
        return button
    }
    
    private func updateToolSelection(_ selectedButton: NSButton) {
        for button in toolButtons {
            if button == selectedButton {
                button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
            } else {
                button.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    @objc private func selectPen() {
        currentTool = .pen
        updateToolSelection(penButton)
        onToolChanged?(.pen)
    }
    
    @objc private func selectHighlighter() {
        currentTool = .highlighter
        updateToolSelection(highlighterButton)
        onToolChanged?(.highlighter)
    }
    
    @objc private func selectEraser() {
        currentTool = .eraser
        updateToolSelection(eraserButton)
        onToolChanged?(.eraser)
    }
    
    @objc private func selectArrow() {
        currentTool = .arrow
        updateToolSelection(arrowButton)
        onToolChanged?(.arrow)
    }
    
    @objc private func selectRectangle() {
        currentTool = .rectangle
        updateToolSelection(rectangleButton)
        onToolChanged?(.rectangle)
    }
    
    @objc private func selectEllipse() {
        currentTool = .ellipse
        updateToolSelection(ellipseButton)
        onToolChanged?(.ellipse)
    }
    
    private func setupColorPicker() {
        colorWell = NSColorWell(frame: .zero)
        colorWell.color = .red
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        addSubview(colorWell)
    }
    
    @objc private func colorChanged() {
        onColorChanged?(colorWell.color)
    }
    
    private func setupLineWidthSlider() {
        lineWidthLabel = NSTextField(labelWithString: "4")
        lineWidthLabel.textColor = .white
        lineWidthLabel.font = NSFont.systemFont(ofSize: 12)
        addSubview(lineWidthLabel)
        
        lineWidthSlider = NSSlider(value: 4, minValue: 1, maxValue: 20, target: self, action: #selector(lineWidthChanged))
        lineWidthSlider.isContinuous = true
        addSubview(lineWidthSlider)
    }
    
    @objc private func lineWidthChanged() {
        let width = CGFloat(lineWidthSlider.doubleValue)
        lineWidthLabel.stringValue = String(format: "%.0f", width)
        onLineWidthChanged?(width)
    }
    
    private func setupActionButtons() {
        undoButton = createActionButton(imageName: "arrow.uturn.backward", tooltip: NSLocalizedString("Undo", comment: "撤销"))
        redoButton = createActionButton(imageName: "arrow.uturn.forward", tooltip: NSLocalizedString("Redo", comment: "重做"))
        clearButton = createActionButton(imageName: "trash", tooltip: NSLocalizedString("Clear", comment: "清除"))
        saveButton = createActionButton(imageName: "square.and.arrow.down", tooltip: NSLocalizedString("Save", comment: "保存"))
        cancelButton = createActionButton(imageName: "xmark", tooltip: NSLocalizedString("Cancel", comment: "取消"))
        
        undoButton.target = self
        undoButton.action = #selector(undoAction)
        redoButton.target = self
        redoButton.action = #selector(redoAction)
        clearButton.target = self
        clearButton.action = #selector(clearAction)
        saveButton.target = self
        saveButton.action = #selector(saveAction)
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction)
    }
    
    private func createActionButton(imageName: String, tooltip: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.toolTip = tooltip
        
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: tooltip) {
            button.image = image
            button.imageScaling = .scaleProportionallyUpOrDown
        }
        button.contentTintColor = .white
        
        addSubview(button)
        return button
    }
    
    @objc private func undoAction() {
        onUndo?()
    }
    
    @objc private func redoAction() {
        onRedo?()
    }
    
    @objc private func clearAction() {
        onClear?()
    }
    
    @objc private func saveAction() {
        onSave?()
    }
    
    @objc private func cancelAction() {
        onCancel?()
    }
    
    private func layoutSubviews() {
        let buttonSize: CGFloat = 32
        let spacing: CGFloat = 8
        let padding: CGFloat = 12
        var x = padding
        
        // 工具按钮
        // Tool buttons
        for button in toolButtons {
            button.frame = NSRect(x: x, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            x += buttonSize + spacing
        }
        
        // 分隔
        // Separator
        x += spacing
        
        // 颜色选择器
        // Color picker
        colorWell.frame = NSRect(x: x, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
        x += buttonSize + spacing
        
        // 线宽滑块
        // Line width slider
        lineWidthLabel.frame = NSRect(x: x, y: (bounds.height - 20) / 2, width: 20, height: 20)
        x += 22
        lineWidthSlider.frame = NSRect(x: x, y: (bounds.height - 20) / 2, width: 80, height: 20)
        x += 80 + spacing * 2
        
        // 操作按钮
        // Action buttons
        undoButton.frame = NSRect(x: x, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
        x += buttonSize + spacing
        redoButton.frame = NSRect(x: x, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
        x += buttonSize + spacing
        clearButton.frame = NSRect(x: x, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
        x += buttonSize + spacing * 2
        
        // 保存和取消按钮
        // Save and cancel buttons
        saveButton.frame = NSRect(x: x, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
        x += buttonSize + spacing
        cancelButton.frame = NSRect(x: x, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
    }
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutSubviews()
    }
    
    func updateUndoRedoState(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        undoButton.contentTintColor = canUndo ? .white : .gray
        redoButton.isEnabled = canRedo
        redoButton.contentTintColor = canRedo ? .white : .gray
    }
}

// MARK: - 图片编辑主视图
// MARK: - Image editing main view
class ImageEditingView: NSView {
    
    // 子视图
    // Subviews
    var canvasView: ImageEditingCanvasView!
    var toolbarView: ImageEditingToolbarView!
    
    // 原始图片
    // Original image
    var originalImage: NSImage?
    
    // 回调
    // Callbacks
    var onSave: ((NSImage) -> Void)?
    var onCancel: (() -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        setupCanvasView()
        setupToolbarView()
        setupBindings()
    }
    
    private func setupCanvasView() {
        canvasView = ImageEditingCanvasView(frame: bounds)
        // 不设置 autoresizingMask，画布位置由外部通过 setImageFrame 控制
        // Don't set autoresizingMask, canvas position is controlled externally via setImageFrame
        addSubview(canvasView)
    }
    
    private func setupToolbarView() {
        let toolbarHeight: CGFloat = 50
        let toolbarWidth: CGFloat = 580
        toolbarView = ImageEditingToolbarView(frame: NSRect(x: (bounds.width - toolbarWidth) / 2,
                                                            y: 20,
                                                            width: toolbarWidth,
                                                            height: toolbarHeight))
        addSubview(toolbarView)
    }
    
    private func setupBindings() {
        toolbarView.onToolChanged = { [weak self] tool in
            self?.canvasView.currentTool = tool
        }
        
        toolbarView.onColorChanged = { [weak self] color in
            self?.canvasView.currentColor = color
        }
        
        toolbarView.onLineWidthChanged = { [weak self] width in
            self?.canvasView.currentLineWidth = width
        }
        
        toolbarView.onUndo = { [weak self] in
            self?.canvasView.undo()
        }
        
        toolbarView.onRedo = { [weak self] in
            self?.canvasView.redo()
        }
        
        toolbarView.onClear = { [weak self] in
            self?.canvasView.clearAll()
        }
        
        toolbarView.onSave = { [weak self] in
            self?.saveEditedImage()
        }
        
        toolbarView.onCancel = { [weak self] in
            self?.onCancel?()
        }
        
        canvasView.onDrawingChanged = { [weak self] in
            guard let self = self else { return }
            self.toolbarView.updateUndoRedoState(canUndo: self.canvasView.canUndo,
                                                  canRedo: self.canvasView.canRedo)
        }
    }
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        
        // 注意：画布的位置由外部通过 setImageFrame 控制，这里不重置
        // Note: Canvas position is controlled externally via setImageFrame, don't reset here
        
        let toolbarHeight: CGFloat = 50
        let toolbarWidth: CGFloat = 580
        toolbarView.frame = NSRect(x: (bounds.width - toolbarWidth) / 2,
                                   y: 20,
                                   width: toolbarWidth,
                                   height: toolbarHeight)
    }
    
    // 保存编辑后的图片
    // Save edited image
    private func saveEditedImage() {
        guard let originalImage = originalImage else {
            return
        }

        let size = NSSize(width: originalImage.size.width * 2.0, height: originalImage.size.height * 2.0)
        
        // 使用原图尺寸生成绘制内容（归一化坐标会自动适配）
        // Generate drawing content at original image size (normalized coordinates will auto-adapt)
        guard let drawingImage = canvasView.getDrawingImage(targetSize: size) else {
            return
        }
        
        // 合成图片
        // Composite image
        let finalImage = NSImage(size: size)
        finalImage.lockFocus()
        
        // 绘制原图
        // Draw original image
        originalImage.draw(in: NSRect(origin: .zero, size: size))
        
        // 直接绘制编辑内容（已经是原图尺寸）
        // Directly draw edited content (already at original image size)
        drawingImage.draw(in: NSRect(origin: .zero, size: size))
        
        finalImage.unlockFocus()
        
        onSave?(finalImage)
    }
    
    // 设置要编辑的图片（用于定位画布）
    // Set image to edit (for canvas positioning)
    func setImageFrame(_ frame: NSRect) {
        canvasView.frame = frame
    }
    
    /// 顺时针旋转画布内容90度
    /// Rotate canvas content clockwise 90 degrees
    func rotateClockwise() {
        canvasView.rotateClockwise()
    }
    
    /// 逆时针旋转画布内容90度
    /// Rotate canvas content counterclockwise 90 degrees
    func rotateCounterclockwise() {
        canvasView.rotateCounterclockwise()
    }
}
