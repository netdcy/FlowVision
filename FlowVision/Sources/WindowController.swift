//
//  WindowController.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/16.
//

import Cocoa

class WindowController: NSWindowController, NSWindowDelegate {

    override func windowDidLoad() {
        super.windowDidLoad()
        
        log("开始windowDidLoad")
        
        self.window?.delegate = self
        
        window?.title = "FlowVision"
        
        NotificationCenter.default.addObserver(self, selector: #selector(saveWindowState), name: NSWindow.willCloseNotification, object: window)
        
        if let window = self.window {
            // 设置标题栏和工具栏合并效果
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = false
            
            // 创建并配置工具栏
            globalVar.toolbarIndex += 1
            let toolbar = NSToolbar(identifier: "MainToolbar"+String(globalVar.toolbarIndex))
            toolbar.delegate = self
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.displayMode = .iconOnly
            toolbar.showsBaselineSeparator = true
            window.toolbar = toolbar

            if globalVar.autoHideToolbar {
                window.acceptsMouseMovedEvents = true
                window.styleMask.insert(.fullSizeContentView)
                window.tabbingMode = .disallowed
            }else{
                window.tabbingMode = .preferred
            }
        }
        
        if globalVar.portableMode && globalVar.startSpeedUpImageSizeCache != nil {
            if let viewController = contentViewController as? ViewController {
                viewController.adjustWindowPortable(refSize: globalVar.startSpeedUpImageSizeCache, firstShowThumb: false, animate: false, justAdjustWindowFrame: true, isToCenter: true)
                globalVar.startSpeedUpImageSizeCache=nil
            }
        }else{
            if let frameString = UserDefaults.standard.string(forKey: "windowFrame") {
                let frame = NSRectFromString(frameString)
                window?.setFrame(frame, display: true)
            }
        }
        
        log("结束windowDidLoad")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }
    
    @objc func saveWindowState() {
        guard let window = self.window else { return }
        if let viewController = contentViewController as? ViewController {
            if viewController.publicVar.isInLargeView {
                return
            }
        }
        let frame = NSStringFromRect(window.frame)
        UserDefaults.standard.set(frame, forKey: "windowFrame")
    }
    
    func windowWillClose(_ notification: Notification) {
        // 移除引用
        if let window = notification.object as? NSWindow {
            log("Window \(window) will close")
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.removeWindowController(self)
            }
        }
        // 在窗口关闭时执行你的代码，例如，保存数据、释放资源等
        if let viewController = contentViewController as? ViewController {
            //供其它线程参考的终止状态
            viewController.willTerminate=true
            //产生空任务，防止等待信号量导致窗口无法销毁/
            viewController.readInfoTaskPoolSemaphore.signal()
            viewController.loadImageTaskPoolSemaphore.signal()
        }
        
        globalVar.windowNum -= 1
        log("Window closed, remain: " + String(globalVar.windowNum))
        if globalVar.windowNum == 0 && globalVar.terminateAfterLastWindowClosed {
            DispatchQueue.main.async { // 不这样会导致windowWillClose被调用两遍
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        log("windowDidBecomeKey")
    }
    
    func toggleWindowOnTop() {
        if let window = self.window {
            if window.level == .floating {
                // 取消置顶
                window.level = .normal
            } else {
                // 置顶
                window.level = .floating
            }
            updateToolbar()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if globalVar.autoHideToolbar {
            showTitleBar()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if globalVar.autoHideToolbar {
            hideTitleBar()
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        if globalVar.autoHideToolbar {
            let location = event.locationInWindow
            if location.y > window!.frame.height - 40 {
                showTitleBar()
            } else {
                hideTitleBar()
            }
        }
    }
    
    // 显示标题栏和工具栏
    func showTitleBar() {
        guard let window = window else { return }
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.titlebarAppearsTransparent = false
        window.toolbar?.isVisible = true
    }
    
    // 隐藏标题栏和工具栏
    func hideTitleBar() {
        guard let window = window else { return }
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.titlebarAppearsTransparent = true
        window.toolbar?.isVisible = false
    }
}

extension NSToolbarItem.Identifier {
    static let sidebar = NSToolbarItem.Identifier("com.example.sidebar")
    static let goBack = NSToolbarItem.Identifier("com.example.goBack")
    static let goForward = NSToolbarItem.Identifier("com.example.goForward")
    static let viewToggle = NSToolbarItem.Identifier("com.example.viewToggle")
    static let newtab = NSToolbarItem.Identifier("com.example.newtab")
    static let showinfo = NSToolbarItem.Identifier("com.example.showinfo")
    static let ontop = NSToolbarItem.Identifier("com.example.ontop")
    static let windowTitle = NSToolbarItem.Identifier("com.example.windowTitle")
    static let rotateL = NSToolbarItem.Identifier("com.example.rotateL")
    static let rotateR = NSToolbarItem.Identifier("com.example.rotateR")
    static let zoomIn = NSToolbarItem.Identifier("com.example.zoomIn")
    static let zoomOut = NSToolbarItem.Identifier("com.example.zoomOut")
    static let sort = NSToolbarItem.Identifier("com.example.sort")
    static let more = NSToolbarItem.Identifier("com.example.more")
    static let favorites = NSToolbarItem.Identifier("com.example.favorites")
    static let thumbSize = NSToolbarItem.Identifier("com.example.thumbSize")
}

extension WindowController: NSToolbarDelegate {
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return getItemIdentifiers()
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return getItemIdentifiers()
    }
    
    func getItemIdentifiers() -> [NSToolbarItem.Identifier] {
        //, .flexibleSpace, .space
        var identifiers: [NSToolbarItem.Identifier] = [.sidebar, .favorites, .goBack, .goForward, .windowTitle]
        if let viewController = contentViewController as? ViewController {
            if viewController.publicVar.isInLargeView {
                identifiers.append(.zoomOut)
                identifiers.append(.zoomIn)
                //identifiers.append(.rotateL)
                identifiers.append(.rotateR)
                identifiers.append(.showinfo)
            }else{
                identifiers.append(.viewToggle)
                identifiers.append(.sort)
                identifiers.append(.thumbSize)
            }
        }
        
        identifiers.append(.space)
        identifiers.append(.flexibleSpace)
        identifiers.append(.more)
        identifiers.append(.newtab)
        
        return identifiers
    }
    
    func updateToolbar() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let toolbar = window?.toolbar else { return }
            let itemIdentifiers = getItemIdentifiers()
            
            while toolbar.items.count > 0 {
                toolbar.removeItem(at: 0)
            }
            
            for (index, identifier) in itemIdentifiers.enumerated() {
                toolbar.insertItem(withItemIdentifier: identifier, at: index)
            }
            
        }
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
        guard let viewController = contentViewController as? ViewController else {return toolbarItem}
        switch itemIdentifier {
            
        case .windowTitle:
            let titleLabel = createWindowTitleLabel()
            toolbarItem.view = titleLabel
            toolbarItem.minSize = NSSize(width: 200, height: titleLabel.fittingSize.height)
            toolbarItem.maxSize = NSSize(width: 10000, height: titleLabel.fittingSize.height)
            //toolbarItem.minSize = titleLabel.fittingSize
            //toolbarItem.maxSize = titleLabel.fittingSize
            toolbarItem.label = NSLocalizedString("window-title", comment: "窗口标题")
            toolbarItem.paletteLabel = NSLocalizedString("window-title", comment: "窗口标题")
            toolbarItem.visibilityPriority = .high
            
        case .sidebar:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "")!, target: self, action: #selector(sidebarAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Sidebar", comment: "侧边栏")
            button.isEnabled = !viewController.publicVar.isInLargeView
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Sidebar", comment: "侧边栏")
            toolbarItem.paletteLabel = NSLocalizedString("Sidebar", comment: "侧边栏")
            toolbarItem.isNavigational = true
            toolbarItem.visibilityPriority = .low
            
        case .favorites:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "star", accessibilityDescription: "")!, target: self, action: #selector(favoritesAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Favorites", comment: "收藏夹")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Favorites", comment: "收藏夹")
            toolbarItem.paletteLabel = NSLocalizedString("Favorites", comment: "收藏夹")
            toolbarItem.isNavigational = true
            toolbarItem.visibilityPriority = .low
            
        case .goBack:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "")!, target: self, action: #selector(goBackAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("go-back", comment: "后退")
            button.isEnabled = (viewController.publicVar.folderStepStack.count > 0) && (!viewController.publicVar.isInLargeView)
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("go-back", comment: "后退")
            toolbarItem.paletteLabel = NSLocalizedString("go-back", comment: "后退")
            toolbarItem.isNavigational = true
            toolbarItem.visibilityPriority = .low
            
        case .goForward:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: "")!, target: self, action: #selector(goForwardAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("go-forward", comment: "前进")
            button.isEnabled = (viewController.publicVar.folderStepForwardStack.count > 0) && (!viewController.publicVar.isInLargeView)
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("go-forward", comment: "前进")
            toolbarItem.paletteLabel = NSLocalizedString("go-forward", comment: "前进")
            toolbarItem.isNavigational = true
            toolbarItem.visibilityPriority = .low
            
        case .newtab:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "rectangle.badge.plus", accessibilityDescription: "")!, target: self, action: #selector(newtabAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("new-tab", comment: "新标签页")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("new-tab", comment: "新标签页")
            toolbarItem.paletteLabel = NSLocalizedString("new-tab", comment: "新标签页")
            toolbarItem.visibilityPriority = .user
            
        case .viewToggle:
            let segmentedControl = NSSegmentedControl(images: [
                //NSImage(systemSymbolName: "rectangle.grid.1x2", accessibilityDescription: "Justified")!,
                NSImage(systemSymbolName: "squares.below.rectangle", accessibilityDescription: "Justified")!,
                NSImage(systemSymbolName: "rectangle.3.offgrid", accessibilityDescription: "Waterfall")!,
                NSImage(systemSymbolName: "rectangle.grid.2x2", accessibilityDescription: "Grid")!
            ], trackingMode: .selectOne, target: self, action: #selector(viewToggleAction(_:)))
            segmentedControl.selectedSegment = viewController.publicVar.layoutType.rawValue
            segmentedControl.segmentStyle = .automatic
            segmentedControl.setToolTip(NSLocalizedString("Justified View", comment: "自适应视图"), forSegment: 0)
            segmentedControl.setToolTip(NSLocalizedString("Waterfall View", comment: "瀑布流视图"), forSegment: 1)
            segmentedControl.setToolTip(NSLocalizedString("Grid View", comment: "网格视图"), forSegment: 2)
            toolbarItem.view = segmentedControl
            toolbarItem.label = NSLocalizedString("View", comment: "视图")
            toolbarItem.paletteLabel = NSLocalizedString("View", comment: "视图")
            //toolbarItem.toolTip = NSLocalizedString("View", comment: "视图")
            toolbarItem.visibilityPriority = .low
            
        case .ontop:
            var image: NSImage
            if window?.level == .floating {
                image = NSImage(systemSymbolName: "pin.circle.fill", accessibilityDescription: "")!
            }else{
                image = NSImage(systemSymbolName: "pin.circle", accessibilityDescription: "")!
            }
            let button = NSButton(title: "", image: image, target: self, action: #selector(ontopAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("pin-window", comment: "置顶")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("pin-window", comment: "置顶")
            toolbarItem.paletteLabel = NSLocalizedString("pin-window", comment: "置顶")
            toolbarItem.visibilityPriority = .standard
        
        case .showinfo:
            var image: NSImage
            if viewController.publicVar.isShowExif {
                image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "")!
            }else{
                image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "")!
            }
            let button = NSButton(title: "", image: image, target: self, action: #selector(showinfoAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("show-info", comment: "显示信息")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("show-info", comment: "显示信息")
            toolbarItem.paletteLabel = NSLocalizedString("show-info", comment: "显示信息")
            toolbarItem.visibilityPriority = .standard
            
        case .rotateL:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "")!, target: self, action: #selector(rotateLAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("rotate-counterclockwise", comment: "逆时针旋转")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("rotate-counterclockwise", comment: "逆时针旋转")
            toolbarItem.paletteLabel = NSLocalizedString("rotate-counterclockwise", comment: "逆时针旋转")
            toolbarItem.visibilityPriority = .low
            
        case .rotateR:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "")!, target: self, action: #selector(rotateRAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("rotate-clockwise", comment: "顺时针旋转")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("rotate-clockwise", comment: "顺时针旋转")
            toolbarItem.paletteLabel = NSLocalizedString("rotate-clockwise", comment: "顺时针旋转")
            toolbarItem.visibilityPriority = .low
            
        case .zoomIn:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "plus", accessibilityDescription: "")!, target: self, action: #selector(zoomInAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("zoom-in", comment: "放大")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("zoom-in", comment: "放大")
            toolbarItem.paletteLabel = NSLocalizedString("zoom-in", comment: "放大")
            toolbarItem.visibilityPriority = .low
            
        case .zoomOut:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "minus", accessibilityDescription: "")!, target: self, action: #selector(zoomOutAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("zoom-out", comment: "缩小")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("zoom-out", comment: "缩小")
            toolbarItem.paletteLabel = NSLocalizedString("zoom-out", comment: "缩小")
            toolbarItem.visibilityPriority = .low
            
        case .sort:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "")!, target: self, action: #selector(showSortMenu(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("sort-type", comment: "排序方式")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("sort-type", comment: "排序方式")
            toolbarItem.paletteLabel = NSLocalizedString("sort-type", comment: "排序方式")
            toolbarItem.visibilityPriority = .low
            
        case .thumbSize:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "")!, target: self, action: #selector(showThumbSizeMenu(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("thumb-size", comment: "缩略图大小")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("thumb-size", comment: "缩略图大小")
            toolbarItem.paletteLabel = NSLocalizedString("thumb-size", comment: "缩略图大小")
            toolbarItem.visibilityPriority = .low
            
        case .more:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "")!, target: self, action: #selector(showMoreMenu(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("More", comment: "更多")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("More", comment: "更多")
            toolbarItem.paletteLabel = NSLocalizedString("More", comment: "更多")
            toolbarItem.visibilityPriority = .user
            
        default:
            return nil
        }
        return toolbarItem
    }
    
    class NonClickableTextField: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil  // 忽略所有鼠标事件
        }
    }
    
    private func createWindowTitleLabel() -> NSTextField {
        var fullTitle = (contentViewController as? ViewController)?.publicVar.fullTitle
        let titleLabel = NonClickableTextField(labelWithString: fullTitle ?? "FlowVision")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        titleLabel.alignment = .center
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byTruncatingHead
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }
    
    func setButtonStyle(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
    }
    
    @objc func sidebarAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.toggleSidebar()
        }
    }
    
    @objc func ontopAction(_ sender: Any?) {
        toggleWindowOnTop()
    }
    
    @objc func goBackAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.switchDirByDirection(direction: .back, stackDeep: 0)
        }
    }

    @objc func goForwardAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.switchDirByDirection(direction: .forward, stackDeep: 0)
        }
    }
    
    @objc func newtabAction(_ sender: Any?) {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let viewController = contentViewController as? ViewController {
            viewController.fileDB.lock()
            let curFolder = viewController.fileDB.curFolder
            viewController.fileDB.unlock()
            appDelegate.createNewWindow(curFolder)
        }
    }
    
    @objc func showinfoAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.publicVar.isShowExif.toggle()
        }
    }
    
    @objc func rotateLAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.largeImageView.actRotateL()
        }
    }
    
    @objc func rotateRAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.largeImageView.actRotateR()
        }
    }
    
    @objc func zoomInAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.largeImageView.zoom(direction: +1)
        }
    }
    
    @objc func zoomOutAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.largeImageView.zoom(direction: -1)
        }
    }
    
    @objc func viewToggleAction(_ sender: NSSegmentedControl) {
        guard let viewController = contentViewController as? ViewController else {return}
        switch sender.selectedSegment {
        case 0:
            // 切换到自适应视图的代码
            viewController.switchToJustifiedView()
        case 1:
            // 切换到瀑布流视图的代码
            viewController.switchToWaterfallView()
        case 2:
            // 切换到网格视图的代码
            viewController.switchToGridView()
        default:
            break
        }
    }
    
    @objc func showSortMenu(_ sender: NSButton) {
        guard let viewController = contentViewController as? ViewController else {return}
        let sortTypes: [(SortType, String)] = [
            (.pathA, NSLocalizedString("sort-pathA", comment: "文件名")),
            (.pathZ, NSLocalizedString("sort-pathZ", comment: "文件名(倒序)")),
            (.sizeA, NSLocalizedString("sort-sizeA", comment: "大小")),
            (.sizeZ, NSLocalizedString("sort-sizeZ", comment: "大小(倒序)")),
            (.extA, NSLocalizedString("sort-extA", comment: "文件类型")),
            (.extZ, NSLocalizedString("sort-extZ", comment: "文件类型(倒序)")),
            (.createDateA, NSLocalizedString("sort-createDateA", comment: "创建日期")),
            (.createDateZ, NSLocalizedString("sort-createDateZ", comment: "创建日期(倒序)")),
            (.modDateA, NSLocalizedString("sort-modDateA", comment: "修改日期")),
            (.modDateZ, NSLocalizedString("sort-modDateZ", comment: "修改日期(倒序)")),
            (.addDateA, NSLocalizedString("sort-addDateA", comment: "添加日期")),
            (.addDateZ, NSLocalizedString("sort-addDateZ", comment: "添加日期(倒序)")),
            (.random, NSLocalizedString("sort-random", comment: "随机"))
        ]
        
        let menu = NSMenu()
        
        let folderFirstItem = NSMenuItem(title: NSLocalizedString("Sort Folders First", comment: "文件夹优先排序"), action: #selector(sortFolderFirst(_:)), keyEquivalent: "")
        folderFirstItem.state = viewController.publicVar.isSortFolderFirst ? .on : .off
        menu.addItem(folderFirstItem)
        
        menu.addItem(NSMenuItem.separator())
        
        for (sortType, title) in sortTypes {
            let menuItem = NSMenuItem(title: title, action: #selector(sortItems(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = sortType
            let curSortType = viewController.publicVar.sortType
            menuItem.state = curSortType == sortType ? .on : .off
            menu.addItem(menuItem)
        }
        
        let buttonFrame = sender.convert(sender.bounds, to: nil)
        let menuLocation = NSPoint(x: 0, y: buttonFrame.height + 4)
        menu.popUp(positioning: nil, at: menuLocation, in: sender)
    }
    
    @objc func sortFolderFirst(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.publicVar.isSortFolderFirst.toggle()
        viewController.changeSortType(viewController.publicVar.sortType)
    }
    
    @objc func sortItems(_ sender: NSMenuItem) {
        guard let sortType = sender.representedObject as? SortType else { return }
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.changeSortType(sortType)
    }
    
    @objc func favoritesAction(_ sender: NSButton) {
        guard let viewController = contentViewController as? ViewController else {return}
        
        let favoritesMenu = NSMenu()
        
        let addFolderMenuItem = NSMenuItem(
            title: NSLocalizedString("add-cur-folder", comment: "添加当前文件夹"),
            action: #selector(favoritesAdd(_:)),
            keyEquivalent: ""
        )
        addFolderMenuItem.target = self
        favoritesMenu.addItem(addFolderMenuItem)
        
        favoritesMenu.addItem(NSMenuItem.separator())
        
        if globalVar.myFavoritesArray.count > 0 {
            for (index, folderPath) in globalVar.myFavoritesArray.enumerated() {
                let folderMenuItem = NSMenuItem(
                    title: folderPath.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!,
                    action: #selector(pathClick(_:)),
                    keyEquivalent: ""
                )
                folderMenuItem.target = self
                
                // 创建子菜单
                let subMenu = NSMenu(title: folderPath)
                
                // 创建删除项
                let deleteMenuItem = NSMenuItem(
                    title: NSLocalizedString("Delete", comment: "删除"),
                    action: #selector(deleteFavorite(_:)),
                    keyEquivalent: ""
                )
                deleteMenuItem.target = self
                deleteMenuItem.representedObject = folderPath
                
                // 创建上移项
                let moveUpMenuItem = NSMenuItem(
                    title: NSLocalizedString("move-up", comment: "上移"),
                    action: #selector(moveUpFavorite(_:)),
                    keyEquivalent: ""
                )
                moveUpMenuItem.target = self
                moveUpMenuItem.representedObject = index
                
                // 创建下移项
                let moveDownMenuItem = NSMenuItem(
                    title: NSLocalizedString("move-down", comment: "下移"),
                    action: #selector(moveDownFavorite(_:)),
                    keyEquivalent: ""
                )
                moveDownMenuItem.target = self
                moveDownMenuItem.representedObject = index
                
                // 将项添加到子菜单
                subMenu.addItem(deleteMenuItem)
                subMenu.addItem(moveUpMenuItem)
                subMenu.addItem(moveDownMenuItem)
                
                // 将子菜单添加到主菜单项
                folderMenuItem.submenu = subMenu
                
                // 将主菜单项添加到 favoritesMenu
                favoritesMenu.addItem(folderMenuItem)
            }
        } else {
            let emptyMenuItem = NSMenuItem(
                title: NSLocalizedString("empty-enclose", comment: "菜单当内容为空时显示的东西"),
                action: nil,
                keyEquivalent: ""
            )
            favoritesMenu.addItem(emptyMenuItem)
        }
        
        let buttonFrame = sender.convert(sender.bounds, to: nil)
        let menuLocation = NSPoint(x: 0, y: buttonFrame.height + 4)
        favoritesMenu.popUp(positioning: nil, at: menuLocation, in: sender)
    }
    
    @objc func showThumbSizeMenu(_ sender: NSButton) {
        guard let viewController = contentViewController as? ViewController else {return}

        let thumbSizeOptions = THUMB_SIZES.map { ($0, "\($0) × \($0)") }
        
        let menu = NSMenu()
        menu.autoenablesItems = false

        let isGenHdThumb = menu.addItem(withTitle: NSLocalizedString("Generate HD Thumbnails", comment: "生成高清缩略图"), action: #selector(genHdThumbAction), keyEquivalent: "")
        isGenHdThumb.state = (globalVar.isGenHdThumb) ? .on : .off
        
        let actionItemSettings = menu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(genHdThumbInfoAction), keyEquivalent: "")
        
        menu.addItem(NSMenuItem.separator())
        
        let enlargeThumb = menu.addItem(withTitle: NSLocalizedString("Enlarge the Thumbnails", comment: "放大缩略图"), action: #selector(enlargeThumb), keyEquivalent: "+")
        enlargeThumb.keyEquivalentModifierMask = []
        
        let reduceThumb = menu.addItem(withTitle: NSLocalizedString("Reduce the Thumbnails", comment: "缩小缩略图"), action: #selector(reduceThumb), keyEquivalent: "-")
        reduceThumb.keyEquivalentModifierMask = []
        
        let defaultThumbSize = menu.addItem(withTitle: NSLocalizedString("Default Thumbnail Size", comment: "默认缩略图大小"), action: #selector(defaultThumbSize), keyEquivalent: "0")
        defaultThumbSize.keyEquivalentModifierMask = []
        
//        menu.addItem(NSMenuItem.separator())
//        
//        for (thumbSize, title) in thumbSizeOptions {
//            let menuItem = NSMenuItem(title: title, action: #selector(selectThumbSize(_:)), keyEquivalent: "")
//            menuItem.target = self
//            menuItem.representedObject = thumbSize
//            let curSortType = viewController.publicVar.thumbSize
//            if viewController.publicVar.layoutType == .grid {
//                menuItem.isEnabled = false
//            }else{
//                menuItem.state = curSortType == thumbSize ? .on : .off
//            }
//            menu.addItem(menuItem)
//        }
        
        
        let buttonFrame = sender.convert(sender.bounds, to: nil)
        let menuLocation = NSPoint(x: 0, y: buttonFrame.height + 4)
        menu.popUp(positioning: nil, at: menuLocation, in: sender)
    }
    
    @objc func genHdThumbAction(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        globalVar.isGenHdThumb.toggle()
        UserDefaults.standard.set(globalVar.isGenHdThumb, forKey: "isGenHdThumb")
        viewController.refreshCollectionView([], dryRun: true)
    }
    
    @objc func genHdThumbInfoAction(_ sender: NSMenuItem){
        showInformation(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("gen-thumb-info", comment: "对于高清缩略图的说明..."))
    }
    
    @objc func enlargeThumb(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.adjustThumbSizeByDirection(direction: +1)
    }
    
    @objc func defaultThumbSize(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.adjustThumbSizeByDirection(direction: 0)
    }
    
    @objc func reduceThumb(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.adjustThumbSizeByDirection(direction: -1)
    }
    
    @objc func selectThumbSize(_ sender: NSMenuItem) {
        guard let thumbSize = sender.representedObject as? Int else { return }
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.changeThumbSize(thumbSize: thumbSize)
    }
    
    @objc func showMoreMenu(_ sender: NSButton) {
        guard let viewController = contentViewController as? ViewController else {return}
        
        let menu = NSMenu()
        menu.autoenablesItems = false

        let actionItemOntop = menu.addItem(withTitle: NSLocalizedString("pin-window", comment: "置顶"), action: #selector(ontopAction), keyEquivalent: "t")
        actionItemOntop.keyEquivalentModifierMask = []
        if let window = window {
            actionItemOntop.state = (window.level == .floating) ? .on : .off
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let actionItemSettings = menu.addItem(withTitle: NSLocalizedString("Settings...", comment: "设置..."), action: #selector(settingsAction), keyEquivalent: ",")
        actionItemSettings.keyEquivalentModifierMask = [.command]
        
        menu.addItem(NSMenuItem.separator())
        
        let actionItemShowHiddenFile = menu.addItem(withTitle: NSLocalizedString("Show Hidden Files", comment: "显示隐藏文件"), action: #selector(showHiddenFileAction), keyEquivalent: ".")
        actionItemShowHiddenFile.state = (globalVar.isShowHiddenFile) ? .on : .off
        actionItemShowHiddenFile.keyEquivalentModifierMask = [.command, .shift]
        
        let showAllTypeFile = menu.addItem(withTitle: NSLocalizedString("Show All Types of Files", comment: "显示所有类型文件"), action: #selector(showAllTypeFileAction), keyEquivalent: "")
        showAllTypeFile.state = (globalVar.isShowAllTypeFile) ? .on : .off
        
        let showImageFile = menu.addItem(withTitle: NSLocalizedString("Show Image Files", comment: "显示图像文件"), action: #selector(showImageFileAction), keyEquivalent: "")
        showImageFile.state = (globalVar.isShowImageFile) ? .on : .off
        
        let showRawFile = menu.addItem(withTitle: NSLocalizedString("Show Camera RAW Files", comment: "显示相机RAW文件"), action: #selector(showRawFileAction), keyEquivalent: "")
        showRawFile.state = (globalVar.isShowRawFile) ? .on : .off
        
        let showVideoFile = menu.addItem(withTitle: NSLocalizedString("Show Video Files", comment: "显示视频文件"), action: #selector(showVideoFileAction), keyEquivalent: "")
        showVideoFile.state = (globalVar.isShowVideoFile) ? .on : .off

        if globalVar.isShowAllTypeFile {
            showImageFile.isEnabled=false
            showRawFile.isEnabled=false
            showVideoFile.isEnabled=false
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let recursiveMode = menu.addItem(withTitle: NSLocalizedString("Recursive Mode", comment: "递归浏览模式"), action: #selector(toggleRecursiveMode), keyEquivalent: "")
        recursiveMode.state = (viewController.publicVar.isRecursiveMode) ? .on : .off
        
        let recursiveModeInfo = menu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(recursiveModeInfo), keyEquivalent: "")
        
        menu.addItem(NSMenuItem.separator())
        
        let portableMode = menu.addItem(withTitle: NSLocalizedString("Portable Browsing Mode", comment: "便携浏览模式"), action: #selector(togglePortableMode), keyEquivalent: "~")
        portableMode.keyEquivalentModifierMask = []
        portableMode.state = globalVar.portableMode ? .on : .off
        
        let portableModeInfo = menu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(portableModeInfo), keyEquivalent: "")
        
        menu.addItem(NSMenuItem.separator())
        
        let maximizeWindow = menu.addItem(withTitle: NSLocalizedString("maximizeWindow", comment: "最大化窗口"), action: #selector(maximizeWindow), keyEquivalent: "1")
        maximizeWindow.keyEquivalentModifierMask = []
        
        let optimizeWindow = menu.addItem(withTitle: NSLocalizedString("optimizeWindow", comment: "合适窗口大小"), action: #selector(optimizeWindow), keyEquivalent: "2")
        optimizeWindow.keyEquivalentModifierMask = []
        
        let adjustWindowActual = menu.addItem(withTitle: NSLocalizedString("adjustWindowActual", comment: "调整窗口至图片实际大小"), action: #selector(adjustWindowActual), keyEquivalent: "3")
        adjustWindowActual.keyEquivalentModifierMask = []
        
        let adjustWindowCurrent = menu.addItem(withTitle: NSLocalizedString("adjustWindowCurrent", comment: "调整窗口至图片当前大小"), action: #selector(adjustWindowCurrent), keyEquivalent: "4")
        adjustWindowCurrent.keyEquivalentModifierMask = []
        
//        let adjustWindowToCenter = menu.addItem(withTitle: NSLocalizedString("Center the Window", comment: "将窗口居中"), action: #selector(adjustWindowToCenter), keyEquivalent: "5")
//        adjustWindowToCenter.keyEquivalentModifierMask = []
        
        adjustWindowActual.isEnabled = (viewController.publicVar.isInLargeView)
        adjustWindowCurrent.isEnabled = (viewController.publicVar.isInLargeView)
        
        menu.addItem(NSMenuItem.separator())
        
        let switchToActualSize = menu.addItem(withTitle: NSLocalizedString("switchToActualSize", comment: "图片默认实际大小"), action: #selector(switchToActualSize), keyEquivalent: "")
        
        let switchToFitToWindow = menu.addItem(withTitle: NSLocalizedString("switchToFitToWindow", comment: "图片默认适应窗口"), action: #selector(switchToFitToWindow), keyEquivalent: "")
        
        switchToActualSize.state = (viewController.publicVar.isLargeImageFitWindow == false) ? .on : .off
        switchToFitToWindow.state = (viewController.publicVar.isLargeImageFitWindow == true) ? .on : .off

        menu.addItem(NSMenuItem.separator())
        
        let switchToSystemTheme = menu.addItem(withTitle: NSLocalizedString("switchToSystemTheme", comment: "跟随系统主题"), action: #selector(switchToSystemTheme), keyEquivalent: "")
        let switchToLightMode = menu.addItem(withTitle: NSLocalizedString("switchToLightMode", comment: "浅色模式"), action: #selector(switchToLightMode), keyEquivalent: "")
        let switchToDarkMode = menu.addItem(withTitle: NSLocalizedString("switchToDarkMode", comment: "黑暗模式"), action: #selector(switchToDarkMode), keyEquivalent: "")
        let theme=NSApp.effectiveAppearance.name
        if NSApp.appearance == nil {
            switchToSystemTheme.state = .on
            switchToLightMode.state = .off
            switchToDarkMode.state = .off
        }else{
            switchToSystemTheme.state = .off
            switchToLightMode.state = (theme == .darkAqua) ? .off : .on
            switchToDarkMode.state = (theme == .darkAqua) ? .on : .off
        }
        
        let buttonFrame = sender.convert(sender.bounds, to: nil)
        let menuLocation = NSPoint(x: 0, y: buttonFrame.height + 4)
        menu.popUp(positioning: nil, at: menuLocation, in: sender)
    }
    
    @objc func maximizeWindow(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.adjustWindowMaximize()
    }
    
    @objc func optimizeWindow(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.adjustWindowSuitable()
    }
    
    @objc func adjustWindowActual(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.adjustWindowImageActual()
    }
    
    @objc func adjustWindowCurrent(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.adjustWindowImageCurrent()
    }
    
    @objc func adjustWindowToCenter(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.adjustWindowToCenter()
    }
    
    @objc func switchToActualSize(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.switchToActualSize()
    }
    
    @objc func switchToFitToWindow(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.switchToFitToWindow()
    }
    
    @objc func switchToSystemTheme(_ sender: NSMenuItem){
        let defaults = UserDefaults.standard
        defaults.set("", forKey: "appearance")
        NSApp.appearance=nil
    }
    
    @objc func switchToLightMode(_ sender: NSMenuItem){
        let defaults = UserDefaults.standard
        defaults.set("aqua", forKey: "appearance")
        NSApp.appearance=NSAppearance(named: .aqua)
    }
    
    @objc func switchToDarkMode(_ sender: NSMenuItem){
        let defaults = UserDefaults.standard
        defaults.set("darkAqua", forKey: "appearance")
        NSApp.appearance=NSAppearance(named: .darkAqua)
    }
    
    @objc func pathClick(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        log("Clicked on \(sender.title)")

        guard let url=URL(string: sender.title) else {return}
        if viewController.publicVar.isInLargeView {
            viewController.closeLargeImage(0)
        }
        viewController.switchDirByDirection(direction: .zero, dest: "file://"+url.absoluteString, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
    }
    
    @objc func favoritesAdd(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.fileDB.lock()
        let curFolder=viewController.fileDB.curFolder
        viewController.fileDB.unlock()
        if !globalVar.myFavoritesArray.contains(curFolder) {
            globalVar.myFavoritesArray.append(curFolder)
            let defaults = UserDefaults.standard
            defaults.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
        }
    }
    @objc func deleteFavorite(_ sender: NSMenuItem) {
        guard let folderPath = sender.representedObject as? String else { return }
        
        // 在这里处理删除逻辑
        if let index = globalVar.myFavoritesArray.firstIndex(of: folderPath) {
            globalVar.myFavoritesArray.remove(at: index)
            let defaults = UserDefaults.standard
            defaults.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
        }
        
        // 更新菜单以反映更改
        //menuNeedsUpdate(favoritesMenu)
    }
    @objc func moveUpFavorite(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, index > 0 else { return }
        
        // 在这里处理上移逻辑
        globalVar.myFavoritesArray.swapAt(index, index - 1)
        let defaults = UserDefaults.standard
        defaults.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
        
        // 更新菜单以反映更改
        //menuNeedsUpdate(favoritesMenu)
    }

    @objc func moveDownFavorite(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, index < globalVar.myFavoritesArray.count - 1 else { return }
        
        // 在这里处理下移逻辑
        globalVar.myFavoritesArray.swapAt(index, index + 1)
        let defaults = UserDefaults.standard
        defaults.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
        
        // 更新菜单以反映更改
        //menuNeedsUpdate(favoritesMenu)
    }
    
    @objc func settingsAction(_ sender: NSMenuItem) {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.settingsWindowController.show()
        }
    }
    
    @objc func showHiddenFileAction(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleIsShowHiddenFile()
    }
    
    @objc func showAllTypeFileAction(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleIsShowAllTypeFile()
    }
    
    @objc func showImageFileAction(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleIsShowImageFile()
    }
    
    @objc func showRawFileAction(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleIsShowRawFile()
    }
    
    @objc func showVideoFileAction(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleIsShowVideoFile()
    }
    
    @objc func togglePortableMode(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.togglePortableMode()
    }
    
    @objc func portableModeInfo(_ sender: NSMenuItem){
        showInformation(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("portable-mode-info", comment: "对于便携模式的说明..."))
    }
    
    @objc func toggleRecursiveMode(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleRecursiveMode()
    }
    
    @objc func recursiveModeInfo(_ sender: NSMenuItem){
        showInformation(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("recursive-mode-info", comment: "对于递归模式的说明..."))
    }
}

