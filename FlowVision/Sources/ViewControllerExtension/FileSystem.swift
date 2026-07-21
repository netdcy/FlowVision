//
//  FileSystem.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

private class ScanCancelHandler: NSObject {
    var onCancel: (() -> Void)?
    @objc func cancel(_ sender: Any?) { onCancel?() }
}

private final class FileInfoScanState {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

extension ViewController {
    
    func scanFiles(at folderURL: URL, contents: inout [URL], properties: [URLResourceKey]) {
        let options: FileManager.DirectoryEnumerationOptions = publicVar.isShowHiddenFile ? [] : [.skipsHiddenFiles]
        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: properties, options: options, errorHandler: { (url, error) -> Bool in
            log("Error enumerating \(url): \(error.localizedDescription)", level: .warn)
            return true
        })
        
        let isRecursiveContainFolder = publicVar.isRecursiveContainFolder
        
        let lock = NSLock()
        var isCancelled = false
        var scannedURLs = [URL]()
        var fileCount = 0
        var imageCount = 0
        var videoCount = 0
        var scanDone = false
        
        // Progress panel (created lazily, only shown if scan takes > 2s)
        let panelWidth: CGFloat = 360
        let panelHeight: CGFloat = 110
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        panel.title = NSLocalizedString("Scan Prompt", comment: "扫描提示")
        panel.isFloatingPanel = true
        panel.center()
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        
        let progressIndicator = NSProgressIndicator(frame: NSRect(x: 20, y: 72, width: panelWidth - 40, height: 20))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        contentView.addSubview(progressIndicator)
        
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: 44, width: panelWidth - 40, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.alignment = .natural
        statusLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(statusLabel)
        
        let cancelButton = NSButton(title: NSLocalizedString("Stop", comment: "停止"), target: nil, action: nil)
        cancelButton.frame = NSRect(x: (panelWidth - 80) / 2, y: 10, width: 80, height: 24)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)
        
        panel.contentView = contentView
        
        var modalStopped = false
        var didEnterModal = false
        
        let cancelHandler = ScanCancelHandler()
        cancelHandler.onCancel = {
            lock.lock()
            isCancelled = true
            lock.unlock()
            if !modalStopped {
                modalStopped = true
                statusLabel.stringValue = NSLocalizedString("Sorting results...", comment: "正在对结果进行排序...")
                DispatchQueue.main.async {
                    NSApp.stopModal()
                }
            }
        }
        cancelButton.target = cancelHandler
        cancelButton.action = #selector(ScanCancelHandler.cancel(_:))
        
        DispatchQueue.global(qos: .userInitiated).async {
            var lastUpdateTime = Date()
            
            while let url = enumerator?.nextObject() as? URL {
                lock.lock()
                let cancelled = isCancelled
                lock.unlock()
                if cancelled { break }
                
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if !isDirectory || isRecursiveContainFolder {
                    lock.lock()
                    scannedURLs.append(url)
                    fileCount += 1
                    if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
                        imageCount += 1
                    } else if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) && isNotFalseTsVideoFile(url) {
                        videoCount += 1
                    }
                    let fc = fileCount
                    let ic = imageCount
                    let vc = videoCount
                    lock.unlock()
                    
                    let now = Date()
                    if now.timeIntervalSince(lastUpdateTime) >= 0.25 {
                        lastUpdateTime = now
                        DispatchQueue.main.async {
                            statusLabel.stringValue = String(format: NSLocalizedString("scanned-files-progress", comment: "已扫描 %d 个文件，其中图像 %d 个，视频 %d 个"), fc, ic, vc)
                        }
                    }
                }
            }
            
            lock.lock()
            scanDone = true
            lock.unlock()
            
            DispatchQueue.main.async {
                if didEnterModal && !modalStopped {
                    modalStopped = true
                    statusLabel.stringValue = NSLocalizedString("Sorting results...", comment: "正在对结果进行排序...")
                    DispatchQueue.main.async {
                        NSApp.stopModal()
                    }
                }
            }
        }
        
        // Wait up to X seconds for scan to finish before showing the panel
        let showPanelDelay: TimeInterval = 2.0
        let waitStart = Date()
        while Date().timeIntervalSince(waitStart) < showPanelDelay {
            lock.lock()
            let done = scanDone
            lock.unlock()
            if done { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        lock.lock()
        let needsModal = !scanDone
        lock.unlock()
        
        if needsModal {
            didEnterModal = true
            lock.lock()
            let fc = fileCount
            let ic = imageCount
            let vc = videoCount
            lock.unlock()
            statusLabel.stringValue = String(format: NSLocalizedString("scanned-files-progress", comment: "已扫描 %d 个文件，其中图像 %d 个，视频 %d 个"), fc, ic, vc)
            progressIndicator.startAnimation(nil)
            
            let storeIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled = false
            NSApp.runModal(for: panel)
            publicVar.isKeyEventEnabled = storeIsKeyEventEnabled
            panel.close()
            withExtendedLifetime(cancelHandler) {}
        }
        
        lock.lock()
        contents.append(contentsOf: scannedURLs)
        lock.unlock()
    }
    
    func scanVirtualFiles(at folderURL: URL, contents: inout [URL], properties: [URLResourceKey],
                          tagName: String) {
        var spotlightPaths = Set<String>()

        let queryString = "kMDItemUserTags == '\(tagName)'"
        if let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) {
            MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
            let count = MDQueryGetResultCount(query)
            for i in 0..<count {
                if let rawPtr = MDQueryGetResultAtIndex(query, i) {
                    let item = Unmanaged<MDItem>.fromOpaque(rawPtr).takeUnretainedValue()
                    if let path = MDItemCopyAttribute(item, kMDItemPath) as? String {
                        spotlightPaths.insert(path)
                        contents.append(URL(fileURLWithPath: path))
                    }
                }
            }
        }

        let enhancedResults = EnhancedIndex.filesForTag(tagName)
        for url in enhancedResults {
            if !spotlightPaths.contains(url.path) {
                contents.append(url)
            }
        }
    }
    
    func isExifSortTimeExceedCancel(folderURL: URL, imageCount: Int, videoCount: Int) -> Bool {
        let networkTimeConsume: Double = Double(imageCount+videoCount)/10.0
        let localTimeConsume: Double = Double(imageCount)/2000.0 + Double(videoCount)/10.0
        
        if (networkTimeConsume > 10 && VolumeManager.shared.isExternalVolume(folderURL)) || localTimeConsume > 10 {
            let alert = NSAlert()
            alert.icon = NSImage(named: NSImage.infoName)
            alert.messageText = NSLocalizedString("Scan Prompt", comment: "扫描提示")
            if VolumeManager.shared.isExternalVolume(folderURL) {
                alert.informativeText = String(format: NSLocalizedString("sort-exif-network-warning", comment: "针对网络驱动exif排序耗时的警告"), imageCount + videoCount, Int(networkTimeConsume))
            }else{
                alert.informativeText = String(format: NSLocalizedString("sort-exif-local-warning", comment: "针对本地exif排序耗时的警告"), imageCount + videoCount, Int(localTimeConsume))
            }
            alert.addButton(withTitle: NSLocalizedString("Continue", comment: "继续"))
            alert.addButton(withTitle: NSLocalizedString("Stop", comment: "停止"))
            
            let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled = false
            let response = alert.runModal()
            publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
            
            if response != .alertFirstButtonReturn {
                return true
            }
        }
        return false
    }
    
    func treeTraversal(folderURL: URL, round: Int, initURL: URL, direction: RightMouseGestureDirection, sameLevel: Bool = false, skip: Bool = false, dryRun: Bool = false) {
        // guard let root = root else { return }
        // let aaa=folderURL.absoluteString
        
        // 找到了则停止
        // Stop if found
        if round != searchFolderRound {return}
        // 重复的则停止
        // Stop if duplicate
        fileDB.lock()
        if fileDB.db[SortKeyDir(folderURL.absoluteString)]?.ver == fileDB.ver {
            fileDB.unlock()
            return
        }
        fileDB.unlock()
        // 找后继时如果不是父目录还小于它则停止
        // Stop when finding successor if not parent directory and less than it
        if direction == .right && SortKeyDir(folderURL.absoluteString) < SortKeyDir(initURL.absoluteString) && !initURL.absoluteString.contains(folderURL.absoluteString) {return}
        // 找前驱时如果大于它则停止
        // Stop when finding predecessor if greater than it
        if direction == .left && SortKeyDir(folderURL.absoluteString) > SortKeyDir(initURL.absoluteString) {return}
        
        
        var contents=[URL]()
        var properties: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .tagNamesKey, .isAliasFileKey, .isSymbolicLinkKey]
        if VolumeManager.shared.isExternalVolume(folderURL) {
            properties = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .tagNamesKey, .isAliasFileKey, .isSymbolicLinkKey]
        }
        var isInSameDir = true
        if !skip {
            do {
                let curDirURLCacheParameters = (folderURL, publicVar.isRecursiveMode, publicVar.isShowHiddenFile, publicVar.isRecursiveContainFolder, properties)
                if let dirURLCacheParameters = dirURLCacheParameters as? (URL, Bool, Bool, Bool, [URLResourceKey]) {
                    if dirURLCacheParameters != curDirURLCacheParameters {
                        dirURLCache.removeAll()
                    }
                }
                dirURLCacheParameters = curDirURLCacheParameters
                
                isInSameDir = !publicVar.isRecursiveMode && !folderURL.path.hasPrefix("/VirtualFinderTagsFolder")
                if dirURLCache.isEmpty {
                    if folderURL.path.hasPrefix("/VirtualFinderTagsFolder") {
                        let tagName = folderURL.lastPathComponent
                        scanVirtualFiles(at: folderURL, contents: &dirURLCache, properties: properties, tagName: tagName)
                    }else if publicVar.isRecursiveMode {
                        scanFiles(at: folderURL, contents: &dirURLCache, properties: properties)
                    }else{
                        dirURLCache = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: properties, options: [])
                    }
                }
                contents.append(contentsOf: dirURLCache)
            }catch{}
        }

        // 过滤隐藏文件
        // Filter hidden files
        contents = contents.filter { url in

            // 获取隐藏属性
            let resourceValues = try? url.resourceValues(forKeys: [.isHiddenKey])
            let isHidden = resourceValues?.isHidden ?? false

            // 保留 /Volumes 目录
            if url.path == "/Volumes" {
                return true
            }

            // 保留 用户的 Library 目录
//            if url.path == NSHomeDirectory() + "/Library" {
//                return true
//            }

            // 过滤掉其他隐藏文件
            return !isHidden || publicVar.isShowHiddenFile
        }

        // 更新增强索引
        // Update enhanced index
        EnhancedIndex.updateFiles(contents, isCalledByDirOpen: true, recordTime: true)

        // 搜索过滤
        // Search filter
        let searchText = search_filterText
        if publicVar.isFilenameFilterOn && searchText != "" {
            let savedUseRegex = search_useRegex
            let savedIsCaseSensitive = search_isCaseSensitive
            let savedIsUseFullPath = search_isUseFullPath
            search_useRegex = search_filterUseRegex
            search_isCaseSensitive = search_filterIsCaseSensitive
            search_isUseFullPath = search_filterIsUseFullPath
            contents = contents.filter { url in
                if let fileName = getFileNameForSearch(path: url.absoluteString) {
                    return isSearchMatch(fileName: fileName, searchText: searchText, forceUseRegex: false)
                }
                return true
            }
            search_useRegex = savedUseRegex
            search_isCaseSensitive = savedIsCaseSensitive
            search_isUseFullPath = savedIsUseFullPath
        }

        // 过滤标签
        // Filter tags
        if !publicVar.finderTagFilters.isEmpty {
            contents = contents.filter { url in
                let tags = Set((try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? [])
                let matched: Bool
                if publicVar.isFinderTagFilterModeAnd {
                    matched = publicVar.finderTagFilters.isSubset(of: tags)
                } else {
                    matched = !tags.isDisjoint(with: publicVar.finderTagFilters)
                }
                return publicVar.isFinderTagFilterReversed ? !matched : matched
            }
        }

        // 过滤评级
        // Filter rating
        if !publicVar.ratingFilters.isEmpty {
            contents = contents.filter { url in
                let rating = readRating(from: url) ?? 0
                let matched = publicVar.ratingFilters.contains(rating)
                return publicVar.isRatingFilterReversed ? !matched : matched
            }
        }
        
        // 过滤出目录列表（含指向目录的替身）
        // Filter out directory list (including aliases pointing to directories)
        var subFolders = contents.filter { url in
            if let isDirectoryResourceValue = try? url.resourceValues(forKeys: [.isDirectoryKey]),
               isDirectoryResourceValue.isDirectory == true {
                return true
            }
            // 替身文件：解析后目标为目录则算作目录
            // Alias file: treat as directory if resolved target is a directory
            if let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]),
               values.isAliasFile == true,
               let resolved = try? URL(resolvingAliasFileAt: url),
               resolved.hasDirectoryPath {
                return true
            }
            return false
        }
        // 如果找平级则无视子目录
        // If finding same level, ignore subdirectories
        if folderURL == initURL && sameLevel { subFolders.removeAll() }
        subFolders.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        // 过滤出需处理文件列表
        // Filter out files to process
        var filesUrlInFolder = [URL]()
        var videoCount=0
        var imageCount=0
        var searchCount=0
        var fileContents = contents.filter { url in
            guard let isDirectoryResourceValue = try? url.resourceValues(forKeys: [.isDirectoryKey]), let isDirectory = isDirectoryResourceValue.isDirectory else {
                return false
            }
            if isDirectory { return false }
            // 指向目录的替身已归入目录列表，不再计入文件
            // Aliases pointing to directories are treated as directories, exclude from file list
            if let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]),
               values.isAliasFile == true,
               let resolved = try? URL(resolvingAliasFileAt: url),
               resolved.hasDirectoryPath {
                return false
            }
            return true
        }
        for file in fileContents {
            let aliasValues = try? file.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
            let isAlias = aliasValues?.isAliasFile == true
            let effectiveExt: String
            if isAlias, let resolved = try? URL(resolvingAliasFileAt: file) {
                effectiveExt = resolved.pathExtension.lowercased()
            } else {
                effectiveExt = file.pathExtension.lowercased()
            }
            let isNotFalseTsVideoFile = isNotFalseTsVideoFile(file)
            if (publicVar.HandledFileExtensions.contains(effectiveExt) && isNotFalseTsVideoFile) || publicVar.isShowAllTypeFile {
                filesUrlInFolder.append(file)
            }
            // 不将替身文件统计为图像或视频
            // Do not count alias files as images or videos
            if let values = try? file.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]),
               values.isAliasFile == true {
                continue
            }
            if publicVar.HandledImageAndRawExtensions.contains(file.pathExtension.lowercased()) {
                imageCount+=1
            }
            if publicVar.HandledVideoExtensions.contains(file.pathExtension.lowercased()) && isNotFalseTsVideoFile {
                videoCount+=1
            }
            if publicVar.HandledSearchExtensions.contains(file.pathExtension.lowercased()) && isNotFalseTsVideoFile {
                searchCount+=1
            }
        }
        
        // Exif排序时间警告
        // Exif sort time warning
        if publicVar.profile.sortType == .exifDateA || publicVar.profile.sortType == .exifDateZ
            || publicVar.profile.sortType == .exifPixelA || publicVar.profile.sortType == .exifPixelZ
            || publicVar.profile.sortType == .ratingA || publicVar.profile.sortType == .ratingZ {
            
            if isExifSortTimeExceedCancel(folderURL: folderURL, imageCount: imageCount, videoCount: videoCount) {
                contents.removeAll()
                fileContents.removeAll()
                subFolders.removeAll()
                filesUrlInFolder.removeAll()
            }
        }
        
        // 好像没必要排序
        // Seems no need to sort
        var filesInFolder = filesUrlInFolder.map{$0.absoluteString}
        let fileCount=filesInFolder.count
        for folder in subFolders {
            filesInFolder.append(folder.absoluteString+"_FolderMark")
            
        }
        
        // 标记当前节点
        // Mark current node
        fileDB.lock()
        if fileDB.db[SortKeyDir(folderURL.absoluteString)] == nil {
            fileDB.db[SortKeyDir(folderURL.absoluteString)] = DirModel(path: folderURL.absoluteString, ver: fileDB.ver)
        }
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.ver = fileDB.ver
        if !skip {
            // 文件过滤
            // File filtering
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isFiltered = publicVar.isFilenameFilterOn
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.folderCount=subFolders.count
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.fileCount=fileCount
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.imageCount=imageCount
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.videoCount=videoCount
        }
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isMemClearedToAvoidRemainingTask=false
        let lastIsRecursiveMode=fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isRecursiveMode
        if lastIsRecursiveMode != publicVar.isRecursiveMode {
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.keepScrollPos=false
        }
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isRecursiveMode=publicVar.isRecursiveMode
        fileDB.unlock()
        
        // 往前则后序遍历
        // Forward traversal uses post-order traversal
        if direction == .left {
            for subFolder in subFolders.reversed(){
                treeTraversal(folderURL: subFolder, round: round, initURL: initURL, direction: direction)
            }
            if folderURL.deletingLastPathComponent().absoluteString != "file:///../" {
                treeTraversal(folderURL: folderURL.deletingLastPathComponent(), round: round, initURL: initURL, direction: direction)
            }
        }
        
        // 有图片且满足条件则停止之后搜索
        // Stop searching if images found and conditions met
        if searchCount > 0 {
            if direction == .left && SortKeyDir(folderURL.absoluteString) < SortKeyDir(initURL.absoluteString) {
                searchFolderRound += 1
            }
            if direction == .right && SortKeyDir(folderURL.absoluteString) > SortKeyDir(initURL.absoluteString) {
                searchFolderRound += 1
            }
            if direction == .zero && folderURL.absoluteString == initURL.absoluteString {
                searchFolderRound += 1
            }
        }
        
        
        // 排序传递性断言
        // Sort transitivity assertion
        //            var testList=[SortKey]()
        //            for filePath in filesInFolder{
        //                let fileSortKey:SortKey
        //                // fileSortKey=SortKeyDir(filePath)
        //                if filePath.hasSuffix("_FolderMark") {
        //                    fileSortKey=SortKeyDir(String(filePath.dropLast("_FolderMark".count)),isDir: true)
        //                }else{
        //                    fileSortKey=SortKeyDir(filePath)
        //                }
        //                testList.append(fileSortKey)
        //                // log(filePath)
        //            }
        //            testList.sort()
        //            for (i, _) in testList.enumerated() {
        //                for (j,_) in testList.enumerated() where j > i {
        //                    assert(testList[i] <= testList[j], "Sort order \(i) and \(j) is incorrect \(testList[i].path.removingPercentEncoding!) and \(testList[j].path.removingPercentEncoding!)")
        //                }
        //            }
        
        
        // 处理当前节点，注意检查skip，否则向上时会清空
        // Process current node, note check skip, otherwise will clear when going up
        fileDB.lock()
        if !skip && (initURL != folderURL || direction == .zero) {
            let folderpath = folderURL.absoluteString
            // log(filesInFolder.count)
            for (i,filePath) in filesInFolder.enumerated(){
                var fileSortKey:SortKeyFile
                let isDir: Bool
                if filePath.hasSuffix("_FolderMark") {
                    fileSortKey = SortKeyFile(String(filePath.dropLast("_FolderMark".count)), isDir: true, isInSameDir: isInSameDir, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)
                    isDir = true
                }else{
                    fileSortKey = SortKeyFile(filePath, isInSameDir: isInSameDir, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)
                    isDir = false
                }
                // 读取文件大小日期
                // Read file size and dates
                var isAlias: Bool = false
                var fileSize: Int?
                var modDate: Date?
                var createDate: Date?
                var addDate: Date?
                var doNotActualRead = false
                var finderTags: [String] = []
                var isHiddenFile = false
                do{
                    // 文件在前i个，目录在后面
                    // Files in first i items, directories after
                    if i < fileCount {
                        let resourceValues = try filesUrlInFolder[i].resourceValues(forKeys: Set(properties))
                        if let tmp = resourceValues.isAliasFile {
                            isAlias=tmp
                        }
                        if let tmp = resourceValues.fileSize {
                            fileSize=tmp
                            fileSortKey.size=tmp
                        }
                        if let tmp = resourceValues.creationDate {
                            createDate=tmp
                            fileSortKey.createDate=tmp
                        }
                        if let tmp = resourceValues.contentModificationDate {
                            modDate=tmp
                            fileSortKey.modDate=tmp
                        }
                        if let tmp = resourceValues.addedToDirectoryDate {
                            addDate=tmp
                            fileSortKey.addDate=tmp
                        }
                        if let isUbiquitousItem = resourceValues.isUbiquitousItem,
                           isUbiquitousItem,
                           let downloadingStatus = resourceValues.ubiquitousItemDownloadingStatus,
                           downloadingStatus != .current {
                            doNotActualRead=true
                        }
                        isHiddenFile = resourceValues.isHidden ?? false
                        let tags = (try? filesUrlInFolder[i].resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
                        finderTags = tags
                        // finderTags = resourceValues.tagNames ?? []
                    // 目录
                    // Directory
                    }else{
                        let resourceValues = try subFolders[i-fileCount].resourceValues(forKeys: Set(properties))
                        if let tmp = resourceValues.isAliasFile {
                            isAlias=tmp
                        }
                        if let tmp = resourceValues.fileSize {
                            fileSize=tmp
                            fileSortKey.size=tmp
                        }
                        if let tmp = resourceValues.creationDate {
                            createDate=tmp
                            fileSortKey.createDate=tmp
                        }
                        if let tmp = resourceValues.contentModificationDate {
                            modDate=tmp
                            fileSortKey.modDate=tmp
                        }
                        if let tmp = resourceValues.addedToDirectoryDate {
                            addDate=tmp
                            fileSortKey.addDate=tmp
                        }
                        // 由于文件夹下内容没下载全，downloadingStatus好像也会为current，因此只要是icloud文件夹，就不生成缩略图
                        // Since folder content not fully downloaded, downloadingStatus might also be current, so if it's an iCloud folder, don't generate thumbnails
                        if let isUbiquitousItem = resourceValues.isUbiquitousItem,
                           isUbiquitousItem
                           {
                            doNotActualRead=true
                        }
                        isHiddenFile = resourceValues.isHidden ?? false
                        let tags = (try? subFolders[i-fileCount].resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
                        finderTags = tags
                        // finderTags = resourceValues.tagNames ?? []
                    }
                }catch{
                    log("Error reading properties.")
                }
                // log("i:",i,"path:",fileSortKey.path.removingPercentEncoding)
                let newFileModel=FileModel(path: fileSortKey.path, ver: fileDB.db[SortKeyDir(folderpath)]!.ver, isDir: isDir, isAlias: isAlias, fileSize: fileSize, createDate: createDate, modDate: modDate, addDate: addDate, doNotActualRead: doNotActualRead)
                newFileModel.finderTags = finderTags
                newFileModel.isHidden = isHiddenFile
                // log(fileSortKey.path)
                if let file = fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] {
                    if file.path == fileSortKey.path {
                        file.ver = fileDB.db[SortKeyDir(folderpath)]!.ver
                        file.isDir=isDir
                        file.isAlias=isAlias
                        file.doNotActualRead=doNotActualRead
                        file.isHidden=isHiddenFile
                        file.finderTags=finderTags
                        // 检查文件或文件夹是否有变化(文件夹fileSize为nil)
                        // Check if file or folder has changed (folder fileSize is nil)
                        if fileSize != file.fileSize || modDate != file.modDate {
                            fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] = newFileModel
                        }
                    }else{
                        // 大小写变化，需要删除再插入
                        // Case change, need to delete then insert
                        fileDB.db[SortKeyDir(folderpath)]!.files.removeValue(forKey: fileSortKey)
                        fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] = newFileModel
                    }
                }else{
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] = newFileModel
                }
            }
            var keysToRemove: [SortKeyFile] = []
            for ele in fileDB.db[SortKeyDir(folderpath)]!.files{
                // log(ele.0.path.removingPercentEncoding)
                if ele.1.ver != fileDB.db[SortKeyDir(folderpath)]!.ver {
                    ele.1.image=nil
                    ele.1.folderImages=[]
                    keysToRemove.append(ele.0)
                }
            }
            for key in keysToRemove {
                fileDB.db[SortKeyDir(folderpath)]!.files.removeValue(forKey: key)
            }
        }
        
        if dryRun || (!skip && (initURL != folderURL || direction == .zero)) {
            let folderpath = folderURL.absoluteString
            var id=0
            var idInImage=0
            var idInImageAndVideo=0
            for ele in fileDB.db[SortKeyDir(folderpath)]!.files{
                ele.1.ver = fileDB.db[SortKeyDir(folderpath)]!.ver
                ele.1.canBeCalcued = false
                let isNotFalseTsVideoFile = isNotFalseTsVideoFile(URL(string: ele.1.path)!)
                if !ele.1.isDir{
                    ele.1.ext=URL(string: ele.1.path)!.pathExtension.lowercased()
                    if ele.1.isAlias {
                        ele.1.type = .other
                        if let resolved = try? URL(resolvingAliasFileAt: URL(string: ele.1.path)!) {
                            ele.1.aliasActualExt = resolved.pathExtension.lowercased()
                            if globalVar.HandledImageAndRawExtensions.contains(ele.1.aliasActualExt) {
                                ele.1.aliasActualType = .image
                            } else if globalVar.HandledVideoExtensions.contains(ele.1.aliasActualExt) && isNotFalseTsVideoFile {
                                ele.1.aliasActualType = .video
                            } else {
                                ele.1.aliasActualType = .other
                            }
                        } else {
                            ele.1.aliasActualType = .other
                            ele.1.aliasActualExt = ""
                        }
                    } else if globalVar.HandledImageAndRawExtensions.contains(ele.1.ext) {
                        ele.1.type = .image
                        ele.1.idInImage = idInImage
                        ele.1.idInImageAndVideo = idInImageAndVideo
                        idInImage += 1
                        idInImageAndVideo += 1
                    }else if globalVar.HandledVideoExtensions.contains(ele.1.ext) && isNotFalseTsVideoFile {
                        ele.1.type = .video
                        ele.1.idInImageAndVideo = idInImageAndVideo
                        idInImageAndVideo += 1
                    }else{
                        ele.1.type = .other
                    }
                }else{
                    ele.1.type = .folder
                    ele.1.aliasActualType = .folder
                }
                ele.1.id = id
                id += 1
            }
        }
        fileDB.unlock()
        
        // 往后则先序遍历
        // Backward traversal uses pre-order traversal
        if direction == .right {
            for subFolder in subFolders{
                treeTraversal(folderURL: subFolder, round: round, initURL: initURL, direction: direction)
            }
            if folderURL.deletingLastPathComponent().absoluteString != "file:///../" {
                treeTraversal(folderURL: folderURL.deletingLastPathComponent(), round: round, initURL: initURL, direction: direction)
            }
        }
        

    }
    
    func switchFolder(path: String) {
        // startTime = DispatchTime.now()
        
        // getFileListOfFolder(folderpath: path)
        
        // 清空任务池
        // Clear task pool
        readInfoTaskPoolLock.lock()
        readInfoTaskPool.removeAll()
        readInfoTaskPoolLock.unlock()
        loadImageTaskPool.lock.lock()
        loadImageTaskPool.removeAllQueue()
        loadImageTaskPool.setMostPriority(queueName: path)
        loadImageTaskPool.lock.unlock()
        
        // 是捕获界面，还是将从finder打开替换为目录中打开
        // Capture interface, or replace opening from finder with opening in directory
        if publicVar.openFromFinderPath == "" {
            if let snapshot = captureSnapshot(of: coreAreaView){
                coreAreaView.addSubview(snapshot)
                snapshotQueue.append(snapshot)
            }
//            currLargeImagePos = -1
            initLargeImagePos = -1
            if publicVar.lastLargeImageIdInImage == 0 {
                nextLargeImage(isShowReachEndPrompt: false, firstShowThumb: false, noLoopBrowsing: true)
                previousLargeImage(isShowReachEndPrompt: false, firstShowThumb: false, noLoopBrowsing: true)
            }else{
                previousLargeImage(isShowReachEndPrompt: false, firstShowThumb: false, noLoopBrowsing: true)
                nextLargeImage(isShowReachEndPrompt: false, firstShowThumb: false, noLoopBrowsing: true)
            }

        }else{
            
            let filename=publicVar.openFromFinderPath
            // log(filename)
            fileDB.lock()
            if let index=fileDB.db[SortKeyDir(path)]?.files.index(forKey: SortKeyFile(filename, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)),
               let offset=fileDB.db[SortKeyDir(path)]?.files.offset(of: index),
               let file=fileDB.db[SortKeyDir(path)]?.files[SortKeyFile(filename, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)],
               let url=URL(string: file.path),
               let totalCount=fileDB.db[SortKeyDir(path)]?.files.count,
               let fileCount=fileDB.db[SortKeyDir(path)]?.fileCount
            {
                fileDB.unlock()
                // log(offset-(totalCount-fileCount))
                currLargeImagePos = offset// -(totalCount-fileCount)
                initLargeImagePos = -1
                publicVar.openFromFinderPath = ""
                file.imageInfo=getImageInfo(url: url, needMetadata: true)
                file.originalSize=file.imageInfo?.size
                if file.originalSize == nil {
                    file.originalSize = DEFAULT_SIZE
                    file.isGetImageSizeFail = true
                }else{
                    file.isGetImageSizeFail = false
                }
                largeImageView.file=file
                
                setWindowTitleOfLargeImage(file: file)
                setLoadThumbPriority(indexPath: IndexPath(item: currLargeImagePos, section: 0), ifNeedVisable: false)
            }else{
                fileDB.unlock()
            }
            
        }
        
        if publicVar.isNeedChangeLayoutType {
            if publicVar.profile.layoutType == .waterfall {
                collectionView.collectionViewLayout=publicVar.waterfallLayout
            }else if publicVar.profile.layoutType == .grid {
                collectionView.collectionViewLayout=publicVar.gridLayout
            }else if publicVar.profile.layoutType == .justified {
                collectionView.collectionViewLayout=publicVar.justifiedLayout
            }else {
                assertionFailure()
            }
            publicVar.isNeedChangeLayoutType = false
        }
        
        // 清空collectionView
        // Clear collectionView
        fileDB.lock()
        let lastCurFolder=fileDB.curFolder
        fileDB.curFolder = path
        let fileNum=fileDB.db[SortKeyDir(path)]?.files.count ?? 0
        let lastLayoutCalcPos=fileDB.db[SortKeyDir(path)]?.layoutCalcPos ?? fileNum
        fileDB.db[SortKeyDir(path)]?.layoutCalcPos=0
        fileDB.db[SortKeyDir(path)]?.lastLayoutCalcPosUsed=0
        fileDB.unlock()
        
        // 如果是切换目录或者文件数量过多，则清空后再insertItems，否则仅reloadData(保持位置)
        // If switching directory or too many files, clear then insertItems, otherwise only reloadData (maintain position)
        fileDB.lock()
        let needClearThenInsert = lastCurFolder != path || fileNum > RESET_VIEW_FILE_NUM_THRESHOLD || fileDB.db[SortKeyDir(path)]?.keepScrollPos == false
        fileDB.unlock()
        if needClearThenInsert {
            // 必须按顺序执行以下两句，否则频繁切换目录时会出现异常
            // Must execute the following two statements in order, otherwise exceptions will occur when frequently switching directories
            // 重载清空
            // Reload to clear
            collectionView.reloadData()
            collectionView.numberOfItems(inSection:0)
            
            fileDB.lock()
            fileDB.db[SortKeyDir(path)]?.keepScrollPos=false
            fileDB.unlock()
        }
        
        // 界面快照渐隐动画
        // Interface snapshot fade-out animation
//        NSAnimationContext.runAnimationGroup({ context in
//            context.duration = 0.6
//            snapshot?.animator().alphaValue = 0
//            largeImageView.animator().alphaValue = 0
//            largeImageBgEffectView.animator().alphaValue = 0
//        }, completionHandler: {
//            snapshot?.removeFromSuperview()
//            self.largeImageView.isHidden=true
//            self.largeImageBgEffectView.isHidden=true
//        })
        
        if true{
            var keys = [(SortKeyFile,FileModel)]()
            fileDB.lock()
            keys = getMapKeysFile(fileDB.db[SortKeyDir(path)]!.files)
            let dirModel = fileDB.db[SortKeyDir(path)]!
            let ver = dirModel.ver
            fileDB.unlock()
            readInfoTaskPoolLock.lock()
            for (i, key) in keys.enumerated(){
                readInfoTaskPool.append((path,dirModel,key.0,key.1,dirModel.ver,OtherTaskInfo()))
                readInfoTaskPoolSemaphore.signal()
            }
            readInfoTaskPoolLock.unlock()
            publicVar.isInStageOneProgress = false

            // Hide folder info
            collectionView.hideFolderInfo()
            
            // 对于空文件夹，播放渐变动画（因为没有分派任务，所以在任务里的渐变调用不到）
            // For empty folders, play fade animation (because no tasks are dispatched, fade in tasks won't be called)
            if keys.isEmpty {
                
                collectionView.reloadData()
                collectionView.numberOfItems(inSection:0)

                setProgress(1.0)

                if !FileManager.default.fileExists(atPath: path.dropLast().replacingOccurrences(of: "file://", with: "").removingPercentEncoding!) {
                    if path == "file:///VirtualFinderTagsFolder/" {
                        collectionView.showFolderInfo(NSLocalizedString("Please select a specific tag", comment: "请选择具体的标签"))
                    } else if !path.hasPrefix("file:///VirtualFinderTagsFolder") {
                        collectionView.showFolderInfo(NSLocalizedString("Directory does not exist", comment: "目录不存在"))
                    }
                }
                
                while snapshotQueue.count > 0{
                    let snapshot=snapshotQueue.first!
                    snapshotQueue.removeFirst()
                    publicVar.isInLargeView=false
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.2
                        snapshot?.animator().alphaValue = 0
                        self.largeImageView.animator().alphaValue = 0
                        self.largeImageBgEffectView.animator().alphaValue = 0
                    }, completionHandler: {
                        snapshot?.removeFromSuperview()
                        self.largeImageView.isHidden=true
                        self.largeImageBgEffectView.isHidden=true
                        self.publicVar.isInLargeViewAfterAnimate=false
                        self.setWindowTitle()
                    })
                }
            }
            
            // 对于非空文件夹，延迟播放渐变动画（主要是针对网络驱动器时，可能连第一个对象获取信息都非常耗时，需要在此处也计时）
            // For non-empty folders, delay fade animation (mainly for network drives, getting info for even the first object can be very time-consuming, need timing here too)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                Thread.sleep(forTimeInterval: 0.5)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    fileDB.lock()
                    let curFolder=fileDB.curFolder
                    let layoutCalcPos=fileDB.db[SortKeyDir(curFolder)]?.layoutCalcPos ?? -1
                    fileDB.unlock()
                    
                    if ver != dirModel.ver {return}
                    
                    if curFolder == path {
                        
                        if snapshotQueue.count > 0 {
                            let curTime = DispatchTime.now()
                            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                            let timeInterval = Double(nanoTime) / 1_000_000_000
                            log("Time taken to reach hidden snapshot reason 2: \(timeInterval) seconds")
                            log("-----------------------------------------------------------")
                        }
                        
                        while snapshotQueue.count > 0{
                            
                            if layoutCalcPos == 0{
                                coreAreaView.showInfo(NSLocalizedString("Loading...", comment: "加载中..."), timeOut: .infinity, cannotBeCleard: false)
                            }
                            
                            let snapshot=snapshotQueue.first!
                            snapshotQueue.removeFirst()
                            // publicVar.isInLargeView=false
                            NSAnimationContext.runAnimationGroup({ context in
                                context.duration = 0.2
                                snapshot?.animator().alphaValue = 0
                                //                                    self.largeImageView.animator().alphaValue = 0
                                //                                    self.largeImageBgEffectView.animator().alphaValue = 0
                            }, completionHandler: {
                                snapshot?.removeFromSuperview()
                                //                                    self.largeImageView.isHidden=true
                                //                                    self.largeImageBgEffectView.isHidden=true
                                //                                    publicVar.isInLargeViewAfterAnimate=false
                            })
                        }
                    }
                }
            }
        }
        
        if true {
            let curTime = DispatchTime.now()
            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let timeInterval = Double(nanoTime) / 1_000_000_000
            log("Time taken to dispatch info task: \(timeInterval) seconds")
        }
    }
    
    /// 选中产生变化的文件（粘贴/移动后）或定位文件夹（返回上级时）
    /// - Parameters:
    ///   - isFinal: true=全量模式（检查所有items、清空列表、滚动定位）；false=增量模式（仅检查指定范围、不清空、不滚动）
    ///   - checkRange: 增量模式下要检查的indexPaths范围；全量模式下忽略此参数
    func selectItemsNewChanged(isFinal: Bool = true, checkRange: [IndexPath]? = nil) {

        let elapsedThreshold = 2.0
        
        let curItemCount = collectionView.numberOfItems(inSection: 0)
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        let dirFiles = fileDB.db[SortKeyDir(curFolder)]?.files
        fileDB.unlock()
        
        // 向上或者后退时定位文件夹
        // Locate folder when going up or back
        if let (lastFolder, _) = publicVar.folderStepForLocate.first {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - publicVar.folderStepForLocateTime.uptimeNanoseconds) / 1_000_000_000
            if elapsed > elapsedThreshold {
                publicVar.folderStepForLocate.removeAll()
            } else if let lastURL = URL(string: lastFolder),
                      let curURL = URL(string: curFolder),
                      lastURL.deletingLastPathComponent().absoluteString == curURL.absoluteString {
                let targetKey = SortKeyFile(lastURL.absoluteString, isDir: true, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)
                fileDB.lock()
                if let files = dirFiles,
                   let index = files.index(forKey: targetKey) {
                    let offset = files.offset(of: index)
                    fileDB.unlock()
                    let indexPath = IndexPath(item: offset, section: 0)
                    if indexPath.item < curItemCount {
                        publicVar.folderStepForLocate.removeAll()
                        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                        collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [indexPath])
                        collectionView.selectItems(at: [indexPath], scrollPosition: [])
                        collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
                        setLoadThumbPriority(ifNeedVisable: true)
                    }
                } else {
                    fileDB.unlock()
                }
            }
        }
        
        // 粘贴或移动后选中变更的文件
        // Select changed files after paste or move
        if !publicVar.filesForLocateAfterChange.isEmpty {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - publicVar.filesForLocateAfterChangeTime.uptimeNanoseconds) / 1_000_000_000
            if elapsed > elapsedThreshold {
                publicVar.filesForLocateAfterChange.removeAll()
                return
            }
            
            let targetPathSet = Set(publicVar.filesForLocateAfterChange.map {
                $0.hasSuffix("/") ? String($0.dropLast()) : $0
            })
            var matchedIndexPaths = [IndexPath]()
            
            fileDB.lock()
            if let files = dirFiles {
                if let checkRange = checkRange, !isFinal {
                    for indexPath in checkRange {
                        guard indexPath.item < curItemCount else { continue }
                        if let element = files.elementSafe(atOffset: indexPath.item) {
                            let normalizedPath = element.0.path.hasSuffix("/") ? String(element.0.path.dropLast()) : element.0.path
                            if targetPathSet.contains(normalizedPath) {
                                matchedIndexPaths.append(indexPath)
                            }
                        }
                    }
                } else {
                    for (offset, element) in files.enumerated() {
                        guard offset < curItemCount else { continue }
                        let normalizedPath = element.0.path.hasSuffix("/") ? String(element.0.path.dropLast()) : element.0.path
                        if targetPathSet.contains(normalizedPath) {
                            matchedIndexPaths.append(IndexPath(item: offset, section: 0))
                        }
                    }
                }
            }
            fileDB.unlock()
            
            if !matchedIndexPaths.isEmpty {
                let isFirstMatch = collectionView.selectionIndexPaths.isEmpty
                collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: Set(matchedIndexPaths))
                collectionView.selectItems(at: Set(matchedIndexPaths), scrollPosition: [])
                collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: Set(matchedIndexPaths))
                if isFirstMatch {
                    collectionView.scrollToItems(at: [matchedIndexPaths[0]], scrollPosition: .nearestHorizontalEdge)
                    setLoadThumbPriority(ifNeedVisable: true)
                }
            }
            
            if isFinal {
                publicVar.filesForLocateAfterChange.removeAll()
            }
        }
    }
    
    func switchDirByDirection(direction rawdirection: RightMouseGestureDirection, dest: String = "", doCollapse: Bool = true, expandLast: Bool = true, skip: Bool = false, stackDeep: Int, dryRun: Bool = false, needStopAutoScroll: Bool = true){
        
        if rawdirection == .zero {
            publicVar.isInStageOneProgress = true
        }
        
        if publicVar.isRecursiveMode {
            if rawdirection == .left || rawdirection == .up_left || rawdirection == .down_left
                || rawdirection == .right || rawdirection == .up_right || rawdirection == .down_right {
                showAlert(message: NSLocalizedString("recursive-mode-nodirection", comment: "递归模式下不能执行此动作"))
                return
            }
        }

        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        if curFolder.hasPrefix("file:///VirtualFinderTagsFolder") || !publicVar.finderTagFilters.isEmpty || !publicVar.ratingFilters.isEmpty {
            if rawdirection == .left || rawdirection == .up_left || rawdirection == .down_left
                || rawdirection == .right || rawdirection == .up_right || rawdirection == .down_right {
                return
            }
        }
        
        // 停止自动滚动
        // Stop auto-scroll
        if needStopAutoScroll {
            stopAutoScroll()
        }
        
        // 停止自动播放
        // Stop auto-play
        stopAutoPlay()
        
        // 关闭搜索窗口
        // Close search window
        // closeSearchOverlay()
        
        // 清空快速搜索
        // Clear quick search
        if quickSearchState {
            coreAreaView.hideInfo(force: true)
        }
        quickSearchText = ""
        quickSearchState = false

        stopWatchingDirectory()
        collectionView.deselectAll(nil)
        // publicVar.selectedUrls=[URL]()
        
        var direction=rawdirection
        var secondDirection: RightMouseGestureDirection = .zero
        if rawdirection == .down_left {direction = .left; secondDirection = .down}
        if rawdirection == .down_right {direction = .right; secondDirection = .down}
        if rawdirection == .up_left {direction = .up; secondDirection = .down_left}
        if rawdirection == .up_right {direction = .up; secondDirection = .down_right}
        
        // 初始为空则返回
        // Return if initially empty
        fileDB.lock()
        if fileDB.curFolder=="" && direction != .zero {
            fileDB.unlock()
            return
        }
        // 记录供定位的上次目录
        // Record previous directory for positioning
        if stackDeep == 0,
           direction == .up || direction == .down || direction == .back {
            publicVar.folderStepForLocate.insert((fileDB.curFolder,direction), at: 0)
            publicVar.folderStepForLocateTime = .now()
            if publicVar.folderStepForLocate.count > 10 {
                publicVar.folderStepForLocate.removeLast()
            }
        }
        fileDB.unlock()
        
        startTime = DispatchTime.now()
        
        // 返回上一次目录
        // Return to previous directory
        if direction == .down || direction == .back {
            if publicVar.folderStepStack.count == 0 {return}
            if publicVar.folderStepStack[0] == "" {return}
            fileDB.lock()
            publicVar.folderStepForwardStack.insert(fileDB.curFolder, at: 0)
            fileDB.unlock()
            switchDirByDirection(direction: .zero, dest: publicVar.folderStepStack.removeFirst(), stackDeep: stackDeep+1)
            publicVar.folderStepStack.removeFirst()
            return
        }else if direction != .forward && stackDeep == 0 {
            publicVar.folderStepForwardStack.removeAll()
        }
        // 前进
        // Forward
        if direction == .forward {
            if publicVar.folderStepForwardStack.count == 0 {return}
            if publicVar.folderStepForwardStack[0] == "" {return}
            switchDirByDirection(direction: .zero, dest: publicVar.folderStepForwardStack.removeFirst(), stackDeep: stackDeep+1)
            return
        }
        // 跳转父级目录
        // Jump to parent directory
        if direction == .up {
            fileDB.lock()
            let newFolderPath=URL(string: fileDB.curFolder)!.deletingLastPathComponent().absoluteString
            fileDB.unlock()
            if newFolderPath == "file:///../" {return}
            switchDirByDirection(direction: .zero, dest: newFolderPath, skip: true, stackDeep: stackDeep+1)
            switchDirByDirection(direction: secondDirection, stackDeep: stackDeep+1)
            if secondDirection != .zero {
                publicVar.folderStepStack.removeFirst()
            }
            return
        }
        
        fileDB.lock()
        var lastFolder = fileDB.curFolder
        fileDB.ver += 1
        fileDB.unlock()
        var startFolder=lastFolder
        if direction == .zero && dest != "" { startFolder = dest }
        if !(direction == .zero && lastFolder == startFolder) {
            // 重置递归模式
            // Reset recursive mode
            if !globalVar.keepFilterStateWhenSwitchFolder{
                publicVar.isRecursiveMode = false
            }
            // 重置搜索过滤
            // Reset search filter
            if !globalVar.keepFilterStateWhenSwitchFolder{
                publicVar.isFilenameFilterOn = false
                
            }
            // 重置Finder标签过滤
            // Reset Finder tag filter
            if !globalVar.keepFilterStateWhenSwitchFolder{
                publicVar.finderTagFilters.removeAll()
                publicVar.isFinderTagFilterReversed = false
                publicVar.isFinderTagFilterModeAnd = false
                publicVar.ratingFilters.removeAll()
                publicVar.isRatingFilterReversed = false
            }
            // 重置自动播放可见视频
            // Reset auto-play visible video
            publicVar.autoPlayVisibleVideo = false
        }
        
        treeTraversal(folderURL: URL(string: startFolder)!, round: searchFolderRound, initURL: URL(string: startFolder)!, direction: direction,
                          sameLevel: secondDirection == .down, skip: skip, dryRun: dryRun)

        // let a=1
        fileDB.lock()
        var curIndex=fileDB.db.index(forKey: SortKeyDir(startFolder))!
        if direction != .zero {
            while true {
                if direction == .right {
                    if(fileDB.db.index(after: curIndex) != fileDB.db.endIndex) {
                        curIndex=fileDB.db.index(after: curIndex)
                    }else{
                        break
                    }
                }
                if direction == .left {
                    if(curIndex != fileDB.db.startIndex) {
                        curIndex=fileDB.db.index(before: curIndex)
                    }else{
                        break
                    }
                }
                
                if fileDB.db[curIndex].1.fileCount>0 && fileDB.db[curIndex].1.ver == fileDB.ver {
                    break
                }
            }
        }
        let nextFolder = fileDB.db[curIndex].0.path
        let fileCount = fileDB.db[curIndex].1.files.count
        // log(fileDB.db[curIndex].1.files.count)
        fileDB.unlock()
        // testTmpFolder=fileDB.db[curIndex].0
        
        if(true){
            let curTime = DispatchTime.now()
            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let timeInterval = Double(nanoTime) / 1_000_000_000
            log("Time taken to complete file list: \(timeInterval) seconds")
            // Time taken to complete file list
        }
        
        if nextFolder != lastFolder {
            publicVar.folderStepStack.insert(lastFolder, at: 0)
        }
        
        if globalVar.dirTreeAutoExpand {
            treeReLocate(path: nextFolder, doCollapse: doCollapse, expandLast: expandLast)
        }
        
        log("Switch:",nextFolder.removingPercentEncoding!)
        switchFolder(path: nextFolder)
        startWatchingDirectory(atPath: nextFolder.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!)
        if !publicVar.isInLargeView {setWindowTitle()}
        LRUMemRecord(path: nextFolder, count: fileCount)
        
        let defaults = UserDefaults.standard
        defaults.set(nextFolder, forKey: "lastFolder")

    }
    
    class FolderStatisticInfo {
        struct Snapshot {
            let folderCount: Int
            let fileCount: Int
            let imageCount: Int
            let videoCount: Int
            let totalSize: Int
        }

        private let lock = NSLock()
        private var folderCount = 0
        private var fileCount = 0
        private var imageCount = 0
        private var videoCount = 0
        private var totalSize = 0

        func snapshot() -> Snapshot {
            lock.lock()
            let result = Snapshot(
                folderCount: folderCount,
                fileCount: fileCount,
                imageCount: imageCount,
                videoCount: videoCount,
                totalSize: totalSize
            )
            lock.unlock()
            return result
        }

        func addFolder(size: Int = 0) {
            lock.lock()
            folderCount += 1
            totalSize += size
            lock.unlock()
        }

        func addFile(url: URL, size: Int) {
            let pathExtension = url.pathExtension.lowercased()
            let isImage = globalVar.HandledImageAndRawExtensions.contains(pathExtension)
            let isVideo = globalVar.HandledVideoExtensions.contains(pathExtension)
                && isNotFalseTsVideoFile(url)

            lock.lock()
            fileCount += 1
            if isImage {
                imageCount += 1
            } else if isVideo {
                videoCount += 1
            }
            totalSize += size
            lock.unlock()
        }
    }
    
    func handleGetInfo(_ providedUrls: [URL] = []) {
        var urls = providedUrls
        if providedUrls.isEmpty {
            urls = publicVar.selectedUrls()
        }
        if urls.isEmpty {return}

        if urls.count == 1 {
            let url = urls[0]
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {

                let aliasResourceValues = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
                let isAliasFile = aliasResourceValues?.isAliasFile ?? false
                let isSymlink = aliasResourceValues?.isSymbolicLink ?? false
                let isAlias = isAliasFile || isSymlink
                let resolvedUrl: URL
                let aliasTypeLabel: String
                if isSymlink {
                    resolvedUrl = url.resolvingSymlinksInPath()
                    aliasTypeLabel = NSLocalizedString("Symbolic Link", comment: "符号链接")
                } else if isAliasFile {
                    resolvedUrl = (try? URL(resolvingAliasFileAt: url)) ?? url
                    aliasTypeLabel = NSLocalizedString("Finder Alias", comment: "Finder替身")
                } else {
                    resolvedUrl = url
                    aliasTypeLabel = ""
                }
                let resolvedIsDirectory = resolvedUrl.hasDirectoryPath

                if !isDirectory.boolValue && !resolvedIsDirectory {
                    presentSingleFileInfo(url: url, resolvedUrl: resolvedUrl, isAlias: isAlias, aliasTypeLabel: aliasTypeLabel)
                    return
                } else {
                    presentSingleFolderInfo(url: url, resolvedUrl: resolvedUrl, isAlias: isAlias, aliasTypeLabel: aliasTypeLabel)
                    return
                }
            }
        }

        presentMultiSelectionInfo(urls: urls)
    }

    // MARK: - Info window builders

    private func presentSingleFileInfo(url: URL, resolvedUrl: URL, isAlias: Bool, aliasTypeLabel: String) {
        let file = FileModel(path: "", ver: 0)
        file.path = url.absoluteString
        file.fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        file.createDate = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
        file.modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        file.addDate = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate)

        let ext = resolvedUrl.pathExtension.lowercased()
        let isImage = globalVar.HandledImageAndRawExtensions.contains(ext)
        let isVideo = globalVar.HandledVideoExtensions.contains(ext) && isNotFalseTsVideoFile(resolvedUrl)
        if isImage || isVideo {
            file.imageInfo = getImageInfo(url: resolvedUrl, needMetadata: true)
        }
        let exifData = convertExifData(file: file)
        var formatedExifData = formatExifData(exifData ?? [:], isVideo: isVideo, needWarp: false)

        formatedExifData.insert((NSLocalizedString("File Path", comment: "文件路径"), bidiIsolate(url.deletingLastPathComponent().path + "/")), at: 0)
        if isAlias {
            formatedExifData.insert((NSLocalizedString("Original Path", comment: "原始路径"), bidiIsolate(resolvedUrl.path)), at: 0)
            formatedExifData.insert((NSLocalizedString("Alias Type", comment: "替身类型"), aliasTypeLabel), at: 0)
        }

        var sections = splitExifIntoSections(formatedExifData)

        if isVideo {
            // if let formatted = getVideoMetadataFormatedFFmpeg(for: resolvedUrl), !formatted.isEmpty {
            //     let pairs = formatted.map { ($0.0, $0.1) }
            //     sections.append(FileInfoSection(
            //         title: NSLocalizedString("Video", comment: "视频"),
            //         kind: .keyValue(pairs)
            //     ))
            // }
            if let formatted = getVideoMetadataFormatedFFmpeg(for: resolvedUrl), !formatted.isEmpty {
                sections.append(contentsOf: splitVideoMetadataIntoSections(formatted))
            }
            if let raw = getVideoMetadataFFmpeg(for: resolvedUrl), !raw.isEmpty {
                sections.append(FileInfoSection(
                    title: true ? "Video Metadata" : NSLocalizedString("Video Metadata", comment: "视频元数据"),
                    kind: .textBlock(raw, monospace: true),
                    collapsible: true,
                    initiallyCollapsed: true
                ))
            }
        }

        if isImage {
            if let properties = file.imageInfo?.properties, !properties.isEmpty {
                let json = jsonDumpString(properties)
                sections.append(FileInfoSection(
                    title: true ? "EXIF Metadata" : NSLocalizedString("EXIF Metadata", comment: "EXIF元数据"),
                    kind: .textBlock(json, monospace: true),
                    collapsible: true,
                    initiallyCollapsed: true
                ))
            }
            if let metadata = file.imageInfo?.metadata,
               let tags = CGImageMetadataCopyTags(metadata) as NSArray? {
                var result = [String: Any]()
                for tag in tags {
                    if CFGetTypeID(tag.self as CFTypeRef) == CGImageMetadataTagGetTypeID() {
                        let tagMetadata = tag as! CGImageMetadataTag
                        if let cfName = CGImageMetadataTagCopyName(tagMetadata),
                           let cfPrefix = CGImageMetadataTagCopyPrefix(tagMetadata),
                           String(cfPrefix) != "exif" && String(cfPrefix) != "aux" && String(cfPrefix) != "exifEX" && String(cfPrefix) != "tiff" {
                            let name = String(cfPrefix) + "::" + String(cfName)
                            let value = CGImageMetadataTagCopyValue(tagMetadata)
                            result[name] = value
                        }
                    }
                }
                if !result.isEmpty {
                    let json = jsonDumpString(result)
                    sections.append(FileInfoSection(
                        title: true ? "XMP / IPTC Metadata" : NSLocalizedString("XMP / IPTC Metadata", comment: "XMP/IPTC元数据"),
                        kind: .textBlock(json, monospace: true),
                        collapsible: true,
                        initiallyCollapsed: true
                    ))
                }
            }
        }

        let header = buildHeaderForSingleFile(
            url: url,
            resolvedUrl: resolvedUrl,
            file: file,
            isAlias: isAlias,
            aliasTypeLabel: aliasTypeLabel
        )

        FileInfoWindowController.show(
            header: header,
            sections: sections,
            revealURLs: [url],
            anchorWindow: view.window
        )
    }

    private func presentSingleFolderInfo(url: URL, resolvedUrl: URL, isAlias: Bool, aliasTypeLabel: String) {
        var generalPairs: [(String, String)] = []
        if isAlias {
            generalPairs.append((NSLocalizedString("Alias Type", comment: "替身类型"), aliasTypeLabel))
            generalPairs.append((NSLocalizedString("Original Path", comment: "原始路径"), bidiIsolate(resolvedUrl.path)))
        }
        generalPairs.append((NSLocalizedString("Folder Path", comment: "文件夹路径"), bidiIsolate(url.path)))
        generalPairs.append((NSLocalizedString("Folder Name", comment: "文件夹名称"), url.lastPathComponent))

        if let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) {
            generalPairs.append((NSLocalizedString("Creation Date", comment: "创建日期"), formatDateToCurrentTimeZone(creationDate)))
        }
        if let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) {
            generalPairs.append((NSLocalizedString("Modification Date", comment: "修改日期"), formatDateToCurrentTimeZone(modDate)))
        }
        if let addDate = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) {
            generalPairs.append((NSLocalizedString("Added Date", comment: "添加日期"), formatDateToCurrentTimeZone(addDate)))
        }

        let stat = FolderStatisticInfo()
        let sections: [FileInfoSection] = [
            FileInfoSection(title: NSLocalizedString("General", comment: "通用"), kind: .keyValue(generalPairs)),
            FileInfoSection(title: NSLocalizedString("Statistics", comment: "统计信息"), kind: .keyValue(folderStatisticPairs(stat))),
        ]

        let header = buildHeaderForFolder(url: url, resolvedUrl: resolvedUrl, isAlias: isAlias, aliasTypeLabel: aliasTypeLabel)
        let scanState = FileInfoScanState()

        let controller = FileInfoWindowController.show(
            header: header,
            sections: sections,
            revealURLs: [url],
            anchorWindow: view.window,
            onClose: { scanState.cancel() }
        )

        startFolderStatisticScan(
            state: scanState,
            controller: controller,
            makeSections: { [weak self] in
                guard let self = self else { return sections }
                return [
                    FileInfoSection(title: NSLocalizedString("General", comment: "通用"), kind: .keyValue(generalPairs)),
                    FileInfoSection(title: NSLocalizedString("Statistics", comment: "统计信息"), kind: .keyValue(self.folderStatisticPairs(stat))),
                ]
            },
            work: { [weak self] isCancelled, onProgress in
                self?.getFolderStatistic(resolvedUrl, result: stat, isCancelled: isCancelled, onProgress: onProgress)
            }
        )
    }

    private func presentMultiSelectionInfo(urls: [URL]) {
        let stat = FolderStatisticInfo()
        let sections: [FileInfoSection] = [
            FileInfoSection(title: NSLocalizedString("Statistics", comment: "统计信息"), kind: .keyValue(folderStatisticPairs(stat))),
        ]

        let header = buildHeaderForMultiSelection(urls: urls)
        let scanState = FileInfoScanState()

        let controller = FileInfoWindowController.show(
            header: header,
            sections: sections,
            revealURLs: urls,
            anchorWindow: view.window,
            onClose: { scanState.cancel() }
        )

        startFolderStatisticScan(
            state: scanState,
            controller: controller,
            makeSections: { [weak self] in
                guard let self = self else { return sections }
                return [
                    FileInfoSection(title: NSLocalizedString("Statistics", comment: "统计信息"), kind: .keyValue(self.folderStatisticPairs(stat))),
                ]
            },
            work: { [weak self] isCancelled, onProgress in
                var lastProgressTime = Date.distantPast
                for url in urls {
                    if isCancelled() { return }
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                        let isAlias = (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) ?? false
                        let aliasSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        if isAlias {
                            let resolvedUrl = try? URL(resolvingAliasFileAt: url)
                            if let resolved = resolvedUrl, resolved.hasDirectoryPath {
                                stat.addFolder(size: aliasSize)
                            } else {
                                stat.addFile(url: resolvedUrl ?? url, size: aliasSize)
                            }
                        } else if isDirectory.boolValue {
                            stat.addFolder()
                            self?.getFolderStatistic(url, result: stat, isCancelled: isCancelled, onProgress: onProgress)
                        } else {
                            stat.addFile(url: url, size: aliasSize)
                        }
                    }
                    if Date().timeIntervalSince(lastProgressTime) >= 0.25 {
                        lastProgressTime = Date()
                        onProgress()
                    }
                }
            }
        )
    }

    // MARK: - Section / header helpers

    private func bidiIsolate(_ s: String) -> String {
        // \u{2066} = LRI, \u{2069} = PDI — keep filesystem paths rendered LTR even in RTL locales
        return "\u{2066}" + s + "\u{2069}"
    }

    private func splitExifIntoSections(_ data: [(String, Any)]) -> [FileInfoSection] {
        var groups: [[(String, String)]] = [[]]
        for (k, v) in data {
            if k == "-" {
                groups.append([])
            } else {
                let valueStr: String
                if let s = v as? String {
                    valueStr = s
                } else {
                    valueStr = String(describing: v)
                }
                groups[groups.count - 1].append((k, valueStr))
            }
        }
        let titles = [
            NSLocalizedString("General", comment: "通用"),
            NSLocalizedString("Image", comment: "图像"),
            NSLocalizedString("GPS", comment: "GPS"),
        ]
        var result: [FileInfoSection] = []
        var idx = 0
        for group in groups {
            if group.isEmpty { idx += 1; continue }
            let title = idx < titles.count ? titles[idx] : NSLocalizedString("Other", comment: "其他")
            result.append(FileInfoSection(title: title, kind: .keyValue(group)))
            idx += 1
        }
        return result
    }

    /// Split the flat FFprobe output (which uses ("-","-") to separate streams) into
    /// semantic sections: container info, then one section per video/audio stream.
    /// Detection relies on the `index` key being the first localized key in each
    /// stream's translation map for both video and audio.
    private func splitVideoMetadataIntoSections(_ pairs: [(String, String)]) -> [FileInfoSection] {
        let videoIndexKey = NSLocalizedString("VideoMetadata-Index", comment: "索引")
        let audioIndexKey = NSLocalizedString("AudioMetadata-Index", comment: "索引")

        var sections: [(title: String, pairs: [(String, String)])] = []
        var currentTitle = NSLocalizedString("Container", comment: "容器")
        var currentPairs: [(String, String)] = []
        var videoCount = 0
        var audioCount = 0

        func flush() {
            if !currentPairs.isEmpty {
                sections.append((currentTitle, currentPairs))
                currentPairs = []
            }
        }

        for p in pairs {
            if p.0 == "-" { continue }
            if p.0 == videoIndexKey {
                flush()
                videoCount += 1
                currentTitle = videoCount > 1
                    ? NSLocalizedString("Video Stream", comment: "视频流") + " \(videoCount)"
                    : NSLocalizedString("Video Stream", comment: "视频流")
            } else if p.0 == audioIndexKey {
                flush()
                audioCount += 1
                currentTitle = audioCount > 1
                    ? NSLocalizedString("Audio Stream", comment: "音频流") + " \(audioCount)"
                    : NSLocalizedString("Audio Stream", comment: "音频流")
            }
            currentPairs.append(p)
        }
        flush()

        return sections.map { FileInfoSection(title: $0.title, kind: .keyValue($0.pairs)) }
    }

    private func folderStatisticPairs(_ stat: FolderStatisticInfo) -> [(String, String)] {
        let stat = stat.snapshot()
        return [
            (NSLocalizedString("Folders", comment: "目录"), "\(stat.folderCount)"),
            (NSLocalizedString("Files", comment: "文件"), "\(stat.fileCount)"),
            (NSLocalizedString("Images", comment: "图像"), "\(stat.imageCount)"),
            (NSLocalizedString("Videos", comment: "视频"), "\(stat.videoCount)"),
            (NSLocalizedString("Total Size", comment: "总大小"), readableFileSize(stat.totalSize)),
        ]
    }

    private func startFolderStatisticScan(
        state: FileInfoScanState,
        controller: FileInfoWindowController,
        makeSections: @escaping () -> [FileInfoSection],
        work: @escaping (_ isCancelled: () -> Bool, _ onProgress: @escaping () -> Void) -> Void
    ) {
        let publish: () -> Void = { [weak controller] in
            DispatchQueue.main.async {
                guard !state.isCancelled() else { return }
                controller?.updateSections(makeSections())
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            work(state.isCancelled, publish)
            publish()
        }
    }

    private func jsonDumpString(_ dictionary: [String: Any]) -> String {
        let sorted = dictionary.sorted { $0.key < $1.key }
        let dict = Dictionary(uniqueKeysWithValues: sorted)
        let serializable = dict.filter { (_, value) in JSONSerialization.isValidJSONObject([value]) }
        do {
            let data = try JSONSerialization.data(withJSONObject: serializable, options: [.prettyPrinted, .sortedKeys])
            if let s = String(data: data, encoding: .utf8) {
                return s.replacingOccurrences(of: "\\/", with: "/")
            }
        } catch {
            log("JSON serialization error: \(error)", level: .warn)
        }
        return "{}"
    }

    private func buildHeaderForSingleFile(url: URL, resolvedUrl: URL, file: FileModel, isAlias: Bool, aliasTypeLabel: String) -> FileInfoHeader {
        let icon = NSWorkspace.shared.icon(forFile: resolvedUrl.path)
        icon.size = NSSize(width: 64, height: 64)

        var parts: [String] = []
        if let t = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription, !t.isEmpty {
            parts.append(t)
        } else if !url.pathExtension.isEmpty {
            parts.append(url.pathExtension.uppercased())
        }
        if let s = file.imageInfo?.size, s.width > 0, s.height > 0 {
            parts.append("\(Int(s.width))×\(Int(s.height))")
        }
        if let size = file.fileSize {
            parts.append(readableFileSize(size))
        }
        if isAlias {
            parts.append(aliasTypeLabel)
        }
        return FileInfoHeader(icon: icon, title: url.lastPathComponent, subtitle: parts.joined(separator: " · "))
    }

    private func buildHeaderForFolder(url: URL, resolvedUrl: URL, isAlias: Bool, aliasTypeLabel: String) -> FileInfoHeader {
        let icon = NSWorkspace.shared.icon(forFile: resolvedUrl.path)
        icon.size = NSSize(width: 64, height: 64)
        var parts: [String] = []
        let typeDesc = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
        if let t = typeDesc, !t.isEmpty {
            parts.append(t)
        } else {
            parts.append(NSLocalizedString("Folder", comment: "文件夹"))
        }
        if isAlias {
            parts.append(aliasTypeLabel)
        }
        let title = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return FileInfoHeader(icon: icon, title: title, subtitle: parts.joined(separator: " · "))
    }

    private func buildHeaderForMultiSelection(urls: [URL]) -> FileInfoHeader {
        let icon: NSImage
        if urls.count == 1, let first = urls.first {
            icon = NSWorkspace.shared.icon(forFile: first.path)
        } else {
            icon = NSImage(named: NSImage.multipleDocumentsName) ?? NSImage()
        }
        icon.size = NSSize(width: 64, height: 64)
        let title = String(format: NSLocalizedString("%d items selected", comment: "选中 %d 项"), urls.count)
        return FileInfoHeader(icon: icon, title: title, subtitle: "")
    }
    
    func getFolderStatistic(_ folderURL: URL, result: FolderStatisticInfo, isCancelled: () -> Bool = { false }, onProgress: (() -> Void)? = nil) {
        let properties: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .isAliasFileKey]
        let options:FileManager.DirectoryEnumerationOptions = [] // [.skipsHiddenFiles]
        
        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: properties, options: options, errorHandler: { (url, error) -> Bool in
            log("Error enumerating \(url): \(error.localizedDescription)", level: .warn)
            return true
        })

        var lastProgressTime = Date.distantPast
        
        while let url = enumerator?.nextObject() as? URL {
            if isCancelled() { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isAlias = (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) ?? false
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

            if isAlias && !isDirectory {
                if let resolved = try? URL(resolvingAliasFileAt: url), resolved.hasDirectoryPath {
                    result.addFolder(size: fileSize)
                } else {
                    result.addFile(url: url, size: fileSize)
                }
            } else if !isDirectory {
                result.addFile(url: url, size: fileSize)
            } else {
                result.addFolder()
            }

            if let onProgress = onProgress, Date().timeIntervalSince(lastProgressTime) >= 0.25 {
                lastProgressTime = Date()
                onProgress()
            }
        }
    }
}
