//
//  FinderTag.swift
//  FlowVision
//

import Foundation
import Cocoa

var customLabels: [String] = []

struct FinderTag {
    let name: String
    let color: NSColor?
    let colorIndex: Int?
    let dotImage: NSImage?
    
    static var all: [FinderTag] {
        let custom = customLabels.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            FinderTag(name: name, color: customLabelColor, colorIndex: nil, dotImage: customLabelDotImage)
        }
        return defaultColorLabels + custom
    }
    
    static let customLabelColor: NSColor = NSColor.white
    static let customLabelDotImage: NSImage = makeDotImage(for: customLabelColor)
    
    static let defaultColorLabels: [FinderTag] = {
        let labels = NSWorkspace.shared.fileLabels
        let colors = NSWorkspace.shared.fileLabelColors
        guard labels.count >= 8, colors.count >= 8 else { return [] }
        // 0=None, 1=Gray, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Red, 7=Orange
        let order: [Int] = [6, 7, 5, 2, 4, 3, 1]  // 红橙黄绿蓝紫灰
        return order.compactMap { i in
            let color = colors[i]
            return FinderTag(name: labels[i], color: color, colorIndex: i, dotImage: makeDotImage(for: color))
        }
    }()

    static func byName(_ name: String) -> FinderTag? {
        all.first { $0.name == name } ?? FinderTag(name: name, color: customLabelColor, colorIndex: nil, dotImage: nil)
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

    private static let indexLock = NSLock()
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
        loadFromFile()
    }

    // MARK: - 扫描文件夹并更新索引

    /// progress callback: (message, isComplete)
    static func scanFolder(_ folderURL: URL, progress: ((String, Bool) -> Void)? = nil) {
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

    static func updateFiles(_ urls: [URL]) {
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
            } else {
                fileIndex[path] = FileMetaInfo(tags: tags)
                for tag in tags {
                    tagIndex[tag, default: Set()].insert(path)
                }
            }
            changed = true
        }
        indexLock.unlock()

        if changed {
            scheduleSave()
        }
    }

    // MARK: - 根据标签查询文件（带验证）

    static func filesForTag(_ tagName: String) -> [URL] {
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
            }
            for (path, newTags) in pathsToUpdate {
                removePathFromIndices(path)
                if newTags.isEmpty {
                    fileIndex.removeValue(forKey: path)
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
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
            log("EnhancedIndex: data file not found, starting fresh", level: .info)
            return
        }

        do {
            let data = try Data(contentsOf: dataFileURL)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return }

            indexLock.lock()
            fileIndex.removeAll(keepingCapacity: true)
            tagIndex.removeAll(keepingCapacity: true)
            for (path, tags) in dict {
                fileIndex[path] = FileMetaInfo(tags: tags)
                for tag in tags {
                    tagIndex[tag, default: Set()].insert(path)
                }
            }
            indexLock.unlock()
        } catch {
            log("EnhancedIndex load failed: \(error)", level: .error)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        log("EnhancedIndex loaded (\(fileIndex.count) entries) in \(String(format: "%.4f", elapsed))s", level: .info)
    }
}
