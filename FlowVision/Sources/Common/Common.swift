//
//  Common.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/24.
//

import Foundation
import Cocoa

@propertyWrapper
struct Atomic<Value> {
    private var value: Value
    private let lock = NSLock()

    init(wrappedValue value: Value) {
        self.value = value
    }

    var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

class MyTimer{
    var intervalDict = Dictionary<String,DispatchTime>()
    var lock = NSLock()
    func intervalSafe(name: String, second: Double, execute: Bool = true) -> Bool {
        var result = false
        lock.lock()
        if intervalDict[name] != nil {
            let lastTime = intervalDict[name]!.uptimeNanoseconds
            let nowTime = DispatchTime.now().uptimeNanoseconds
            let nanoTime = nowTime - lastTime
            let timeInterval = Double(nanoTime) / 1_000_000_000
            if(timeInterval>=second){
                if execute {
                    intervalDict[name] = DispatchTime.now()
                }
                result = true
            }
        }else{
            if execute {
                intervalDict[name] = DispatchTime.now()
            }else{
                intervalDict[name] = DispatchTime.init(uptimeNanoseconds: 0)
            }
            result = true
        }
        lock.unlock()
        return result
    }
//    func reset(name: String, second: Double) {
//        lock.lock()
//        intervalDict[name] = DispatchTime.now()
//        lock.unlock()
//    }
}

class ExecutionTimer {
    private var startTime: CFAbsoluteTime?
    
    func start() {
        startTime = CFAbsoluteTimeGetCurrent()
    }
    
    func stop() -> TimeInterval? {
        guard let startTime = startTime else {
            log("Timer was not started.")
            return nil
        }
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        self.startTime = nil // Reset start time
        return timeElapsed
    }
}

extension UserDefaults {
//    // 存储 String 类型的 RawRepresentable 枚举
//    func setEnum<T: RawRepresentable>(_ value: T, forKey key: String) where T.RawValue == String {
//        self.set(value.rawValue, forKey: key)
//    }
//    
//    // 读取 String 类型的 RawRepresentable 枚举
//    func enumValue<T: RawRepresentable>(forKey key: String) -> T? where T.RawValue == String {
//        guard let rawValue = self.string(forKey: key) else {
//            return nil
//        }
//        return T(rawValue: rawValue)
//    }
    
//    // 存储 Int 类型的 RawRepresentable 枚举
//    func setEnum<T: RawRepresentable>(_ value: T, forKey key: String) where T.RawValue == Int {
//        self.set(value.rawValue, forKey: key)
//    }
//    
//    // 读取 Int 类型的 RawRepresentable 枚举
//    func enumValue<T: RawRepresentable>(forKey key: String) -> T? where T.RawValue == Int {
//        let rawValue = self.integer(forKey: key)
//        return T(rawValue: rawValue)
//    }
    
    // 存储 Int 类型的 RawRepresentable 枚举
    func setEnum<T: RawRepresentable>(_ value: T, forKey key: String) where T.RawValue == Int {
        self.set(value.rawValue, forKey: key)
    }
    
    // 读取 Int 类型的 RawRepresentable 枚举
    func enumValue<T: RawRepresentable>(forKey key: String) -> T? where T.RawValue == Int {
        let rawValue = self.object(forKey: key) as? Int
        return rawValue.flatMap { T(rawValue: $0) }
    }
}

func getFileStylePath(_ path: String) -> String {
    guard let url=URL(string: path.removingPercentEncoding!.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!) else{return ""}
    var path=url.absoluteString
    path = path.hasPrefix("file://") ? path : "file://" + path
    return path
}

func getFileStyleFolderPath(_ path: String) -> String {
    guard let url=URL(string: path.removingPercentEncoding!.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!) else{return ""}
    var folderPath=url.deletingLastPathComponent().absoluteString
    folderPath = folderPath.hasPrefix("file://") ? folderPath : "file://" + folderPath
    return folderPath
}

func attributedStringWithSymbols(_ symbols: [String]) -> NSAttributedString {
    let attributedString = NSMutableAttributedString()
    
    for symbol in symbols {
        if let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = symbolImage
            
            // 调整图片高度以使其居中
            let imageString = NSAttributedString(attachment: attachment)
            let mutableImageString = NSMutableAttributedString(attributedString: imageString)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            mutableImageString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: imageString.length))
            
            attributedString.append(mutableImageString)
            
            // 添加一些间距
            attributedString.append(NSAttributedString(string: ""))
        }
    }
    
    return attributedString
}

func isCommandKeyPressed() -> Bool {
    if let currentEvent = NSApp.currentEvent {
        return currentEvent.modifierFlags.contains(.command)
    }
    return false
}

func isControlKeyPressed() -> Bool {
    if let currentEvent = NSApp.currentEvent {
        return currentEvent.modifierFlags.contains(.control)
    }
    return false
}

func isShiftKeyPressed() -> Bool {
    if let currentEvent = NSApp.currentEvent {
        return currentEvent.modifierFlags.contains(.shift)
    }
    return false
}

func isOptionKeyPressed() -> Bool {
    if let currentEvent = NSApp.currentEvent {
        return currentEvent.modifierFlags.contains(.option)
    }
    return false
}

func showAlert(message: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.icon = NSImage(named: NSImage.cautionName)
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
}

func showInformation(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.icon = NSImage(named: NSImage.infoName)
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
}

func showInformationLongDeprecate(title: String, message: String, width: CGFloat = 400) {
    let alert = NSAlert()
    alert.messageText = title
    //alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.icon = NSImage(named: NSImage.infoName)
    
    // 设置对话框宽度
    let textField = NSTextView()
    textField.isEditable = false
    textField.backgroundColor = .clear
    textField.isSelectable = true
    textField.textColor = NSColor.headerTextColor
    
    // 创建段落样式并设置行间距
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 1.2  // 设置行间距
    
    // 使用富文本设置内容和样式
    let attributedString = NSAttributedString(
        string: message,
        attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor.headerTextColor,
            .paragraphStyle: paragraphStyle
        ]
    )
    textField.textStorage?.setAttributedString(attributedString)
    
    textField.isVerticallyResizable = true
    textField.isHorizontallyResizable = false
    textField.textContainer?.widthTracksTextView = true
    textField.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    
    // 计算文本高度
    let contentSize = textField.layoutManager?.usedRect(for: textField.textContainer!).size ?? .zero
    let height = min(max(contentSize.height, 50), 600) // 设置最小50和最大600的高度限制
    
    textField.frame = NSRect(x: 0, y: 0, width: width, height: height)
    alert.accessoryView = textField
    
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
}

func showInformationLong(title: String, message: String, width: CGFloat = 400) {
    let alert = NSAlert()
    alert.messageText = title
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.icon = NSImage(named: NSImage.infoName)
    
    // 创建滚动视图
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false  // 设置滚动视图背景为透明
    
    // 设置文本视图
    let textField = NSTextView(frame: NSRect(x: 0, y: 0, width: width - 20, height: 0))
    textField.isEditable = false
    textField.backgroundColor = .clear  // 设置文本视图背景为透明
    textField.drawsBackground = false   // 确保文本视图不绘制背景
    textField.isSelectable = true
    textField.textColor = NSColor.headerTextColor
    
    // 创建段落样式并设置行间距
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 1.2
    
    // 使用富文本设置内容和样式
    let attributedString = NSAttributedString(
        string: message,
        attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor.headerTextColor,
            .paragraphStyle: paragraphStyle
        ]
    )
    textField.textStorage?.setAttributedString(attributedString)
    
    // 配置文本视图容器
    textField.isVerticallyResizable = true
    textField.isHorizontallyResizable = false
    textField.textContainer?.widthTracksTextView = true
    textField.textContainer?.containerSize = NSSize(width: width - 20, height: CGFloat.greatestFiniteMagnitude)
    textField.layoutManager?.ensureLayout(for: textField.textContainer!)
    
    // 设置滚动视图的大小
    let contentSize = textField.layoutManager?.usedRect(for: textField.textContainer!).size ?? .zero
    // 添加一点额外的高度来防止不必要的滚动条
    let height = min(max(contentSize.height + 5, 50), 400)  // 添加5个点的额外空间
    scrollView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    
    // 设置文本视图的frame，同样添加额外空间
    textField.frame = NSRect(x: 0, y: 0, width: width - 20, height: contentSize.height + 5)
    
    // 设置滚动视图
    scrollView.documentView = textField
    
    // 设置为警告框的附件视图
    alert.accessoryView = scrollView
    
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled = false
    alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
}

func showInformationCopy(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("Copy", comment: "复制"))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
    alert.icon = NSImage(named: NSImage.infoName)
    
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled = false
    let response = alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled

    if response == .alertFirstButtonReturn {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)
    } else if response == .alertSecondButtonReturn {
        // cancel
    }
}

func renameAlert(urls: [URL]) -> Bool {
    if urls.isEmpty { return false }
    
    // 创建一个警告对话框
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Rename", comment: "重命名")
    alert.informativeText = NSLocalizedString("New name for", comment: "请输入新的名称用于") + " \(urls[0].lastPathComponent):"
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
    alert.icon = NSImage(named: NSImage.infoName)// 设置系统通知图标
    
    // 添加一个文本输入框到警告对话框中
    let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    inputTextField.stringValue = urls[0].lastPathComponent
    if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
        textFieldCell.usesSingleLineMode = true
        textFieldCell.wraps = false
        textFieldCell.isScrollable = true
    }
    alert.accessoryView = inputTextField
    
    // 显示对话框
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled = false
    DispatchQueue.main.async {
        // 判断是否是文件夹
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &isDirectory)
        
        _ = inputTextField.becomeFirstResponder()
        if isDirectory.boolValue {
            // 如果是文件夹，选中全部内容
            inputTextField.selectText(nil)
        } else {
            // 如果是文件，选中文件名不包含扩展名的部分
            let fileName = urls[0].deletingPathExtension().lastPathComponent
            inputTextField.currentEditor()?.selectedRange = NSRange(location: 0, length: fileName.count)
        }
    }
    let response = alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
    
    // 根据用户的选择处理结果
    if response == .alertFirstButtonReturn { // OK按钮
        let newBaseName = inputTextField.stringValue
        
        if newBaseName != "" {

            // 记录操作到日志
            let sourceFiles = urls.map { url -> String in
                return url.lastPathComponent
            }
            
            let sourceFilesStr: String
            if sourceFiles.count > 3 {
                sourceFilesStr = sourceFiles[0...2].joined(separator: ", ") + "..."
            } else {
                sourceFilesStr = sourceFiles.joined(separator: ", ")
            }
            
            let operationLog = "[Rename] \(sourceFilesStr) -> \(newBaseName)"
            globalVar.operationLogs.append(operationLog)

            var allSuccess = true
            
            for (index, originalUrl) in urls.enumerated() {
                // 构建新文件名
                var newName = newBaseName
                if index >= 0 && urls.count > 1 {
                    // 如果有扩展名，在扩展名前添加序号
                    if let ext = originalUrl.pathExtension.isEmpty ? nil : originalUrl.pathExtension {
                        let nameWithoutExt = (newBaseName as NSString).deletingPathExtension
                        newName = "\(nameWithoutExt)_\(index + 1).\(ext)"
                    } else {
                        newName = "\(newBaseName)_\(index + 1)"
                    }
                }
                
                let newUrl = originalUrl.deletingLastPathComponent().appendingPathComponent(newName)
                
                // 检查是否存在同名文件
                if FileManager.default.fileExists(atPath: newUrl.path) &&
                    originalUrl.path.lowercased() != newUrl.path.lowercased() {
                    showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                    allSuccess = false
                    break
                } else if originalUrl.path != newUrl.path {
                    // 执行重命名操作
                    do {
                        // 文件更改计数
                        getMainViewController()?.publicVar.fileChangedCount += 1
                        
                        try FileManager.default.moveItem(at: originalUrl, to: newUrl)
                        log("File renamed to \(newName)")
                    } catch {
                        log("Failed to rename file: \(error)")
                        allSuccess = false
                        break
                    }
                }
            }
            
            // 针对递归模式处理
            if let viewController = getMainViewController() {
                if viewController.publicVar.isRecursiveMode {
                    if viewController.fileDB.db[SortKeyDir(viewController.fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD {
                        viewController.scheduledRefresh()
                    }
                }
            }
            
            return allSuccess
        }
    }
    return false
}

//// 接受字符串路径的函数
//func isExternalVolume(_ path: String) -> Bool {
//    // 将字符串路径转换为URL
//    guard var url = URL(string: path) else {
//        return false
//    }
//
//    // 如果URL没有scheme，则将其视作文件路径
//    if url.scheme == nil {
//        url = URL(fileURLWithPath: path)
//    }
//
//    // 标准化URL路径
//    let standardizedPath = url.standardized.path
//
//    // 检查路径是否以/Volumes/开头
//    return standardizedPath.hasPrefix("/Volumes/")
//}
//
//// 接受URL路径的函数
//func isExternalVolume(_ url: URL) -> Bool {
//    // 标准化URL路径
//    let standardizedPath = url.standardized.path
//
//    // 检查路径是否以/Volumes/开头
//    return standardizedPath.hasPrefix("/Volumes/")
//}

func getDirectoryPath(_ path: String) -> String {
    if path.hasPrefix("file://") {
        let url = URL(string: path)!
        return url.deletingLastPathComponent().absoluteString
    } else {
        return (path as NSString).deletingLastPathComponent
    }
}


class VolumeManager {
    static let shared = VolumeManager()
    private var externalVolumes: [URL] = []
    private let fileManager = FileManager.default
    private let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey]
    private let lock = NSLock()
    private var timer = MyTimer()
    
    private init() {
        self.updateExternalVolumes()
    }
    
    func updateExternalVolumes() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        if !timer.intervalSafe(name: "updateExternalVolumes", second: 1) {
            return false
        }
        
        //log("======updateExternalVolumes=====")
        
        externalVolumes = []
        if let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) {
            for url in urls {
                do {
                    let resourceValues = try url.resourceValues(forKeys: Set(keys))
                    if let isInternal = resourceValues.volumeIsInternal {
                        if !isInternal {
                            externalVolumes.append(url)
                        }
                    }else{
                        externalVolumes.append(url)
                    }
                } catch {
                    log("Error retrieving resource values: \(error)")
                }
            }
        } else {
            log("No mounted volumes found.")
        }
        return true
    }
    
    func isExternalVolume(_ path: String) -> Bool {
        guard var url = URL(string: path) else {
            return false
        }
        
        if url.scheme == nil {
            url = URL(fileURLWithPath: path.removingPercentEncoding!)
        }
        
        return isExternalVolume(url)
    }
    
    func isExternalVolume(_ url: URL) -> Bool {
        let standardizedPath = url.standardized.path
        
        lock.lock()
        let volumes = externalVolumes
        lock.unlock()
        
        for volumeURL in volumes {
            if standardizedPath.hasPrefix(volumeURL.standardized.path) {
                return true
            }
        }
        
        // 更新外置卷列表并再检查一次
        if updateExternalVolumes() {
            lock.lock()
            let updatedVolumes = externalVolumes
            lock.unlock()
            
            for volumeURL in updatedVolumes {
                if standardizedPath.hasPrefix(volumeURL.standardized.path) {
                    return true
                }
            }
        }

        return false
    }
    
    func getExternalVolumes() -> [URL] {
        updateExternalVolumes()
        return externalVolumes
    }
}

func requestAppleEventsPermission() -> Bool {
    let appleEventDescriptor = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments), targetDescriptor: appleEventDescriptor, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    
    var error: NSDictionary?
    
    // 使用NSAppleScript来执行Apple事件
    let script = NSAppleScript(source: """
        tell application "Finder"
            get name of startup disk
        end tell
    """)
    
    if let script = script {
        let result = script.executeAndReturnError(&error)
        
        if let error = error {
            log("请求自动化权限失败: \(error)")
        } else {
            log("请求自动化权限成功: \(result.stringValue ?? "")")
            return true
        }
    } else {
        log("无法创建AppleScript实例")
    }
    
    return false
}

class PrintView: NSView {
    var contentToPrint: NSView?

    init(content: NSView) {
        self.contentToPrint = content
        super.init(frame: content.frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let contentToPrint = contentToPrint else { return }
        
        // 保存当前图形上下文状态
        let graphicsContext = NSGraphicsContext.current?.cgContext
        graphicsContext?.saveGState()
        
        // 判断是否需要翻转
        if !(contentToPrint is NSImageView) {
            // 翻转和变换坐标系
            graphicsContext?.translateBy(x: 0, y: contentToPrint.bounds.height)
            graphicsContext?.scaleBy(x: 1.0, y: -1.0)
        }
        
        // 绘制内容
        contentToPrint.layer?.render(in: graphicsContext!)
        
        // 恢复图形上下文状态
        graphicsContext?.restoreGState()
    }
}

func printContent(_ content: NSView) {
    let printView = PrintView(content: content)
    let printInfo = NSPrintInfo.shared
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .fit

    let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
    printOperation.run()
}

func captureSnapshotDeprecated(of view: NSView) -> NSView? {
    guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: bitmapRep)
    
    let snapshotView = NSImageView(frame: view.bounds)
    snapshotView.image = NSImage(size: view.bounds.size)
    snapshotView.image?.addRepresentation(bitmapRep)
    return snapshotView
}

func captureSnapshotDeprecated2(of view: NSView) -> NSView? {
    // 创建一个新的NSImageView作为快照容器
    let snapshotView = NSImageView(frame: view.bounds)
    
    // 创建一个位图上下文来渲染视图
    let image = NSImage(size: view.bounds.size)
    image.lockFocus()
    
    if let context = NSGraphicsContext.current?.cgContext {
        // 保存上下文状态
        context.saveGState()
        
        // 判断是否需要翻转坐标系
        if !(view is NSImageView) {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1.0, y: -1.0)
        }
        
        // 使用layer渲染视图内容
        view.layer?.render(in: context)
        
        // 恢复上下文状态
        context.restoreGState()
    }
    
    image.unlockFocus()
    
    // 设置快照图像
    snapshotView.image = image
    
    return snapshotView
}

func captureSnapshot(of view: NSView) -> NSView? {
    guard let window = view.window else { return nil }
    
    // 将视图坐标转换为屏幕坐标
    let rect = view.convert(view.bounds, to: nil)
    var screenRect = window.convertToScreen(rect)

    // 将y坐标转换为从上到下
    if screenRect.origin.y == window.frame.origin.y {
        if let screen = NSScreen.screens.first {
            screenRect.origin.y = screen.frame.height - screenRect.origin.y - screenRect.height
        }
    }

    // 获取当前窗口的windowNumber
    let windowID = window.windowNumber
    
    // 只捕获指定窗口的内容
    guard let cgImage = CGWindowListCreateImage(
        screenRect,
        .optionIncludingWindow,  // 改为只包含指定窗口
        CGWindowID(windowID),    // 指定窗口ID
        .bestResolution
    ) else { return nil }
    
    let image = NSImage(cgImage: cgImage, size: view.bounds.size)
    
    // 保存图片用于调试
//        if let tiffData = image.tiffRepresentation,
//           let bitmapImage = NSBitmapImageRep(data: tiffData),
//           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
//            try? pngData.write(to: URL(fileURLWithPath: "/tmp/snapshot.png"))
//        }
    
    let snapshotView = NSImageView(frame: view.bounds)
    snapshotView.image = image
    return snapshotView
}

class ThumbnailOptionsWindow: NSWindow {
    // Get initial values from CustomProfile
    private var initialProfile = CustomProfile()
    
    // Define initial values from CustomProfile
    private var initialWindowTitleUseFullPath: Bool {
        return initialProfile.getValue(forKey: "isWindowTitleUseFullPath") == "true"
    }
    private var initialWindowTitleShowStatistics: Bool {
        return initialProfile.getValue(forKey: "isWindowTitleShowStatistics") == "true"
    }
    private var initialShowThumbnailBadge: Bool {
        return initialProfile.getValue(forKey: "isShowThumbnailBadge") == "true"
    }
    private var initialShowThumbnailFilename: Bool {
        return initialProfile.isShowThumbnailFilename
    }
    private var initialThumbnailFilenameSize: Double {
        return initialProfile.ThumbnailFilenameSize
    }
    private var initialThumbnailCellPadding: Double {
        return initialProfile._thumbnailCellPadding
    }
    private var initialThumbnailBorderRadiusInGrid: Double {
        return initialProfile.ThumbnailBorderRadiusInGrid
    }
    private var initialThumbnailBorderRadius: Double {
        return initialProfile.ThumbnailBorderRadius
    }
    private var initialThumbnailBorderThickness: Double {
        return initialProfile._thumbnailBorderThickness
    }
    private var initialThumbnailLineSpaceAdjust: Double {
        return initialProfile.ThumbnailLineSpaceAdjust
    }
    private var initialThumbnailShowShadow: Bool {
        return initialProfile.ThumbnailShowShadow
    }

    // Variables to store current settings
    var isWindowTitleUseFullPath: Bool
    var isWindowTitleShowStatistics: Bool
    var isShowThumbnailBadge: Bool
    var isShowThumbnailFilename: Bool
    var thumbnailFilenameSize: Double
    var thumbnailCellPadding: Double
    var thumbnailBorderRadiusInGrid: Double
    var thumbnailBorderRadius: Double
    var thumbnailBorderThickness: Double
    var thumbnailLineSpaceAdjust: Double
    var thumbnailShowShadow: Bool
    
    init() {
        let windowSize = NSSize(width: 740, height: 520)
        let windowRect = NSRect(origin: .zero, size: windowSize)
        
        // Get current values
        let profile = getMainViewController()!.publicVar.profile
        isWindowTitleUseFullPath = profile.getValue(forKey: "isWindowTitleUseFullPath") == "true"
        isWindowTitleShowStatistics = profile.getValue(forKey: "isWindowTitleShowStatistics") == "true"
        isShowThumbnailBadge = profile.getValue(forKey: "isShowThumbnailBadge") == "true"
        isShowThumbnailFilename = profile.isShowThumbnailFilename
        thumbnailFilenameSize = profile.ThumbnailFilenameSize
        thumbnailCellPadding = profile._thumbnailCellPadding
        thumbnailBorderRadiusInGrid = profile.ThumbnailBorderRadiusInGrid
        thumbnailBorderRadius = profile.ThumbnailBorderRadius
        thumbnailBorderThickness = profile._thumbnailBorderThickness
        thumbnailLineSpaceAdjust = profile.ThumbnailLineSpaceAdjust
        thumbnailShowShadow = profile.ThumbnailShowShadow
        
        super.init(contentRect: windowRect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.title = NSLocalizedString("Thumbnail Options", comment: "缩略图选项")
        
        // Create a custom view with a glass-like effect
        let customView = NSVisualEffectView(frame: windowRect)
        customView.material = .hudWindow
        customView.blendingMode = .withinWindow
        customView.state = .active
        
        // Create a stack view for layout
        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 15
        
        // Create an NSImageView for the icon
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        
        // Add a title label
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("Custom Layout Style", comment: "自定义布局样式"))
        titleLabel.alignment = .center
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        
        // Create a horizontal stack view for the icon and title
        let titleStackView = NSStackView(views: [icon, titleLabel])
        titleStackView.orientation = .horizontal
        titleStackView.alignment = .centerY
        titleStackView.spacing = 5
        
        stackView.addArrangedSubview(titleStackView)
        
        // Add spacing below the title
        let spacingView = NSView()
        spacingView.translatesAutoresizingMaskIntoConstraints = false
        spacingView.heightAnchor.constraint(equalToConstant: 0).isActive = true
        stackView.addArrangedSubview(spacingView)
        
        // Create labeled controls
        let windowTitleFullPathCheckboxView = createLabeledCheckbox(label: NSLocalizedString("Use Full Path in Window Title", comment: "在窗口标题中使用完整路径"), isChecked: isWindowTitleUseFullPath)
        let windowTitleStatsCheckboxView = createLabeledCheckbox(label: NSLocalizedString("Show Statistics in Window Title", comment: "在窗口标题中显示统计信息"), isChecked: isWindowTitleShowStatistics)
        let showBadgeCheckboxView = createLabeledCheckbox(label: NSLocalizedString("Show RAW/HDR Badge in Thumbnail(if exist)", comment: "缩略图显示RAW/HDR标记(如果存在)"), isChecked: isShowThumbnailBadge)
        let showFilenameCheckboxView = createLabeledCheckbox(label: NSLocalizedString("Show Thumbnail Filename", comment: "缩略图显示文件名"), isChecked: isShowThumbnailFilename)
        let filenameSizeTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Filename Font Size", comment: "缩略图文件名字体大小"), defaultValue: String(thumbnailFilenameSize))
        let cellPaddingTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Cell Padding", comment: "缩略图单元格外边距"), defaultValue: String(thumbnailCellPadding))
        let borderRadiusInGridTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Corner Radius (Grid View)", comment: "缩略图圆角半径(网格视图)"), defaultValue: String(thumbnailBorderRadiusInGrid))
        let borderRadiusTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Corner Radius (Non-Grid View)", comment: "缩略图圆角半径(非网格视图)"), defaultValue: String(thumbnailBorderRadius))
        let borderThicknessTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Border Thickness (Non-Grid View)", comment: "缩略图边框厚度(非网格视图)"), defaultValue: String(thumbnailBorderThickness))
        let lineSpaceAdjustTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Line Space Adjustment (Non-Grid View)", comment: "缩略图行间距调整(非网格视图)"), defaultValue: String(thumbnailLineSpaceAdjust))
        let showShadowCheckboxView = createLabeledCheckbox(label: NSLocalizedString("Show Thumbnail Shadow (Non-Grid View)", comment: "显示缩略图阴影(非网格视图)"), isChecked: thumbnailShowShadow)
        
        // Add subviews to stack view in the new order
        stackView.addArrangedSubview(windowTitleFullPathCheckboxView)
        stackView.addArrangedSubview(windowTitleStatsCheckboxView)
        stackView.addArrangedSubview(showBadgeCheckboxView)
        stackView.addArrangedSubview(showFilenameCheckboxView)
        stackView.addArrangedSubview(filenameSizeTextField)
        stackView.addArrangedSubview(cellPaddingTextField)
        stackView.addArrangedSubview(borderRadiusInGridTextField)
        stackView.addArrangedSubview(borderRadiusTextField)
        stackView.addArrangedSubview(borderThicknessTextField)
        stackView.addArrangedSubview(lineSpaceAdjustTextField)
        stackView.addArrangedSubview(showShadowCheckboxView)
        
        // Create buttons
        let buttonStackView = NSStackView()
        buttonStackView.orientation = .horizontal
        buttonStackView.spacing = 20
        
        let okButton = NSButton(title: NSLocalizedString("OK", comment: "确定"), target: self, action: #selector(okButtonPressed))
        let cancelButton = NSButton(title: NSLocalizedString("Cancel", comment: "取消"), target: self, action: #selector(cancelButtonPressed))
        let resetButton = NSButton(title: NSLocalizedString("Reset", comment: "重置"), target: self, action: #selector(resetButtonPressed))
        
        buttonStackView.addArrangedSubview(okButton)
        buttonStackView.addArrangedSubview(resetButton)
        buttonStackView.addArrangedSubview(cancelButton)
        
        stackView.addArrangedSubview(buttonStackView)
        
        // Add stack view to custom view
        customView.addSubview(stackView)
        
        // Set custom view as the content view
        self.contentView = customView
        
        // Add constraints
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: customView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: customView.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: customView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: customView.trailingAnchor, constant: -20)
        ])
    }
    
    // Helper function to create labeled text fields
    private func createLabeledTextField(label: String, defaultValue: String) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        
        let textField = NSTextField(string: defaultValue)
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = NSStackView(views: [labelView, textField])
        stackView.orientation = .horizontal
        stackView.spacing = 10
        
        NSLayoutConstraint.activate([
            labelView.widthAnchor.constraint(equalToConstant: 320),
            textField.widthAnchor.constraint(equalToConstant: 320)
        ])
        
        return stackView
    }
    
    // Helper function to create labeled checkbox
    private func createLabeledCheckbox(label: String, isChecked: Bool) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.state = isChecked ? .on : .off
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = NSStackView(views: [labelView, checkbox])
        stackView.orientation = .horizontal
        stackView.spacing = 10
        
        NSLayoutConstraint.activate([
            labelView.widthAnchor.constraint(equalToConstant: 320),
            checkbox.widthAnchor.constraint(equalToConstant: 320)
        ])
        
        return stackView
    }
    
    @objc func okButtonPressed() {
        guard let contentView = self.contentView else { return }
        let stackView = contentView.subviews[0] as! NSStackView
        
        let windowTitleFullPathCheckbox = (stackView.arrangedSubviews[2] as! NSStackView).views[1] as! NSButton
        let windowTitleStatsCheckbox = (stackView.arrangedSubviews[3] as! NSStackView).views[1] as! NSButton
        let showBadgeCheckbox = (stackView.arrangedSubviews[4] as! NSStackView).views[1] as! NSButton
        let showFilenameCheckbox = (stackView.arrangedSubviews[5] as! NSStackView).views[1] as! NSButton
        let filenameSizeTextField = (stackView.arrangedSubviews[6] as! NSStackView).views[1] as! NSTextField
        let cellPaddingTextField = (stackView.arrangedSubviews[7] as! NSStackView).views[1] as! NSTextField
        let borderRadiusInGridTextField = (stackView.arrangedSubviews[8] as! NSStackView).views[1] as! NSTextField
        let borderRadiusTextField = (stackView.arrangedSubviews[9] as! NSStackView).views[1] as! NSTextField
        let borderThicknessTextField = (stackView.arrangedSubviews[10] as! NSStackView).views[1] as! NSTextField
        let lineSpaceAdjustTextField = (stackView.arrangedSubviews[11] as! NSStackView).views[1] as! NSTextField
        let showShadowCheckbox = (stackView.arrangedSubviews[12] as! NSStackView).views[1] as! NSButton
        
        self.isWindowTitleUseFullPath = windowTitleFullPathCheckbox.state == .on
        self.isWindowTitleShowStatistics = windowTitleStatsCheckbox.state == .on
        self.isShowThumbnailBadge = showBadgeCheckbox.state == .on
        self.isShowThumbnailFilename = showFilenameCheckbox.state == .on
        self.thumbnailFilenameSize = Double(filenameSizeTextField.stringValue) ?? initialThumbnailFilenameSize
        self.thumbnailCellPadding = Double(cellPaddingTextField.stringValue) ?? initialThumbnailCellPadding
        self.thumbnailBorderRadiusInGrid = Double(borderRadiusInGridTextField.stringValue) ?? initialThumbnailBorderRadiusInGrid
        self.thumbnailBorderRadius = Double(borderRadiusTextField.stringValue) ?? initialThumbnailBorderRadius
        self.thumbnailBorderThickness = Double(borderThicknessTextField.stringValue) ?? initialThumbnailBorderThickness
        self.thumbnailLineSpaceAdjust = Double(lineSpaceAdjustTextField.stringValue) ?? initialThumbnailLineSpaceAdjust
        self.thumbnailShowShadow = showShadowCheckbox.state == .on
        
        self.sheetParent?.endSheet(self, returnCode: .OK)
    }
    
    @objc func cancelButtonPressed() {
        self.sheetParent?.endSheet(self, returnCode: .cancel)
    }
    
    @objc func resetButtonPressed() {
        guard let contentView = self.contentView else { return }
        let stackView = contentView.subviews[0] as! NSStackView
        
        let windowTitleFullPathCheckbox = (stackView.arrangedSubviews[2] as! NSStackView).views[1] as! NSButton
        let windowTitleStatsCheckbox = (stackView.arrangedSubviews[3] as! NSStackView).views[1] as! NSButton
        let showBadgeCheckbox = (stackView.arrangedSubviews[4] as! NSStackView).views[1] as! NSButton
        let showFilenameCheckbox = (stackView.arrangedSubviews[5] as! NSStackView).views[1] as! NSButton
        let filenameSizeTextField = (stackView.arrangedSubviews[6] as! NSStackView).views[1] as! NSTextField
        let cellPaddingTextField = (stackView.arrangedSubviews[7] as! NSStackView).views[1] as! NSTextField
        let borderRadiusInGridTextField = (stackView.arrangedSubviews[8] as! NSStackView).views[1] as! NSTextField
        let borderRadiusTextField = (stackView.arrangedSubviews[9] as! NSStackView).views[1] as! NSTextField
        let borderThicknessTextField = (stackView.arrangedSubviews[10] as! NSStackView).views[1] as! NSTextField
        let lineSpaceAdjustTextField = (stackView.arrangedSubviews[11] as! NSStackView).views[1] as! NSTextField
        let showShadowCheckbox = (stackView.arrangedSubviews[12] as! NSStackView).views[1] as! NSButton
        
        // Reset values to initial values
        windowTitleFullPathCheckbox.state = initialWindowTitleUseFullPath ? .on : .off
        windowTitleStatsCheckbox.state = initialWindowTitleShowStatistics ? .on : .off
        showBadgeCheckbox.state = initialShowThumbnailBadge ? .on : .off
        showFilenameCheckbox.state = initialShowThumbnailFilename ? .on : .off
        filenameSizeTextField.stringValue = String(initialThumbnailFilenameSize)
        cellPaddingTextField.stringValue = String(initialThumbnailCellPadding)
        borderRadiusInGridTextField.stringValue = String(initialThumbnailBorderRadiusInGrid)
        borderRadiusTextField.stringValue = String(initialThumbnailBorderRadius)
        borderThicknessTextField.stringValue = String(initialThumbnailBorderThickness)
        lineSpaceAdjustTextField.stringValue = String(initialThumbnailLineSpaceAdjust)
        showShadowCheckbox.state = initialThumbnailShowShadow ? .on : .off
    }
}


// Function to display the panel as a sheet
func showThumbnailOptionsPanel(on parentWindow: NSWindow, completion: @escaping (Bool, Bool, Bool, Bool, Double, Double, Double, Double, Double, Double, Bool) -> Void) {
    let thumbnailOptionsWindow = ThumbnailOptionsWindow()
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    parentWindow.beginSheet(thumbnailOptionsWindow) { response in
        getMainViewController()!.publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
        if response == .OK {
            completion(thumbnailOptionsWindow.isWindowTitleUseFullPath,
                      thumbnailOptionsWindow.isWindowTitleShowStatistics,
                      thumbnailOptionsWindow.isShowThumbnailBadge,
                      thumbnailOptionsWindow.isShowThumbnailFilename,
                      thumbnailOptionsWindow.thumbnailFilenameSize,
                      thumbnailOptionsWindow.thumbnailCellPadding,
                      thumbnailOptionsWindow.thumbnailBorderRadiusInGrid,
                      thumbnailOptionsWindow.thumbnailBorderRadius,
                      thumbnailOptionsWindow.thumbnailBorderThickness,
                      thumbnailOptionsWindow.thumbnailLineSpaceAdjust,
                      thumbnailOptionsWindow.thumbnailShowShadow)
        } else {
            // Handle cancellation if needed
            log("User canceled custom style window.")
        }
    }
}

func triggerFinderSound() {
    let fileManager = FileManager.default
    
    do {
        // 获取应用支持目录路径
        let appSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        // 创建应用专用目录
        let appDirectory = appSupportDirectory.appendingPathComponent("FlowVision", isDirectory: true)
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        // 创建临时文件路径
        let tempFilePath = appDirectory.appendingPathComponent("tempFileForSound.txt")
        
        // 创建临时文件
        if !fileManager.fileExists(atPath: tempFilePath.path) {
            fileManager.createFile(atPath: tempFilePath.path, contents: nil, attributes: nil)
        }
        
        // 使用 AppleScript 移动文件以触发 Finder 提示音
        let script = """
        tell application "Finder"
            try
                set tempFile to POSIX file "\(tempFilePath.path)" as alias
                -- 移动文件到自身位置以触发提示音
                move tempFile to container of tempFile
            end try
        end tell
        """
        
        // 执行 AppleScript
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                log("AppleScript Error: \(error)")
            }
        }
    } catch {
        log("Error setting up directories: \(error)")
    }
}

func resolveRelativePath(basePath: String, relativePath: String) -> String? {
    // 移除开头的 file:// 并解码
    var base = basePath.replacingOccurrences(of: "file://", with: "").removingPercentEncoding ?? basePath
    var relative = relativePath.removingPercentEncoding ?? relativePath
    
    // 处理波浪号(~)表示用户主目录
    if relative.hasPrefix("~") {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        relative = relative.replacingOccurrences(of: "~", with: homeDir, options: [.anchored])
    }
    
    // 如果相对路径以/开头,则直接返回
    if relative.hasPrefix("/") {
        return relative
    }
    
    // 确保基础路径不以/结尾
    if base.hasSuffix("/") {
        base = String(base.dropLast())
    }
    
    // 将路径分割成组件
    var components = base.split(separator: "/").map(String.init)
    let relativeComponents = relative.split(separator: "/").map(String.init)
    
    // 处理每个相对路径组件
    for component in relativeComponents {
        switch component {
        case "..":
            if !components.isEmpty {
                components.removeLast()
            } else {
                return nil // 试图超出根目录
            }
        case ".", "":
            continue
        default:
            components.append(component)
        }
    }
    
    // 重新组合路径
    let resolvedPath = "/" + components.joined(separator: "/")
    
    // 如果原始相对路径以/结尾,则保留
    let shouldAddSlash = relative.hasSuffix("/")
    return resolvedPath + (shouldAddSlash ? "/" : "")
}

// 将汉字转换为全拼
func chineseToFullPinyin(_ chinese: String) -> String {
    let mutableString = NSMutableString(string: chinese) as CFMutableString
    // 将汉字转换为拼音
    if CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false) {
        // 去除声调
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
    }
    return mutableString as String
}

// 将汉字转换为拼音首字母
func chineseToPinyinInitials(_ chinese: String) -> String {
    let mutableString = NSMutableString(string: chinese) as CFMutableString
    // 将汉字转换为拼音
    if CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false) {
        // 去除声调
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
    }
    
    // 获取每个拼音的首字母
    let pinyinString = mutableString as String
    let words = pinyinString.components(separatedBy: " ")
    let initials = words.compactMap { $0.first }.map { String($0) }
    
    return initials.joined()
}

// 判断字符是否为汉字
func isChineseCharacter(_ character: Character) -> Bool {
    return character.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
}

// 处理字符串，转换其中的汉字部分
func convertToPinyin(_ input: String, toPinyinFull: Bool) -> String {
    var result = ""
    var currentChineseSegment = ""
    
    for character in input {
        if isChineseCharacter(character) {
            currentChineseSegment.append(character)
        } else {
            // Convert current Chinese segment if exists
            if !currentChineseSegment.isEmpty {
                if toPinyinFull {
                    result += chineseToFullPinyin(currentChineseSegment).replacingOccurrences(of: " ", with: "")
                } else {
                    result += chineseToPinyinInitials(currentChineseSegment)
                }
                currentChineseSegment = ""
            }
            // Append non-Chinese character directly
            result.append(character)
        }
    }
    
    // Handle any remaining Chinese segment
    if !currentChineseSegment.isEmpty {
        if toPinyinFull {
            result += chineseToFullPinyin(currentChineseSegment).replacingOccurrences(of: " ", with: "")
        } else {
            result += chineseToPinyinInitials(currentChineseSegment)
        }
    }
    
    return result
}
