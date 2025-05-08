//
//  WindowController.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/16.
//

import Cocoa

class WindowController: NSWindowController, NSWindowDelegate {
    
    var pathShortenStore = ""
    var windowFrameBeforeFullScreen: NSRect?

    override func windowDidLoad() {
        super.windowDidLoad()
        
        log("开始windowDidLoad")
        
        self.window?.delegate = self
        
        window?.title = "FlowVision"

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
            //toolbar.showsBaselineSeparator = true
            window.toolbar = toolbar

            window.acceptsMouseMovedEvents = true
            if globalVar.autoHideToolbar {
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
                log("Set window frame to:",frame)
                if let viewController = contentViewController as? ViewController {
                    viewController.changeWaterfallLayoutNumberOfColumns()
                }
            }
        }
        
        //设置焦点
        if let viewController = contentViewController as? ViewController {
            window?.makeFirstResponder(viewController.collectionView)
        }
        
        log("结束windowDidLoad")
    }
    
    func prepareForDeinit() {
        saveWindowState()
    }
    
    func saveWindowState() {
        guard let window = self.window else { return }
        if let viewController = contentViewController as? ViewController {
            if viewController.publicVar.isInLargeView || window.styleMask.contains(.fullScreen) {
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
        
        // 在窗口关闭时执行清理，例如，保存数据、释放资源等
        if let viewController = contentViewController as? ViewController {
            viewController.largeImageView.prepareForDeinit()
            viewController.prepareForDeinit()
        }
        self.prepareForDeinit()
        
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
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleOnTop()
    }

    // 在窗口将要进入全屏模式时执行
    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let window = self.window else { return }
        // 保存当前窗口大小
        windowFrameBeforeFullScreen = window.frame
    }
    
    // 在窗口已经进入全屏模式时执行
    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let viewController = contentViewController as? ViewController else {return}

        if !globalVar.autoHideToolbar {
            window?.titlebarAppearsTransparent = true
            window?.toolbar?.isVisible = false
        }

        if viewController.publicVar.isInLargeView {
            if viewController.largeImageView.file.type == .image {
                viewController.changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
            } else {
                viewController.largeImageView.determineBlackBg()
            }
        }
    }
    
    // 在窗口已经退出全屏模式时执行
    func windowDidExitFullScreen(_ notification: Notification) {
        guard let viewController = contentViewController as? ViewController else {return}

        if !globalVar.autoHideToolbar {
            if window?.toolbar?.isVisible == false {
                window?.titlebarAppearsTransparent = false
                window?.toolbar?.isVisible = true
                if let frame = windowFrameBeforeFullScreen {
                    window?.setFrame(frame, display: true)
                }
            }
        }
        
        if viewController.publicVar.isInLargeView {
            if viewController.largeImageView.file.type == .image {
                viewController.changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
            } else {
                viewController.largeImageView.determineBlackBg()
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
//        if globalVar.autoHideToolbar {
//            showTitleBar()
//        }
    }
    
    override func mouseExited(with event: NSEvent) {
//        if globalVar.autoHideToolbar {
//            hideTitleBar()
//        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard let window = window else { return }
        guard let toolbar = window.toolbar else { return }
        guard let viewController = contentViewController as? ViewController else {return}
        let location = event.locationInWindow
        if globalVar.autoHideToolbar {
            if location.y > window.frame.height - 40 {
                showTitleBar()
            } else if !window.styleMask.contains(.fullScreen) || (location.y < window.frame.height - 60) {
                hideTitleBar()
            }
        }else{
            if location.y > window.frame.height - 20 {
                if toolbar.isVisible == false {
                    window.titlebarAppearsTransparent = false
                    toolbar.isVisible = true
                    viewController.largeImageView.determineBlackBg()
                }
            } else if window.styleMask.contains(.fullScreen) && (location.y < window.frame.height - 20) {
                if toolbar.isVisible == true {
                    window.titlebarAppearsTransparent = true
                    toolbar.isVisible = false
                    viewController.largeImageView.determineBlackBg()
                }
            }
        }
    }
    
    // 显示标题栏和工具栏
    func showTitleBar() {
        guard let window = window else { return }
        guard let toolbar = window.toolbar else { return }
        if toolbar.isVisible == true { return }
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.titlebarAppearsTransparent = false
        toolbar.isVisible = true
    }
    
    // 隐藏标题栏和工具栏
    func hideTitleBar() {
        guard let window = window else { return }
        guard let toolbar = window.toolbar else { return }
        if toolbar.isVisible == false { return }
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.titlebarAppearsTransparent = true
        toolbar.isVisible = false
    }
}

extension NSToolbarItem.Identifier {
    static let sidebar = NSToolbarItem.Identifier("com.example.sidebar")
    static let goBack = NSToolbarItem.Identifier("com.example.goBack")
    static let goForward = NSToolbarItem.Identifier("com.example.goForward")
    static let upFolder = NSToolbarItem.Identifier("com.example.upFolder")
    static let viewToggle = NSToolbarItem.Identifier("com.example.viewToggle")
    static let newtab = NSToolbarItem.Identifier("com.example.newtab")
    static let showinfo = NSToolbarItem.Identifier("com.example.showinfo")
    static let ontop = NSToolbarItem.Identifier("com.example.ontop")
    static let windowTitle = NSToolbarItem.Identifier("com.example.windowTitle")
    static let windowTitleStatistics = NSToolbarItem.Identifier("com.example.windowTitleStatistics")
    static let pathControl = NSToolbarItem.Identifier("com.example.pathControl")
    static let rotateL = NSToolbarItem.Identifier("com.example.rotateL")
    static let rotateR = NSToolbarItem.Identifier("com.example.rotateR")
    static let zoomIn = NSToolbarItem.Identifier("com.example.zoomIn")
    static let zoomOut = NSToolbarItem.Identifier("com.example.zoomOut")
    static let sort = NSToolbarItem.Identifier("com.example.sort")
    static let more = NSToolbarItem.Identifier("com.example.more")
    static let favorites = NSToolbarItem.Identifier("com.example.favorites")
    static let thumbSize = NSToolbarItem.Identifier("com.example.thumbSize")
    static let isRecursiveMode = NSToolbarItem.Identifier("com.example.isRecursiveMode")
    static let isSearchFilterOn = NSToolbarItem.Identifier("com.example.isSearchFilterOn")
    static let isAutoPlayVisibleVideo = NSToolbarItem.Identifier("com.example.isAutoPlayVisibleVideo")
    static let isEnableHDR = NSToolbarItem.Identifier("com.example.isEnableHDR")
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
        var identifiers: [NSToolbarItem.Identifier] = [.sidebar, .favorites, .goBack, .goForward]
        
        //identifiers.append(.upFolder)
        
        if let viewController = contentViewController as? ViewController {
            if viewController.publicVar.isInLargeView {
                identifiers.append(.windowTitle)
                if #available(macOS 14.0, *) {
                    if viewController.largeImageView.file.imageInfo?.isHDR ?? false {
                        identifiers.append(.isEnableHDR)
                    }
                }
                if viewController.largeImageView.file.type == .image {
                    identifiers.append(.zoomOut)
                    identifiers.append(.zoomIn)
                }
                //identifiers.append(.rotateL)
                identifiers.append(.rotateR)
                identifiers.append(.showinfo)
            }else{
                if viewController.publicVar.profile.getValue(forKey: "isWindowTitleUseFullPath") == "true" {
                    identifiers.append(.pathControl)
                    if viewController.publicVar.profile.getValue(forKey: "isWindowTitleShowStatistics") == "true" {
                        identifiers.append(.windowTitleStatistics)
                    }
                    identifiers.append(.flexibleSpace)
                }else{
                    identifiers.append(.windowTitle)
                }
                
                if viewController.publicVar.autoPlayVisibleVideo {
                    identifiers.append(.isAutoPlayVisibleVideo)
                }
                if viewController.publicVar.isCurrentFolderFiltered {
                    identifiers.append(.isSearchFilterOn)
                }
                if viewController.publicVar.isRecursiveMode {
                    identifiers.append(.isRecursiveMode)
                }
                identifiers.append(.viewToggle)
                identifiers.append(.thumbSize)
                identifiers.append(.sort)
            }
        }
        
        identifiers.append(NSToolbarItem.Identifier("CustomSeparator"))
        
        
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
        
        //let titleFontColor = NSApp.effectiveAppearance.name == .darkAqua ? hexToNSColor(hex: "#FFFFFF", alpha: 0.847) : hexToNSColor(hex: "#000000", alpha: 0.847)
        //let titleFontColor = NSApp.effectiveAppearance.name == .darkAqua ? hexToNSColor(hex: "#FFFFFF", alpha: 0.64) : hexToNSColor(hex: "#000000", alpha: 0.6)
        let titleFontColor = NSColor.labelColor
        //let titleFontColor = NSColor.controlTextColor
        
        switch itemIdentifier {
            
        case .windowTitle:
            let text = (contentViewController as? ViewController)?.publicVar.toolbarTitle
            let titleLabel = createWindowTitleLabel(string: text ?? "FlowVision")
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            titleLabel.textColor = titleFontColor
            titleLabel.alignment = .center
            toolbarItem.view = titleLabel
            toolbarItem.minSize = NSSize(width: 200, height: titleLabel.fittingSize.height)
            toolbarItem.maxSize = NSSize(width: 10000, height: titleLabel.fittingSize.height)
            //toolbarItem.minSize = titleLabel.fittingSize
            //toolbarItem.maxSize = titleLabel.fittingSize
            toolbarItem.label = NSLocalizedString("Window Title", comment: "窗口标题")
            toolbarItem.paletteLabel = NSLocalizedString("Window Title", comment: "窗口标题")
            toolbarItem.visibilityPriority = .high
            
        case .windowTitleStatistics:
            let text = (contentViewController as? ViewController)?.publicVar.titleStatisticInfo
            let titleLabel = createWindowTitleLabel(string: text ?? "")
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            titleLabel.textColor = NSColor.placeholderTextColor
            titleLabel.alignment = .left
            toolbarItem.view = titleLabel
//            toolbarItem.minSize = NSSize(width: 200, height: titleLabel.fittingSize.height)
//            toolbarItem.maxSize = NSSize(width: 10000, height: titleLabel.fittingSize.height)
            //toolbarItem.minSize = titleLabel.fittingSize
            //toolbarItem.maxSize = titleLabel.fittingSize
            toolbarItem.label = NSLocalizedString("Window Title", comment: "窗口标题")
            toolbarItem.paletteLabel = NSLocalizedString("Window Title", comment: "窗口标题")
            toolbarItem.visibilityPriority = .high
            
        case .pathControl:
            let pathControl = CustomPathControl()
            pathControl.pathStyle = .standard
            pathControl.isEditable = false
            pathControl.backgroundColor = .clear
            pathControl.focusRingType = .none
            pathControl.target = self
            pathControl.action = #selector(pathControlClicked(_:))
            let font = NSFont.systemFont(ofSize: 13, weight: .regular)
            
            if let viewController = contentViewController as? ViewController {
                let curFolder = viewController.fileDB.curFolder
                var pathString = curFolder.replacingOccurrences(of: "file:///", with: "")
                if pathString.hasPrefix("/") {
                    pathString.removeFirst()
                }
                if pathString.hasSuffix("/") {
                    pathString.removeLast()
                }
                let components = pathString.components(separatedBy: "/")
                var pathItems: [CustomPathControlItem] = []
                
                for (i,component) in components.enumerated() {
                    if component == "" {continue}
                    let item = CustomPathControlItem()
                    item.title = component.removingPercentEncoding!

                    let componentPath = components[0..<i + 1].joined(separator: "/")
                    let encodedPath = "file:///\(componentPath)/"
                    item.myUrl = URL(string: encodedPath)

                    pathItems.append(item)
                }
                
                let rootItem = CustomPathControlItem()
                rootItem.title = ROOT_NAME
                rootItem.myUrl = URL(string: "file:///")
                pathItems.insert(rootItem, at: 0)
                
                var maxWidth = (window?.frame.width ?? 1000) - 600 // 指定总宽度
                if viewController.publicVar.autoPlayVisibleVideo {
                    maxWidth -= 45
                }
                if viewController.publicVar.isCurrentFolderFiltered {
                    maxWidth -= 45
                }
                if viewController.publicVar.isRecursiveMode {
                    maxWidth -= 45
                }
                if viewController.publicVar.profile.getValue(forKey: "isWindowTitleShowStatistics") == "true" {
                    maxWidth -= viewController.publicVar.titleStatisticInfo.size(withAttributes: [.font: font]).width + 20
                }
                var totalWidth: CGFloat = 0
                var startIndex = pathItems.count - 1
                
                // 从后往前计算每个路径项的实际宽度
                for i in (0..<pathItems.count).reversed() {
                    let itemWidth = pathItems[i].title.size(withAttributes: [.font: font]).width + 15 // 15为分隔符宽度
                    totalWidth += itemWidth
                    if totalWidth > maxWidth {
                        startIndex = i + 1
                        break
                    }
                }

                // 最后一个时已经超过
                if startIndex == pathItems.count {
                    startIndex = pathItems.count - 1
                }
                
                // 如果超过最大字符数,替换前面的为...
                if totalWidth > maxWidth && startIndex != 0 {
                    let item = CustomPathControlItem()
                    item.title = "..."
                    item.myUrl = pathItems[startIndex].myUrl?.deletingLastPathComponent()
                    pathItems = [item] + pathItems[startIndex...]
                }
                
                pathItems.last?.myUrl = nil

                pathControl.pathItems = pathItems
            }
            
            for item in pathControl.pathItems {
                let range = NSMakeRange(0, item.attributedTitle.length)
                let attributedTitle = NSMutableAttributedString(attributedString: item.attributedTitle)
                attributedTitle.addAttribute(.foregroundColor, value: titleFontColor, range: range)
                attributedTitle.addAttribute(.font, value: font, range: range)
                item.attributedTitle = attributedTitle
            }
            
            toolbarItem.view = pathControl
            toolbarItem.label = NSLocalizedString("Window Title", comment: "窗口标题")
            toolbarItem.paletteLabel = NSLocalizedString("Window Title", comment: "窗口标题") 
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
            button.toolTip = NSLocalizedString("Go Back", comment: "后退")
            button.isEnabled = (viewController.publicVar.folderStepStack.count > 0) && (!viewController.publicVar.isInLargeView)
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Go Back", comment: "后退")
            toolbarItem.paletteLabel = NSLocalizedString("Go Back", comment: "后退")
            toolbarItem.isNavigational = true
            toolbarItem.visibilityPriority = .low
            
        case .goForward:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: "")!, target: self, action: #selector(goForwardAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Go Forward", comment: "前进")
            button.isEnabled = (viewController.publicVar.folderStepForwardStack.count > 0) && (!viewController.publicVar.isInLargeView)
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Go Forward", comment: "前进")
            toolbarItem.paletteLabel = NSLocalizedString("Go Forward", comment: "前进")
            toolbarItem.isNavigational = true
            toolbarItem.visibilityPriority = .low
            
        case .upFolder:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "")!, target: self, action: #selector(upFolderAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("up-folder", comment: "上层文件夹")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("up-folder", comment: "上层文件夹")
            toolbarItem.paletteLabel = NSLocalizedString("up-folder", comment: "上层文件夹")
            toolbarItem.visibilityPriority = .low
            
        case .viewToggle:
            let segmentedControl = NSSegmentedControl(images: [
                //NSImage(systemSymbolName: "rectangle.grid.1x2", accessibilityDescription: "Justified")!,
                NSImage(systemSymbolName: "squares.below.rectangle", accessibilityDescription: "Justified")!,
                NSImage(systemSymbolName: "rectangle.3.offgrid", accessibilityDescription: "Waterfall")!,
                NSImage(systemSymbolName: "rectangle.grid.2x2", accessibilityDescription: "Grid")!
            ], trackingMode: .selectOne, target: self, action: #selector(viewToggleAction(_:)))
            segmentedControl.selectedSegment = viewController.publicVar.profile.layoutType.rawValue
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
            button.toolTip = NSLocalizedString("Pin Window", comment: "置顶")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Pin Window", comment: "置顶")
            toolbarItem.paletteLabel = NSLocalizedString("Pin Window", comment: "置顶")
            toolbarItem.visibilityPriority = .standard

        case .isEnableHDR:
            let button: NSButton
            if viewController.publicVar.isEnableHDR {
                button = NSButton(title: "HDR", target: self, action: #selector(toggleEnableHDR(_:)))
                button.contentTintColor = .controlAccentColor
            } else {
                button = NSButton(title: "SDR", target: self, action: #selector(toggleEnableHDR(_:)))
                button.contentTintColor = .secondaryLabelColor
            }
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Enable HDR", comment: "启用HDR")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Enable HDR", comment: "启用HDR")
            toolbarItem.paletteLabel = NSLocalizedString("Enable HDR", comment: "启用HDR")
            toolbarItem.visibilityPriority = .low
        
        case .showinfo:
            var image: NSImage
            if viewController.publicVar.isShowExif {
                image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "")!
            }else{
                image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "")!
            }
            let button = NSButton(title: "", image: image, target: self, action: #selector(showinfoAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Show Info", comment: "显示信息")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Show Info", comment: "显示信息")
            toolbarItem.paletteLabel = NSLocalizedString("Show Info", comment: "显示信息")
            toolbarItem.visibilityPriority = .standard
            
        case .rotateL:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "")!, target: self, action: #selector(rotateLAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Rotate Counterclockwise", comment: "逆时针旋转")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Rotate Counterclockwise", comment: "逆时针旋转")
            toolbarItem.paletteLabel = NSLocalizedString("Rotate Counterclockwise", comment: "逆时针旋转")
            toolbarItem.visibilityPriority = .low
            
        case .rotateR:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "")!, target: self, action: #selector(rotateRAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Rotate Clockwise", comment: "顺时针旋转")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Rotate Clockwise", comment: "顺时针旋转")
            toolbarItem.paletteLabel = NSLocalizedString("Rotate Clockwise", comment: "顺时针旋转")
            toolbarItem.visibilityPriority = .low
            
        case .zoomIn:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "plus", accessibilityDescription: "")!, target: self, action: #selector(zoomInAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Zoom In", comment: "放大")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Zoom In", comment: "放大")
            toolbarItem.paletteLabel = NSLocalizedString("Zoom In", comment: "放大")
            toolbarItem.visibilityPriority = .low
            
        case .zoomOut:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "minus", accessibilityDescription: "")!, target: self, action: #selector(zoomOutAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Zoom Out", comment: "缩小")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Zoom Out", comment: "缩小")
            toolbarItem.paletteLabel = NSLocalizedString("Zoom Out", comment: "缩小")
            toolbarItem.visibilityPriority = .low
            
        case .sort:
            var title = ""
            var image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "")!
            if let viewController = contentViewController as? ViewController {
                switch viewController.publicVar.profile.sortType {
                case .pathA,.pathZ:
                    title = NSLocalizedString("sort-label-name", comment: "名称")
                case .extA,.extZ:
                    title = NSLocalizedString("sort-label-ext", comment: "类型")
                case .sizeA,.sizeZ:
                    title = NSLocalizedString("sort-label-size", comment: "大小")
                case .createDateA,.createDateZ,.modDateA,.modDateZ,.addDateA,.addDateZ:
                    title = NSLocalizedString("sort-label-date", comment: "日期")
                case .random:
                    title = NSLocalizedString("sort-label-random", comment: "随机")
                case .exifDateA,.exifDateZ:
                    title = NSLocalizedString("sort-label-exifDate", comment: "Exif日期")
                case .exifPixelA,.exifPixelZ:
                    title = NSLocalizedString("sort-label-exifPixel", comment: "Exif像素")
                }
                switch viewController.publicVar.profile.sortType {
                case .pathA,.extA,.sizeA,.createDateA,.modDateA,.addDateA,.exifDateA,.exifPixelA:
                    //image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "")!
                    //image = NSImage(systemSymbolName: "arrowtriangle.up", accessibilityDescription: "")!
                    image = NSImage(systemSymbolName: "chevron.up.circle", accessibilityDescription: "")!
                case .pathZ,.extZ,.sizeZ,.createDateZ,.modDateZ,.addDateZ,.exifDateZ,.exifPixelZ:
                    image = NSImage(systemSymbolName: "chevron.down.circle", accessibilityDescription: "")!
                case .random:
                    //image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "")!
                    image = NSImage(systemSymbolName: "arrow.2.circlepath", accessibilityDescription: "")!
                }
            }
            
            let button = NSButton(title: title, image: image, target: self, action: #selector(showSortMenu(_:)))
            setButtonStyle(button)
            
            // 自定义title的字体大小和颜色
            let font = NSFont.systemFont(ofSize: 13)
            let attributedTitle = NSAttributedString(string: title, attributes: [
                .font: font,
                //.foregroundColor: titleFontColor
            ])
            button.attributedTitle = attributedTitle
            button.toolTip = NSLocalizedString("Sort Order", comment: "排序方式")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Sort Order", comment: "排序方式")
            toolbarItem.paletteLabel = NSLocalizedString("Sort Order", comment: "排序方式")
            toolbarItem.visibilityPriority = .low
            
        case .thumbSize:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "photo", accessibilityDescription: "")!, target: self, action: #selector(showThumbSizeMenu(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Thumbnail Size", comment: "缩略图大小")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Thumbnail Size", comment: "缩略图大小")
            toolbarItem.paletteLabel = NSLocalizedString("Thumbnail Size", comment: "缩略图大小")
            toolbarItem.visibilityPriority = .low
            
        case .isAutoPlayVisibleVideo:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "v.circle.fill", accessibilityDescription: "")!, target: self, action: #selector(toggleAutoPlayVisibleVideo(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("Cancel Auto Play Visible Video", comment: "取消自动播放可见视频")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Cancel Auto Play Visible Video", comment: "取消自动播放可见视频")
            toolbarItem.paletteLabel = NSLocalizedString("Cancel Auto Play Visible Video", comment: "取消自动播放可见视频")
            toolbarItem.visibilityPriority = .low
            
        case .isSearchFilterOn:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "f.circle.fill", accessibilityDescription: "")!, target: self, action: #selector(toggleSearchFilter(_:)))
            setButtonStyle(button)
            //button.showsBorderOnlyWhileMouseInside = false
            button.toolTip = NSLocalizedString("Cancel Filter", comment: "取消过滤")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Cancel Filter", comment: "取消过滤")
            toolbarItem.paletteLabel = NSLocalizedString("Cancel Filter", comment: "取消过滤")
            toolbarItem.visibilityPriority = .low
            
        case .isRecursiveMode:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "r.circle.fill", accessibilityDescription: "")!, target: self, action: #selector(toggleRecursiveMode(_:)))
            setButtonStyle(button)
            //button.showsBorderOnlyWhileMouseInside = false
            button.toolTip = NSLocalizedString("Exit Recursive Mode", comment: "退出递归浏览模式")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("Exit Recursive Mode", comment: "退出递归浏览模式")
            toolbarItem.paletteLabel = NSLocalizedString("Exit Recursive Mode", comment: "退出递归浏览模式")
            toolbarItem.visibilityPriority = .low
            
        case .more:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "")!, target: self, action: #selector(showMoreMenu(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("More", comment: "更多")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("More", comment: "更多")
            toolbarItem.paletteLabel = NSLocalizedString("More", comment: "更多")
            toolbarItem.visibilityPriority = .high
            
        case .newtab:
            let button = NSButton(title: "", image: NSImage(systemSymbolName: "rectangle.badge.plus", accessibilityDescription: "")!, target: self, action: #selector(newtabAction(_:)))
            setButtonStyle(button)
            button.toolTip = NSLocalizedString("New Tab", comment: "新标签页")
            toolbarItem.view = button
            toolbarItem.label = NSLocalizedString("New Tab", comment: "新标签页")
            toolbarItem.paletteLabel = NSLocalizedString("New Tab", comment: "新标签页")
            toolbarItem.visibilityPriority = .high
            
        case NSToolbarItem.Identifier("CustomSeparator"):
            let margin: CGFloat = 4
            let lineWidth: CGFloat = 1
            let height: CGFloat = 16
            let containerWidth = margin * 2 + lineWidth
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: height))
            let line = NSBox()
            line.boxType = .separator
            line.frame = NSRect(x: margin, y: 0, width: lineWidth, height: height)
            line.fillColor = NSColor.separatorColor
            containerView.addSubview(line)
            toolbarItem.view = containerView
            toolbarItem.visibilityPriority = .low
            
        default:
            return nil
        }
        return toolbarItem
    }
    
    @objc func pathControlClicked(_ sender: NSPathControl) {
        guard let viewController = contentViewController as? ViewController else {return}
        if let clickedItem = sender.clickedPathItem as? CustomPathControlItem {
            if let itemURL = clickedItem.myUrl {
                if viewController.publicVar.isInLargeView {
                    viewController.closeLargeImage(0)
                }
                viewController.switchDirByDirection(direction: .zero, dest: itemURL.absoluteString, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
            }
        }
    }
    
    class NonClickableTextField: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil  // 忽略所有鼠标事件
        }
    }
    
    private func createWindowTitleLabel(string: String) -> NSTextField {
        let titleLabel = NonClickableTextField(labelWithString: string)
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
//        button.bezelStyle = .toolbar
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

    @objc func upFolderAction(_ sender: Any?) {
        if let viewController = contentViewController as? ViewController {
            viewController.switchDirByDirection(direction: .up, stackDeep: 0)
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
            viewController.largeImageView.actShowExif()
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
    
    @objc func showSortMenu(_ sender: Any?) {
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
        
        let exifSortTypes: [(SortType, String)] = [
            (.exifDateA, NSLocalizedString("sort-exifDateA", comment: "Exif日期")),
            (.exifDateZ, NSLocalizedString("sort-exifDateZ", comment: "Exif日期(倒序)")),
            (.exifPixelA, NSLocalizedString("sort-exifPixelA", comment: "Exif像素数")),
            (.exifPixelZ, NSLocalizedString("sort-exifPixelZ", comment: "Exif像素数(倒序)"))
        ]
        
        let menu = NSMenu()
        
        let folderFirstItem = NSMenuItem(title: NSLocalizedString("Sort Folders First", comment: "文件夹优先排序"), action: #selector(sortFolderFirst(_:)), keyEquivalent: "")
        folderFirstItem.state = viewController.publicVar.profile.isSortFolderFirst ? .on : .off
        menu.addItem(folderFirstItem)

        let sortUseFullPathItem = NSMenuItem(title: NSLocalizedString("Sort Using Full Path In Recursive Mode", comment: "递归模式下使用完整路径排序"), action: #selector(sortUseFullPath(_:)), keyEquivalent: "")
        sortUseFullPathItem.state = viewController.publicVar.profile.isSortUseFullPath ? .on : .off
        menu.addItem(sortUseFullPathItem)

        let sortReadme = menu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(sortReadmeAction), keyEquivalent: "")
        
        menu.addItem(NSMenuItem.separator())
        
        for (sortType, title) in sortTypes {
            let menuItem = NSMenuItem(title: title, action: #selector(sortItems(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = sortType
            let curSortType = viewController.publicVar.profile.sortType
            menuItem.state = curSortType == sortType ? .on : .off
            menu.addItem(menuItem)
        }
        
        // 添加 EXIF 排序子菜单
        let exifSubmenu = NSMenu()
        let exifMenuItem = NSMenuItem(title: NSLocalizedString("Sort by EXIF Info", comment: "根据Exif信息排序"), action: nil, keyEquivalent: "")
        exifMenuItem.submenu = exifSubmenu
        
        for (sortType, title) in exifSortTypes {
            let menuItem = NSMenuItem(title: title, action: #selector(sortItems(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = sortType
            let curSortType = viewController.publicVar.profile.sortType
            menuItem.state = curSortType == sortType ? .on : .off
            exifSubmenu.addItem(menuItem)
        }
        
        menu.addItem(exifMenuItem)
        
        if let button = sender as? NSButton {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let menuLocation = NSPoint(x: 0, y: buttonFrame.height + 4)
            menu.popUp(positioning: nil, at: menuLocation, in: button)
        } else {
            let menuLocation = NSEvent.mouseLocation
            menu.popUp(positioning: nil, at: menuLocation, in: nil)
        }
    }

    @objc func sortReadmeAction(_ sender: NSMenuItem) {
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("sort-readme", comment: "排序说明..."))
    }
    
    @objc func sortFolderFirst(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.publicVar.profile.isSortFolderFirst.toggle()
        viewController.changeSortType(sortType: viewController.publicVar.profile.sortType, isSortFolderFirst: viewController.publicVar.profile.isSortFolderFirst, isSortUseFullPath: viewController.publicVar.profile.isSortUseFullPath)
    }
    
    @objc func sortUseFullPath(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.publicVar.profile.isSortUseFullPath.toggle()
        viewController.changeSortType(sortType: viewController.publicVar.profile.sortType, isSortFolderFirst: viewController.publicVar.profile.isSortFolderFirst, isSortUseFullPath: viewController.publicVar.profile.isSortUseFullPath)
    }
    
    @objc func sortItems(_ sender: NSMenuItem) {
        guard let sortType = sender.representedObject as? SortType else { return }
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.changeSortType(sortType: sortType, isSortFolderFirst: viewController.publicVar.profile.isSortFolderFirst, isSortUseFullPath: viewController.publicVar.profile.isSortUseFullPath)
    }
    
    @objc func favoritesAction(_ sender: Any?) {
        guard let viewController = contentViewController as? ViewController else {return}
        
        let favoritesMenu = NSMenu()
        
        let addFolderMenuItem = NSMenuItem(
            title: NSLocalizedString("Add Current Folder", comment: "添加当前文件夹"),
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
                    title: NSLocalizedString("Move Up", comment: "上移"),
                    action: #selector(moveUpFavorite(_:)),
                    keyEquivalent: ""
                )
                moveUpMenuItem.target = self
                moveUpMenuItem.representedObject = index
                
                // 创建下移项
                let moveDownMenuItem = NSMenuItem(
                    title: NSLocalizedString("Move Down", comment: "下移"),
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
        
        if let button = sender as? NSButton {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let menuLocation = NSPoint(x: 0, y: buttonFrame.height + 4)
            favoritesMenu.popUp(positioning: nil, at: menuLocation, in: button)
        } else {
            let menuLocation = NSEvent.mouseLocation
            favoritesMenu.popUp(positioning: nil, at: menuLocation, in: nil)
        }
    }
    
    @objc func showThumbSizeMenu(_ sender: Any?) {
        guard let viewController = contentViewController as? ViewController else {return}

        let thumbSizeOptions = THUMB_SIZES.map { ($0, "\($0) × \($0)") }
        
        let menu = NSMenu()
        menu.autoenablesItems = false

        let isPreferInternalThumb = menu.addItem(withTitle: NSLocalizedString("Prefer Using Embedded Thumbnails", comment: "优先使用内嵌缩略图"), action: #selector(preferInternalThumbAction), keyEquivalent: "")
        isPreferInternalThumb.state = (viewController.publicVar.isPreferInternalThumb) ? .on : .off

        let isNormalThumb = menu.addItem(withTitle: NSLocalizedString("Always Generate Standard Thumbnails", comment: "总是生成标准缩略图"), action: #selector(normalThumbAction), keyEquivalent: "")
        isNormalThumb.state = (!viewController.publicVar.isPreferInternalThumb && !viewController.publicVar.isGenHdThumb) ? .on : .off

        let isGenHdThumb = menu.addItem(withTitle: NSLocalizedString("Always Generate HD Thumbnails", comment: "总是生成高清缩略图"), action: #selector(genHdThumbAction), keyEquivalent: "")
        isGenHdThumb.state = (viewController.publicVar.isGenHdThumb) ? .on : .off
        
        let thumbReadme = menu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(thumbReadmeAction), keyEquivalent: "")
        
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
        
        
        if let button = sender as? NSButton {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let menuLocation = NSPoint(x: 0, y: buttonFrame.height + 4)
            menu.popUp(positioning: nil, at: menuLocation, in: button)
        } else {
            let menuLocation = NSEvent.mouseLocation
            menu.popUp(positioning: nil, at: menuLocation, in: nil)
        }
    }

    @objc func preferInternalThumbAction(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.publicVar.isPreferInternalThumb = true
        viewController.publicVar.isGenHdThumb = false
        UserDefaults.standard.set(viewController.publicVar.isPreferInternalThumb, forKey: "isPreferInternalThumb")
        UserDefaults.standard.set(viewController.publicVar.isGenHdThumb, forKey: "isGenHdThumb")
        ThumbImageProcessor.clearCache()
        viewController.refreshCollectionView([.all], dryRun: true, needLoadThumbPriority: false)
    }

    @objc func normalThumbAction(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.publicVar.isPreferInternalThumb = false
        viewController.publicVar.isGenHdThumb = false
        UserDefaults.standard.set(viewController.publicVar.isPreferInternalThumb, forKey: "isPreferInternalThumb")
        UserDefaults.standard.set(viewController.publicVar.isGenHdThumb, forKey: "isGenHdThumb")
        ThumbImageProcessor.clearCache()
        viewController.refreshCollectionView([.all], dryRun: true, needLoadThumbPriority: false)
    }
    
    @objc func genHdThumbAction(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.publicVar.isGenHdThumb = true
        viewController.publicVar.isPreferInternalThumb = false
        UserDefaults.standard.set(viewController.publicVar.isGenHdThumb, forKey: "isGenHdThumb")
        UserDefaults.standard.set(viewController.publicVar.isPreferInternalThumb, forKey: "isPreferInternalThumb")
        ThumbImageProcessor.clearCache()
        viewController.refreshCollectionView([.all], dryRun: true, needLoadThumbPriority: false)
    }
    
    @objc func thumbReadmeAction(_ sender: NSMenuItem){
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("gen-thumb-info", comment: "对于高清缩略图的说明..."))
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
    
    @objc func showMoreMenu(_ sender: Any?) {
        guard let viewController = contentViewController as? ViewController else {return}
        
        let menu = NSMenu()
        menu.autoenablesItems = false

        let actionItemOntop = menu.addItem(withTitle: NSLocalizedString("Pin Window", comment: "置顶"), action: #selector(ontopAction), keyEquivalent: "t")
        actionItemOntop.keyEquivalentModifierMask = []
        if let window = window {
            actionItemOntop.state = (window.level == .floating) ? .on : .off
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let actionItemSettings = menu.addItem(withTitle: NSLocalizedString("Settings...", comment: "设置..."), action: #selector(settingsAction), keyEquivalent: ",")
        actionItemSettings.keyEquivalentModifierMask = [.command]
        
        menu.addItem(NSMenuItem.separator())
        
        let customLayoutStyle = menu.addItem(withTitle: NSLocalizedString("Custom Layout Style...", comment: "自定义布局样式..."), action: #selector(customLayoutStyle), keyEquivalent: "")
        customLayoutStyle.isEnabled = !viewController.publicVar.isInLargeView

        menu.addItem(NSMenuItem.separator())
        
        let actionItemShowHiddenFile = menu.addItem(withTitle: NSLocalizedString("Show Hidden Files", comment: "显示隐藏文件"), action: #selector(showHiddenFileAction), keyEquivalent: ".")
        actionItemShowHiddenFile.state = (viewController.publicVar.isShowHiddenFile) ? .on : .off
        actionItemShowHiddenFile.keyEquivalentModifierMask = [.command, .shift]
        
        let showAllTypeFile = menu.addItem(withTitle: NSLocalizedString("Show All Types of Files", comment: "显示所有类型文件"), action: #selector(showAllTypeFileAction), keyEquivalent: ",")
        showAllTypeFile.state = (viewController.publicVar.isShowAllTypeFile) ? .on : .off
        showAllTypeFile.keyEquivalentModifierMask = [.command, .shift]
        
        let showImageFile = menu.addItem(withTitle: NSLocalizedString("Show Image Files", comment: "显示图像文件"), action: #selector(showImageFileAction), keyEquivalent: "")
        showImageFile.state = (viewController.publicVar.isShowImageFile) ? .on : .off
        
        let showRawFile = menu.addItem(withTitle: NSLocalizedString("Show Camera RAW Files", comment: "显示相机RAW文件"), action: #selector(showRawFileAction), keyEquivalent: "")
        showRawFile.state = (viewController.publicVar.isShowRawFile) ? .on : .off

        let showVideoFile = menu.addItem(withTitle: NSLocalizedString("Show Video Files", comment: "显示视频文件"), action: #selector(showVideoFileAction), keyEquivalent: "")
        showVideoFile.state = (viewController.publicVar.isShowVideoFile) ? .on : .off

        if viewController.publicVar.isShowAllTypeFile {
            showImageFile.isEnabled=false
            showRawFile.isEnabled=false
            showVideoFile.isEnabled=false
        }

        menu.addItem(NSMenuItem.separator())

        let rawFileUseThumbnail = menu.addItem(withTitle: NSLocalizedString("Use Embedded Thumbnail for Camera RAW Files", comment: ""), action: #selector(rawFileUseThumbnailAction), keyEquivalent: "")
        rawFileUseThumbnail.state = (viewController.publicVar.isRawFileUseThumbnail) ? .on : .off
        
        menu.addItem(NSMenuItem.separator())

        let autoPlayVisibleVideo = menu.addItem(withTitle: NSLocalizedString("Auto Play Visible Video", comment: "自动播放可见视频"), action: #selector(toggleAutoPlayVisibleVideo), keyEquivalent: "g")
        autoPlayVisibleVideo.keyEquivalentModifierMask = [.command, .shift]
        autoPlayVisibleVideo.state = viewController.publicVar.autoPlayVisibleVideo ? .on : .off
        autoPlayVisibleVideo.isEnabled = !viewController.publicVar.isInLargeView

        let useInternalPlayer = menu.addItem(withTitle: NSLocalizedString("Use Internal Video Player", comment: "使用内置视频播放器"), action: #selector(toggleUseInternalPlayer), keyEquivalent: "")
        useInternalPlayer.state = globalVar.useInternalPlayer ? .on : .off

        let videoPlayInfo = menu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(videoPlayInfo), keyEquivalent: "")
        
        menu.addItem(NSMenuItem.separator())

        let recursiveMode = menu.addItem(withTitle: NSLocalizedString("Recursive Mode", comment: "递归浏览模式"), action: #selector(toggleRecursiveMode), keyEquivalent: "r")
        recursiveMode.keyEquivalentModifierMask = [.command, .shift]
        recursiveMode.state = (viewController.publicVar.isRecursiveMode) ? .on : .off

        let recursiveContainFolder = menu.addItem(withTitle: NSLocalizedString("Include Folders", comment: "包含文件夹"), action: #selector(toggleRecursiveContainFolder), keyEquivalent: "t")
        recursiveContainFolder.keyEquivalentModifierMask = [.command, .shift]
        recursiveContainFolder.state = (viewController.publicVar.isRecursiveContainFolder) ? .on : .off
        
        let recursiveModeInfo = menu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(recursiveModeInfo), keyEquivalent: "")
        
        menu.addItem(NSMenuItem.separator())
        
        let portableMode = menu.addItem(withTitle: NSLocalizedString("Portable Browsing Mode", comment: "便携浏览模式"), action: #selector(togglePortableMode), keyEquivalent: "")
        portableMode.keyEquivalentModifierMask = []
        portableMode.state = globalVar.portableMode ? .on : .off
        
        let portableModeInfo = menu.addItem(withTitle: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(portableModeInfo), keyEquivalent: "")
        
        menu.addItem(NSMenuItem.separator())

        var autoScrollMenuText = NSLocalizedString("Enable Automatic Scroll", comment: "启用自动滚动")
        if viewController.autoScrollTimer != nil {
            autoScrollMenuText = NSLocalizedString("Disable Automatic Scroll", comment: "停止自动滚动")
        }
        let autoScroll = menu.addItem(withTitle: autoScrollMenuText, action: #selector(toggleAutoScroll), keyEquivalent: "")
        autoScroll.isEnabled = !viewController.publicVar.isInLargeView
        
        var autoPlayMenuText = NSLocalizedString("Enable Automatic Play", comment: "启用自动播放")
        if viewController.autoPlayTimer != nil {
            autoPlayMenuText = NSLocalizedString("Disable Automatic Play", comment: "停止自动播放")
        }
        let autoPlay = menu.addItem(withTitle: autoPlayMenuText, action: #selector(toggleAutoPlay), keyEquivalent: "")
        autoPlay.isEnabled = viewController.publicVar.isInLargeView

        menu.addItem(NSMenuItem.separator())
        
        let maximizeWindow = menu.addItem(withTitle: NSLocalizedString("Maximize Window", comment: "最大化窗口"), action: #selector(maximizeWindow), keyEquivalent: "1")
        maximizeWindow.keyEquivalentModifierMask = []
        
        let optimizeWindow = menu.addItem(withTitle: NSLocalizedString("optimizeWindow", comment: "合适窗口大小"), action: #selector(optimizeWindow), keyEquivalent: "2")
        optimizeWindow.keyEquivalentModifierMask = []
        
        let adjustWindowActual = menu.addItem(withTitle: NSLocalizedString("Adjust Window to Actual Image Size", comment: "调整窗口至图片实际大小"), action: #selector(adjustWindowActual), keyEquivalent: "3")
        adjustWindowActual.keyEquivalentModifierMask = []
        
        let adjustWindowCurrent = menu.addItem(withTitle: NSLocalizedString("Adjust Window to Current Image Size", comment: "调整窗口至图片当前大小"), action: #selector(adjustWindowCurrent), keyEquivalent: "4")
        adjustWindowCurrent.keyEquivalentModifierMask = []
        
        let adjustWindowToCenter = menu.addItem(withTitle: NSLocalizedString("Center the Window", comment: "将窗口居中"), action: #selector(adjustWindowToCenter), keyEquivalent: "5")
        adjustWindowToCenter.keyEquivalentModifierMask = []
        
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
        
        if let button = sender as? NSButton {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let menuLocation = NSPoint(x: 0, y: buttonFrame.height + 4)
            menu.popUp(positioning: nil, at: menuLocation, in: button)
        } else {
            let menuLocation = NSEvent.mouseLocation
            menu.popUp(positioning: nil, at: menuLocation, in: nil)
        }
    }

    @objc func toggleEnableHDR(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.publicVar.isEnableHDR.toggle()
        UserDefaults.standard.set(viewController.publicVar.isEnableHDR, forKey: "isEnableHDR")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if #available(macOS 14.0, *) {
                viewController.largeImageView.imageView.preferredImageDynamicRange = (viewController.publicVar.isEnableHDR) ? .high : .standard
            }
            //self.updateToolbar()
            viewController.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false, forceRefresh: true)
        }
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

        guard let url=URL(string: getFileStylePath(sender.title)) else {return}
        if viewController.publicVar.isInLargeView {
            viewController.closeLargeImage(0)
        }
        viewController.switchDirByDirection(direction: .zero, dest: url.absoluteString, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
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
    
    @objc func rawFileUseThumbnailAction(_ sender: NSMenuItem) {
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleIsRawFileUseThumbnail()
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
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("portable-mode-info", comment: "对于便携模式的说明..."), width: 300)
    }
    
    @objc func toggleSearchFilter(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.applyFilter(isReset: true)
    }
    
    @objc func toggleRecursiveMode(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleRecursiveMode()
    }
    
    @objc func toggleRecursiveContainFolder(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleRecursiveContainFolder()
    }
    
    @objc func recursiveModeInfo(_ sender: NSMenuItem){
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("recursive-mode-info", comment: "对于递归模式的说明..."), width: 300)
    }
    
    @objc func toggleAutoScroll(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleAutoScroll()
    }
    
    @objc func toggleAutoPlay(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleAutoPlay()
    }
    
    @objc func toggleAutoPlayVisibleVideo(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleAutoPlayVisibleVideo()
    }

    @objc func toggleUseInternalPlayer(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.toggleUseInternalPlayer()
    }
    
    @objc func videoPlayInfo(_ sender: NSMenuItem){
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("video-play-info", comment: "对于视频播放的说明..."), width: 300)
    }
    
    @objc func customLayoutStyle(_ sender: NSMenuItem){
        guard let viewController = contentViewController as? ViewController else {return}
        viewController.customLayoutStylePrompt()
    }
}
