//
//  PaneContainerViewController.swift
//  FlowVision
//

import Cocoa

// 分屏方向
// Split direction
enum PaneSplitDirection {
    // 左右并排
    // Side by side
    case right
    // 上下堆叠
    // Stacked vertically
    case down
}

// 分屏窗格之间的分隔条
// Divider between split panes
class PaneSplitView: NSSplitView {

    override var dividerThickness: CGFloat {
        return 1
    }

    override var dividerColor: NSColor {
        return NSColor.separatorColor
    }

    // 加宽分隔条的拖动热区，避免1像素难以命中
    // Widen the divider hit area, a 1px divider is hard to grab
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for i in 0..<max(0, subviews.count - 1) {
            var rect = dividerRect(at: i)
            rect = rect.insetBy(dx: isVertical ? -3 : 0, dy: isVertical ? 0 : -3)
            if rect.contains(local) {
                return self
            }
        }
        return super.hitTest(point)
    }

    private func dividerRect(at index: Int) -> NSRect {
        guard index < subviews.count - 1 else { return .zero }
        let before = subviews[index].frame
        if isVertical {
            return NSRect(x: before.maxX, y: 0, width: dividerThickness, height: bounds.height)
        } else {
            // 非翻转坐标系下，第一个子视图在上方
            // In non-flipped coordinates the first subview sits on top
            return NSRect(x: 0, y: before.minY - dividerThickness, width: bounds.width, height: dividerThickness)
        }
    }
}

// 标示当前活动窗格的边框，不接收鼠标事件
// Border marking the active pane, never takes mouse events
class PaneFocusIndicatorView: NSView {

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override var isOpaque: Bool {
        return false
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }
}

// 分屏容器：作为窗口的contentViewController，承载一个或多个ViewController作为窗格
// Pane container: acts as the window's contentViewController, hosting one or more ViewControllers as panes
class PaneContainerViewController: NSViewController, NSSplitViewDelegate {

    static let minPaneSize: CGFloat = 200
    // 窗格数量上限，再多每个窗格就窄到放不下缩略图了
    // Upper bound on panes, beyond this each pane is too narrow to show thumbnails
    static let maxPanes = 8

    let splitView = PaneSplitView()
    private let focusIndicator = PaneFocusIndicatorView()

    // 从左到右（或从上到下）排列的窗格
    // Panes ordered left to right (or top to bottom)
    private(set) var panes: [ViewController] = []

    private weak var storedActivePane: ViewController?

    var isSplit: Bool {
        return panes.count > 1
    }

    var activePane: ViewController? {
        if let stored = storedActivePane, panes.contains(where: { $0 === stored }) {
            return stored
        }
        return panes.first
    }

    var splitDirection: PaneSplitDirection {
        return splitView.isVertical ? .right : .down
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        root.autoresizingMask = [.width, .height]

        splitView.frame = root.bounds
        splitView.autoresizingMask = [.width, .height]
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.arrangesAllSubviews = true
        splitView.delegate = self
        root.addSubview(splitView)

        focusIndicator.isHidden = true
        root.addSubview(focusIndicator)

        self.view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateFocusIndicator()
    }

    // MARK: - 窗格管理
    // MARK: - Pane management

    // 接管一个ViewController作为窗格（可能来自另一个窗口）
    // Take over a ViewController as a pane (possibly coming from another window)
    func adoptPane(_ pane: ViewController, at index: Int? = nil, makeActive: Bool = true) {
        let insertIndex = min(max(index ?? panes.count, 0), panes.count)

        if pane.parent != nil {
            pane.removeFromParent()
        }
        if pane.view.superview != nil {
            pane.view.removeFromSuperview()
        }

        addChild(pane)
        pane.view.translatesAutoresizingMaskIntoConstraints = true
        if insertIndex >= splitView.arrangedSubviews.count {
            splitView.addArrangedSubview(pane.view)
        } else {
            splitView.insertArrangedSubview(pane.view, at: insertIndex)
        }
        panes.insert(pane, at: insertIndex)

        equalizePanes()
        if makeActive {
            setActivePane(pane)
        } else {
            updateFocusIndicator()
        }
        notifyPanesOfLayoutChange()
    }

    // 把窗格从容器中摘出来但不销毁，用于移动到其它窗口
    // Detach a pane without destroying it, used when moving it to another window
    @discardableResult
    func detachPane(_ pane: ViewController) -> ViewController? {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return nil }
        panes.remove(at: index)
        pane.view.removeFromSuperview()
        pane.removeFromParent()
        if storedActivePane === pane {
            storedActivePane = nil
        }
        equalizePanes()
        if let next = activePane {
            setActivePane(next)
        }
        updateFocusIndicator()
        notifyPanesOfLayoutChange()
        return pane
    }

    // 关闭并销毁一个窗格
    // Close and tear down a pane
    func closePane(_ pane: ViewController) {
        guard panes.contains(where: { $0 === pane }) else { return }
        detachPane(pane)
        pane.largeImageView.prepareForDeinit()
        pane.prepareForDeinit()
    }

    // 窗口关闭时销毁所有窗格
    // Tear down every pane when the window closes
    func prepareForDeinit() {
        for pane in panes {
            pane.largeImageView.prepareForDeinit()
            pane.prepareForDeinit()
        }
    }

    // 在活动窗格旁边新增一个窗格
    // Add a new pane next to the active pane
    @discardableResult
    func addPane(direction: PaneSplitDirection, folder: String? = nil) -> ViewController? {
        guard let newPane = PaneContainerViewController.instantiatePaneViewController() else { return nil }

        setSplitDirection(direction)

        let reference = activePane
        let insertIndex = reference.flatMap { pane in panes.firstIndex(where: { $0 === pane }).map { $0 + 1 } }

        // 新窗格默认沿用当前窗格的目录
        // A new pane starts in the folder the current pane is showing
        var openFolder = folder
        if openFolder == nil, let reference = reference {
            reference.fileDB.lock()
            openFolder = reference.fileDB.curFolder
            reference.fileDB.unlock()
        }
        if let openFolder = openFolder {
            newPane.fileDB.lock()
            newPane.fileDB.curFolder = openFolder
            newPane.fileDB.unlock()
        }

        adoptPane(newPane, at: insertIndex)

        DispatchQueue.main.async {
            newPane.afterFinishLoad(openFolder)
        }
        return newPane
    }

    // 从storyboard新建一个ViewController实例
    // Create a fresh ViewController instance from the storyboard
    static func instantiatePaneViewController() -> ViewController? {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let viewController = storyboard.instantiateController(withIdentifier: "ViewController") as? ViewController else {
            log("Cannot find ViewController in Main.storyboard", level: .error)
            return nil
        }
        // 触发viewDidLoad
        // Force viewDidLoad
        _ = viewController.view
        return viewController
    }

    func setSplitDirection(_ direction: PaneSplitDirection) {
        let shouldBeVertical = (direction == .right)
        guard splitView.isVertical != shouldBeVertical else { return }
        splitView.isVertical = shouldBeVertical
        equalizePanes()
        notifyPanesOfLayoutChange()
    }

    func toggleSplitDirection() {
        setSplitDirection(splitDirection == .right ? .down : .right)
    }

    // MARK: - 活动窗格
    // MARK: - Active pane

    func setActivePane(_ pane: ViewController, moveFocus: Bool = true) {
        guard panes.contains(where: { $0 === pane }) else { return }
        let changed = storedActivePane !== pane
        storedActivePane = pane
        updateFocusIndicator()
        guard changed else { return }

        if moveFocus, let window = view.window {
            let target: NSView = pane.publicVar.isInLargeView ? pane.largeImageView : pane.collectionView
            if window.firstResponder !== target {
                window.makeFirstResponder(target)
            }
        }
        // 标题栏与工具栏跟随活动窗格
        // Title bar and toolbar follow the active pane
        pane.setWindowTitle()
    }

    func activatePane(at index: Int) {
        guard index >= 0 && index < panes.count else { return }
        setActivePane(panes[index])
    }

    func activateNextPane(offset: Int) {
        guard isSplit, let current = activePane,
              let index = panes.firstIndex(where: { $0 === current }) else { return }
        let count = panes.count
        let next = ((index + offset) % count + count) % count
        setActivePane(panes[next])
    }

    // 命中测试：找出某个窗口坐标落在哪个窗格里
    // Hit test: find which pane a window-space point falls into
    func pane(atWindowPoint point: NSPoint) -> ViewController? {
        for pane in panes {
            let local = pane.view.convert(point, from: nil)
            if pane.view.bounds.contains(local) {
                return pane
            }
        }
        return nil
    }

    // MARK: - 布局
    // MARK: - Layout

    func equalizePanes() {
        guard panes.count > 1 else {
            splitView.adjustSubviews()
            return
        }
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        guard total > 0 else { return }
        let dividers = CGFloat(panes.count - 1) * splitView.dividerThickness
        let each = max(PaneContainerViewController.minPaneSize / 2, (total - dividers) / CGFloat(panes.count))
        splitView.adjustSubviews()
        for i in 0..<(panes.count - 1) {
            let position = each * CGFloat(i + 1) + splitView.dividerThickness * CGFloat(i)
            splitView.setPosition(position, ofDividerAt: i)
        }
        updateFocusIndicator()
    }

    private func updateFocusIndicator() {
        guard isSplit, let active = activePane, active.view.superview === splitView else {
            focusIndicator.isHidden = true
            return
        }
        focusIndicator.isHidden = false
        focusIndicator.frame = view.convert(active.view.frame, from: splitView)
        focusIndicator.needsDisplay = true
        // 始终保持在最上层
        // Always keep it on top
        if view.subviews.last !== focusIndicator {
            focusIndicator.removeFromSuperview()
            view.addSubview(focusIndicator)
        }
    }

    // 窗格尺寸变化后重新计算瀑布流布局
    // Recalculate the waterfall layout after pane sizes change
    private func notifyPanesOfLayoutChange() {
        for pane in panes {
            pane.changeWaterfallLayoutNumberOfColumns()
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMinimumPosition + PaneContainerViewController.minPaneSize
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMaximumPosition - PaneContainerViewController.minPaneSize
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        updateFocusIndicator()
    }
}
