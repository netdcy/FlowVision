//
//  FinderTag.swift
//  FlowVision
//

import Foundation
import Cocoa
import BTree

var customLabels: [(String, Int?)] = [("Test", nil)]

let FILE_LABEL_COLORS = NSWorkspace.shared.fileLabelColors
let FILE_LABELS = NSWorkspace.shared.fileLabels

struct FinderTag {
    let name: String
    let colorIndex: Int?
    
    static let defaultLabelColor: NSColor = NSColor.white
    static let defaultDotImage: NSImage = makeDotImage(for: defaultLabelColor)
    
    var color: NSColor {
        if let colorIndex = colorIndex,
           colorIndex < FILE_LABEL_COLORS.count,
           colorIndex != 0 {
            return FILE_LABEL_COLORS[colorIndex]
        }
        return FinderTag.defaultLabelColor
    }

    var dotImage: NSImage {
        if let colorIndex = colorIndex,
           colorIndex < FinderTag.systemDotImages.count {
            return FinderTag.systemDotImages[colorIndex]
        }
        return FinderTag.defaultDotImage
    }

    static let systemDotImages: [NSImage] = {
        return FILE_LABEL_COLORS.map { color in
            makeDotImage(for: color)
        }
    }()

    // 0=None, 1=Gray, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Red, 7=Orange
    static let systemColorDisplayOrder: [Int] = [6, 7, 5, 2, 4, 3, 1] // 红橙黄绿蓝紫灰

    static let systemColorLabels: [FinderTag] = {
        let labels = FILE_LABELS
        let colors = FILE_LABEL_COLORS
        guard labels.count >= 8, colors.count >= 8 else { return [] }
        
        let order: [Int] = systemColorDisplayOrder
        return order.compactMap { i in
            return FinderTag(name: labels[i], colorIndex: i)
        }
    }()

    static var all: [FinderTag] {
        let custom = customLabels.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }.map { name, colorIndex in
            FinderTag(name: name, colorIndex: colorIndex)
        }
        return systemColorLabels + custom
    }

    static func byName(_ name: String) -> FinderTag? {
        all.first { $0.name == name } ?? FinderTag(name: name, colorIndex: nil)
    }
    
    static func makeDotImage(for color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    static func makeDotImageWithBorder(for color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let r = rect.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(ovalIn: r)
            color.setFill()
            path.fill()
            let strokeColor: NSColor = color.usingColorSpace(.genericGray)?.whiteComponent ?? 0 > 0.9 ? .black : .white
            strokeColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}

enum FinderTagHelper {
    static func readTags(from url: URL) -> [String] {
        guard let values = try? url.resourceValues(forKeys: [.tagNamesKey]) else { return [] }
        return values.tagNames ?? []
    }

    static private func writeTags(_ tags: [String], to url: URL) {
        try? (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    /// returns `true` if the tag was added, `false` if removed
    @discardableResult
    static func toggleTag(_ tagName: String, on urls: [URL]) -> Bool {
        let allHaveTag = urls.allSatisfy { readTags(from: $0).contains(tagName) }
        let adding = !allHaveTag
        for url in urls {
            var tags = readTags(from: url)
            if adding {
                if !tags.contains(tagName) { tags.append(tagName) }
            } else {
                tags.removeAll { $0 == tagName }
            }
            writeTags(tags, to: url)
        }
        // Update EnhancedIndex
        EnhancedIndex.updateFiles(urls)
        return adding
    }

    static func removeAllTags(from urls: [URL]) {
        for url in urls {
            writeTags([], to: url)
        }
        // Update EnhancedIndex
        EnhancedIndex.updateFiles(urls)
    }
}

// MARK: - 增强索引

class EnhancedIndex {

    struct FileMetaInfo: Codable {
        var tags: [String]
    }

    private static var fileIndex: [String: FileMetaInfo] = [:]
    private static var tagIndex: [String: Set<String>] = [:]
    private static var sortedPaths = SortedSet<String>()

    private static let indexLock = NSLock()
    private static let loadingGroup = DispatchGroup()
    private static var isLoaded = false
    private static var pendingWorkItem: DispatchWorkItem?
    private static let saveQueue = DispatchQueue(label: "com.flowvision.EnhancedIndex.save")
    private static let debounceInterval: TimeInterval = 2.0

    private static let scanQueue = DispatchQueue(label: "com.flowvision.EnhancedIndex.scan")
    private static var currentScanID = 0
    private static let scanIDLock = NSLock()

    private static var dataFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let flowVisionDir = appSupport.appendingPathComponent("FlowVision")
        try? FileManager.default.createDirectory(at: flowVisionDir, withIntermediateDirectories: true)
        return flowVisionDir.appendingPathComponent("EnhancedIndex.json")
    }

    // MARK: - 初始化

    static func initialize() {
        guard ENHANCED_INDEX_ENABLED else { return }
        loadingGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            loadFromFile()
            isLoaded = true
            loadingGroup.leave()
        }
    }

    private static func waitUntilLoaded() {
        if isLoaded { return }
        loadingGroup.wait()
    }

    // MARK: - 扫描文件夹并更新索引

    /// progress callback: (message, isComplete)
    static func scanFolder(_ folderURL: URL, progress: ((String, Bool) -> Void)? = nil) {
        guard ENHANCED_INDEX_ENABLED else { return }
        waitUntilLoaded()
        scanIDLock.lock()
        currentScanID += 1
        let myScanID = currentScanID
        scanIDLock.unlock()

        scanQueue.async {
            func isCancelled() -> Bool {
                scanIDLock.lock()
                let cancelled = myScanID != currentScanID
                scanIDLock.unlock()
                return cancelled
            }

            guard !isCancelled() else { return }
            progress?(NSLocalizedString("Scanning...", comment: "扫描中..."), false)

            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.tagNamesKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return }

            var urls: [URL] = [folderURL]
            for case let url as URL in enumerator {
                urls.append(url)
                if urls.count % 1000 == 0 {
                    guard !isCancelled() else { return }
                    progress?("\(NSLocalizedString("Scanning", comment: "扫描中")): \(urls.count) ...", false)
                }
            }

            guard !isCancelled() else { return }
            progress?("\(NSLocalizedString("Updating Index", comment: "更新索引中")): \(urls.count) ...", false)
            updateFiles(urls)
            progress?("\(NSLocalizedString("Scan Complete", comment: "扫描完成"))", true)
        }
    }

    // MARK: - 批量更新文件的标签信息

    static func updateFiles(_ urls: [URL], isCalledByDirOpen: Bool = false, recordTime: Bool = false) {
        guard ENHANCED_INDEX_ENABLED else { return }
        if !isLoaded {
            if isCalledByDirOpen { return }
            waitUntilLoaded()
        }
        let startTime = recordTime ? CFAbsoluteTimeGetCurrent() : 0

        indexLock.lock()
        var changed = false
        for url in urls {
            let path = url.path
            let tags = (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []

            if let existing = fileIndex[path] {
                if existing.tags == tags { continue }
            } else {
                if tags.isEmpty { continue }
            }

            removePathFromIndices(path)

            if tags.isEmpty {
                fileIndex.removeValue(forKey: path)
                sortedPaths.remove(path)
            } else {
                fileIndex[path] = FileMetaInfo(tags: tags)
                for tag in tags {
                    tagIndex[tag, default: Set()].insert(path)
                }
                sortedPaths.insert(path)
            }
            changed = true
        }
        indexLock.unlock()

        if changed {
            scheduleSave()
        }

        if recordTime {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            log("EnhancedIndex: updateFiles(\(urls.count) urls, changed=\(changed)) in \(String(format: "%.4f", elapsed))s", level: .debug)
        }
    }

    // MARK: - 根据标签查询文件（带验证）

    static func filesForTag(_ tagName: String) -> [URL] {
        guard ENHANCED_INDEX_ENABLED else { return [] }
        waitUntilLoaded()
        indexLock.lock()
        let paths = tagIndex[tagName] ?? Set()
        indexLock.unlock()

        var result: [URL] = []
        var pathsToRemove: [String] = []
        var pathsToUpdate: [(String, [String])] = []

        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else {
                pathsToRemove.append(path)
                continue
            }

            let url = URL(fileURLWithPath: path)
            let currentTags = (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []

            indexLock.lock()
            let cachedTags = fileIndex[path]?.tags
            indexLock.unlock()

            if cachedTags != currentTags {
                pathsToUpdate.append((path, currentTags))
            }

            if currentTags.contains(tagName) {
                result.append(url)
            }
        }

        if !pathsToRemove.isEmpty || !pathsToUpdate.isEmpty {
            indexLock.lock()
            for path in pathsToRemove {
                removePathFromIndices(path)
                fileIndex.removeValue(forKey: path)
                sortedPaths.remove(path)
            }
            for (path, newTags) in pathsToUpdate {
                removePathFromIndices(path)
                if newTags.isEmpty {
                    fileIndex.removeValue(forKey: path)
                    sortedPaths.remove(path)
                } else {
                    fileIndex[path] = FileMetaInfo(tags: newTags)
                    for tag in newTags {
                        tagIndex[tag, default: Set()].insert(path)
                    }
                }
            }
            indexLock.unlock()
            scheduleSave()
        }

        return result
    }

    // MARK: - 排序路径辅助（调用方需持有 indexLock）

    /// O(log n + k) prefix search via B-Tree. Caller must hold indexLock.
    private static func indexedPaths(withPrefix prefix: String) -> [String] {
        guard let startIdx = sortedPaths.indexOfFirstElement(notBefore: prefix) else { return [] }
        var result: [String] = []
        var idx = startIdx
        while idx != sortedPaths.endIndex {
            let path = sortedPaths[idx]
            guard path.hasPrefix(prefix) else { break }
            result.append(path)
            idx = sortedPaths.index(after: idx)
        }
        return result
    }

    // MARK: - 文件操作索引维护

    /// 文件/文件夹移动或重命名后更新索引，自动处理子路径前缀替换。
    static func handleFilesMoved(_ moves: [(oldPath: String, newPath: String)]) {
        guard ENHANCED_INDEX_ENABLED else { return }
        waitUntilLoaded()
        indexLock.lock()
        var changed = false
        for (oldPath, newPath) in moves {
            let childPrefix = oldPath + "/"
            let affectedChildren = indexedPaths(withPrefix: childPrefix)
            var affectedPaths = affectedChildren
            if fileIndex[oldPath] != nil { affectedPaths.insert(oldPath, at: 0) }

            let destChildPrefix = newPath + "/"
            let existingAtDest = indexedPaths(withPrefix: destChildPrefix)
            var allExistingAtDest = existingAtDest
            if fileIndex[newPath] != nil { allExistingAtDest.insert(newPath, at: 0) }
            for p in allExistingAtDest {
                removePathFromIndices(p)
                fileIndex.removeValue(forKey: p)
                sortedPaths.remove(p)
                changed = true
            }

            for path in affectedPaths {
                guard let info = fileIndex[path] else { continue }
                let suffix = String(path.dropFirst(oldPath.count))
                let newFullPath = newPath + suffix

                removePathFromIndices(path)
                fileIndex.removeValue(forKey: path)
                sortedPaths.remove(path)

                fileIndex[newFullPath] = info
                for tag in info.tags {
                    tagIndex[tag, default: Set()].insert(newFullPath)
                }
                sortedPaths.insert(newFullPath)
                changed = true
            }
        }
        indexLock.unlock()
        if changed { scheduleSave() }
    }

    /// 文件/文件夹删除后清理索引，自动处理子路径。
    static func handleFilesDeleted(_ paths: [String]) {
        guard ENHANCED_INDEX_ENABLED else { return }
        waitUntilLoaded()
        indexLock.lock()
        var changed = false
        for path in paths {
            let childPrefix = path + "/"
            let affectedChildren = indexedPaths(withPrefix: childPrefix)
            var affectedPaths = affectedChildren
            if fileIndex[path] != nil { affectedPaths.insert(path, at: 0) }

            for p in affectedPaths {
                removePathFromIndices(p)
                fileIndex.removeValue(forKey: p)
                sortedPaths.remove(p)
                changed = true
            }
        }
        indexLock.unlock()
        if changed { scheduleSave() }
    }

    /// 文件/文件夹复制后复制索引条目，自动处理子路径。
    static func handleFilesCopied(_ copies: [(sourcePath: String, destPath: String)]) {
        guard ENHANCED_INDEX_ENABLED else { return }
        waitUntilLoaded()
        indexLock.lock()
        var changed = false
        for (sourcePath, destPath) in copies {
            let destChildPrefix = destPath + "/"
            let existingAtDest = indexedPaths(withPrefix: destChildPrefix)
            var allExistingAtDest = existingAtDest
            if fileIndex[destPath] != nil { allExistingAtDest.insert(destPath, at: 0) }
            for p in allExistingAtDest {
                removePathFromIndices(p)
                fileIndex.removeValue(forKey: p)
                sortedPaths.remove(p)
                changed = true
            }

            let sourceChildPrefix = sourcePath + "/"
            let affectedChildren = indexedPaths(withPrefix: sourceChildPrefix)
            var affectedPaths = affectedChildren
            if fileIndex[sourcePath] != nil { affectedPaths.insert(sourcePath, at: 0) }

            for path in affectedPaths {
                guard let info = fileIndex[path] else { continue }
                let suffix = String(path.dropFirst(sourcePath.count))
                let newFullPath = destPath + suffix

                fileIndex[newFullPath] = info
                for tag in info.tags {
                    tagIndex[tag, default: Set()].insert(newFullPath)
                }
                sortedPaths.insert(newFullPath)
                changed = true
            }
        }
        indexLock.unlock()
        if changed { scheduleSave() }
    }

    // MARK: - 内部辅助（调用方需持有 indexLock）

    private static func removePathFromIndices(_ path: String) {
        guard let info = fileIndex[path] else { return }
        for tag in info.tags {
            tagIndex[tag]?.remove(path)
            if tagIndex[tag]?.isEmpty == true {
                tagIndex.removeValue(forKey: tag)
            }
        }
    }

    // MARK: - 防抖持久化

    private static func scheduleSave() {
        saveQueue.async {
            pendingWorkItem?.cancel()
            let item = DispatchWorkItem {
                performSave()
            }
            pendingWorkItem = item
            saveQueue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        }
    }

    static func flushPendingSave() {
        guard ENHANCED_INDEX_ENABLED else { return }
        waitUntilLoaded()
        saveQueue.sync {
            guard let item = pendingWorkItem, !item.isCancelled else { return }
            item.cancel()
            pendingWorkItem = nil
            performSave()
        }
    }

    private static func performSave() {
        indexLock.lock()
        let snapshot = fileIndex
        indexLock.unlock()

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            var serializable: [String: [String]] = [:]
            for (path, info) in snapshot {
                serializable[path] = info.tags
            }
            let data = try JSONSerialization.data(withJSONObject: serializable, options: [])
            try data.write(to: dataFileURL, options: .atomic)
        } catch {
            log("EnhancedIndex save failed: \(error)", level: .error)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        log("EnhancedIndex saved (\(snapshot.count) entries) in \(String(format: "%.4f", elapsed))s", level: .info)
    }

    private static func loadFromFile() {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            log("EnhancedIndex: loadFromFile finished (\(fileIndex.count) entries) in \(String(format: "%.4f", elapsed))s", level: .debug)
        }

        guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
            log("EnhancedIndex: data file not found, starting fresh", level: .info)
            return
        }

        do {
            let readStart = CFAbsoluteTimeGetCurrent()
            let data = try Data(contentsOf: dataFileURL)
            let readElapsed = CFAbsoluteTimeGetCurrent() - readStart

            let parseStart = CFAbsoluteTimeGetCurrent()
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return }
            let parseElapsed = CFAbsoluteTimeGetCurrent() - parseStart

            indexLock.lock()
            fileIndex.removeAll(keepingCapacity: true)
            fileIndex.reserveCapacity(dict.count)
            tagIndex.removeAll(keepingCapacity: true)
            tagIndex.reserveCapacity(dict.count)

            let fileIndexStart = CFAbsoluteTimeGetCurrent()
            for (path, tags) in dict {
                fileIndex[path] = FileMetaInfo(tags: tags)
            }
            let fileIndexElapsed = CFAbsoluteTimeGetCurrent() - fileIndexStart

            let tagIndexStart = CFAbsoluteTimeGetCurrent()
            for (path, info) in fileIndex {
                for tag in info.tags {
                    tagIndex[tag, default: Set()].insert(path)
                }
            }
            let tagIndexElapsed = CFAbsoluteTimeGetCurrent() - tagIndexStart

            let sortedPathsStart = CFAbsoluteTimeGetCurrent()
            sortedPaths = SortedSet(fileIndex.keys)
            let sortedPathsElapsed = CFAbsoluteTimeGetCurrent() - sortedPathsStart

            indexLock.unlock()

            log("EnhancedIndex: read=\(String(format: "%.4f", readElapsed))s, parse=\(String(format: "%.4f", parseElapsed))s, buildFileIndex=\(String(format: "%.4f", fileIndexElapsed))s, buildTagIndex=\(String(format: "%.4f", tagIndexElapsed))s, buildSortedPaths=\(String(format: "%.4f", sortedPathsElapsed))s", level: .debug)
        } catch {
            log("EnhancedIndex load failed: \(error)", level: .error)
        }
    }
}

struct FileTagAttributes {
    var userTags: [FinderTag]
    var finderInfoTagIndex: Int?
    var finderInfoTagName: String? {
        if let finderInfoTagIndex = finderInfoTagIndex,
           finderInfoTagIndex < FILE_LABELS.count {
            return FILE_LABELS[finderInfoTagIndex]
        }
        return nil
    }
    var finderInfoTagColor: NSColor? {
        if let finderInfoTagIndex = finderInfoTagIndex,
           finderInfoTagIndex < FILE_LABEL_COLORS.count {
            return FILE_LABEL_COLORS[finderInfoTagIndex]
        }
        return nil
    }
}



func readFinderExtendedAttributes(url: URL, needFinderInfo: Bool = false) -> FileTagAttributes? {
    let filePath = url.path
    var finderInfoTagIndex: Int? = nil
    var userTags: [FinderTag] = []

    if needFinderInfo {
        // 读取 com.apple.FinderInfo（固定32字节），直接用栈上缓冲区，单次 syscall
        // byte[9] 的高3位为 label color: none=00,01 grey=02,03 green=04,05
        // purple=06,07 blue=08,09 yellow=0A,0B red=0C,0D orange=0E,0F
        var finderInfoBuf = (
            UInt64(0), UInt64(0), UInt64(0), UInt64(0)
        )
        let finderInfoReadSize = withUnsafeMutableBytes(of: &finderInfoBuf) { buf in
            getxattr(filePath, "com.apple.FinderInfo", buf.baseAddress, 32, 0, 0)
        }
        if finderInfoReadSize >= 10 {
            let byte9 = withUnsafeBytes(of: &finderInfoBuf) { $0[9] }
            let index = Int(byte9) >> 1
            if index > 0 {
                finderInfoTagIndex = index
            }
        }
    }

    // 读取 com.apple.metadata:_kMDItemUserTags（bplist 格式）
    // 预分配 1KB 缓冲区覆盖绝大多数情况，仅在 ERANGE 时回退到两次调用
    // 每条记录格式为 "标签名\ncolorIndex"
    let userTagsAttr = "com.apple.metadata:_kMDItemUserTags"
    let bufferSize = 1024
    var userTagsBuf = [UInt8](repeating: 0, count: bufferSize)
    var readSize = getxattr(filePath, userTagsAttr, &userTagsBuf, bufferSize, 0, 0)
    if readSize == -1 && errno == ERANGE {
        let actualSize = getxattr(filePath, userTagsAttr, nil, 0, 0, 0)
        if actualSize > 0 {
            userTagsBuf = [UInt8](repeating: 0, count: actualSize)
            readSize = getxattr(filePath, userTagsAttr, &userTagsBuf, actualSize, 0, 0)
        }
    }
    if readSize > 0 {
        let userTagsData = Data(userTagsBuf[0..<readSize])
        if let plist = try? PropertyListSerialization.propertyList(from: userTagsData, options: [], format: nil),
           let tagStrings = plist as? [String] {
            for tagString in tagStrings {
                let parts = tagString.split(separator: "\n", maxSplits: 1)
                let name = String(parts[0])
                let colorIndex: Int? = parts.count > 1 ? Int(parts[1]) : nil
                userTags.append(FinderTag(name: name, colorIndex: colorIndex))
            }
        }
    }

    if finderInfoTagIndex == nil && userTags.isEmpty {
        return nil
    }

    let result = FileTagAttributes(userTags: userTags, finderInfoTagIndex: finderInfoTagIndex)
    return result
}

func readFinderExtendedAttributesDeprecated(url: URL) -> FileTagAttributes? {
    let filePath = url.path
    var finderInfoTagIndex: Int? = nil
    var userTags: [FinderTag] = []

    // 读取 com.apple.FinderInfo (32字节二进制)
    // byte[9] 的高3位为 label color: none=00,01 grey=02,03 green=04,05
    // purple=06,07 blue=08,09 yellow=0A,0B red=0C,0D orange=0E,0F
    let finderInfoAttr = "com.apple.FinderInfo"
    let finderInfoSize = getxattr(filePath, finderInfoAttr, nil, 0, 0, 0)
    if finderInfoSize > 0 {
        var finderInfoBuf = [UInt8](repeating: 0, count: finderInfoSize)
        let readSize = getxattr(filePath, finderInfoAttr, &finderInfoBuf, finderInfoSize, 0, 0)
        if readSize >= 10 {
            let index = Int(finderInfoBuf[9]) >> 1
            if index > 0 {
                finderInfoTagIndex = index
            }
        }
    }

    // 读取 com.apple.metadata:_kMDItemUserTags (bplist格式)
    // 每条记录格式为 "标签名\ncolorIndex"
    let userTagsAttr = "com.apple.metadata:_kMDItemUserTags"
    let userTagsSize = getxattr(filePath, userTagsAttr, nil, 0, 0, 0)
    if userTagsSize > 0 {
        var userTagsBuf = [UInt8](repeating: 0, count: userTagsSize)
        let readSize = getxattr(filePath, userTagsAttr, &userTagsBuf, userTagsSize, 0, 0)
        if readSize > 0 {
            let userTagsData = Data(userTagsBuf[0..<readSize])
            if let plist = try? PropertyListSerialization.propertyList(from: userTagsData, options: [], format: nil),
               let tagStrings = plist as? [String] {
                for tagString in tagStrings {
                    let parts = tagString.split(separator: "\n", maxSplits: 1)
                    let name = String(parts[0])
                    let colorIndex: Int? = parts.count > 1 ? Int(parts[1]) : nil
                    userTags.append(FinderTag(name: name, colorIndex: colorIndex))
                }
            }
        }
    }

    if finderInfoTagIndex == nil && userTags.isEmpty {
        return nil
    }

    let result = FileTagAttributes(userTags: userTags, finderInfoTagIndex: finderInfoTagIndex)
    return result
}
