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

private struct MediaUnitScanConfiguration {
    let showHidden: Bool
    let showAllTypes: Bool
    let showArchives: Bool
    let handledExtensions: Set<String>
    let imageExtensions: Set<String>
    let videoExtensions: Set<String>
    let sortType: SortType
    let sortFolderFirst: Bool
    let sortUseFullPath: Bool
    let randomSeed: Int
    let searchEnabled: Bool
    let searchText: String
    let searchUseRegex: Bool
    let searchCaseSensitive: Bool
    let searchUseFullPath: Bool
    let usePinyinSearch: Bool
    let usePinyinInitialSearch: Bool
    let finderFilters: Set<String>
    let finderFilterAnd: Bool
    let finderFilterReversed: Bool
    let ratingFilters: Set<Int>
    let ratingFilterReversed: Bool
}

extension ViewController {
    private func directMediaCounts(in folderURL: URL, showHiddenFiles: Bool) -> (images: Int, videos: Int)? {
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isAliasFileKey],
            options: options
        ) else {
            return nil
        }

        var imageCount = 0
        var videoCount = 0
        for fileURL in contents {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey])
            if values?.isDirectory == true || values?.isAliasFile == true {
                continue
            }

            let ext = fileURL.pathExtension.lowercased()
            if globalVar.HandledImageAndRawExtensions.contains(ext) {
                imageCount += 1
            } else if globalVar.HandledVideoExtensions.contains(ext) {
                videoCount += 1
            }
        }
        return (imageCount, videoCount)
    }

    /// Populate an external folder's optional count badge only when its item is
    /// actually requested by the collection view. This avoids an N+1 scan of
    /// every SMB child folder during first paint.
    func scheduleNetworkFolderMediaCountIfNeeded(for fileModel: FileModel) {
        guard globalVar.showFolderMediaCountBadge,
              fileModel.isDir,
              fileModel.childImageCount == nil,
              fileModel.childVideoCount == nil,
              let folderURL = URL(string: fileModel.path),
              VolumeManager.shared.isNetworkVolume(folderURL)
        else { return }

        fileDB.lock()
        let parentFolder = fileDB.curFolder
        let expectedVersion = fileDB.db[SortKeyDir(parentFolder)]?.ver
        fileDB.unlock()
        guard let expectedVersion else { return }

        let taskKey = "\(expectedVersion)|\(folderURL.absoluteString)"
        folderMediaCountTasksLock.lock()
        guard !folderMediaCountTasks.contains(taskKey) else {
            folderMediaCountTasksLock.unlock()
            return
        }
        folderMediaCountTasks.insert(taskKey)
        folderMediaCountTasksLock.unlock()

        let showHiddenFiles = publicVar.isShowHiddenFile

        // Leave the first paint and visible-thumbnail requests a short head
        // start before an optional child-folder enumeration uses the share.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self else { return }
            defer {
                self.folderMediaCountTasksLock.lock()
                self.folderMediaCountTasks.remove(taskKey)
                self.folderMediaCountTasksLock.unlock()
            }

            func isCurrent() -> Bool {
                self.fileDB.lock()
                let current = self.fileDB.curFolder == parentFolder
                    && self.fileDB.db[SortKeyDir(parentFolder)]?.ver == expectedVersion
                self.fileDB.unlock()
                return current && !self.willTerminate
            }

            guard isCurrent() else { return }

            guard let ioLease = NetworkIOCoordinator.shared.beginBackgroundAccess(
                for: folderURL,
                shouldContinue: isCurrent
            ) else { return }
            let counts = self.directMediaCounts(
                in: folderURL,
                showHiddenFiles: showHiddenFiles
            )
            ioLease.end()
            guard let counts else { return }

            DispatchQueue.main.async { [weak self, weak fileModel] in
                guard let self, let fileModel else { return }
                self.fileDB.lock()
                guard self.fileDB.curFolder == parentFolder,
                      self.fileDB.db[SortKeyDir(parentFolder)]?.ver == expectedVersion,
                      fileModel.ver == expectedVersion
                else {
                    self.fileDB.unlock()
                    return
                }
                fileModel.childImageCount = counts.images
                fileModel.childVideoCount = counts.videos
                self.fileDB.unlock()

                for case let item as CustomCollectionViewItem in self.collectionView.visibleItems()
                where item.file === fileModel {
                    item.refreshFolderMediaCountBadge()
                }
            }
        }
    }

    private func isMediaUnitRoot(_ folderURL: URL) -> Bool {
        guard publicVar.isMediaUnitMode,
              let rootPath = publicVar.mediaUnitRootPath else { return false }
        return isSameOrDescendantMediaUnitPath(folderURL.absoluteString, of: rootPath)
            && normalizedMediaUnitURL(folderURL.absoluteString)?.path
                == normalizedMediaUnitURL(rootPath)?.path
    }

    private func isMediaUnitFolder(_ folderURL: URL) -> Bool {
        guard publicVar.isMediaUnitMode,
              let rootPath = publicVar.mediaUnitRootPath else { return false }
        return isDirectMediaUnitChildPath(folderURL.absoluteString, of: rootPath)
    }

    private func mediaUnitSearchMatches(
        path: String,
        searchText: String,
        useRegex: Bool,
        caseSensitive: Bool,
        useFullPath: Bool,
        usePinyinSearch: Bool,
        usePinyinInitialSearch: Bool
    ) -> Bool {
        guard !searchText.isEmpty else { return true }
        let decodedPath = path.removingPercentEncoding ?? path
        let fileName: String
        if useFullPath {
            fileName = decodedPath.replacingOccurrences(of: "file://", with: "")
        } else {
            fileName = URL(string: path)?.lastPathComponent ?? decodedPath
        }
        if useRegex {
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: searchText, options: options) else {
                return false
            }
            let range = NSRange(location: 0, length: fileName.utf16.count)
            return regex.firstMatch(in: fileName, options: [], range: range) != nil
        }
        var matchFileName = fileName
        var matchSearchText = searchText
        if !caseSensitive {
            matchFileName = matchFileName.lowercased()
            matchSearchText = matchSearchText.lowercased()
        }
        var result = matchFileName.contains(matchSearchText)
        if usePinyinSearch {
            result = result || convertToPinyin(matchFileName, toPinyinFull: true).contains(matchSearchText)
        }
        if usePinyinInitialSearch {
            result = result || convertToPinyin(matchFileName, toPinyinFull: false).contains(matchSearchText)
        }
        return result
    }

    private func makeMediaUnitScanConfiguration() -> MediaUnitScanConfiguration {
        MediaUnitScanConfiguration(
            showHidden: publicVar.isShowHiddenFile,
            showAllTypes: publicVar.isShowAllTypeFile,
            showArchives: globalVar.showArchiveFileType,
            handledExtensions: Set(publicVar.HandledFileExtensions),
            imageExtensions: Set(publicVar.HandledImageAndRawExtensions),
            videoExtensions: Set(publicVar.HandledVideoExtensions),
            sortType: publicVar.profile.sortType,
            sortFolderFirst: publicVar.profile.isSortFolderFirst,
            sortUseFullPath: publicVar.profile.isSortUseFullPath,
            randomSeed: publicVar.randomSeed,
            searchEnabled: publicVar.isFilenameFilterOn,
            searchText: searchField?.stringValue ?? search_searchText,
            searchUseRegex: search_useRegex,
            searchCaseSensitive: search_isCaseSensitive,
            searchUseFullPath: search_isUseFullPath,
            usePinyinSearch: globalVar.usePinyinSearch,
            usePinyinInitialSearch: globalVar.usePinyinInitialSearch,
            finderFilters: publicVar.finderTagFilters,
            finderFilterAnd: publicVar.isFinderTagFilterModeAnd,
            finderFilterReversed: publicVar.isFinderTagFilterReversed,
            ratingFilters: publicVar.ratingFilters,
            ratingFilterReversed: publicVar.isRatingFilterReversed
        )
    }

    /// Build a flat model for one media unit away from the main thread. The
    /// enumerator never follows aliases/symlinks into another hierarchy and
    /// checks the directory generation on every item so a stale navigation can
    /// stop promptly.
    private func buildMediaUnitModel(
        folderURL: URL,
        version: Int,
        configuration: MediaUnitScanConfiguration,
        shouldContinue: @escaping () -> Bool
    ) -> DirModel? {
        let model = DirModel(path: folderURL.absoluteString, ver: version)
        model.isMediaUnitMode = true
        model.isRecursiveMode = false

        var propertyKeys: Set<URLResourceKey> = [
            .isDirectoryKey, .isHiddenKey, .isAliasFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .creationDateKey, .contentModificationDateKey,
            .addedToDirectoryDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
            .tagNamesKey
        ]
        let shouldReadFinderTagsSynchronously = !VolumeManager.shared.isNetworkVolume(folderURL)
            || !configuration.finderFilters.isEmpty
        if !shouldReadFinderTagsSynchronously {
            propertyKeys.remove(.tagNamesKey)
        }
        let options: FileManager.DirectoryEnumerationOptions = configuration.showHidden ? [] : [.skipsHiddenFiles]
        var enumerationFailed = false
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(propertyKeys),
            options: options,
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        )

        guard let enumerator else { return model }
        while let itemURL = enumerator.nextObject() as? URL {
            guard shouldContinue() else { return nil }
            let values = try? itemURL.resourceValues(forKeys: propertyKeys)
            let isDirectory = values?.isDirectory ?? false
            let isAlias = values?.isAliasFile ?? false
            let isSymlink = values?.isSymbolicLink ?? false
            if isDirectory {
                // Do not let a link or Finder alias escape the media root.
                if isAlias || isSymlink {
                    enumerator.skipDescendants()
                }
                continue
            }
            if isAlias || isSymlink {
                // A file alias remains addressable by its real path in the
                // ordinary scanner; in a media unit it is safer to omit links
                // because resolving them can leave the selected unit.
                continue
            }

            let ext = itemURL.pathExtension.lowercased()
            let supportedArchive = configuration.showArchives && isSupportedArchiveURL(itemURL)
            guard configuration.showAllTypes || configuration.handledExtensions.contains(ext) || supportedArchive else { continue }
            let absolutePath = itemURL.absoluteString
            if configuration.searchEnabled && !mediaUnitSearchMatches(
                path: absolutePath,
                searchText: configuration.searchText,
                useRegex: configuration.searchUseRegex,
                caseSensitive: configuration.searchCaseSensitive,
                useFullPath: configuration.searchUseFullPath,
                usePinyinSearch: configuration.usePinyinSearch,
                usePinyinInitialSearch: configuration.usePinyinInitialSearch
            ) {
                continue
            }

            let tags = shouldReadFinderTagsSynchronously ? (values?.tagNames ?? []) : []
            if !configuration.finderFilters.isEmpty {
                let tagSet = Set(tags)
                let matched = configuration.finderFilterAnd
                    ? configuration.finderFilters.isSubset(of: tagSet)
                    : !configuration.finderFilters.isDisjoint(with: tagSet)
                if configuration.finderFilterReversed ? matched : !matched { continue }
            }
            if !configuration.ratingFilters.isEmpty {
                let rating = readRating(from: itemURL) ?? 0
                let matched = configuration.ratingFilters.contains(rating)
                if configuration.ratingFilterReversed ? matched : !matched { continue }
            }

            let fileKey = SortKeyFile(
                absolutePath,
                isInSameDir: false,
                sortType: configuration.sortType,
                isSortFolderFirst: configuration.sortFolderFirst,
                isSortUseFullPath: configuration.sortUseFullPath,
                randomSeed: configuration.randomSeed
            )
            fileKey.size = values?.fileSize ?? 0
            fileKey.createDate = values?.creationDate ?? Date()
            fileKey.modDate = values?.contentModificationDate ?? Date()
            fileKey.addDate = values?.addedToDirectoryDate ?? Date()
            let fileModel = FileModel(
                path: absolutePath,
                ver: version,
                fileSize: values?.fileSize,
                createDate: values?.creationDate,
                modDate: values?.contentModificationDate,
                addDate: values?.addedToDirectoryDate
            )
            if values?.isUbiquitousItem == true,
               let downloadingStatus = values?.ubiquitousItemDownloadingStatus,
               downloadingStatus != .current {
                fileModel.doNotActualRead = true
            }
            fileModel.finderTags = tags
            model.files[fileKey] = fileModel
            model.fileCount += 1
            if configuration.imageExtensions.contains(ext) { model.imageCount += 1 }
            if configuration.videoExtensions.contains(ext) { model.videoCount += 1 }
        }

        var id = 0
        var imageID = 0
        var imageAndVideoID = 0
        for (_, file) in model.files {
            file.id = id
            id += 1
            // Navigation and thumbnail decoding consume type/ext, not the
            // scanner's counts. Initialize them before publishing the model,
            // just as the ordinary directory scanner does.
            file.ext = URL(string: file.path)?.pathExtension.lowercased() ?? ""
            if configuration.imageExtensions.contains(file.ext) {
                file.type = .image
                file.idInImage = imageID
                file.idInImageAndVideo = imageAndVideoID
                imageID += 1
                imageAndVideoID += 1
            } else if configuration.videoExtensions.contains(file.ext) {
                file.type = .video
                file.idInImageAndVideo = imageAndVideoID
                imageAndVideoID += 1
            } else {
                file.type = .other
            }
        }
        guard !enumerationFailed else { return nil }
        model.isFiltered = configuration.searchEnabled
        return model
    }

    private func beginMediaUnitScan(
        folderURL: URL,
        lastFolder: String,
        doCollapse: Bool,
        expandLast: Bool,
        version: Int,
        removePendingHistoryAfterCompletion: Bool = false
    ) {
        guard let rootPath = publicVar.mediaUnitRootPath else {
            publicVar.isInStageOneProgress = false
            return
        }
        let destinationPath = folderURL.absoluteString
        let configuration = makeMediaUnitScanConfiguration()
        publicVar.mediaUnitPendingPath = destinationPath
        coreAreaView.showInfo(
            NSLocalizedString("Loading Media Unit...", comment: "正在加载媒体单元…"),
            timeOut: .infinity,
            cannotBeCleard: false
        )
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let model = self.buildMediaUnitModel(
                folderURL: folderURL,
                version: version,
                configuration: configuration,
                shouldContinue: { [weak self] in
                    guard let self else { return false }
                    self.fileDB.lock()
                    let currentVersion = self.fileDB.ver == version
                    self.fileDB.unlock()
                    return currentVersion && !self.willTerminate
                }
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.fileDB.lock()
                let isCurrent = self.fileDB.ver == version
                    && self.publicVar.isMediaUnitMode
                    && self.publicVar.mediaUnitRootPath == rootPath
                    && self.publicVar.mediaUnitPendingPath == destinationPath
                self.fileDB.unlock()
                guard isCurrent else { return }
                guard let model else {
                    self.publicVar.mediaUnitPendingPath = nil
                    self.publicVar.isInStageOneProgress = false
                    self.coreAreaView.hideInfo(force: true)
                    self.coreAreaView.showOperationToast(
                        NSLocalizedString("Failed to load media unit", comment: "媒体单元加载失败"),
                        autoHide: 2.0
                    )
                    if let lastURL = URL(string: lastFolder), lastURL.isFileURL {
                        self.startWatchingDirectory(atPath: lastURL.path)
                    }
                    return
                }
                self.fileDB.lock()
                self.fileDB.db[SortKeyDir(destinationPath)] = model
                self.fileDB.unlock()
                if destinationPath != lastFolder {
                    self.publicVar.folderStepStack.insert(lastFolder, at: 0)
                }
                if removePendingHistoryAfterCompletion,
                   !self.publicVar.folderStepStack.isEmpty {
                    self.publicVar.folderStepStack.removeFirst()
                }
                if globalVar.dirTreeAutoExpand {
                    self.treeReLocate(path: destinationPath, doCollapse: doCollapse, expandLast: expandLast)
                }
                self.coreAreaView.hideInfo(force: true)
                self.switchFolder(path: destinationPath)
                if configuration.finderFilters.isEmpty,
                   VolumeManager.shared.isNetworkVolume(folderURL) {
                    let tagItems = model.files.compactMap { _, fileModel -> (url: URL, fileModel: FileModel)? in
                        guard let url = URL(string: fileModel.path) else { return nil }
                        return (url, fileModel)
                    }
                    self.scheduleNetworkTagHydration(
                        parentFolderURL: folderURL,
                        items: tagItems,
                        expectedVersion: version,
                        tagsAlreadyLoaded: false
                    )
                }
                self.startWatchingDirectory(atPath: folderURL.path)
                if !self.publicVar.isInLargeView { self.setWindowTitle() }
                LRUMemRecord(path: destinationPath, count: model.files.count)
                UserDefaults.standard.set(destinationPath, forKey: "lastFolder")
                self.publicVar.mediaUnitPendingPath = nil
            }
        }
    }

    /// Hydrates Finder tags after a network directory has already produced its
    /// first model/layout pass. Reads share the bounded SMB background budget
    /// and pause while a video on the same share is playing.
    private func scheduleNetworkTagHydration(
        parentFolderURL: URL,
        items: [(url: URL, fileModel: FileModel)],
        expectedVersion: Int,
        tagsAlreadyLoaded: Bool
    ) {
        guard !items.isEmpty else { return }
        let parentFolder = parentFolderURL.absoluteString
        let taskKey = "\(expectedVersion)|\(parentFolder)"

        networkMetadataTasksLock.lock()
        guard !networkMetadataTasks.contains(taskKey) else {
            networkMetadataTasksLock.unlock()
            return
        }
        networkMetadataTasks.insert(taskKey)
        networkMetadataTasksLock.unlock()

        // Finder tags are optional for the ordinary directory view, so give
        // first paint and visible thumbnails a head start on the share.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self else { return }
            defer {
                self.networkMetadataTasksLock.lock()
                self.networkMetadataTasks.remove(taskKey)
                self.networkMetadataTasksLock.unlock()
            }

            func isCurrent() -> Bool {
                self.fileDB.lock()
                let current = self.fileDB.curFolder == parentFolder
                    && self.fileDB.db[SortKeyDir(parentFolder)]?.ver == expectedVersion
                self.fileDB.unlock()
                return current && !self.willTerminate
            }

            func publish(_ batch: [(url: URL, fileModel: FileModel, tags: [String])]) {
                guard !batch.isEmpty else { return }
                EnhancedIndex.updateFiles(
                    batch.map { (url: $0.url, tags: $0.tags) },
                    isCalledByDirOpen: true
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.fileDB.lock()
                    guard self.fileDB.curFolder == parentFolder,
                          self.fileDB.db[SortKeyDir(parentFolder)]?.ver == expectedVersion
                    else {
                        self.fileDB.unlock()
                        return
                    }
                    for entry in batch where entry.fileModel.ver == expectedVersion {
                        entry.fileModel.finderTags = entry.tags
                    }
                    self.fileDB.unlock()

                    for case let item as CustomCollectionViewItem in self.collectionView.visibleItems() {
                        if batch.contains(where: { $0.fileModel === item.file }) {
                            item.refreshFinderTagDots()
                        }
                    }
                }
            }

            var batch: [(url: URL, fileModel: FileModel, tags: [String])] = []
            batch.reserveCapacity(16)
            for item in items {
                guard isCurrent() else { return }
                let tags: [String]
                if tagsAlreadyLoaded {
                    self.fileDB.lock()
                    tags = item.fileModel.finderTags
                    self.fileDB.unlock()
                } else {
                    guard let ioLease = NetworkIOCoordinator.shared.beginBackgroundAccess(
                        for: item.url,
                        shouldContinue: isCurrent
                    ) else { return }
                    tags = (try? item.url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
                    ioLease.end()
                }
                batch.append((item.url, item.fileModel, tags))
                if batch.count == 16 {
                    publish(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            publish(batch)
        }
    }

    func scanFiles(at folderURL: URL, contents: inout [URL], properties: [URLResourceKey]) {
        let options: FileManager.DirectoryEnumerationOptions = publicVar.isShowHiddenFile ? [] : [.skipsHiddenFiles]
        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: properties, options: options, errorHandler: { (url, error) -> Bool in
            print("Error enumerating \(url): \(error.localizedDescription)")
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
                    } else if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
                        videoCount += 1
                    }
                    let fc = fileCount
                    let ic = imageCount
                    let vc = videoCount
                    lock.unlock()
                    
                    let now = Date()
                    if now.timeIntervalSince(lastUpdateTime) >= 0.3 {
                        lastUpdateTime = now
                        DispatchQueue.main.async {
                            statusLabel.stringValue = String(format: NSLocalizedString("scanned-files-progress", comment: "当前已扫描 %d 个文件，其中图像 %d 个，视频 %d 个"), fc, ic, vc)
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
            statusLabel.stringValue = String(format: NSLocalizedString("scanned-files-progress", comment: "当前已扫描 %d 个文件，其中图像 %d 个，视频 %d 个"), fc, ic, vc)
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

    private func isArchiveExtension(_ ext: String) -> Bool {
        let archiveExtensions: Set<String> = ["zip", "cbz", "tar", "tgz", "tbz", "tbz2", "txz", "tar.gz", "tar.bz2", "tar.xz"]
        return archiveExtensions.contains(ext.lowercased())
    }

    func isSupportedArchiveURL(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tar.xz") {
            return true
        }
        return isArchiveExtension(url.pathExtension.lowercased())
    }

    func getArchiveVirtualFolderURL(_ archiveURL: URL) -> URL? {
        let safePath = archiveURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        if safePath.isEmpty { return nil }
        return URL(string: "\(VIRTUAL_ARCHIVE_PREFIX)/\(safePath)/")
    }

    private func decodeArchiveURL(from virtualArchiveURL: URL) -> URL? {
        return parseVirtualArchivePath(virtualArchiveURL.absoluteString)?.archiveURL
    }

    private func makeVirtualArchiveEntryURL(archiveURL: URL, entryPath: String) -> URL? {
        guard let root = getArchiveVirtualFolderURL(archiveURL) else { return nil }
        let encodedEntryPath = entryPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entryPath
        return URL(string: "\(root.absoluteString)\(encodedEntryPath)")
    }

    private func resolveArchiveImageEntries(for archiveURL: URL) -> [String] {
        let archivePath = archiveURL.absoluteString
        if let cached = archiveImageEntryCache[archivePath] {
            return cached
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = ["-tf", archiveURL.path]
        let stdOut = Pipe()
        let stdErr = Pipe()
        process.standardOutput = stdOut
        process.standardError = stdErr
        do {
            try process.run()
        } catch {
            log("Failed to list archive entries: \(error)", level: .error)
            return []
        }
        
        // Read stdout first to avoid potential pipe blocking on very large listing output.
        let outputData = stdOut.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            if let errText = String(data: stdErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), !errText.isEmpty {
                log("Failed to list archive entries: \(errText)", level: .error)
            }
            return []
        }

        let output = String(data: outputData, encoding: .utf8) ?? ""
        var entries: [String] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let decodedLine = decodeBsdtarEscapedPath(line)
            registerArchiveEntryPathAlias(archiveURL: archiveURL, displayPath: decodedLine, rawPath: line)
            if decodedLine.hasSuffix("/") { continue }
            let ext = URL(fileURLWithPath: decodedLine).pathExtension.lowercased()
            if globalVar.HandledImageAndRawExtensions.contains(ext) {
                entries.append(decodedLine)
            }
        }
        entries.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        archiveImageEntryCache[archivePath] = entries
        return entries
    }

    private func loadVirtualFolderContents(_ folderURL: URL) -> [URL] {
        if folderURL.path == "/VirtualFinderTagsFolder" {
            return []
        }
        if folderURL.path == "/VirtualFavoritesFolder" {
            var result: [URL] = []
            var seen = Set<String>()
            for favoritePath in globalVar.myFavoritesArray {
                guard let url = URL(string: favoritePath) else { continue }
                if seen.contains(url.absoluteString) { continue }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    seen.insert(url.absoluteString)
                    result.append(url)
                }
            }
            return result
        }
        if folderURL.path == "/VirtualHistoryFolder" {
            var result: [URL] = []
            var seen = Set<String>()
            for historyPath in publicVar.folderStepStack {
                guard let url = URL(string: historyPath) else { continue }
                if isVirtualFolderPath(url.absoluteString) { continue }
                if seen.contains(url.absoluteString) { continue }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    seen.insert(url.absoluteString)
                    result.append(url)
                }
            }
            return result
        }
        if folderURL.path.hasPrefix("/VirtualArchiveFolder") {
            guard let archiveURL = decodeArchiveURL(from: folderURL) else { return [] }
            let entries = resolveArchiveImageEntries(for: archiveURL)
            return entries.compactMap { makeVirtualArchiveEntryURL(archiveURL: archiveURL, entryPath: $0) }
        }
        return []
    }

    @discardableResult
    func openArchiveAsVirtualFolder(_ archiveURL: URL) -> Bool {
        guard let virtualURL = getArchiveVirtualFolderURL(archiveURL) else { return false }
        switchDirByDirection(direction: .zero, dest: virtualURL.absoluteString, stackDeep: 0)
        return true
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
        let isNetworkVolume = VolumeManager.shared.isNetworkVolume(folderURL)
        let shouldReadFinderTagsSynchronously = !isNetworkVolume
            || !publicVar.finderTagFilters.isEmpty
        var properties: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .tagNamesKey, .isAliasFileKey, .isSymbolicLinkKey]
        if VolumeManager.shared.isExternalVolume(folderURL) {
            properties = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .tagNamesKey, .isAliasFileKey, .isSymbolicLinkKey]
        }
        if !shouldReadFinderTagsSynchronously {
            properties.removeAll { $0 == .tagNamesKey }
        }
        var isInSameDir = true
        if !skip {
            do {
                // Do not reuse a cache produced under ordinary browsing when
                // the same folder becomes a media hierarchy root.
                if isMediaUnitRoot(folderURL) {
                    dirURLCache.removeAll()
                }
                let curDirURLCacheParameters = (folderURL, publicVar.isRecursiveMode, publicVar.isShowHiddenFile, publicVar.isRecursiveContainFolder, properties)
                if let dirURLCacheParameters = dirURLCacheParameters as? (URL, Bool, Bool, Bool, [URLResourceKey]) {
                    if dirURLCacheParameters != curDirURLCacheParameters {
                        dirURLCache.removeAll()
                    }
                }
                dirURLCacheParameters = curDirURLCacheParameters

                isInSameDir = !publicVar.isRecursiveMode && !isMediaUnitFolder(folderURL) && !isVirtualFolderPath(folderURL.absoluteString)
                if dirURLCache.isEmpty {
                    if folderURL.path.hasPrefix("/VirtualFinderTagsFolder") {
                        let tagName = folderURL.lastPathComponent
                        scanVirtualFiles(at: folderURL, contents: &dirURLCache, properties: properties, tagName: tagName)
                    } else if isVirtualFolderPath(folderURL.absoluteString) {
                        dirURLCache = loadVirtualFolderContents(folderURL)
                    } else if folderURL.standardizedFileURL.path == "/Volumes" {
                        // The URL-based API resolves properties for every mount and
                        // throws when the mount table still contains a stale SMB entry.
                        // Raw names avoid per-mount metadata probes during enumeration.
                        dirURLCache = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
                            .map { folderURL.appendingPathComponent($0, isDirectory: true) }
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
        if !isNetworkVolume {
            EnhancedIndex.updateFiles(contents, isCalledByDirOpen: true, recordTime: true)
        }

        // 搜索过滤
        // Search filter
        let searchText = searchField?.stringValue ?? search_searchText
        if publicVar.isFilenameFilterOn && searchText != "" {
            contents = contents.filter { url in
                if let fileName = getFileNameForSearch(path: url.absoluteString) {
                    return isSearchMatch(fileName: fileName, searchText: searchText, forceUseRegex: false)
                }
                return true
            }
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
            if isVirtualArchiveEntryPath(url.absoluteString) {
                return false
            }
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
        subFolders.sort { $0.lastPathComponent.lowercased().localizedStandardCompare($1.lastPathComponent.lowercased()) == .orderedAscending }
        
        // 过滤出需处理文件列表
        // Filter out files to process
        var filesUrlInFolder = [URL]()
        var videoCount=0
        var imageCount=0
        var searchCount=0
        var fileContents = contents.filter { url in
            if isVirtualArchiveEntryPath(url.absoluteString) {
                return true
            }
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
            let effectiveURL: URL
            let effectiveExt: String
            if isAlias, let resolved = try? URL(resolvingAliasFileAt: file) {
                effectiveURL = resolved
                effectiveExt = resolved.pathExtension.lowercased()
            } else {
                effectiveURL = file
                effectiveExt = file.pathExtension.lowercased()
            }
            let shouldShowArchive = globalVar.showArchiveFileType && isSupportedArchiveURL(effectiveURL)
            if publicVar.HandledFileExtensions.contains(effectiveExt) || publicVar.isShowAllTypeFile || shouldShowArchive {
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
            if publicVar.HandledVideoExtensions.contains(file.pathExtension.lowercased()) {
                videoCount+=1
            }
            if publicVar.HandledSearchExtensions.contains(file.pathExtension.lowercased()) {
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
            fileDB.db[SortKeyDir(folderURL.absoluteString)]?.isFiltered = publicVar.isFilenameFilterOn
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.folderCount=subFolders.count
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.fileCount=fileCount
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.imageCount=imageCount
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.videoCount=videoCount
        }
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isMemClearedToAvoidRemainingTask=false
        let lastIsRecursiveMode=fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isRecursiveMode
        let lastIsMediaUnitMode=fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isMediaUnitMode
        if lastIsRecursiveMode != publicVar.isRecursiveMode || lastIsMediaUnitMode != isMediaUnitRoot(folderURL) {
            fileDB.db[SortKeyDir(folderURL.absoluteString)]!.keepScrollPos=false
        }
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isRecursiveMode=publicVar.isRecursiveMode
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isMediaUnitMode=isMediaUnitRoot(folderURL)
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
                var childImageCount: Int?
                var childVideoCount: Int?
                do{
                    // 文件在前i个，目录在后面
                    // Files in first i items, directories after
                    if i < fileCount {
                        let currentURL = filesUrlInFolder[i]
                        if isVirtualArchiveEntryPath(currentURL.absoluteString) {
                            // Virtual archive entries are streamed from archive; skip FS attributes.
                            // Their sort fallback remains name/path based.
                        } else {
                            let resourceValues = try currentURL.resourceValues(forKeys: Set(properties))
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
                            if shouldReadFinderTagsSynchronously {
                                finderTags = resourceValues.tagNames ?? []
                            }
                        }
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
                        if shouldReadFinderTagsSynchronously {
                            finderTags = resourceValues.tagNames ?? []
                        }
                        if globalVar.showFolderMediaCountBadge,
                           !VolumeManager.shared.isNetworkVolume(folderURL),
                           let counts = directMediaCounts(
                               in: subFolders[i-fileCount],
                               showHiddenFiles: publicVar.isShowHiddenFile
                           ) {
                            childImageCount = counts.images
                            childVideoCount = counts.videos
                        }
                        // finderTags = resourceValues.tagNames ?? []
                    }
                }catch{
                    log("Error reading properties.")
                }
                // log("i:",i,"path:",fileSortKey.path.removingPercentEncoding)
                let newFileModel=FileModel(path: fileSortKey.path, ver: fileDB.db[SortKeyDir(folderpath)]!.ver, isDir: isDir, isAlias: isAlias, fileSize: fileSize, createDate: createDate, modDate: modDate, addDate: addDate, doNotActualRead: doNotActualRead)
                newFileModel.finderTags = finderTags
                newFileModel.childImageCount = childImageCount
                newFileModel.childVideoCount = childVideoCount
                // log(fileSortKey.path)
                if let file = fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] {
                    if file.path == fileSortKey.path {
                        file.ver = fileDB.db[SortKeyDir(folderpath)]!.ver
                        file.isDir=isDir
                        file.isAlias=isAlias
                        file.doNotActualRead=doNotActualRead
                        if shouldReadFinderTagsSynchronously {
                            file.finderTags=finderTags
                        }
                        file.childImageCount=childImageCount
                        file.childVideoCount=childVideoCount
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
                if !ele.1.isDir{
                    ele.1.ext=URL(string: ele.1.path)!.pathExtension.lowercased()
                    if ele.1.isAlias {
                        ele.1.type = .other
                    } else if globalVar.HandledImageAndRawExtensions.contains(ele.1.ext) {
                        ele.1.type = .image
                        ele.1.idInImage = idInImage
                        ele.1.idInImageAndVideo = idInImageAndVideo
                        idInImage += 1
                        idInImageAndVideo += 1
                    }else if globalVar.HandledVideoExtensions.contains(ele.1.ext) {
                        ele.1.type = .video
                        ele.1.idInImageAndVideo = idInImageAndVideo
                        idInImageAndVideo += 1
                    }else{
                        ele.1.type = .other
                    }
                }else{
                    ele.1.type = .folder
                }
                ele.1.id = id
                id += 1
            }
        }
        fileDB.unlock()

        if !skip,
           direction == .zero,
           folderURL == initURL,
           isNetworkVolume {
            fileDB.lock()
            let expectedVersion = fileDB.db[SortKeyDir(folderURL.absoluteString)]?.ver
            let tagItems: [(url: URL, fileModel: FileModel)] = fileDB.db[SortKeyDir(folderURL.absoluteString)]?.files.compactMap { _, fileModel in
                guard let url = URL(string: fileModel.path) else { return nil }
                return (url, fileModel)
            } ?? []
            fileDB.unlock()
            if let expectedVersion {
                scheduleNetworkTagHydration(
                    parentFolderURL: folderURL,
                    items: tagItems,
                    expectedVersion: expectedVersion,
                    tagsAlreadyLoaded: shouldReadFinderTagsSynchronously
                )
            }
        }
        
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
    
    /// A replaced media-unit model can keep its own version unchanged while
    /// queued callbacks still retain it. Check the active model and navigation
    /// generation as well before touching collection items or layout state.
    func isCurrentDirectoryTask(path: String, model: DirModel, version: Int) -> Bool {
        fileDB.lock()
        defer { fileDB.unlock() }
        return fileDB.curFolder == path
            && fileDB.ver == version
            && model.ver == version
            && fileDB.db[SortKeyDir(path)] === model
    }

    func switchFolder(path: String) {
        // startTime = DispatchTime.now()

        fileDB.lock()
        let hasDirectoryModel = fileDB.db[SortKeyDir(path)] != nil
        fileDB.unlock()
        guard hasDirectoryModel else {
            publicVar.isInStageOneProgress = false
            return
        }
        
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
        // Never carry old directory pixels into a new listing. This applies
        // to normal folders and tab switches as well as media units; waiting
        // for thumbnail completion to fade them leaves mixed content on stalls.
        for snapshot in snapshotQueue { snapshot?.removeFromSuperview() }
        snapshotQueue.removeAll()
        if publicVar.openFromFinderPath == "" {
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
            }else {
                collectionView.collectionViewLayout=publicVar.justifiedLayout
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
            collectionView.collectionViewLayout?.invalidateLayout()
            
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
            guard let dirModel = fileDB.db[SortKeyDir(path)] else {
                fileDB.unlock()
                publicVar.isInStageOneProgress = false
                return
            }
            keys = getMapKeysFile(dirModel.files)
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
                if publicVar.selectionAfterDeletion?.folderPath == path {
                    publicVar.selectionAfterDeletion = nil
                }
                
                collectionView.reloadData()
                collectionView.numberOfItems(inSection:0)

                setProgress(1.0)

                let filesystemPath = path.dropLast()
                    .replacingOccurrences(of: "file://", with: "")
                    .removingPercentEncoding
                if let filesystemPath,
                   !FileManager.default.fileExists(atPath: filesystemPath) {
                    if path == "file:///VirtualFinderTagsFolder/" {
                        collectionView.showFolderInfo(NSLocalizedString("Please select a specific tag", comment: "请选择具体的标签"))
                    } else if !isVirtualFolderPath(path) {
                        collectionView.showFolderInfo(NSLocalizedString("Directory does not exist", comment: "目录不存在"))
                    }
                }

                // A directory switch can leave the large-image view pointing at
                // a file that no longer exists. Stop the player before fading the
                // stale snapshot so callbacks cannot restart the removed media.
                largeImageView.invalidateForDeletedContent()
                largeImageBgEffectView.isHidden = true
                publicVar.isInLargeView = false
                publicVar.isInLargeViewAfterAnimate = false
                setWindowTitle()
                
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
                    
                    if !isCurrentDirectoryTask(path: path, model: dirModel, version: ver) {return}
                    
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

        // Large folders and network volumes can take several seconds to finish
        // rebuilding. Keep the pending target long enough for the final pass.
        let elapsedThreshold = 15.0
        
        let curItemCount = collectionView.numberOfItems(inSection: 0)
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        let dirFiles = fileDB.db[SortKeyDir(curFolder)]?.files
        fileDB.unlock()

        // The target may arrive in a later layout batch on a large/SMB unit.
        // Keep it until visible; unlike copy/move hints this has no timeout.
        if let pending = publicVar.selectionAfterDeletion {
            if pending.folderPath != curFolder {
                publicVar.selectionAfterDeletion = nil
            } else {
                let offset = dirFiles?.enumerated().first(where: {
                    $0.element.1.path == pending.filePath
                })?.offset
                if let offset, offset < curItemCount {
                    let indexPath = IndexPath(item: offset, section: 0)
                    collectionView.selectionIndexPaths = [indexPath]
                    collectionViewManager.lastSelectedIndexPath = indexPath
                    collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                    setLoadThumbPriority(ifNeedVisable: true)
                    view.window?.makeFirstResponder(collectionView)
                    publicVar.selectionAfterDeletion = nil
                } else if isFinal {
                    publicVar.selectionAfterDeletion = nil
                }
            }
        }
        
        // 向上或者后退时定位文件夹
        // Locate folder when going up or back
        if let (lastFolder, _) = publicVar.folderStepForLocate.first {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - publicVar.folderStepForLocateTime.uptimeNanoseconds) / 1_000_000_000
            if elapsed > elapsedThreshold {
                publicVar.folderStepForLocate.removeAll()
            } else if let lastURL = URL(string: lastFolder),
                      let curURL = URL(string: curFolder) {
                let targetURL = parseVirtualArchivePath(lastFolder)?.archiveURL ?? lastURL
                let isTargetDirectory = targetURL.hasDirectoryPath
                if targetURL.deletingLastPathComponent().absoluteString == curURL.absoluteString {
                    let targetKey = SortKeyFile(targetURL.absoluteString, isDir: isTargetDirectory, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)
                    fileDB.lock()
                    if let files = dirFiles,
                       let index = files.index(forKey: targetKey) {
                        let offset = files.offset(of: index)
                        fileDB.unlock()
                        let indexPath = IndexPath(item: offset, section: 0)
                        if indexPath.item < curItemCount {
                            publicVar.folderStepForLocate.removeAll()
                            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                            collectionView.selectItems(at: [indexPath], scrollPosition: [])
                            setLoadThumbPriority(ifNeedVisable: true)
                        }
                    } else {
                        fileDB.unlock()
                    }
                }
            }
        }
        
        // 粘贴或移动后选中变更的文件
        // Select changed files after paste or move
        if !publicVar.filesForLocateAfterChange.isEmpty {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - publicVar.filesForLocateAfterChangeTime.uptimeNanoseconds) / 1_000_000_000
            if elapsed > elapsedThreshold {
                publicVar.filesForLocateAfterChange.removeAll()
            } else {
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
                    collectionView.selectItems(at: Set(matchedIndexPaths), scrollPosition: [])
                    if isFirstMatch {
                        collectionView.scrollToItems(at: [matchedIndexPaths[0]], scrollPosition: .nearestHorizontalEdge)
                        setLoadThumbPriority(ifNeedVisable: true)
                    }
                }
            }
            
            if isFinal {
                publicVar.filesForLocateAfterChange.removeAll()
            }
        }

        if isFinal, let pendingAnchor = publicVar.collectionViewportAnchorAfterRefresh {
            publicVar.collectionViewportAnchorAfterRefresh = nil
            if curFolder == pendingAnchor.folderPath {
                var anchorIndexPath: IndexPath?
                fileDB.lock()
                if let files = dirFiles {
                    for (offset, element) in files.enumerated() {
                        if element.1.path == pendingAnchor.filePath {
                            anchorIndexPath = IndexPath(item: offset, section: 0)
                            break
                        }
                    }
                }
                fileDB.unlock()

                if let anchorIndexPath {
                    publicVar.collectionScrollRestoreAfterRefresh = nil
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              let scrollView = self.collectionView.enclosingScrollView else { return }
                        self.collectionView.layoutSubtreeIfNeeded()
                        guard let frame = self.collectionView.layoutAttributesForItem(at: anchorIndexPath)?.frame else { return }
                        let clipView = scrollView.contentView
                        var proposedBounds = clipView.bounds
                        proposedBounds.origin = NSPoint(
                            x: frame.minX - pendingAnchor.offset.x,
                            y: frame.minY - pendingAnchor.offset.y
                        )
                        let constrainedBounds = clipView.constrainBoundsRect(proposedBounds)
                        clipView.scroll(to: constrainedBounds.origin)
                        scrollView.reflectScrolledClipView(clipView)
                        self.setLoadThumbPriority(ifNeedVisable: true)
                    }
                    return
                }
            }
        }

        if isFinal, let pendingRestore = publicVar.collectionScrollRestoreAfterRefresh {
            fileDB.lock()
            let currentFolder = fileDB.curFolder
            fileDB.unlock()
            publicVar.collectionScrollRestoreAfterRefresh = nil

            guard currentFolder == pendingRestore.folderPath else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let scrollView = self.collectionView.enclosingScrollView else { return }
                self.collectionView.layoutSubtreeIfNeeded()
                let clipView = scrollView.contentView
                var proposedBounds = clipView.bounds
                proposedBounds.origin = pendingRestore.origin
                let constrainedBounds = clipView.constrainBoundsRect(proposedBounds)
                clipView.scroll(to: constrainedBounds.origin)
                scrollView.reflectScrolledClipView(clipView)
                self.setLoadThumbPriority(ifNeedVisable: true)
            }
        }
    }
    
    func switchDirByDirection(direction rawdirection: RightMouseGestureDirection, dest: String = "", doCollapse: Bool = true, expandLast: Bool = true, skip: Bool = false, stackDeep: Int, dryRun: Bool = false, needStopAutoScroll: Bool = true, mediaUnitHistoryCleanupAfterAsync: Bool = false){
        
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

        // Do this only after navigation guards have accepted the action. A
        // forbidden left/right gesture must leave the in-flight unit scan
        // intact. Bumping the generation makes the worker exit promptly when
        // a real navigation cancels the pending destination.
        let cancelPendingMediaUnitScan: () -> Void = {
            guard self.publicVar.mediaUnitPendingPath != nil else { return }
            self.fileDB.lock()
            self.fileDB.ver += 1
            self.fileDB.unlock()
            self.publicVar.mediaUnitPendingPath = nil
            self.coreAreaView.hideInfo(force: true)
        }

        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        if publicVar.isMediaUnitMode,
           publicVar.isMediaUnitNavigationPath(curFolder),
           (rawdirection == .left || rawdirection == .up_left || rawdirection == .down_left
            || rawdirection == .right || rawdirection == .up_right || rawdirection == .down_right) {
            publicVar.isInStageOneProgress = false
            showAlert(message: NSLocalizedString("media-unit-mode-nodirection", comment: "媒体单元模式下不能执行此动作"))
            return
        }
        if isVirtualFolderPath(curFolder) || !publicVar.finderTagFilters.isEmpty || !publicVar.ratingFilters.isEmpty {
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
            cancelPendingMediaUnitScan()
            let destination = publicVar.folderStepStack.removeFirst()
            let shouldDeferHistoryCleanup = URL(string: destination).map(isMediaUnitFolder) ?? false
            fileDB.lock()
            publicVar.folderStepForwardStack.insert(fileDB.curFolder, at: 0)
            fileDB.unlock()
            switchDirByDirection(
                direction: .zero,
                dest: destination,
                stackDeep: stackDeep + 1,
                mediaUnitHistoryCleanupAfterAsync: shouldDeferHistoryCleanup
            )
            if !shouldDeferHistoryCleanup, !publicVar.folderStepStack.isEmpty {
                publicVar.folderStepStack.removeFirst()
            }
            return
        }else if direction != .forward && stackDeep == 0 {
            publicVar.folderStepForwardStack.removeAll()
        }
        // 前进
        // Forward
        if direction == .forward {
            if publicVar.folderStepForwardStack.count == 0 {return}
            if publicVar.folderStepForwardStack[0] == "" {return}
            cancelPendingMediaUnitScan()
            switchDirByDirection(direction: .zero, dest: publicVar.folderStepForwardStack.removeFirst(), stackDeep: stackDeep+1)
            return
        }
        // 跳转父级目录
        // Jump to parent directory
        if direction == .up {
            // In virtual archive view, Command+Up should leave archive and go to
            // the real parent directory of the archive file (e.g. SMB folder).
            if isVirtualArchivePath(curFolder),
               let parsed = parseVirtualArchivePath(curFolder) {
                let realParent = parsed.archiveURL.deletingLastPathComponent().absoluteString
                if !realParent.isEmpty {
                    switchDirByDirection(direction: .zero, dest: realParent, skip: true, stackDeep: stackDeep+1)
                    return
                }
            }
            let navigationPath = publicVar.mediaUnitPendingPath ?? curFolder
            let hadPendingMediaUnitScan = publicVar.mediaUnitPendingPath != nil
            fileDB.lock()
            guard let currentFolderURL = URL(string: navigationPath) else {
                fileDB.unlock()
                publicVar.isInStageOneProgress = false
                return
            }
            let newFolderPath=currentFolderURL.deletingLastPathComponent().absoluteString
            fileDB.unlock()
            if newFolderPath == "file:///../" {return}
            if hadPendingMediaUnitScan {
                cancelPendingMediaUnitScan()
            }
            switchDirByDirection(direction: .zero, dest: newFolderPath, skip: true, stackDeep: stackDeep+1)
            switchDirByDirection(direction: secondDirection, stackDeep: stackDeep+1)
            if secondDirection != .zero {
                publicVar.folderStepStack.removeFirst()
            }
            return
        }
        
        fileDB.lock()
        let lastFolder = fileDB.curFolder
        fileDB.unlock()
        var startFolder=lastFolder
        if direction == .zero && dest != "" { startFolder = dest }
        if let pending = publicVar.selectionAfterDeletion, pending.folderPath != startFolder {
            publicVar.selectionAfterDeletion = nil
        }
        if direction == .zero,
           dest.isEmpty,
           let pendingPath = publicVar.mediaUnitPendingPath,
           pendingPath != lastFolder {
            startFolder = pendingPath
            publicVar.mediaUnitPendingPath = nil
        }
        if let startURL = URL(string: startFolder),
           isUnavailableMountedVolumeURL(startURL) {
            publicVar.isInStageOneProgress = false
            coreAreaView.showOperationToast(
                NSLocalizedString("The network volume is not mounted.", comment: "网络卷尚未挂载。"),
                autoHide: 2.0
            )
            return
        }
        guard let startURL = URL(string: startFolder) else {
            publicVar.isInStageOneProgress = false
            return
        }
        cancelPendingMediaUnitScan()
        fileDB.lock()
        fileDB.ver += 1
        let expectedMediaUnitVersion = fileDB.ver
        fileDB.unlock()
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

        if direction == .zero && isMediaUnitFolder(startURL) {
            beginMediaUnitScan(
                folderURL: startURL,
                lastFolder: lastFolder,
                doCollapse: doCollapse,
                expandLast: expandLast,
                version: expectedMediaUnitVersion,
                removePendingHistoryAfterCompletion: mediaUnitHistoryCleanupAfterAsync
            )
            return
        }
        
        treeTraversal(folderURL: startURL, round: searchFolderRound, initURL: startURL, direction: direction,
                          sameLevel: secondDirection == .down, skip: skip, dryRun: dryRun)

        // let a=1
        fileDB.lock()
        guard var curIndex = fileDB.db.index(forKey: SortKeyDir(startFolder)) else {
            fileDB.unlock()
            // Directory enumeration can finish after a watcher has reported a
            // deletion. Keep the current model usable and let the next refresh
            // retry instead of force-unwrapping a vanished directory entry.
            publicVar.isInStageOneProgress = false
            if let lastURL = URL(string: lastFolder), lastURL.isFileURL {
                startWatchingDirectory(atPath: lastURL.path)
            }
            return
        }
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
        
        log("Switch:", nextFolder.removingPercentEncoding ?? nextFolder)
        switchFolder(path: nextFolder)
        let nextFolderFilesystemPath = nextFolder
            .replacingOccurrences(of: "file://", with: "")
            .removingPercentEncoding
        if let nextFolderFilesystemPath {
            startWatchingDirectory(atPath: nextFolderFilesystemPath)
        }
        if !publicVar.isInLargeView {setWindowTitle()}
        LRUMemRecord(path: nextFolder, count: fileCount)
        
        let defaults = UserDefaults.standard
        defaults.set(nextFolder, forKey: "lastFolder")

    }
    
    class FolderStatisticInfo {
        var folderCount = 0
        var fileCount = 0
        var imageCount = 0
        var videoCount = 0
        var totalSize = 0
        
        var description: String {
            let text = String(format: NSLocalizedString("statistic-content", comment: "(统计内容)"),folderCount,fileCount,imageCount,videoCount,readableFileSize(totalSize))
            return text
        }
    }
    
    func handleGetInfo(_ providedUrls: [URL] = []) {
        var urls = providedUrls
        if providedUrls.isEmpty {
            urls = publicVar.selectedUrls()
        }
        if urls.isEmpty {return}

        // log(readFinderExtendedAttributes(url: urls[0], needFinderInfo: true), level: .debug)
        // return;
        
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

                    let file = FileModel(path: "", ver: 0)
                    file.path = url.absoluteString
                    file.fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    file.createDate = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                    file.modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    file.addDate = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate)
                    
                    let ext = resolvedUrl.pathExtension.lowercased()
                    if globalVar.HandledImageAndRawExtensions.contains(ext) || globalVar.HandledVideoExtensions.contains(ext) {
                        file.imageInfo = getImageInfo(url: resolvedUrl, needMetadata: true)
                    }
                    let exifData = convertExifData(file: file)
                    var formatedExifData = formatExifData(exifData ?? [:], isVideo: globalVar.HandledVideoExtensions.contains(ext), needWarp: false)

                    formatedExifData.insert((NSLocalizedString("File Path", comment: "文件路径"), "\u{2066}" + url.deletingLastPathComponent().path + "/" + "\u{2069}"), at: 0)

                    if isAlias {
                        formatedExifData.insert((NSLocalizedString("Original Path", comment: "原始路径"), "\u{2066}" + resolvedUrl.path + "\u{2069}"), at: 0)
                        formatedExifData.insert((NSLocalizedString("Alias Type", comment: "替身类型"), aliasTypeLabel), at: 0)
                    }
                    
                    let separator = "--------------------"
                    
                    func formatExifDataAligned(_ exifData: [(String, Any)]) -> String {
                        
                        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                        // 计算最长的key的长度
                        let maxKeyLength = exifData.map { $0.0.size(withAttributes: [.font: font]).width }.max() ?? 0
                        
                        // 格式化每一行，使冒号对齐
                        let formattedLines = exifData.map { (key, value) -> String in
                            if key == "-" {
                                return separator
                            }
                            let keyLength = key.size(withAttributes: [.font: font]).width
                            let padding = String(repeating: " ", count: Int((maxKeyLength - keyLength) / " ".size(withAttributes: [.font: font]).width))
                            return "\(key):\(padding) \(value)"
                        }
                        
                        return formattedLines.joined(separator: "\n")
                    }
                    
                    var text = formatExifDataAligned(formatedExifData)

                    func appendSection(_ content: String) {
                        text += (text.hasSuffix(separator) ? "\n" : "\n" + separator + "\n") + content
                    }

                    if globalVar.HandledVideoExtensions.contains(ext),
                       let videoRawMetadata = getVideoMetadataFFmpeg(for: resolvedUrl),
                       let specificMetadata = getVideoMetadataFormatedFFmpeg(for: resolvedUrl) {
                        let metadataAligned = formatExifDataAligned(specificMetadata)
                        appendSection(metadataAligned + "\n" + separator + "\n" + videoRawMetadata)
                    }
                    
                    if globalVar.HandledImageAndRawExtensions.contains(ext) {
                        func formatDictionary(_ dictionary: [String: Any], indentLevel: Int = 0, outputFormat: String = "json", sort: Bool = true) -> String {
                            let sortedDictionary: [(String, Any)]
                            if sort {
                                sortedDictionary = dictionary.sorted { $0.key < $1.key }
                            } else {
                                sortedDictionary = Array(dictionary)
                            }
                            
                            // 添加错误处理和防护
                            if outputFormat == "json" {
                                do {
                                    let sortedDict = Dictionary(uniqueKeysWithValues: sortedDictionary)
                                    // 移除不能被JSON序列化的值
                                    let serializableDict = sortedDict.filter { (_, value) in
                                        JSONSerialization.isValidJSONObject([value])
                                    }
                                    let jsonData = try JSONSerialization.data(withJSONObject: serializableDict, options: [.prettyPrinted, .sortedKeys])
                                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                                        return jsonString
                                    }
                                } catch {
                                    print("JSON serialization error: \(error)")
                                }
                                return "{}"
                            } else {
                                let indent = String(repeating: "  ", count: indentLevel)
                                var formattedString = ""
                                for (key, value) in sortedDictionary {
                                    if let nestedDict = value as? [String: Any] {
                                        formattedString += "\(indent)\(key):\n"
                                        formattedString += formatDictionary(nestedDict, indentLevel: indentLevel + 1, outputFormat: outputFormat, sort: sort)
                                    } else {
                                        formattedString += "\(indent)\(key): \(value)\n"
                                    }
                                }
                                return formattedString
                            }
                        }

                        if let properties = file.imageInfo?.properties {
                            if properties.count > 0 {
                                appendSection(formatDictionary(properties).replacingOccurrences(of: "\\/", with: "/"))
                            }
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
                            if result.count > 0 {
                                appendSection(formatDictionary(result).replacingOccurrences(of: "\\/", with: "/"))
                            }
                        }
                    }
                    
                    if text.hasSuffix(separator) {
                        text = String(text.dropLast(separator.count)).trimmingCharacters(in: .newlines)
                    }
                    showInformationLong(title: NSLocalizedString("File Info", comment: "文件信息"), message: text, width: 400)
                    
                    return
                } else {
                    let targetUrl = url
                    
                    var folderInfoData: [(String, Any)] = []

                    if isAlias {
                        folderInfoData.append((NSLocalizedString("Alias Type", comment: "替身类型"), aliasTypeLabel))
                        folderInfoData.append((NSLocalizedString("Original Path", comment: "原始路径"), "\u{2066}" + resolvedUrl.path + "\u{2069}"))
                    }
                    
                    folderInfoData.append((NSLocalizedString("Folder Path", comment: "文件夹路径"), "\u{2066}" + targetUrl.path + "\u{2069}"))
                    folderInfoData.append((NSLocalizedString("Folder Name", comment: "文件夹名称"), targetUrl.lastPathComponent))
                    
                    if let creationDate = (try? targetUrl.resourceValues(forKeys: [.creationDateKey]).creationDate) {
                        folderInfoData.append((NSLocalizedString("Creation Date", comment: "创建日期"), formatDateToCurrentTimeZone(creationDate)))
                    }
                    if let modDate = (try? targetUrl.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) {
                        folderInfoData.append((NSLocalizedString("Modification Date", comment: "修改日期"), formatDateToCurrentTimeZone(modDate)))
                    }
                    if let addDate = (try? targetUrl.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) {
                        folderInfoData.append((NSLocalizedString("Added Date", comment: "添加日期"), formatDateToCurrentTimeZone(addDate)))
                    }
                    
                    let separator = "--------------------"
                    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    let maxKeyLength = folderInfoData.map { $0.0.size(withAttributes: [.font: font]).width }.max() ?? 0
                    let formattedLines = folderInfoData.map { (key, value) -> String in
                        let keyLength = key.size(withAttributes: [.font: font]).width
                        let padding = String(repeating: " ", count: Int((maxKeyLength - keyLength) / " ".size(withAttributes: [.font: font]).width))
                        return "\(key):\(padding) \(value)"
                    }
                    var text = formattedLines.joined(separator: "\n")
                    
                    let result = FolderStatisticInfo()
                    getFolderStatistic(resolvedUrl, result: result)
                    text += "\n" + separator + "\n" + result.description
                    
                    showInformationLong(title: NSLocalizedString("Folder Info", comment: "文件夹信息"), message: text, width: 400)
                    
                    return
                }
            }
        }
        
        // 以下是针对非单个图像、视频文件的处理
        // Below is handling for non-single image/video files
        
        let result = FolderStatisticInfo()
        
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                let isAlias = (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) ?? false
                let aliasSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if isAlias {
                    let resolvedUrl = try? URL(resolvingAliasFileAt: url)
                    if let resolved = resolvedUrl, resolved.hasDirectoryPath {
                        result.folderCount += 1
                        result.totalSize += aliasSize
                    } else {
                        result.fileCount += 1
                        let ext = (resolvedUrl ?? url).pathExtension.lowercased()
                        if globalVar.HandledImageAndRawExtensions.contains(ext) {
                            result.imageCount += 1
                        } else if globalVar.HandledVideoExtensions.contains(ext) {
                            result.videoCount += 1
                        }
                        result.totalSize += aliasSize
                    }
                } else if isDirectory.boolValue {
                    result.folderCount += 1
                    getFolderStatistic(url, result: result)
                } else {
                    result.fileCount += 1
                    if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
                        result.imageCount += 1
                    } else if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
                        result.videoCount += 1
                    }
                    result.totalSize += aliasSize
                }
            }
        }
        
        showInformation(title: NSLocalizedString("Statistic", comment: "统计信息"), message: result.description)
    }
    
    func getFolderStatistic(_ folderURL: URL, result: FolderStatisticInfo) {
        let properties: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .isAliasFileKey]
        let options:FileManager.DirectoryEnumerationOptions = [] // [.skipsHiddenFiles]
        
        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: properties, options: options, errorHandler: { (url, error) -> Bool in
            print("Error enumerating \(url): \(error.localizedDescription)")
            return true
        })

        // var result = StatisticInfo()
        let scanInterval: TimeInterval = 4.0
        var startDate = Date()
        
        while let url = enumerator?.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isAlias = (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) ?? false
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

            if isAlias && !isDirectory {
                if let resolved = try? URL(resolvingAliasFileAt: url), resolved.hasDirectoryPath {
                    result.folderCount += 1
                    result.totalSize += fileSize
                } else {
                    result.fileCount += 1
                    if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
                        result.imageCount += 1
                    } else if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
                        result.videoCount += 1
                    }
                    result.totalSize += fileSize
                }
            } else if !isDirectory {
                result.fileCount += 1
                if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
                    result.imageCount += 1
                } else if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
                    result.videoCount += 1
                }
                result.totalSize += fileSize
            } else {
                result.folderCount += 1
            }
            
            // let elapsedTime = Date().timeIntervalSince(startDate)
            // if elapsedTime >= scanInterval {
            //     let shouldContinue = showScanAlert(fileCount: result.fileCount, imageCount: result.imageCount, videoCount: result.videoCount)
            //     if !shouldContinue {
            //         break
            //     }
            //     startDate = Date()
            // }
        }
    }
}
