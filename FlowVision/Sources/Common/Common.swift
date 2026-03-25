//
//  Common.swift
//  FlowVision
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
    // Store RawRepresentable enum with Int raw value
    func setEnum<T: RawRepresentable>(_ value: T, forKey key: String) where T.RawValue == Int {
        self.set(value.rawValue, forKey: key)
    }
    
    // 读取 Int 类型的 RawRepresentable 枚举
    // Read RawRepresentable enum with Int raw value
    func enumValue<T: RawRepresentable>(forKey key: String) -> T? where T.RawValue == Int {
        let rawValue = self.object(forKey: key) as? Int
        return rawValue.flatMap { T(rawValue: $0) }
    }
}

func getFileSchemeAbsPath(_ path: String) -> String {
    var pathNoScheme = path.hasPrefix("file://") ? String(path.dropFirst("file://".count)) : path
    pathNoScheme = pathNoScheme.removingPercentEncoding!.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    let pathWithScheme = "file://" + pathNoScheme
    return pathWithScheme
}

func getFileSchemeAbsParentFolderPath(_ path: String) -> String {
    var pathNoScheme = path.hasPrefix("file://") ? String(path.dropFirst("file://".count)) : path
    pathNoScheme = pathNoScheme.removingPercentEncoding!.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    let pathWithScheme = "file://" + pathNoScheme
    guard let url=URL(string: pathWithScheme) else { return "" }
    var folderPath=url.deletingLastPathComponent().absoluteString
    return folderPath
}

func attributedStringWithSymbols(_ symbols: [String]) -> NSAttributedString {
    let attributedString = NSMutableAttributedString()
    
    for symbol in symbols {
        if let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = symbolImage
            
            // 调整图片高度以使其居中
            // Adjust image height to center it
            let imageString = NSAttributedString(attachment: attachment)
            let mutableImageString = NSMutableAttributedString(attributedString: imageString)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            mutableImageString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: imageString.length))
            
            attributedString.append(mutableImageString)
            
            // 添加一些间距
            // Add some spacing
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

func showConfirmation(title: String, message: String, confirmButtonText: String? = nil, cancelButtonText: String? = nil) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: confirmButtonText ?? NSLocalizedString("OK", comment: "确定"))
    alert.addButton(withTitle: cancelButtonText ?? NSLocalizedString("Cancel", comment: "取消"))
    alert.icon = NSImage(named: NSImage.cautionName)
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled = false
    let response = alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
    return response == .alertFirstButtonReturn
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
    // alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.icon = NSImage(named: NSImage.infoName)
    
    // 设置对话框宽度
    // Set dialog width
    let textField = NSTextView()
    textField.isEditable = false
    textField.backgroundColor = .clear
    textField.isSelectable = true
    textField.textColor = NSColor.headerTextColor
    
    // 创建段落样式并设置行间距
    // Create paragraph style and set line spacing
    let paragraphStyle = NSMutableParagraphStyle()
    // 设置行间距
    // Set line spacing
    paragraphStyle.lineSpacing = 1.2
    
    // 使用富文本设置内容和样式
    // Use rich text to set content and style
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
    // Calculate text height
    let contentSize = textField.layoutManager?.usedRect(for: textField.textContainer!).size ?? .zero
    // 设置最小50和最大600的高度限制
    // Set minimum 50 and maximum 600 height limit
    let height = min(max(contentSize.height, 50), 600)
    
    textField.frame = NSRect(x: 0, y: 0, width: width, height: height)
    alert.accessoryView = textField
    
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
}

func showInformationLong(title: String, message: String, width: CGFloat = 400) {
    let attributedMessage = parseSimpleMarkup(message, fontSize: 11.5)
    showInformationLong(title: title, attributedMessage: attributedMessage, width: width)
}

/// 解析简单标记文本，支持 **加粗**
func parseSimpleMarkup(_ text: String, fontSize: CGFloat) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 1.2
    let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize),
        .foregroundColor: NSColor.headerTextColor,
        .paragraphStyle: paragraphStyle
    ]
    let boldAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: NSColor.headerTextColor,
        .paragraphStyle: paragraphStyle
    ]
    
    let result = NSMutableAttributedString()
    let scanner = Scanner(string: text)
    scanner.charactersToBeSkipped = nil
    
    while !scanner.isAtEnd {
        if let plain = scanner.scanUpToString("**") {
            result.append(NSAttributedString(string: plain, attributes: baseAttributes))
        }
        if scanner.scanString("**") != nil {
            if let bold = scanner.scanUpToString("**") {
                result.append(NSAttributedString(string: bold, attributes: boldAttributes))
                scanner.scanString("**")
            }
        }
    }
    return result
}

func showInformationLong(title: String, attributedMessage: NSAttributedString, width: CGFloat = 400) {
    let alert = NSAlert()
    alert.messageText = title
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.icon = NSImage(named: NSImage.infoName)
    
    // 创建滚动视图
    // Create scroll view
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    // 设置滚动视图背景为透明
    // Set scroll view background to transparent
    scrollView.drawsBackground = false
    
    // 设置文本视图
    // Set up text view
    let textField = NSTextView(frame: NSRect(x: 0, y: 0, width: width - 20, height: 0))
    textField.isEditable = false
    // 设置文本视图背景为透明
    // Set text view background to transparent
    textField.backgroundColor = .clear
    // 确保文本视图不绘制背景
    // Ensure text view doesn't draw background
    textField.drawsBackground = false
    textField.isSelectable = true
    textField.textColor = NSColor.headerTextColor
    
    textField.textStorage?.setAttributedString(attributedMessage)
    
    // 配置文本视图容器
    // Configure text view container
    textField.isVerticallyResizable = true
    textField.isHorizontallyResizable = false
    textField.textContainer?.widthTracksTextView = true
    textField.textContainer?.containerSize = NSSize(width: width - 20, height: CGFloat.greatestFiniteMagnitude)
    textField.layoutManager?.ensureLayout(for: textField.textContainer!)
    
    // 设置滚动视图的大小
    // Set scroll view size
    let contentSize = textField.layoutManager?.usedRect(for: textField.textContainer!).size ?? .zero
    // 添加一点额外的高度来防止不必要的滚动条
    // Add a bit of extra height to prevent unnecessary scrollbar
    // 添加5个点的额外空间
    // Add 5 points of extra space
    let height = min(max(contentSize.height + 5, 50), 300)
    scrollView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    
    // 设置文本视图的frame，同样添加额外空间
    // Set text view frame, also add extra space
    textField.frame = NSRect(x: 0, y: 0, width: width - 20, height: contentSize.height + 5)
    
    // 设置滚动视图
    // Set up scroll view
    scrollView.documentView = textField
    
    // 设置为警告框的附件视图
    // Set as alert accessory view
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
    // Create an alert dialog
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Rename", comment: "重命名")
    alert.informativeText = NSLocalizedString("New name for", comment: "请输入新的名称用于") + " \(urls[0].lastPathComponent):"
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
    // 设置系统通知图标
    // Set system notification icon
    alert.icon = NSImage(named: NSImage.infoName)
    
    // 添加一个文本输入框到警告对话框中
    // Add a text input field to the alert dialog
    let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    inputTextField.stringValue = urls[0].lastPathComponent
    if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
        textFieldCell.usesSingleLineMode = true
        textFieldCell.wraps = false
        textFieldCell.isScrollable = true
    }
    alert.accessoryView = inputTextField
    
    // 显示对话框
    // Show dialog
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled = false
    DispatchQueue.main.async {
        // 判断是否是文件夹
        // Check if it's a folder
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &isDirectory)
        
        _ = inputTextField.becomeFirstResponder()
        if isDirectory.boolValue {
            // 如果是文件夹，选中全部内容
            // If it's a folder, select all content
            inputTextField.selectText(nil)
        } else {
            // 如果是文件，选中文件名不包含扩展名的部分
            // If it's a file, select the filename part without extension
            let fileName = urls[0].deletingPathExtension().lastPathComponent
            inputTextField.currentEditor()?.selectedRange = NSRange(location: 0, length: fileName.count)
        }
    }
    let response = alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
    
    // 根据用户的选择处理结果
    // Process result based on user's choice
    // OK按钮
    // OK button
    if response == .alertFirstButtonReturn {
        let newBaseName = inputTextField.stringValue
        
        if newBaseName != "" {

            // 记录操作到日志
            // Log operation to log
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
            
            // 第一步：生成最终目标名字列表
            // Step 1: Generate final target name list
            var finalNames: [(originalUrl: URL, finalUrl: URL)] = []
            var nameIndex = 1
            
            for originalUrl in urls {
                var newName = newBaseName
                // 批量重命名
                // Batch rename
                if urls.count > 1 {
                    var newUrl: URL
                    var collision = false
                    repeat {
                        // 如果有扩展名，在扩展名前添加序号
                        // If there's an extension, add index before extension
                        if let ext = originalUrl.pathExtension.isEmpty ? nil : originalUrl.pathExtension {
                            let nameWithoutExt = (newBaseName as NSString).deletingPathExtension
                            newName = "\(nameWithoutExt)_\(nameIndex).\(ext)"
                        } else {
                            newName = "\(newBaseName)_\(nameIndex)"
                        }
                        newUrl = originalUrl.deletingLastPathComponent().appendingPathComponent(newName)
                        nameIndex += 1
                        
                        // 检查是否存在同名文件，但排除当前待重命名列表中的文件
                        // Check if file with same name exists, but exclude files in current rename list
                        if FileManager.default.fileExists(atPath: newUrl.path) &&
                             !urls.contains(where: { $0.path.lowercased() == newUrl.path.lowercased() })
                        {
                            collision = true
                            
                            let alert = NSAlert()
                            alert.messageText = NSLocalizedString("File Already Exists", comment: "文件已存在")
                            alert.informativeText = NSLocalizedString("file-exists-continue-batch-rename", comment: "批量重命名的序号与已有文件重名，是否继续?")
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: NSLocalizedString("Continue", comment: "继续"))
                            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
                            
                            if alert.runModal() == .alertSecondButtonReturn {
                                return false
                            }
                        }else{
                            collision = false
                        }
                    } while collision
                }else{
                    // 单个重命名
                    // Single rename
                    let newUrl = originalUrl.deletingLastPathComponent().appendingPathComponent(newName)
                    if FileManager.default.fileExists(atPath: newUrl.path) {
                        showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                        allSuccess = false
                        return false
                    }
                }
                
                let finalUrl = originalUrl.deletingLastPathComponent().appendingPathComponent(newName)
                finalNames.append((originalUrl: originalUrl, finalUrl: finalUrl))
            }
            
            // 第二步：将所有文件改成临时文件名
            // Step 2: Rename all files to temporary names
            var tempNames: [(tempUrl: URL, finalUrl: URL)] = []
            for (index, item) in finalNames.enumerated() {
                let tempName = "temp_rename_\(UUID().uuidString)"
                let tempUrl = item.originalUrl.deletingLastPathComponent().appendingPathComponent(tempName)
                
                do {
                    try FileManager.default.moveItem(at: item.originalUrl, to: tempUrl)
                    tempNames.append((tempUrl: tempUrl, finalUrl: item.finalUrl))
                } catch {
                    // 如果临时重命名失败，回滚之前的临时重命名
                    // If temporary rename fails, rollback previous temporary renames
                    for prevTemp in tempNames {
                        try? FileManager.default.moveItem(at: prevTemp.tempUrl, to: finalNames[tempNames.count].originalUrl)
                    }
                    log("Failed to create temp name: \(error)", level: .error)
                    allSuccess = false
                    break
                }
            }
            
            // 第三步：将临时文件名改成最终文件名
            // Step 3: Rename temporary files to final names
            if allSuccess {
                for item in tempNames {
                    do {
                        // 文件更改计数
                        // File change count
                        getMainViewController()?.publicVar.fileChangedCount += 1
                        
                        try FileManager.default.moveItem(at: item.tempUrl, to: item.finalUrl)
                        log("File renamed to \(item.finalUrl.lastPathComponent)")
                    } catch {
                        log("Failed to rename file: \(error)", level: .error)
                        allSuccess = false
                        // 这里不需要回滚，因为用户可以通过临时文件找回
                        // No need to rollback here, as user can recover through temporary files
                        break
                    }
                }
            }
            
            if allSuccess && !finalNames.isEmpty {
                EnhancedIndex.handleFilesMoved(finalNames.map { (oldPath: $0.originalUrl.path, newPath: $0.finalUrl.path) })
            }

            // 针对递归模式处理
            // Handle recursive mode
            if let viewController = getMainViewController() {
                if viewController.publicVar.isRecursiveMode {
                    viewController.fileDB.lock()
                    let ifRefresh = viewController.fileDB.db[SortKeyDir(viewController.fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
                    viewController.fileDB.unlock()
                    if ifRefresh {
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
// func isExternalVolume(_ path: String) -> Bool {
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
// }
//
//// 接受URL路径的函数
// func isExternalVolume(_ url: URL) -> Bool {
//    // 标准化URL路径
//    let standardizedPath = url.standardized.path
//
//    // 检查路径是否以/Volumes/开头
//    return standardizedPath.hasPrefix("/Volumes/")
// }

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
        
        // log("======updateExternalVolumes=====")
        
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
        // Update external volume list and check again
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
    // Use NSAppleScript to execute Apple events
    let script = NSAppleScript(source: """
        tell application "Finder"
            get name of startup disk
        end tell
    """)
    
    if let script = script {
        let result = script.executeAndReturnError(&error)
        
        if let error = error {
            log("Failed to request automation permission: \(error)", level: .warn)
            // Request automation permission failed
        } else {
            log("Successfully requested automation permission: \(result.stringValue ?? "")")
            // Request automation permission succeeded
            return true
        }
    } else {
        log("Unable to create AppleScript instance", level: .error)
        // Unable to create AppleScript instance
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
        // Save current graphics context state
        let graphicsContext = NSGraphicsContext.current?.cgContext
        graphicsContext?.saveGState()
        
        // 判断是否需要翻转
        // Determine if flipping is needed
        if !(contentToPrint is NSImageView) {
            // 翻转和变换坐标系
            // Flip and transform coordinate system
            graphicsContext?.translateBy(x: 0, y: contentToPrint.bounds.height)
            graphicsContext?.scaleBy(x: 1.0, y: -1.0)
        }
        
        // 绘制内容
        // Draw content
        contentToPrint.layer?.render(in: graphicsContext!)
        
        // 恢复图形上下文状态
        // Restore graphics context state
        graphicsContext?.restoreGState()
    }
}

func printContent(_ content: NSView) {
    let printView = PrintView(content: content)
    let printInfo = NSPrintInfo.shared
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .fit

    let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
    printOperation.printPanel.options.insert(.showsPaperSize)
    printOperation.printPanel.options.insert(.showsOrientation)
    printOperation.printPanel.options.insert(.showsScaling)
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
    // Create a new NSImageView as snapshot container
    let snapshotView = NSImageView(frame: view.bounds)
    
    // 创建一个位图上下文来渲染视图
    // Create a bitmap context to render the view
    let image = NSImage(size: view.bounds.size)
    image.lockFocus()
    
    if let context = NSGraphicsContext.current?.cgContext {
        // 保存上下文状态
        // Save context state
        context.saveGState()
        
        // 判断是否需要翻转坐标系
        // Determine if coordinate system needs to be flipped
        if !(view is NSImageView) {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1.0, y: -1.0)
        }
        
        // 使用layer渲染视图内容
        // Use layer to render view content
        view.layer?.render(in: context)
        
        // 恢复上下文状态
        // Restore context state
        context.restoreGState()
    }
    
    image.unlockFocus()
    
    // 设置快照图像
    // Set snapshot image
    snapshotView.image = image
    
    return snapshotView
}

func captureSnapshot(of view: NSView) -> NSView? {
    guard let window = view.window else { return nil }
    
    // 将视图坐标转换为屏幕坐标
    // Convert view coordinates to screen coordinates
    let rect = view.convert(view.bounds, to: nil)
    var screenRect = window.convertToScreen(rect)

    // 将y坐标转换为从上到下
    // Convert y coordinate from top to bottom
    if screenRect.origin.y == window.frame.origin.y {
        if let screen = NSScreen.screens.first {
            screenRect.origin.y = screen.frame.height - screenRect.origin.y - screenRect.height
        }
    }

    // 获取当前窗口的windowNumber
    // Get current window's windowNumber
    let windowID = window.windowNumber
    
    // 只捕获指定窗口的内容
    // Only capture content of specified window
    // 改为只包含指定窗口
    // Changed to only include specified window
    // 指定窗口ID
    // Specify window ID
    guard let cgImage = CGWindowListCreateImage(
        screenRect,
        .optionIncludingWindow,
        CGWindowID(windowID),
        .bestResolution
    ) else { return nil }
    
    let image = NSImage(cgImage: cgImage, size: view.bounds.size)
    
    // 保存图片用于调试
    // Save image for debugging
//        if let tiffData = image.tiffRepresentation,
//           let bitmapImage = NSBitmapImageRep(data: tiffData),
//           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
//            try? pngData.write(to: URL(fileURLWithPath: "/tmp/snapshot.png"))
//        }
    
    let snapshotView = NSImageView(frame: view.bounds)
    snapshotView.image = image
    return snapshotView
}

func triggerFinderSound() {
    let fileManager = FileManager.default
    
    do {
        // 获取应用支持目录路径
        // Get application support directory path
        let appSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        // 创建应用专用目录
        // Create application-specific directory
        let appDirectory = appSupportDirectory.appendingPathComponent("FlowVision", isDirectory: true)
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        // 创建临时文件路径
        // Create temporary file path
        let tempFilePath = appDirectory.appendingPathComponent("TempFileForSound.txt")
        
        // 创建临时文件
        // Create temporary file
        if !fileManager.fileExists(atPath: tempFilePath.path) {
            fileManager.createFile(atPath: tempFilePath.path, contents: nil, attributes: nil)
        }
        
        // 使用 AppleScript 移动文件以触发 Finder 提示音
        // Use AppleScript to move file to trigger Finder sound
        let script = """
        tell application "Finder"
            try
                set tempFile to POSIX file "\(tempFilePath.path)" as alias
                -- 移动文件到自身位置以触发提示音
                -- Move file to its own location to trigger sound
                move tempFile to container of tempFile
            end try
        end tell
        """
        
        // 执行 AppleScript
        // Execute AppleScript
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
    // Remove leading file:// and decode
    var base = basePath.replacingOccurrences(of: "file://", with: "").removingPercentEncoding ?? basePath
    var relative = relativePath.removingPercentEncoding ?? relativePath
    
    // 处理波浪号(~)表示用户主目录
    // Handle tilde (~) representing user home directory
    if relative.hasPrefix("~") {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        relative = relative.replacingOccurrences(of: "~", with: homeDir, options: [.anchored])
    }
    
    // 如果相对路径以/开头,则直接返回
    // If relative path starts with /, return directly
    if relative.hasPrefix("/") {
        return relative
    }
    
    // 确保基础路径不以/结尾
    // Ensure base path doesn't end with /
    if base.hasSuffix("/") {
        base = String(base.dropLast())
    }
    
    // 将路径分割成组件
    // Split path into components
    var components = base.split(separator: "/").map(String.init)
    let relativeComponents = relative.split(separator: "/").map(String.init)
    
    // 处理每个相对路径组件
    // Process each relative path component
    for component in relativeComponents {
        switch component {
        case "..":
            if !components.isEmpty {
                components.removeLast()
            } else {
                // 试图超出根目录
                // Attempting to go beyond root directory
                return nil
            }
        case ".", "":
            continue
        default:
            components.append(component)
        }
    }
    
    // 重新组合路径
    // Recombine path
    let resolvedPath = "/" + components.joined(separator: "/")
    
    // 如果原始相对路径以/结尾,则保留
    // If original relative path ends with /, keep it
    let shouldAddSlash = relative.hasSuffix("/")
    return resolvedPath + (shouldAddSlash ? "/" : "")
}

// 将汉字转换为全拼
// Convert Chinese characters to full pinyin
func chineseToFullPinyin(_ chinese: String) -> String {
    let mutableString = NSMutableString(string: chinese) as CFMutableString
    // 将汉字转换为拼音
    // Convert Chinese characters to pinyin
    if CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false) {
        // 去除声调
        // Remove tone marks
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
    }
    return mutableString as String
}

// 将汉字转换为拼音首字母
// Convert Chinese characters to pinyin initials
func chineseToPinyinInitials(_ chinese: String) -> String {
    let mutableString = NSMutableString(string: chinese) as CFMutableString
    // 将汉字转换为拼音
    // Convert Chinese characters to pinyin
    if CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false) {
        // 去除声调
        // Remove tone marks
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
    }
    
    // 获取每个拼音的首字母
    // Get first letter of each pinyin
    let pinyinString = mutableString as String
    let words = pinyinString.components(separatedBy: " ")
    let initials = words.compactMap { $0.first }.map { String($0) }
    
    return initials.joined()
}

// 判断字符是否为汉字
// Determine if character is Chinese
func isChineseCharacter(_ character: Character) -> Bool {
    return character.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
}

// 处理字符串，转换其中的汉字部分
// Process string, convert Chinese character parts
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
