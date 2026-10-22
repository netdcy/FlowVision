//
//  CustomPathControl.swift
//  FlowVision
//

import Foundation
import Cocoa

class CustomPathControl: NSPathControl, NSMenuDelegate {
    var fullPathItems: [CustomPathControlItem] = []
    private var eventMonitor: Any?
    private var highlightView: NSView?
    private var rightClickedURL: URL?
    private weak var dragHighlightedCell: NSPathComponentCell?

    override func awakeFromNib() {
        super.awakeFromNib()
        // 注册接受文件URL拖拽（仅作为拖拽目标，不支持拖拽出）
        // Register for accepting file URL drops (drop target only, no drag-out support)
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
                guard let self = self else { return event }
                return self.handleRightMouseMenu(event) ? nil : event
            }
        } else if window == nil, let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Hit Test & Highlight

    private func titleRect(of componentCell: NSPathComponentCell) -> NSRect? {
        guard let pathCell = self.cell as? NSPathCell else { return nil }
        let cellRect = pathCell.rect(of: componentCell, withFrame: bounds, in: self)
        let titleWidth = componentCell.attributedStringValue.size().width + 8
        return NSRect(x: cellRect.minX, y: cellRect.minY, width: min(titleWidth, cellRect.width), height: cellRect.height)
    }

    private func componentCell(at windowPoint: NSPoint) -> NSPathComponentCell? {
        guard let pathCell = self.cell as? NSPathCell else { return nil }
        let point = convert(windowPoint, from: nil)
        for cell in pathCell.pathComponentCells {
            if let rect = titleRect(of: cell), rect.contains(point) { return cell }
        }
        return nil
    }

    private func showHighlight(for componentCell: NSPathComponentCell) {
        guard let rect = titleRect(of: componentCell) else { return }
        let hv = NSView(frame: rect)
        hv.wantsLayer = true
        hv.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        hv.layer?.cornerRadius = 4
        addSubview(hv)
        highlightView = hv
    }

    private func removeHighlight() {
        highlightView?.removeFromSuperview()
        highlightView = nil
    }

    // MARK: - Left Click

    override func mouseDown(with event: NSEvent) {
        if let cell = componentCell(at: event.locationInWindow) {
            showHighlight(for: cell)
        }
        // super.mouseDown 内部会阻塞直到鼠标弹起，同时设置 clickedPathItem 并触发 action
        super.mouseDown(with: event)
        removeHighlight()
    }

    // MARK: - Right Click

    private func urlForCell(_ cell: NSPathComponentCell) -> URL? {
        guard let pathCell = self.cell as? NSPathCell else { return nil }
        let cells = pathCell.pathComponentCells
        guard let index = cells.firstIndex(of: cell),
              index < pathItems.count else { return nil }
        return (pathItems[index] as? CustomPathControlItem)?.myUrl
    }

    private func handleRightMouseMenu(_ event: NSEvent) -> Bool {
        guard event.window == self.window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point),
              let cell = componentCell(at: event.locationInWindow) else { return false }

        // 获取点击的路径项对应的URL
        // Get the URL for the clicked path item
        let clickedURL: URL
        if let url = urlForCell(cell) {
            clickedURL = url
        } else {
            // 最后一个路径项的myUrl为nil，使用当前文件夹路径
            // Last path item has nil myUrl, use current folder path
            guard let vc = self.window?.contentViewController as? ViewController else { return false }
            vc.fileDB.lock()
            let curFolder = vc.fileDB.curFolder
            vc.fileDB.unlock()
            guard let url = URL(string: curFolder) else { return false }
            clickedURL = url
        }
        rightClickedURL = clickedURL

        showHighlight(for: cell)

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        // 打开
        let actionItemOpen = menu.addItem(withTitle: NSLocalizedString("Open", comment: "打开"), action: #selector(actOpen), keyEquivalent: "")

        // 在新标签页中打开
        let actionItemOpenInNewTab = menu.addItem(withTitle: NSLocalizedString("Open in New Tab", comment: "在新标签页中打开"), action: #selector(actOpenInNewTab), keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())

        // 打开方式
        addOpenWithSubMenu(to: menu, url: clickedURL)

        // 在Finder中显示
        menu.addItem(withTitle: NSLocalizedString("Show in Finder", comment: "在Finder中显示"), action: #selector(actShowInFinder), keyEquivalent: "")

        // 显示简介
        menu.addItem(withTitle: NSLocalizedString("file-rightmenu-get-info", comment: "显示简介"), action: #selector(actGetInfo), keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())

        // 复制
        menu.addItem(withTitle: NSLocalizedString("Copy", comment: "复制"), action: #selector(actCopy), keyEquivalent: "")

        // 复制路径
        menu.addItem(withTitle: NSLocalizedString("Copy Path", comment: "复制路径"), action: #selector(actCopyPath), keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())

        // 在终端中打开
        menu.addItem(withTitle: NSLocalizedString("Open in Terminal", comment: "在终端中打开"), action: #selector(actOpenInTerminal), keyEquivalent: "")

        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: point, in: self)
        return true
    }

    // MARK: - Open With Submenu

    private func addOpenWithSubMenu(to menu: NSMenu, url: URL) {
        let openWithMenu = NSMenu(title: "openWith")
        let openWithMenuItem = NSMenuItem(title: NSLocalizedString("Open With", comment: "打开方式"), action: nil, keyEquivalent: "")
        openWithMenuItem.submenu = openWithMenu

        let cfURL = url as CFURL
        let appURLs = LSCopyApplicationURLsForURL(cfURL, .all)?.takeRetainedValue() as? [URL] ?? []

        for appURL in appURLs {
            let appName = FileManager.default.displayName(atPath: appURL.path)
            let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            let appMenuItem = NSMenuItem(title: appName.replacingOccurrences(of: ".app", with: " "), action: #selector(actOpenWithApp(_:)), keyEquivalent: "")
            appMenuItem.representedObject = appURL
            appMenuItem.target = self
            appMenuItem.image = appIcon
            appMenuItem.image?.size = NSSize(width: 16, height: 16)
            openWithMenu.addItem(appMenuItem)
        }

        if appURLs.isEmpty {
            let emptyMenuItem = NSMenuItem(
                title: NSLocalizedString("empty-enclose", comment: "菜单当内容为空时显示的东西"),
                action: nil,
                keyEquivalent: ""
            )
            openWithMenu.addItem(emptyMenuItem)
        }

        menu.addItem(openWithMenuItem)
    }

    // MARK: - Menu Actions

    @objc private func actOpen() {
        guard let url = rightClickedURL else { return }
        guard let vc = self.window?.contentViewController as? ViewController else { return }
        if vc.publicVar.isInLargeView {
            vc.closeLargeImage(0)
        }
        vc.switchDirByDirection(direction: .zero, dest: url.absoluteString, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
    }

    @objc private func actOpenInNewTab() {
        guard let url = rightClickedURL else { return }
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            // 按住 Cmd 点击菜单项时在后台打开
            // Hold Cmd when clicking the menu item to open in background
            _ = appDelegate.createNewWindow(url.absoluteString, openInBackground: NSEvent.modifierFlags.contains(.command))
        }
    }

    @objc private func actOpenWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL,
              let url = rightClickedURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func actShowInFinder() {
        guard let url = rightClickedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func actGetInfo() {
        guard let url = rightClickedURL else { return }
        guard let vc = self.window?.contentViewController as? ViewController else { return }
        vc.handleGetInfo([url])
    }

    @objc private func actCopy() {
        guard let url = rightClickedURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    @objc private func actCopyPath() {
        guard let url = rightClickedURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    @objc private func actOpenInTerminal() {
        guard let url = rightClickedURL else { return }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", url.path]
        task.launch()
    }

    func menuDidClose(_ menu: NSMenu) {
        removeHighlight()
    }

    // MARK: - Drag Destination

    /// 根据拖拽位置定位到的路径段及其目标URL
    /// Locate the path component cell and its target URL for the drag location
    private func componentCellAndURL(for sender: NSDraggingInfo) -> (NSPathComponentCell, URL)? {
        let location = sender.draggingLocation
        guard let cell = componentCell(at: location) else { return nil }
        if let url = urlForCell(cell) {
            return (cell, url)
        }
        // 最后一个路径项的myUrl为nil，使用当前文件夹路径
        // Last path item has nil myUrl, use current folder path
        guard let vc = self.window?.contentViewController as? ViewController else { return nil }
        vc.fileDB.lock()
        let curFolder = vc.fileDB.curFolder
        vc.fileDB.unlock()
        guard let url = URL(string: curFolder) else { return nil }
        return (cell, url)
    }

    private func updateDragHighlight(for cell: NSPathComponentCell?) {
        if dragHighlightedCell === cell { return }
        removeHighlight()
        dragHighlightedCell = cell
        if let cell = cell {
            showHighlight(for: cell)
        }
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard let (cell, targetUrl) = componentCellAndURL(for: sender) else {
            updateDragHighlight(for: nil)
            return []
        }

        // 不允许拖拽到虚拟文件夹
        // Disallow dropping onto virtual folders
        let urlString = targetUrl.absoluteString
        if urlString.hasPrefix("file:///VirtualFinderTagsFolder") || urlString.contains("FlowVisionTitleFolder") {
            updateDragHighlight(for: nil)
            return []
        }

        // 拖拽源就是目标本身、或源文件已经位于目标目录内时不允许
        // Disallow when source equals target or source already lives inside the target directory
        if let data = sender.draggingPasteboard.data(forType: .fileURL),
           let sourceUrl = URL(dataRepresentation: data, relativeTo: nil),
           sourceUrl == targetUrl || sourceUrl.deletingLastPathComponent().path == targetUrl.path {
            updateDragHighlight(for: nil)
            return []
        }

        updateDragHighlight(for: cell)
        return .move
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return dragOperation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateDragHighlight(for: nil)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        updateDragHighlight(for: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { updateDragHighlight(for: nil) }

        guard let (_, targetUrl) = componentCellAndURL(for: sender) else { return false }
        guard let viewController = self.window?.contentViewController as? ViewController else { return false }

        let pasteboard = sender.draggingPasteboard

        // 拖拽源就是目标本身、或源文件已经位于目标目录内时不允许
        // Disallow when source equals target or source already lives inside the target directory
        if let data = pasteboard.data(forType: .fileURL),
           let sourceUrl = URL(dataRepresentation: data, relativeTo: nil),
           sourceUrl == targetUrl || sourceUrl.deletingLastPathComponent().path == targetUrl.path {
            return false
        }

        if viewController.handleFilePromiseDrop(targetURL: targetUrl, pasteboard: pasteboard) {
            return true
        }

        // 同窗口内拖拽时弹出确认对话框防止误操作
        // Show confirmation when dragging within the same window to prevent mistakes
        if let sourceView = sender.draggingSource as? NSView,
           sourceView.window == self.window,
           let data = pasteboard.data(forType: .fileURL),
           let sourceUrl = URL(dataRepresentation: data, relativeTo: nil) {
            let sourceName = sourceUrl.lastPathComponent
            let confirmed = showConfirmation(
                title: NSLocalizedString("Move Items", comment: "移动项目"),
                message: String(format: NSLocalizedString("Are you sure you want to move xxx to xxx?", comment: "确定要移动 xxx 到 xxx?"), sourceName, targetUrl.lastPathComponent)
            )
            if !confirmed {
                return false
            }
        }

        viewController.handleMove(targetURL: targetUrl, pasteboard: pasteboard)
        return true
    }
}

class CustomPathControlItem: NSPathControlItem {
    var myUrl: URL?
}
