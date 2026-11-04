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

// 共享目录树的宿主。它位于窗口层级而不在任何窗格内，所以某个窗格进入大图/全屏时盖不住它。
// 通过把响应链接到当前活动窗格，树上的右键菜单和导航依然作用于活动窗格。
// Host for the shared folder tree. It lives at window level rather than inside any pane, so a pane
// going large image / full screen cannot cover it. Splicing the responder chain to the active pane
// keeps the tree's context menu and navigation acting on that pane.
class SharedSidebarHostView: NSView {

    weak var ownerPane: ViewController?

    override var nextResponder: NSResponder? {
        get { return ownerPane ?? super.nextResponder }
        set { super.nextResponder = newValue }
    }
}

// 每个窗格右上角的关闭按钮。它画在容器层，因此窗格进入大图时依然点得到。
// Close button at each pane's top right corner. It is drawn at container level, so it stays clickable
// even when the pane is showing a large image.
class PaneCloseButton: NSButton {

    weak var pane: ViewController?
    private var hoverTrackingArea: NSTrackingArea?

    static let size: CGFloat = 18
    private let restingAlpha: CGFloat = 0.45

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: PaneCloseButton.size, height: PaneCloseButton.size))
        isBordered = false
        bezelStyle = .circular
        title = ""
        wantsLayer = true
        layer?.cornerRadius = PaneCloseButton.size / 2
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        if let symbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: NSLocalizedString("Close Pane", comment: "关闭窗格")) {
            image = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        }
        imageScaling = .scaleProportionallyDown
        contentTintColor = .white
        alphaValue = restingAlpha
        toolTip = NSLocalizedString("Close Pane", comment: "关闭窗格")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        animator().alphaValue = 1.0
    }

    override func mouseExited(with event: NSEvent) {
        animator().alphaValue = restingAlpha
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
    // 外层分栏：左边是共享目录树，右边是并排的窗格
    // Outer split: the shared folder tree on the left, the side by side panes on the right
    let outerSplitView = NSSplitView()
    private let sidebarHost = SharedSidebarHostView()
    private let focusIndicator = PaneFocusIndicatorView()
    private var paneCloseButtons: [PaneCloseButton] = []

    static let defaultSharedSidebarWidth: CGFloat = 270
    private var sharedSidebarWidth = PaneContainerViewController.defaultSharedSidebarWidth
    // 用户在分屏状态下手动收起了共享目录树
    // The user collapsed the shared folder tree while split
    private(set) var isSharedSidebarHidden = false

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

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.arrangesAllSubviews = true
        splitView.delegate = self

        outerSplitView.frame = root.bounds
        outerSplitView.autoresizingMask = [.width, .height]
        outerSplitView.isVertical = true
        outerSplitView.dividerStyle = .thin
        outerSplitView.arrangesAllSubviews = true
        outerSplitView.delegate = self
        root.addSubview(outerSplitView)
        outerSplitView.addArrangedSubview(splitView)

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
        updateSharedSidebar()
        rebuildPaneCloseButtons()
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
        updateSharedSidebar()
        rebuildPaneCloseButtons()
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
        newPane.collapseSidebarAsSecondaryPane()

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

        // 共享目录树跟随活动窗格
        // The shared folder tree follows the active pane
        updateSharedSidebar()

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

    // MARK: - 共享目录树
    // MARK: - Shared folder tree

    var isSharedSidebarVisible: Bool {
        return sidebarHost.superview != nil
    }

    // 分屏时把活动窗格的目录树提到窗口层级；回到单窗格时再交还给它
    // While split, lift the active pane's folder tree up to window level; hand it back at a single pane
    func updateSharedSidebar() {
        guard isSplit, !isSharedSidebarHidden, let active = activePane else {
            teardownSharedSidebar()
            return
        }
        if sidebarHost.superview == nil {
            outerSplitView.insertArrangedSubview(sidebarHost, at: 0)
            outerSplitView.adjustSubviews()
            outerSplitView.setPosition(sharedSidebarWidth, ofDividerAt: 0)
        }
        hostTree(of: active)
        // 窗口里只留共享的这一棵树，其余窗格内部的侧栏一律收起
        // Keep only the shared tree in the window, every pane's own sidebar stays collapsed
        for pane in panes where pane !== active {
            pane.collapseSidebarAsSecondaryPane()
        }
    }

    private func hostTree(of pane: ViewController) {
        if sidebarHost.ownerPane === pane && pane.outlineScrollView?.superview === sidebarHost {
            return
        }
        if let previous = sidebarHost.ownerPane, previous !== pane {
            returnTree(to: previous)
        }
        // outlineScrollView是weak outlet，搬动期间必须由强引用持住，否则会被释放
        // outlineScrollView is a weak outlet, a strong reference has to hold it across the move or it is deallocated
        guard let scrollView: NSScrollView = pane.outlineScrollView else { return }
        if pane.outlineScrollViewHomeView == nil {
            pane.outlineScrollViewHomeView = scrollView.superview
        }
        scrollView.removeFromSuperview()
        scrollView.frame = sidebarHost.bounds
        scrollView.autoresizingMask = [.width, .height]
        sidebarHost.addSubview(scrollView)
        sidebarHost.ownerPane = pane
        // 窗格内部的侧栏收起，树已经搬到窗口层级了
        // Collapse the pane's own sidebar, its tree now lives at window level
        pane.collapseSidebarAsSecondaryPane()
        pane.outlineViewManager?.adjustColumnWidth()
    }

    private func returnTree(to pane: ViewController) {
        guard let home = pane.outlineScrollViewHomeView else { return }
        guard let scrollView: NSScrollView = pane.outlineScrollView else { return }
        guard scrollView.superview === sidebarHost else { return }
        scrollView.removeFromSuperview()
        scrollView.frame = home.bounds
        scrollView.autoresizingMask = [.width, .height]
        home.addSubview(scrollView)
    }

    private func teardownSharedSidebar() {
        if let owner = sidebarHost.ownerPane {
            returnTree(to: owner)
        }
        sidebarHost.ownerPane = nil
        if sidebarHost.superview != nil {
            sharedSidebarWidth = max(120, sidebarHost.frame.width)
            sidebarHost.removeFromSuperview()
            outerSplitView.adjustSubviews()
        }
        // 每个窗格都把自己的侧栏要回去
        // Every pane takes its own sidebar back
        for pane in panes {
            pane.restoreSidebarIfAutoHidden()
        }
    }

    // 分屏状态下切换共享目录树的显示
    // Toggle the shared folder tree while split
    func toggleSharedSidebar() {
        guard isSplit else { return }
        if isSharedSidebarVisible {
            isSharedSidebarHidden = true
            if let owner = sidebarHost.ownerPane {
                returnTree(to: owner)
            }
            sidebarHost.ownerPane = nil
            sharedSidebarWidth = max(120, sidebarHost.frame.width)
            sidebarHost.removeFromSuperview()
            outerSplitView.adjustSubviews()
        } else {
            isSharedSidebarHidden = false
            updateSharedSidebar()
        }
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

    // 分屏时每个窗格都有自己的关闭按钮，不必先切到那个窗格
    // While split every pane carries its own close button, no need to switch to it first
    private func rebuildPaneCloseButtons() {
        for button in paneCloseButtons {
            button.removeFromSuperview()
        }
        paneCloseButtons.removeAll()
        guard isSplit else { return }
        for pane in panes {
            let button = PaneCloseButton()
            button.pane = pane
            button.target = self
            button.action = #selector(paneCloseButtonClicked(_:))
            view.addSubview(button)
            paneCloseButtons.append(button)
        }
        layoutPaneCloseButtons()
    }

    private func layoutPaneCloseButtons() {
        let inset: CGFloat = 8
        for button in paneCloseButtons {
            guard let pane = button.pane, pane.view.superview === splitView else {
                button.isHidden = true
                continue
            }
            button.isHidden = false
            let frameInView = view.convert(pane.view.frame, from: splitView)
            button.frame = NSRect(x: frameInView.maxX - PaneCloseButton.size - inset,
                                  y: frameInView.maxY - PaneCloseButton.size - inset,
                                  width: PaneCloseButton.size,
                                  height: PaneCloseButton.size)
            // 保证浮在窗格内容和焦点框之上
            // Keep it above the pane content and the focus ring
            if view.subviews.last !== button {
                button.removeFromSuperview()
                view.addSubview(button)
            }
        }
    }

    @objc private func paneCloseButtonClicked(_ sender: PaneCloseButton) {
        guard let pane = sender.pane else { return }
        closePane(pane)
    }

    private func updateFocusIndicator() {
        guard isSplit, let active = activePane, active.view.superview === splitView else {
            focusIndicator.isHidden = true
            layoutPaneCloseButtons()
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
        layoutPaneCloseButtons()
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
        // 外层分栏的分隔条控制共享目录树的宽度
        // The outer split's divider sizes the shared folder tree
        if splitView === outerSplitView {
            return 150
        }
        return proposedMinimumPosition + PaneContainerViewController.minPaneSize
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === outerSplitView {
            return min(450, max(150, splitView.bounds.width - PaneContainerViewController.minPaneSize))
        }
        return proposedMaximumPosition - PaneContainerViewController.minPaneSize
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        if (notification.object as? NSSplitView) === outerSplitView, isSharedSidebarVisible {
            sharedSidebarWidth = max(120, sidebarHost.frame.width)
        }
        updateFocusIndicator()
    }
}
