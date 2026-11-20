//
//  Common.swift
//  FlowVision
//

import Foundation
import Cocoa
import Darwin

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

let VIRTUAL_FINDER_TAGS_PREFIX = "file:///VirtualFinderTagsFolder"
let VIRTUAL_FAVORITES_PREFIX = "file:///VirtualFavoritesFolder"
let VIRTUAL_HISTORY_PREFIX = "file:///VirtualHistoryFolder"
let VIRTUAL_ARCHIVE_PREFIX = "file:///VirtualArchiveFolder"

@discardableResult
func openVideoWithPreferredExternalPlayer(_ url: URL) -> Bool {
    if globalVar.preferIINAForExternalVideoPlayer,
       let iinaURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.colliderli.iina") {
        NSWorkspace.shared.open([url], withApplicationAt: iinaURL, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
    NSWorkspace.shared.open(url)
    return true
}

func isVirtualFolderPath(_ path: String) -> Bool {
    return path.hasPrefix(VIRTUAL_FINDER_TAGS_PREFIX)
    || path.hasPrefix(VIRTUAL_FAVORITES_PREFIX)
    || path.hasPrefix(VIRTUAL_HISTORY_PREFIX)
    || path.hasPrefix(VIRTUAL_ARCHIVE_PREFIX)
}

func isReadOnlyVirtualFolderPath(_ path: String) -> Bool {
    return isVirtualFolderPath(path)
}

func isVirtualArchivePath(_ path: String) -> Bool {
    return path.hasPrefix(VIRTUAL_ARCHIVE_PREFIX)
}

func isVirtualArchiveRootPath(_ path: String) -> Bool {
    guard isVirtualArchivePath(path) else { return false }
    let prefix = "\(VIRTUAL_ARCHIVE_PREFIX)/"
    guard path.hasPrefix(prefix) else { return false }
    let remain = String(path.dropFirst(prefix.count))
    return !remain.isEmpty && !remain.contains("/")
}

func isVirtualArchiveEntryPath(_ path: String) -> Bool {
    guard isVirtualArchivePath(path) else { return false }
    let prefix = "\(VIRTUAL_ARCHIVE_PREFIX)/"
    guard path.hasPrefix(prefix) else { return false }
    let remain = String(path.dropFirst(prefix.count))
    let comps = remain.split(separator: "/", omittingEmptySubsequences: true)
    return comps.count >= 2
}

func parseVirtualArchivePath(_ path: String) -> (archiveURL: URL, entryPath: String?)? {
    let prefix = "\(VIRTUAL_ARCHIVE_PREFIX)/"
    guard path.hasPrefix(prefix) else { return nil }
    let remain = String(path.dropFirst(prefix.count))
    guard !remain.isEmpty else { return nil }
    let comps = remain.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
    guard let encodedArchive = comps.first else {
        return nil
    }
    let archiveAbsPath = String(encodedArchive).removingPercentEncoding ?? String(encodedArchive)
    let archiveURL: URL?
    if let parsed = URL(string: archiveAbsPath) {
        archiveURL = parsed
    } else if archiveAbsPath.hasPrefix("file://") {
        let rawPath = String(archiveAbsPath.dropFirst("file://".count)).removingPercentEncoding
            ?? String(archiveAbsPath.dropFirst("file://".count))
        archiveURL = URL(fileURLWithPath: rawPath)
    } else {
        archiveURL = nil
    }
    guard let archiveURL else { return nil }
    if comps.count == 1 {
        return (archiveURL, nil)
    }
    let encodedEntryPath = String(comps[1])
    let entryPath = encodedEntryPath.removingPercentEncoding ?? encodedEntryPath
    return (archiveURL, entryPath)
}

private let archiveEntryDataCache = NSCache<NSString, NSData>()

private func bsdtarEscapedPathBytes(_ text: String) -> [UInt8] {
    let chars = Array(text.utf8)
    var out: [UInt8] = []
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c == 92, i + 1 < chars.count { // '\'
            // Octal form: \ooo
            if i + 3 < chars.count,
               chars[i + 1] >= 48, chars[i + 1] <= 55,
               chars[i + 2] >= 48, chars[i + 2] <= 55,
               chars[i + 3] >= 48, chars[i + 3] <= 55 {
                let value = Int(chars[i + 1] - 48) * 64
                    + Int(chars[i + 2] - 48) * 8
                    + Int(chars[i + 3] - 48)
                out.append(UInt8(value))
                i += 4
                continue
            }
            // Common escapes
            let n = chars[i + 1]
            switch n {
            case 92: out.append(92) // \\
            case 110: out.append(10) // \n
            case 114: out.append(13) // \r
            case 116: out.append(9) // \t
            default:
                out.append(n)
            }
            i += 2
            continue
        }
        out.append(c)
        i += 1
    }
    return out
}

private let archiveEntryPathAliasLock = NSLock()
private var archiveEntryPathAliasMap: [String: String] = [:]

private func archiveEntryPathAliasKey(archiveURL: URL, entryPath: String) -> String {
    "\(archiveURL.absoluteString)|\(entryPath)"
}

func registerArchiveEntryPathAlias(archiveURL: URL, displayPath: String, rawPath: String) {
    guard displayPath != rawPath else { return }
    archiveEntryPathAliasLock.lock()
    archiveEntryPathAliasMap[archiveEntryPathAliasKey(archiveURL: archiveURL, entryPath: displayPath)] = rawPath
    archiveEntryPathAliasLock.unlock()
}

private func rawArchiveEntryPathAlias(archiveURL: URL, entryPath: String) -> String? {
    archiveEntryPathAliasLock.lock()
    let rawPath = archiveEntryPathAliasMap[archiveEntryPathAliasKey(archiveURL: archiveURL, entryPath: entryPath)]
    archiveEntryPathAliasLock.unlock()
    return rawPath
}

private func stringEncoding(ianaName: String) -> String.Encoding? {
    let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaName as CFString)
    guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
    let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
    guard nsEncoding != UInt(kCFStringEncodingInvalidId) else { return nil }
    return String.Encoding(rawValue: nsEncoding)
}

private let archiveFilenameEncodings: [String.Encoding] = {
    var encodings: [String.Encoding] = [.utf8, .shiftJIS]
    for name in ["windows-31j", "cp932", "x-mac-japanese", "euc-jp", "iso-2022-jp"] {
        if let encoding = stringEncoding(ianaName: name), !encodings.contains(encoding) {
            encodings.append(encoding)
        }
    }
    return encodings
}()

func decodeBsdtarEscapedPath(_ text: String) -> String {
    let bytes = bsdtarEscapedPathBytes(text)
    let data = Data(bytes)
    for encoding in archiveFilenameEncodings {
        if let decoded = String(data: data, encoding: encoding) {
            return decoded
        }
    }
    return text
}

func encodeBsdtarEscapedPath(_ text: String, encoding: String.Encoding = .utf8) -> String {
    guard let data = text.data(using: encoding) else { return text }
    var result = ""
    for byte in data {
        if byte >= 0x80 || byte == 0x5C {
            result += String(format: "\\%03o", byte)
        } else {
            result.append(Character(UnicodeScalar(byte)))
        }
    }
    return result
}

func getArchiveEntryData(archiveURL: URL, entryPath: String) -> Data? {
    let cacheKey = "\(archiveURL.absoluteString)|\(entryPath)" as NSString
    if let cached = archiveEntryDataCache.object(forKey: cacheKey) {
        return Data(referencing: cached)
    }
    
    // Try decoded path first, then bsdtar-escaped fallback for legacy zip name encoding output.
    var candidatePaths: [String] = []
    if let rawAlias = rawArchiveEntryPathAlias(archiveURL: archiveURL, entryPath: entryPath) {
        candidatePaths.append(rawAlias)
    }
    let decoded = decodeBsdtarEscapedPath(entryPath)
    if !candidatePaths.contains(decoded) {
        candidatePaths.append(decoded)
    }
    if decoded != entryPath {
        if !candidatePaths.contains(entryPath) {
            candidatePaths.append(entryPath)
        }
    } else {
        let escaped = encodeBsdtarEscapedPath(entryPath)
        if escaped != entryPath {
            candidatePaths.append(escaped)
        }
        for encoding in archiveFilenameEncodings {
            let encoded = encodeBsdtarEscapedPath(entryPath, encoding: encoding)
            if encoded != entryPath && !candidatePaths.contains(encoded) {
                candidatePaths.append(encoded)
            }
        }
    }
    
    for candidate in candidatePaths {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = ["-xOf", archiveURL.path, candidate]
        let stdOut = Pipe()
        let stdErr = Pipe()
        process.standardOutput = stdOut
        process.standardError = stdErr
        
        do {
            try process.run()
        } catch {
            log("Archive stream failed: \(error)", level: .error)
            continue
        }
        
        // Read stdout first to avoid pipe deadlock on large entries.
        let data = stdOut.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            archiveEntryDataCache.setObject(data as NSData, forKey: cacheKey)
            return data
        }
        
        if let err = String(data: stdErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), !err.isEmpty {
            log("Archive stream failed(candidate=\(candidate)): \(err)", level: .warn)
        }
    }
    
    return nil
}

func getArchiveEntryDataIfNeeded(url: URL) -> Data? {
    guard let parsed = parseVirtualArchivePath(url.absoluteString),
          let entryPath = parsed.entryPath else {
        return nil
    }
    return getArchiveEntryData(archiveURL: parsed.archiveURL, entryPath: entryPath)
}

private func normalizeFavoriteFolderPath(_ rawPath: String) -> String? {
    guard let rawURL = URL(string: getFileSchemeAbsPath(rawPath)) else { return nil }
    if rawURL.hasDirectoryPath {
        return rawURL.absoluteString
    }
    return rawURL.deletingLastPathComponent().absoluteString
}

@discardableResult
func addFavoritePath(_ rawPath: String) -> Bool {
    guard let folderPath = normalizeFavoriteFolderPath(rawPath), !folderPath.isEmpty else { return false }
    if globalVar.myFavoritesArray.contains(folderPath) {
        return false
    }
    globalVar.myFavoritesArray.append(folderPath)
    UserDefaults.standard.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
    return true
}

@discardableResult
func removeFavoritePath(_ rawPath: String) -> Bool {
    guard let folderPath = normalizeFavoriteFolderPath(rawPath), !folderPath.isEmpty else { return false }
    guard let index = globalVar.myFavoritesArray.firstIndex(of: folderPath) else { return false }
    globalVar.myFavoritesArray.remove(at: index)
    UserDefaults.standard.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
    return true
}

func isFavoritePath(_ rawPath: String) -> Bool {
    guard let folderPath = normalizeFavoriteFolderPath(rawPath), !folderPath.isEmpty else { return false }
    return globalVar.myFavoritesArray.contains(folderPath)
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
    let okButton = alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
    okButton.keyEquivalent = "\u{1b}"
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

private struct MountedVolumeInfo {
    let rootURL: URL
    let isNetwork: Bool
}

private let networkVolumeFileSystemTypes: Set<String> = [
    "smbfs", "afpfs", "nfs", "webdav"
]

/// Lists the names currently presented by `/Volumes` without asking
/// Foundation to resolve every mounted URL. `contentsOfDirectory(atPath:)`
/// deliberately avoids the per-item resource-value probes that can block on a
/// stale SMB mount.
private func availableVolumeEntryNames() -> Set<String> {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") else {
        return []
    }
    return Set(names)
}

/// Takes a non-blocking POSIX mount-table snapshot, then drops ghost entries
/// that no longer appear in `/Volumes`. No file inside a share is opened.
private func mountedVolumeInfoSnapshot() -> [MountedVolumeInfo] {
    let availableNames = availableVolumeEntryNames()
    var mountBuffer: UnsafeMutablePointer<statfs>?
    let mountCount = getmntinfo(&mountBuffer, MNT_NOWAIT)
    guard mountCount > 0, let mountBuffer else { return [] }

    return (0..<Int(mountCount)).compactMap { index in
        var item = mountBuffer[index]
        let mountPath = withUnsafePointer(to: &item.f_mntonname) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
        let fileSystemType = withUnsafePointer(to: &item.f_fstypename) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0).lowercased()
            }
        }

        let rootURL = URL(fileURLWithPath: mountPath, isDirectory: true).standardizedFileURL
        let components = rootURL.pathComponents
        guard components.count >= 3,
              components[0] == "/",
              components[1] == "Volumes",
              !components[2].hasPrefix("."),
              availableNames.contains(components[2]) else { return nil }

        let isNetwork = networkVolumeFileSystemTypes.contains(fileSystemType)
            || (item.f_flags & UInt32(MNT_LOCAL)) == 0
        return MountedVolumeInfo(rootURL: rootURL, isNetwork: isNetwork)
    }
}

/// Returns true without touching the target path when it sits below a volume
/// root that is not currently present. This avoids triggering a blocking SMB
/// reconnect merely to validate a remembered `/Volumes/<share>/...` path.
func isUnavailableMountedVolumeURL(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    let components = url.standardizedFileURL.pathComponents
    guard components.count >= 3,
          components[0] == "/",
          components[1] == "Volumes" else { return false }

    return !availableVolumeEntryNames().contains(components[2])
}


class VolumeManager {
    static let shared = VolumeManager()
    private var externalVolumes: [URL] = []
    private var networkVolumes: [URL] = []
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
        
        let volumes = mountedVolumeInfoSnapshot()
        externalVolumes = volumes.map(\.rootURL)
        networkVolumes = volumes.filter(\.isNetwork).map(\.rootURL)
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
        if matchingVolumeRoot(for: url, in: externalVolumeSnapshot()) != nil { return true }
        
        // 更新外置卷列表并再检查一次
        // Update external volume list and check again
        if updateExternalVolumes() {
            return matchingVolumeRoot(for: url, in: externalVolumeSnapshot()) != nil
        }

        return false
    }

    func isNetworkVolume(_ path: String) -> Bool {
        guard var url = URL(string: path) else { return false }
        if url.scheme == nil {
            url = URL(fileURLWithPath: path.removingPercentEncoding ?? path)
        }
        return isNetworkVolume(url)
    }

    func isNetworkVolume(_ url: URL) -> Bool {
        networkVolumeRoot(for: url) != nil
    }

    /// Returns the mounted network-volume root without probing the target path.
    /// Mounted SMB paths otherwise look like ordinary local file URLs.
    func networkVolumeRoot(for url: URL) -> URL? {
        if let root = matchingVolumeRoot(for: url, in: networkVolumeSnapshot()) {
            return root
        }
        if updateExternalVolumes() {
            return matchingVolumeRoot(for: url, in: networkVolumeSnapshot())
        }
        return nil
    }
    
    func getExternalVolumes() -> [URL] {
        updateExternalVolumes()
        return externalVolumeSnapshot()
    }

    private func externalVolumeSnapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return externalVolumes
    }

    private func networkVolumeSnapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return networkVolumes
    }

    private func matchingVolumeRoot(for url: URL, in volumes: [URL]) -> URL? {
        guard url.isFileURL else { return nil }
        let path = url.standardizedFileURL.path
        return volumes.first { volumeURL in
            let rootPath = volumeURL.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }
}

/// Allows two bounded background reads per mounted network volume and lets
/// active playback preempt new thumbnail, metadata, folder-count, and preheat work.
/// A task already inside a synchronous framework call is allowed to finish;
/// cancellable readers should additionally check `isPlaybackActive(for:)`.
final class NetworkIOCoordinator {
    static let shared = NetworkIOCoordinator()

    final class PlaybackLease {
        private weak var coordinator: NetworkIOCoordinator?
        private let volumeKey: String
        private let lock = NSLock()
        private var ended = false

        fileprivate init(coordinator: NetworkIOCoordinator, volumeKey: String) {
            self.coordinator = coordinator
            self.volumeKey = volumeKey
        }

        func end() {
            lock.lock()
            guard !ended else {
                lock.unlock()
                return
            }
            ended = true
            let coordinator = coordinator
            lock.unlock()
            coordinator?.finishPlayback(on: volumeKey)
        }

        deinit { end() }
    }

    final class BackgroundLease {
        private weak var coordinator: NetworkIOCoordinator?
        private let volumeKey: String?
        private let lock = NSLock()
        private var ended = false

        fileprivate init(coordinator: NetworkIOCoordinator?, volumeKey: String?) {
            self.coordinator = coordinator
            self.volumeKey = volumeKey
        }

        func end() {
            lock.lock()
            guard !ended else {
                lock.unlock()
                return
            }
            ended = true
            let coordinator = coordinator
            let volumeKey = volumeKey
            lock.unlock()
            if let volumeKey {
                coordinator?.finishBackgroundAccess(on: volumeKey)
            }
        }

        deinit { end() }
    }

    private let condition = NSCondition()
    private var playbackCounts: [String: Int] = [:]
    private var backgroundAccessCounts: [String: Int] = [:]
    private let maxConcurrentBackgroundAccessesPerVolume = 2

    private init() {}

    func beginPlayback(for url: URL) -> PlaybackLease? {
        guard let volumeKey = volumeKey(for: url) else { return nil }
        condition.lock()
        playbackCounts[volumeKey, default: 0] += 1
        condition.broadcast()
        condition.unlock()
        return PlaybackLease(coordinator: self, volumeKey: volumeKey)
    }

    /// Waits for playback or a free background slot on the same SMB volume.
    /// The cancellation closure is checked at least every 100 ms while waiting.
    func beginBackgroundAccess(
        for url: URL,
        shouldContinue: () -> Bool = { true }
    ) -> BackgroundLease? {
        guard let volumeKey = volumeKey(for: url) else {
            return shouldContinue() ? BackgroundLease(coordinator: nil, volumeKey: nil) : nil
        }

        while true {
            // Caller cancellation checks can acquire the directory/preheat
            // locks. Never call them while holding the coordinator lock:
            // playback completion on main may hold those locks in reverse.
            guard shouldContinue() else { return nil }
            condition.lock()
            if playbackCounts[volumeKey, default: 0] == 0
                && backgroundAccessCounts[volumeKey, default: 0] < maxConcurrentBackgroundAccessesPerVolume {
                backgroundAccessCounts[volumeKey, default: 0] += 1
                condition.unlock()
                let lease = BackgroundLease(coordinator: self, volumeKey: volumeKey)
                guard shouldContinue() else {
                    lease.end()
                    return nil
                }
                return lease
            }
            _ = condition.wait(until: Date().addingTimeInterval(0.1))
            condition.unlock()
        }
    }

    func isPlaybackActive(for url: URL) -> Bool {
        guard let volumeKey = volumeKey(for: url) else { return false }
        condition.lock()
        defer { condition.unlock() }
        return playbackCounts[volumeKey, default: 0] > 0
    }

    private func volumeKey(for url: URL) -> String? {
        VolumeManager.shared.networkVolumeRoot(for: url)?.standardizedFileURL.path
    }

    private func finishPlayback(on volumeKey: String) {
        condition.lock()
        let remaining = max(0, playbackCounts[volumeKey, default: 0] - 1)
        if remaining == 0 {
            playbackCounts.removeValue(forKey: volumeKey)
        } else {
            playbackCounts[volumeKey] = remaining
        }
        condition.broadcast()
        condition.unlock()
    }

    private func finishBackgroundAccess(on volumeKey: String) {
        condition.lock()
        let remaining = max(0, backgroundAccessCounts[volumeKey, default: 0] - 1)
        if remaining == 0 {
            backgroundAccessCounts.removeValue(forKey: volumeKey)
        } else {
            backgroundAccessCounts[volumeKey] = remaining
        }
        condition.broadcast()
        condition.unlock()
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

/// RTL时将容器内fixedFrame子视图转为Auto Layout（leading排列），自然支持RTL镜像
/// 非RTL时不执行任何操作
/// Convert fixedFrame subviews to Auto Layout with leading anchors for proper RTL support.
/// No-op when not RTL.
func convertToLeadingLayoutForRTL(_ container: NSView) {
    guard container.userInterfaceLayoutDirection == .rightToLeft else { return }
    guard !container.subviews.isEmpty else { return }

    // 按原始x坐标排序，保持LTR下的逻辑顺序
    // Sort by original x to preserve logical order from LTR
    let sorted = container.subviews.sorted { $0.frame.origin.x < $1.frame.origin.x }

    // 先记录原始frame信息，再切换到Auto Layout
    // Record original frames before switching to Auto Layout
    let frames = sorted.map { $0.frame }
    for subview in sorted {
        subview.translatesAutoresizingMaskIntoConstraints = false
    }

    for (i, subview) in sorted.enumerated() {
        let frame = frames[i]
        subview.widthAnchor.constraint(equalToConstant: frame.width).isActive = true
        subview.heightAnchor.constraint(equalToConstant: frame.height).isActive = true
        subview.centerYAnchor.constraint(equalTo: container.centerYAnchor).isActive = true

        if i == 0 {
            let leadingGap = frame.origin.x
            subview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leadingGap).isActive = true
        } else {
            let gap = frame.origin.x - frames[i - 1].maxX
            subview.leadingAnchor.constraint(equalTo: sorted[i - 1].trailingAnchor, constant: gap).isActive = true
        }
    }
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
