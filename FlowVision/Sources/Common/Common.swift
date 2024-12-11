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

func showAlert(message: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.icon = NSImage(named: NSImage.cautionName)
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled=true
}

func showInformation(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.icon = NSImage(named: NSImage.infoName)
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled=true
}

func showInformationCopy(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("Copy", comment: "复制"))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
    alert.icon = NSImage(named: NSImage.infoName)
    
    getMainViewController()!.publicVar.isKeyEventEnabled = false
    let response = alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled = true

    if response == .alertFirstButtonReturn {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)
    } else if response == .alertSecondButtonReturn {
        // cancel
    }
}

func renameAlert(url: URL) -> Bool {
    let originalUrl = url
    
    // 创建一个警告对话框
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Rename", comment: "重命名")
    alert.informativeText = NSLocalizedString("new-name-for", comment: "请输入新的名称用于") + " \(originalUrl.lastPathComponent):"
    alert.alertStyle = .informational
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
    alert.icon = NSImage(named: NSImage.infoName)// 设置系统通知图标
    
    // 添加一个文本输入框到警告对话框中
    let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    inputTextField.stringValue = originalUrl.lastPathComponent
    if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
        textFieldCell.usesSingleLineMode = true
        textFieldCell.wraps = false
        textFieldCell.isScrollable = true
    }
    alert.accessoryView = inputTextField
    
    // 显示对话框
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    DispatchQueue.main.async {
        // 判断是否是文件夹
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: originalUrl.path, isDirectory: &isDirectory)
        
        _ = inputTextField.becomeFirstResponder()
        if isDirectory.boolValue {
            // 如果是文件夹，选中全部内容
            inputTextField.selectText(nil)
        } else {
            // 如果是文件，选中文件名不包含扩展名的部分
            let fileName = originalUrl.deletingPathExtension().lastPathComponent
            inputTextField.currentEditor()?.selectedRange = NSRange(location: 0, length: fileName.count)
        }
    }
    let response = alert.runModal()
    getMainViewController()!.publicVar.isKeyEventEnabled=true
    
    // 根据用户的选择处理结果
    if response == .alertFirstButtonReturn { // OK按钮
        let newName = inputTextField.stringValue
        
        if newName != "" {
            // 获取新的完整文件路径
            let newUrl = originalUrl.deletingLastPathComponent().appendingPathComponent(newName)
            
            // 检查是否存在同名文件
            if FileManager.default.fileExists(atPath: newUrl.path) {
                if originalUrl.path != newUrl.path {
                    showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                }
            }else{
                // 执行重命名操作
                do {
                    // 文件更改计数
                    getMainViewController()?.publicVar.fileChangedCount += 1
                    
                    try FileManager.default.moveItem(at: originalUrl, to: newUrl)
                    log("File renamed to \(newName)")
                    return true
                } catch {
                    log("Failed to rename file: \(error)")
                }
            }
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

class ThumbnailOptionsWindow: NSWindow {
    // Define initial values as constants
    private let initialShowThumbnailFilename: Bool = true
    private let initialThumbnailBorderThickness: Double = 6.0
    private let initialThumbnailCellPadding: Double = 5.0
    private let initialThumbnailBorderRadius: Double = 5.0
    private let initialThumbnailFilenameSize: Double = 12.0
    
    // Variables to store current settings
    var isShowThumbnailFilename: Bool
    var thumbnailBorderThickness: Double
    var thumbnailCellPadding: Double
    var thumbnailBorderRadius: Double
    var thumbnailFilenameSize: Double
    
    init() {
        let windowSize = NSSize(width: 400, height: 340)
        let windowRect = NSRect(origin: .zero, size: windowSize)
        
        // Get current values
        let profile = getMainViewController()!.publicVar.profile
        isShowThumbnailFilename = profile.isShowThumbnailFilename
        thumbnailBorderThickness = profile.ThumbnailBorderThickness
        thumbnailCellPadding = profile.ThumbnailCellPadding
        thumbnailBorderRadius = profile.ThumbnailBorderRadius
        thumbnailFilenameSize = profile.ThumbnailFilenameSize
        
        super.init(contentRect: windowRect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.title = NSLocalizedString("Thumbnail Options", comment: "缩略图选项")
        
        // Create a custom view with a glass-like effect
        let customView = NSVisualEffectView(frame: windowRect)
        customView.material = .hudWindow
        customView.blendingMode = .behindWindow
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
        let showFilenameCheckboxView = createLabeledCheckbox(label: NSLocalizedString("Show Thumbnail Filename", comment: "显示缩略图文件名"), isChecked: isShowThumbnailFilename)
        let borderThicknessTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Border Thickness", comment: "缩略图边框厚度"), defaultValue: String(thumbnailBorderThickness))
        let cellPaddingTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Cell Padding", comment: "缩略图单元格外边距"), defaultValue: String(thumbnailCellPadding))
        let borderRadiusTextField = createLabeledTextField(label: NSLocalizedString("Thumbnail Corner Radius", comment: "缩略图圆角半径"), defaultValue: String(thumbnailBorderRadius))
        let filenameSizeTextField = createLabeledTextField(label: NSLocalizedString("Filename Font Size", comment: "文件名字体大小"), defaultValue: String(thumbnailFilenameSize))
        
        // Add subviews to stack view
        stackView.addArrangedSubview(showFilenameCheckboxView)
        stackView.addArrangedSubview(borderThicknessTextField)
        stackView.addArrangedSubview(cellPaddingTextField)
        stackView.addArrangedSubview(borderRadiusTextField)
        stackView.addArrangedSubview(filenameSizeTextField)
        
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
            labelView.widthAnchor.constraint(equalToConstant: 200),
            textField.widthAnchor.constraint(equalToConstant: 200)
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
            labelView.widthAnchor.constraint(equalToConstant: 200),
            checkbox.widthAnchor.constraint(equalToConstant: 200)
        ])
        
        return stackView
    }
    
    @objc func okButtonPressed() {
        guard let contentView = self.contentView else { return }
        let stackView = contentView.subviews[0] as! NSStackView
        
        let showFilenameCheckbox = (stackView.arrangedSubviews[2] as! NSStackView).views[1] as! NSButton
        let borderThicknessTextField = (stackView.arrangedSubviews[3] as! NSStackView).views[1] as! NSTextField
        let cellPaddingTextField = (stackView.arrangedSubviews[4] as! NSStackView).views[1] as! NSTextField
        let borderRadiusTextField = (stackView.arrangedSubviews[5] as! NSStackView).views[1] as! NSTextField
        let filenameSizeTextField = (stackView.arrangedSubviews[6] as! NSStackView).views[1] as! NSTextField
        
        self.isShowThumbnailFilename = showFilenameCheckbox.state == .on
        self.thumbnailBorderThickness = Double(borderThicknessTextField.stringValue) ?? initialThumbnailBorderThickness
        self.thumbnailCellPadding = Double(cellPaddingTextField.stringValue) ?? initialThumbnailCellPadding
        self.thumbnailBorderRadius = Double(borderRadiusTextField.stringValue) ?? initialThumbnailBorderRadius
        self.thumbnailFilenameSize = Double(filenameSizeTextField.stringValue) ?? initialThumbnailFilenameSize
        
        self.sheetParent?.endSheet(self, returnCode: .OK)
    }
    
    @objc func cancelButtonPressed() {
        self.sheetParent?.endSheet(self, returnCode: .cancel)
    }
    
    @objc func resetButtonPressed() {
        guard let contentView = self.contentView else { return }
        let stackView = contentView.subviews[0] as! NSStackView
        
        let showFilenameCheckbox = (stackView.arrangedSubviews[2] as! NSStackView).views[1] as! NSButton
        let borderThicknessTextField = (stackView.arrangedSubviews[3] as! NSStackView).views[1] as! NSTextField
        let cellPaddingTextField = (stackView.arrangedSubviews[4] as! NSStackView).views[1] as! NSTextField
        let borderRadiusTextField = (stackView.arrangedSubviews[5] as! NSStackView).views[1] as! NSTextField
        let filenameSizeTextField = (stackView.arrangedSubviews[6] as! NSStackView).views[1] as! NSTextField
        
        // Reset values to initial values
        showFilenameCheckbox.state = initialShowThumbnailFilename ? .on : .off
        borderThicknessTextField.stringValue = String(initialThumbnailBorderThickness)
        cellPaddingTextField.stringValue = String(initialThumbnailCellPadding)
        borderRadiusTextField.stringValue = String(initialThumbnailBorderRadius)
        filenameSizeTextField.stringValue = String(initialThumbnailFilenameSize)
    }
}


// Function to display the panel as a sheet
func showThumbnailOptionsPanel(on parentWindow: NSWindow, completion: @escaping (Bool, Double, Double, Double, Double) -> Void) {
    let thumbnailOptionsWindow = ThumbnailOptionsWindow()
    
    parentWindow.beginSheet(thumbnailOptionsWindow) { response in
        if response == .OK {
            completion(thumbnailOptionsWindow.isShowThumbnailFilename,
                       thumbnailOptionsWindow.thumbnailBorderThickness,
                       thumbnailOptionsWindow.thumbnailCellPadding,
                       thumbnailOptionsWindow.thumbnailBorderRadius,
                       thumbnailOptionsWindow.thumbnailFilenameSize)
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
