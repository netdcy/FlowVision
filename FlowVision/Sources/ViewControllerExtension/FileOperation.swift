//
//  FileOperation.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration
import ImageIO

enum BatchMediaRotation: Int {
    case clockwise90 = 90
    case clockwise180 = 180
    case counterclockwise90 = -90
    case restoreVideo = 1000

    var imageDegrees: CGFloat {
        switch self {
        case .clockwise90:
            return -90
        case .clockwise180:
            return 180
        case .counterclockwise90:
            return 90
        case .restoreVideo:
            return 0
        }
    }

    var videoFilter: String {
        switch self {
        case .clockwise90:
            return "transpose=1"
        case .clockwise180:
            return "transpose=1,transpose=1"
        case .counterclockwise90:
            return "transpose=2"
        case .restoreVideo:
            return ""
        }
    }
}

extension ViewController {
    enum CompressMode {
        case plainZip
        case encryptedZip(password: String)
    }

    private struct FileRenameMapping {
        let from: URL
        let to: URL
    }

    private struct PendingTempRename {
        let tempURL: URL
        let targetURL: URL
    }

    struct VideoCropRect {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    func hasSelectedRotatableMedia() -> Bool {
        publicVar.selectedUrls().contains { isRotatableMediaURL($0) }
    }
    
    func hasSelectedVideoMedia() -> Bool {
        if publicVar.isInLargeView,
           largeImageView.file.type == .video,
           let url = URL(string: largeImageView.file.path) {
            return isEditableVideoURL(url)
        }
        return publicVar.selectedUrls().contains {
            isEditableVideoURL($0)
        }
    }

    func handleBatchCropSelectedVideos() {
        let urls: [URL]
        if publicVar.isInLargeView,
           largeImageView.file.type == .video,
           let currentURL = URL(string: largeImageView.file.path),
           isEditableVideoURL(currentURL) {
            if largeImageView.isInVideoCropSelectionMode {
                largeImageView.confirmVideoCropSelection()
                return
            }
            largeImageView.beginVideoCropSelectionMode()
            return
        } else {
            urls = publicVar.selectedUrls().filter { isEditableVideoURL($0) }
        }
        guard !urls.isEmpty else {
            showAlert(message: NSLocalizedString("Please select at least one video first.", comment: "请先选择至少一个视频。"))
            return
        }

        guard let cropSize = promptVideoCropSize() else { return }
        handleBatchCropVideos(urls, cropSize: cropSize)
    }

    func handleCropCurrentVideo(selection cropRect: VideoCropRect) {
        guard publicVar.isInLargeView,
              largeImageView.file.type == .video,
              let currentURL = URL(string: largeImageView.file.path),
              isEditableVideoURL(currentURL) else {
            showAlert(message: NSLocalizedString("Please open a video first.", comment: "请先打开一个视频。"))
            return
        }

        publicVar.isInFileOperation = true
        coreAreaView.showOperationIndeterminate(
            String(format: NSLocalizedString("Cropping %@", comment: "裁剪中 %@"), currentURL.lastPathComponent)
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let ok = self.cropVideoFile(currentURL, cropRect: cropRect)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.publicVar.isInFileOperation = false

                if ok {
                    self.publicVar.fileChangedCount += 1
                    self.publicVar.filesForLocateAfterChange = [currentURL.absoluteString]
                    ThumbImageProcessor.clearCache()
                    LargeImageProcessor.clearCache()
                    self.coreAreaView.showOperationProgress(NSLocalizedString("Crop complete", comment: "裁剪完成"), progress: 1.0)
                    self.coreAreaView.hideOperationOverlay(delayed: 0.8)
                    self.changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false, forceRefresh: true)
                    self.scheduledRefresh()
                } else {
                    self.coreAreaView.hideOperationOverlay(delayed: 0.2)
                    showAlert(message: NSLocalizedString("Failed to crop video.", comment: "视频裁剪失败。"))
                }
            }
        }
    }

    private func isRotatableMediaURL(_ url: URL) -> Bool {
        if isReadOnlyVirtualFolderPath(url.absoluteString) || isVirtualArchiveEntryPath(url.absoluteString) {
            return false
        }
        let ext = url.pathExtension.lowercased()
        return isRotatableImageExtension(ext) || globalVar.HandledVideoExtensions.contains(ext)
    }

    private func isRotatableImageExtension(_ ext: String) -> Bool {
        guard globalVar.HandledImageExtensions.contains(ext) else { return false }
        return !["ai", "gif", "icns", "ico", "psd", "svg", "webp"].contains(ext)
    }

    private func isEditableVideoURL(_ url: URL) -> Bool {
        !isReadOnlyVirtualFolderPath(url.absoluteString) &&
        !isVirtualArchiveEntryPath(url.absoluteString) &&
        globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased())
    }

    private func promptVideoCropSize() -> CGSize? {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Crop Video Size", comment: "裁剪视频尺寸")
        alert.informativeText = NSLocalizedString("Enter the target crop width and height in pixels. The video will be center-cropped and the original file will be replaced.", comment: "输入目标裁剪宽高（像素）。视频将居中裁剪并替换原文件。")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

        let widthField = NSTextField(frame: NSRect(x: 72, y: 34, width: 120, height: 24))
        let heightField = NSTextField(frame: NSRect(x: 72, y: 0, width: 120, height: 24))
        widthField.placeholderString = "1920"
        heightField.placeholderString = "1080"

        let widthLabel = NSTextField(labelWithString: NSLocalizedString("Width", comment: "宽度"))
        widthLabel.frame = NSRect(x: 0, y: 36, width: 64, height: 20)
        widthLabel.alignment = .right

        let heightLabel = NSTextField(labelWithString: NSLocalizedString("Height", comment: "高度"))
        heightLabel.frame = NSRect(x: 0, y: 2, width: 64, height: 20)
        heightLabel.alignment = .right

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 210, height: 58))
        container.addSubview(widthLabel)
        container.addSubview(widthField)
        container.addSubview(heightLabel)
        container.addSubview(heightField)
        alert.accessoryView = container

        let storedKey = "videoCropSize"
        if let stored = UserDefaults.standard.string(forKey: storedKey) {
            let parts = stored.split(separator: "x")
            if parts.count == 2 {
                widthField.stringValue = String(parts[0])
                heightField.stringValue = String(parts[1])
            }
        }

        let previousKeyEventState = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        DispatchQueue.main.async {
            widthField.becomeFirstResponder()
        }
        let response = alert.runModal()
        publicVar.isKeyEventEnabled = previousKeyEventState

        guard response == .alertFirstButtonReturn else { return nil }
        let width = Int(widthField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let height = Int(heightField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard width > 0, height > 0 else {
            showAlert(message: NSLocalizedString("Please enter a valid video crop size.", comment: "请输入有效的视频裁剪尺寸。"))
            return nil
        }

        let evenWidth = width - (width % 2)
        let evenHeight = height - (height % 2)
        guard evenWidth > 0, evenHeight > 0 else {
            showAlert(message: NSLocalizedString("Video crop size must be at least 2 pixels.", comment: "视频裁剪尺寸至少需要 2 像素。"))
            return nil
        }

        UserDefaults.standard.set("\(evenWidth)x\(evenHeight)", forKey: storedKey)
        return CGSize(width: evenWidth, height: evenHeight)
    }

    func handleBatchRotateSelectedMedia(_ rotation: BatchMediaRotation) {
        var urls = publicVar.selectedUrls().filter { isRotatableMediaURL($0) }
        if rotation == .restoreVideo {
            urls = urls.filter { globalVar.HandledVideoExtensions.contains($0.pathExtension.lowercased()) }
        }
        guard !urls.isEmpty else {
            if rotation == .restoreVideo {
                showAlert(message: NSLocalizedString("Please select at least one video first.", comment: "请先选择至少一个视频。"))
            } else {
                showAlert(message: NSLocalizedString("Please select at least one image or video first.", comment: "请先选择至少一个图片或视频。"))
            }
            return
        }

        publicVar.isInFileOperation = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var failed: [URL] = []
            let total = urls.count

            for (index, url) in urls.enumerated() {
                let startedRatio = Double(index) / Double(total)
                DispatchQueue.main.async { [weak self] in
                    self?.coreAreaView.showOperationProgress(
                        String(
                            format: rotation == .restoreVideo
                                ? NSLocalizedString("Restoring %d/%d: %@", comment: "还原中 %d/%d: %@")
                                : NSLocalizedString("Rotating %d/%d: %@", comment: "旋转中 %d/%d: %@"),
                            index + 1, total, url.lastPathComponent
                        ),
                        progress: startedRatio
                    )
                }

                let ext = url.pathExtension.lowercased()
                let ok: Bool
                if self.isRotatableImageExtension(ext) {
                    ok = self.rotateImageFile(url, rotation: rotation)
                } else {
                    ok = self.rotateVideoFile(url, rotation: rotation)
                }
                if !ok {
                    failed.append(url)
                }

                let finishedRatio = Double(index + 1) / Double(total)
                DispatchQueue.main.async { [weak self] in
                    self?.coreAreaView.showOperationProgress(
                        String(
                            format: rotation == .restoreVideo
                                ? NSLocalizedString("Restoring... %d%%", comment: "还原中... %d%%")
                                : NSLocalizedString("Rotating... %d%%", comment: "旋转中... %d%%"),
                            Int(finishedRatio * 100)
                        ),
                        progress: finishedRatio
                    )
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.publicVar.isInFileOperation = false
                self.publicVar.fileChangedCount += total - failed.count
                self.publicVar.filesForLocateAfterChange = urls.map(\.absoluteString)
                ThumbImageProcessor.clearCache()
                LargeImageProcessor.clearCache()

                if failed.isEmpty {
                    self.coreAreaView.showOperationProgress(
                        rotation == .restoreVideo
                            ? NSLocalizedString("Restore complete", comment: "还原完成")
                            : NSLocalizedString("Rotation complete", comment: "旋转完成"),
                        progress: 1.0
                    )
                    self.coreAreaView.hideOperationOverlay(delayed: 0.8)
                } else {
                    let preview = failed.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
                    self.coreAreaView.showOperationToast(
                        String(format: NSLocalizedString("Rotation complete, failed: %d", comment: "旋转完成，失败：%d"), failed.count),
                        autoHide: 2.0
                    )
                    showAlert(message: String(format: NSLocalizedString("Failed to rotate some files: %@", comment: "部分文件旋转失败：%@"), preview))
                }

                if total - failed.count > 0 {
                    self.scheduledRefresh()
                }
            }
        }
    }

    private func makeTemporarySiblingURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".flowvision_rotate_\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
    }

    private func replaceOriginalFile(at url: URL, with tempURL: URL) -> Bool {
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL, backupItemName: nil, options: [])
            return true
        } catch {
            log("Failed to replace rotated file: \(error)", level: .error)
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }

    private func handleBatchCropVideos(_ urls: [URL], cropSize: CGSize) {
        publicVar.isInFileOperation = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var failed: [URL] = []
            let total = urls.count

            for (index, url) in urls.enumerated() {
                let startedRatio = Double(index) / Double(total)
                DispatchQueue.main.async { [weak self] in
                    self?.coreAreaView.showOperationProgress(
                        String(
                            format: NSLocalizedString("Cropping %d/%d: %@", comment: "裁剪中 %d/%d: %@"),
                            index + 1, total, url.lastPathComponent
                        ),
                        progress: startedRatio
                    )
                }

                if !self.cropVideoFile(url, cropSize: cropSize) {
                    failed.append(url)
                }

                let finishedRatio = Double(index + 1) / Double(total)
                DispatchQueue.main.async { [weak self] in
                    self?.coreAreaView.showOperationProgress(
                        String(
                            format: NSLocalizedString("Cropping... %d%%", comment: "裁剪中... %d%%"),
                            Int(finishedRatio * 100)
                        ),
                        progress: finishedRatio
                    )
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.publicVar.isInFileOperation = false
                self.publicVar.fileChangedCount += total - failed.count
                self.publicVar.filesForLocateAfterChange = urls.map(\.absoluteString)
                ThumbImageProcessor.clearCache()
                LargeImageProcessor.clearCache()

                if failed.isEmpty {
                    self.coreAreaView.showOperationProgress(
                        NSLocalizedString("Crop complete", comment: "裁剪完成"),
                        progress: 1.0
                    )
                    self.coreAreaView.hideOperationOverlay(delayed: 0.8)
                } else {
                    let preview = failed.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
                    self.coreAreaView.showOperationToast(
                        String(format: NSLocalizedString("Crop complete, failed: %d", comment: "裁剪完成，失败：%d"), failed.count),
                        autoHide: 2.0
                    )
                    showAlert(message: String(format: NSLocalizedString("Failed to crop some videos: %@", comment: "部分视频裁剪失败：%@"), preview))
                }

                if total - failed.count > 0 {
                    self.scheduledRefresh()
                }
            }
        }
    }

    private func cropVideoFile(_ url: URL, cropSize: CGSize) -> Bool {
        let width = max(2, Int(cropSize.width) - (Int(cropSize.width) % 2))
        let height = max(2, Int(cropSize.height) - (Int(cropSize.height) % 2))
        let cropFilter = "crop=\(width):\(height):(iw-\(width))/2:(ih-\(height))/2,setsar=1"
        return cropVideoFile(url, cropFilter: cropFilter)
    }

    private func cropVideoFile(_ url: URL, cropRect: VideoCropRect) -> Bool {
        let cropFilter = "crop=\(cropRect.width):\(cropRect.height):\(cropRect.x):\(cropRect.y),setsar=1"
        return cropVideoFile(url, cropFilter: cropFilter)
    }

    private func cropVideoFile(_ url: URL, cropFilter: String) -> Bool {
        guard FFmpegKitWrapper.shared.getIfLoaded() else { return false }

        let tempURL = makeTemporarySiblingURL(for: url)
        try? FileManager.default.removeItem(at: tempURL)

        let args = [
            "-y",
            "-i", url.path,
            "-map", "0",
            "-filter:v:0", cropFilter,
            "-map_metadata", "0",
            "-c:a", "copy",
            "-c:s", "copy",
            tempURL.path
        ]

        guard let session = FFmpegKitWrapper.shared.executeFFmpegCommand(args),
              FFmpegKitWrapper.shared.isSuccess(FFmpegKitWrapper.shared.getReturnCode(from: session)) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        return replaceOriginalFile(at: url, with: tempURL)
    }

    private func rotateImageFile(_ url: URL, rotation: BatchMediaRotation) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(imageSource) == 1,
              let sourceType = CGImageSourceGetType(imageSource),
              let image = NSImage(contentsOf: url),
              let rotatedCGImage = image.rotated(by: rotation.imageDegrees).cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let tempURL = makeTemporarySiblingURL(for: url)
        try? FileManager.default.removeItem(at: tempURL)
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, sourceType, 1, nil) else {
            return false
        }

        let properties = (CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]) ?? [:]
        let mutableProperties = NSMutableDictionary(dictionary: properties)
        mutableProperties[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(destination, rotatedCGImage, mutableProperties)

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        return replaceOriginalFile(at: url, with: tempURL)
    }

    private func rotateVideoFile(_ url: URL, rotation: BatchMediaRotation) -> Bool {
        guard FFmpegKitWrapper.shared.getIfLoaded() else { return false }

        let tempURL = makeTemporarySiblingURL(for: url)
        try? FileManager.default.removeItem(at: tempURL)
        
        if rotation == .restoreVideo {
            let restoreArgs = [
                "-y",
                "-i", url.path,
                "-map", "0",
                "-c", "copy",
                "-map_metadata", "0",
                "-metadata:s:v:0", "rotate=0",
                tempURL.path
            ]
            guard let session = FFmpegKitWrapper.shared.executeFFmpegCommand(restoreArgs),
                  FFmpegKitWrapper.shared.isSuccess(FFmpegKitWrapper.shared.getReturnCode(from: session)) else {
                try? FileManager.default.removeItem(at: tempURL)
                return false
            }
            return replaceOriginalFile(at: url, with: tempURL)
        }
        
        // Fast path: for common mp4/mov containers, update rotate metadata without re-encoding.
        let fastExts = Set(["mp4", "mov", "m4v"])
        let ext = url.pathExtension.lowercased()
        if fastExts.contains(ext) {
            let rotateDegree: String
            switch rotation {
            case .clockwise90: rotateDegree = "90"
            case .clockwise180: rotateDegree = "180"
            case .counterclockwise90: rotateDegree = "270"
            case .restoreVideo: rotateDegree = "0"
            }
            let copyArgs = [
                "-y",
                "-i", url.path,
                "-map", "0",
                "-c", "copy",
                "-metadata:s:v:0", "rotate=\(rotateDegree)",
                "-map_metadata", "0",
                tempURL.path
            ]
            if let session = FFmpegKitWrapper.shared.executeFFmpegCommand(copyArgs),
               FFmpegKitWrapper.shared.isSuccess(FFmpegKitWrapper.shared.getReturnCode(from: session)) {
                return replaceOriginalFile(at: url, with: tempURL)
            }
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let args = [
            "-y",
            "-i", url.path,
            "-map", "0",
            "-filter:v:0", rotation.videoFilter,
            "-map_metadata", "0",
            "-c:a", "copy",
            "-c:s", "copy",
            tempURL.path
        ]

        guard let session = FFmpegKitWrapper.shared.executeFFmpegCommand(args),
              FFmpegKitWrapper.shared.isSuccess(FFmpegKitWrapper.shared.getReturnCode(from: session)) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        return replaceOriginalFile(at: url, with: tempURL)
    }

    private func fileOperationUndoManager() -> UndoManager? {
        view.window?.undoManager ?? NSApp.keyWindow?.undoManager ?? undoManager
    }

    @discardableResult
    private func executeFileRenameMappings(
        _ mappings: [FileRenameMapping],
        actionName: String,
        registerUndo: Bool = true,
        locateTargets: [URL]? = nil
    ) -> Bool {
        guard !mappings.isEmpty else { return true }

        let fileManager = FileManager.default
        let sourcePathSet = Set(mappings.map { $0.from.path.lowercased() })

        for mapping in mappings {
            guard fileManager.fileExists(atPath: mapping.from.path) else {
                log("Rename source missing: \(mapping.from.path)", level: .error)
                return false
            }

            let targetPath = mapping.to.path.lowercased()
            if mapping.from.path.lowercased() == targetPath {
                continue
            }

            if fileManager.fileExists(atPath: mapping.to.path) && !sourcePathSet.contains(targetPath) {
                showAlert(message: String(format: NSLocalizedString("无法完成重命名，目标已存在：%@", comment: "rename undo conflict"), mapping.to.lastPathComponent))
                return false
            }
        }

        publicVar.isInFileOperation = true
        defer { publicVar.isInFileOperation = false }

        var pendingMoves: [PendingTempRename] = []

        for mapping in mappings {
            if mapping.from.path.lowercased() == mapping.to.path.lowercased() {
                continue
            }

            let tempURL = mapping.from.deletingLastPathComponent().appendingPathComponent("temp_rename_\(UUID().uuidString)")
            do {
                try fileManager.moveItem(at: mapping.from, to: tempURL)
                pendingMoves.append(PendingTempRename(tempURL: tempURL, targetURL: mapping.to))
            } catch {
                for pending in pendingMoves.reversed() {
                    try? fileManager.moveItem(at: pending.tempURL, to: mappings.first(where: { $0.to == pending.targetURL })?.from ?? pending.targetURL)
                }
                log("Failed to create temp rename path: \(error)", level: .error)
                showAlert(message: String(format: NSLocalizedString("重命名失败：%@", comment: "rename failed"), error.localizedDescription))
                return false
            }
        }

        var appliedMoves: [FileRenameMapping] = []
        for pending in pendingMoves {
            do {
                try fileManager.moveItem(at: pending.tempURL, to: pending.targetURL)
                publicVar.fileChangedCount += 1
                if let source = mappings.first(where: { $0.to == pending.targetURL })?.from {
                    appliedMoves.append(FileRenameMapping(from: source, to: pending.targetURL))
                }
            } catch {
                for applied in appliedMoves.reversed() {
                    try? fileManager.moveItem(at: applied.to, to: applied.from)
                }
                for remaining in pendingMoves where fileManager.fileExists(atPath: remaining.tempURL.path) {
                    if let original = mappings.first(where: { $0.to == remaining.targetURL })?.from {
                        try? fileManager.moveItem(at: remaining.tempURL, to: original)
                    }
                }
                log("Failed to complete rename: \(error)", level: .error)
                showAlert(message: String(format: NSLocalizedString("重命名失败：%@", comment: "rename failed"), error.localizedDescription))
                return false
            }
        }

        guard !appliedMoves.isEmpty else { return true }

        EnhancedIndex.handleFilesMoved(appliedMoves.map { (oldPath: $0.from.path, newPath: $0.to.path) })
        publicVar.filesForLocateAfterChange = (locateTargets ?? appliedMoves.map(\.to)).map(\.absoluteString)

        if registerUndo, let undoManager = fileOperationUndoManager() {
            let inverseMappings = appliedMoves.map { FileRenameMapping(from: $0.to, to: $0.from) }
            undoManager.registerUndo(withTarget: self) { target in
                _ = target.executeFileRenameMappings(
                    inverseMappings,
                    actionName: actionName,
                    registerUndo: true,
                    locateTargets: appliedMoves.map(\.from)
                )
            }
            undoManager.setActionName(actionName)
        }

        var ifRefresh = true
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        if publicVar.isRecursiveMode || isVirtualFolderPath(curFolder) {
            fileDB.lock()
            ifRefresh = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
            fileDB.unlock()
        }
        if ifRefresh {
            scheduledRefresh()
        }

        return true
    }

    @discardableResult
    func handleFilePromiseDrop(targetURL: URL, pasteboard: NSPasteboard) -> Bool {
        guard let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty else {
            return false
        }

        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("FlowVisionPromisedFiles-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        } catch {
            log("Failed to create temp folder for promised files: \(error)", level: .error)
            return false
        }

        var pendingCount = receivers.count
        var receivedURLs: [URL] = []

        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: tempRoot, options: [:], operationQueue: .main) { [weak self] fileURL, error in
                if let error = error {
                    log("Failed to receive promised file: \(error)", level: .error)
                } else {
                    receivedURLs.append(fileURL)
                }

                pendingCount -= 1
                if pendingCount == 0 {
                    defer { try? fileManager.removeItem(at: tempRoot) }

                    guard let self = self, !receivedURLs.isEmpty else {
                        return
                    }

                    let tempPasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
                    tempPasteboard.clearContents()
                    tempPasteboard.writeObjects(receivedURLs as [NSURL])
                    self.handlePaste(targetURL: targetURL, pasteboard: tempPasteboard)
                    tempPasteboard.releaseGlobally()
                }
            }
        }

        return true
    }

    func getUniqueDestinationURL(for url: URL, isInPlace: Bool = false) -> URL {
        var newURL = url
        var counter = 1

        while FileManager.default.fileExists(atPath: newURL.path) {
            let baseName = url.deletingPathExtension().lastPathComponent
            let extensionName = url.pathExtension
            var duplicateName = ""
            var newName = "\(baseName)_\(duplicateName)\(counter > 0 ? "\(counter+1)" : "")"
            if isInPlace {
                duplicateName = NSLocalizedString("copy-lowercase", comment: "copy(首字母小写)")
                newName = "\(baseName)_\(duplicateName)\(counter > 1 ? "\(counter)" : "")"
            }


            newURL = url.deletingLastPathComponent().appendingPathComponent(newName).appendingPathExtension(extensionName)
            counter += 1
        }

        return newURL
    }

    func handleNewFolder(targetURL: URL? = nil) -> (Bool,URL?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("New Folder", comment: "新建文件夹")
        alert.informativeText = NSLocalizedString("input-new-folder-name", comment: "请输入文件夹名称：")
        alert.alertStyle = .informational
        // 设置系统通知图标
        // Set system notification icon
        alert.icon = NSImage(named: NSImage.infoName)

        // 添加一个文本输入框
        // Add a text input field
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
            textFieldCell.usesSingleLineMode = true
            textFieldCell.wraps = false
            textFieldCell.isScrollable = true
        }
        alert.accessoryView = inputTextField

        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled=false
        DispatchQueue.main.async {
            _ = inputTextField.becomeFirstResponder()
        }
        let response = alert.runModal()
        publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled

        if response == .alertFirstButtonReturn {
            let folderName = inputTextField.stringValue

            if !folderName.isEmpty {
                fileDB.lock()
                let curFolder = fileDB.curFolder
                fileDB.unlock()

                var destinationURL = URL(string: curFolder)
                if targetURL != nil {destinationURL=targetURL}
                guard let destinationURL=destinationURL else {return (false,nil)}

                let newFolderURL = destinationURL.appendingPathComponent(folderName)

                // 检查是否存在同名文件
                // Check if file with same name exists
                if FileManager.default.fileExists(atPath: newFolderURL.path) {
                    showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                }else{
                    // 执行新建操作
                    // Execute create operation
                    do {
                        // 文件更改计数
                        // File change count
                        publicVar.fileChangedCount += 1

                        try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: true, attributes: nil)
                        log("Successfully created folder: \(newFolderURL.path)")
                        publicVar.filesForLocateAfterChange = [newFolderURL.absoluteString]
                        publicVar.filesForLocateAfterChangeTime = .now()
                        return (true,newFolderURL)
                    } catch {
                        log("Failed to create folder: \(error)", level: .error)
                        // Create folder failed
                    }
                }
            }
        }
        return (false,nil)
    }

    func handleNewTextFile(targetURL: URL? = nil) -> (Bool,URL?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("New Text File", comment: "新建文本文件")
        alert.informativeText = NSLocalizedString("input-new-textfile-name", comment: "请输入文件名称：")
        alert.alertStyle = .informational
        // 设置系统通知图标
        // Set system notification icon
        alert.icon = NSImage(named: NSImage.infoName)

        // 添加一个文本输入框
        // Add a text input field
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
            textFieldCell.usesSingleLineMode = true
            textFieldCell.wraps = false
            textFieldCell.isScrollable = true
        }
        alert.accessoryView = inputTextField

        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled=false
        DispatchQueue.main.async {
            _ = inputTextField.becomeFirstResponder()
        }
        let response = alert.runModal()
        publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled

        if response == .alertFirstButtonReturn {
            var fileName = inputTextField.stringValue

            if !fileName.isEmpty {
                // 如果用户没有输入扩展名，则加.txt后缀
                // If user didn't enter extension, add .txt suffix
                if !fileName.contains(".") {
                    fileName += ".txt"
                }

                fileDB.lock()
                let curFolder = fileDB.curFolder
                fileDB.unlock()

                var destinationURL = URL(string: curFolder)
                if targetURL != nil {destinationURL=targetURL}
                guard let destinationURL=destinationURL else {return (false,nil)}

                let newFileURL = destinationURL.appendingPathComponent(fileName)

                // 检查是否存在同名文件
                // Check if file with same name exists
                if FileManager.default.fileExists(atPath: newFileURL.path) {
                    showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                }else{
                    // 执行新建操作
                    // Execute create operation
                    do {
                        // 创建空文本文件
                        // Create empty text file
                        try "".write(to: newFileURL, atomically: true, encoding: .utf8)

                        // 文件更改计数
                        // File change count
                        publicVar.fileChangedCount += 1

                        log("Successfully created text file: \(newFileURL.path)")
                        publicVar.filesForLocateAfterChange = [newFileURL.absoluteString]
                        publicVar.filesForLocateAfterChangeTime = .now()
                        return (true,newFileURL)
                    } catch {
                        log("Failed to create text file: \(error)", level: .error)
                    }
                }
            }
        }
        return (false,nil)
    }

    func handleNewFolderWithSelection() {
        var urls = publicVar.selectedUrls()
        if urls.isEmpty {return}

        let (ifSuccess,newFolderURL) = handleNewFolder()

        if ifSuccess {
            // 备份剪贴板内容
            // Backup pasteboard content
            let backupItems = backupPasteboard()

            handleCopy()
            handleMove(targetURL: newFolderURL)

            if let newFolderURL = newFolderURL {
                publicVar.filesForLocateAfterChange = [newFolderURL.absoluteString]
                publicVar.filesForLocateAfterChangeTime = .now()
            }

            // 还原剪贴板内容
            // Restore pasteboard content
            restorePasteboard(items: backupItems)
        }

    }

//    // 备份剪贴板内容的函数
//    func backupPasteboard() -> [NSPasteboard.PasteboardType: Any] {
//        let pasteboard = NSPasteboard.general
//        var backupItems = [NSPasteboard.PasteboardType: Any]()
//
//        for type in pasteboard.types ?? [] {
//            if let item = pasteboard.data(forType: type) {
//                backupItems[type] = item
//            }
//        }
//
//        return backupItems
//    }
//
//    // 还原剪贴板内容的函数
//    func restorePasteboard(items: [NSPasteboard.PasteboardType: Any]) {
//        let pasteboard = NSPasteboard.general
//        pasteboard.clearContents()
//
//        for (type, item) in items {
//            if let data = item as? Data {
//                pasteboard.setData(data, forType: type)
//            }
//        }
//    }

    // 备份剪贴板内容的函数
    // Function to backup pasteboard content
    func backupPasteboard() -> [[String: Data]] {
        let pasteboard = NSPasteboard.general
        var backupItems = [[String: Data]]()

        for item in pasteboard.pasteboardItems ?? [] {
            var backupItem = [String: Data]()
            for type in item.types {
                if let data = item.data(forType: type) {
                    backupItem[type.rawValue] = data
                }
            }
            backupItems.append(backupItem)
        }

        return backupItems
    }

    // 还原剪贴板内容的函数
    // Function to restore pasteboard content
    func restorePasteboard(items: [[String: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for itemData in items {
            let newItem = NSPasteboardItem()
            for (type, data) in itemData {
                newItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: type))
            }
            pasteboard.writeObjects([newItem])
        }
    }

    func handleCopy() {
        let pasteboard = NSPasteboard.general
        // 清除剪贴板现有内容
        // Clear existing pasteboard content
        pasteboard.clearContents()
        // 将文件URL添加到剪贴板
        // Add file URLs to pasteboard
        pasteboard.writeObjects(publicVar.selectedUrls() as [NSPasteboardWriting])
        // 复制操作重置剪切模式
        // Copy operation resets cut mode
        globalVar.isCutMode = false
        clearCutItemsDimEffect()
    }

    func handleCopyToDownload() {
        if publicVar.selectedUrls().isEmpty {return}

        // 备份剪贴板内容
        // Backup pasteboard content
        let backupItems = backupPasteboard()

        handleCopy()
        handlePaste(targetURL: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)

        // 还原剪贴板内容
        // Restore pasteboard content
        restorePasteboard(items: backupItems)
    }

    func handleCopyToPhotoFolder1() {
        let selectedURLs = publicVar.selectedUrls()
        if selectedURLs.isEmpty { return }
        handleCopyToConfiguredFolder(
            selectedURLs: selectedURLs,
            targetPath: globalVar.photoFolder1Path,
            emptyPathMessage: NSLocalizedString("Please set Photo Folder 1 in Settings first.", comment: "请先在设置中配置图片文件夹1。"),
            invalidPathMessage: NSLocalizedString("Photo Folder 1 does not exist or is not a folder.", comment: "图片文件夹1不存在或不是文件夹。")
        )
    }

    func handleCopySelectedVideosToPhotoFolder2() {
        let selectedURLs = publicVar.selectedUrls()
        if selectedURLs.isEmpty { return }

        let videoURLs = selectedURLs.filter { isVideoURLForFolder2Copy($0) }
        guard !videoURLs.isEmpty else {
            showAlert(message: NSLocalizedString("Please select at least one video first.", comment: "请先选择至少一个视频。"))
            return
        }

        handleCopyToConfiguredFolder(
            selectedURLs: videoURLs,
            targetPath: globalVar.photoFolder2Path,
            emptyPathMessage: NSLocalizedString("Please set Video Folder 2 in Settings first.", comment: "请先在设置中配置视频文件夹2。"),
            invalidPathMessage: NSLocalizedString("Video Folder 2 does not exist or is not a folder.", comment: "视频文件夹2不存在或不是文件夹。")
        )
    }

    func handleCopyCurrentVideoToPhotoFolder2() {
        guard publicVar.isInLargeView,
              largeImageView.file.type == .video,
              let currentURL = URL(string: largeImageView.file.path) else {
            return
        }

        handleCopyToConfiguredFolder(
            selectedURLs: [currentURL],
            targetPath: globalVar.photoFolder2Path,
            emptyPathMessage: NSLocalizedString("Please set Video Folder 2 in Settings first.", comment: "请先在设置中配置视频文件夹2。"),
            invalidPathMessage: NSLocalizedString("Video Folder 2 does not exist or is not a folder.", comment: "视频文件夹2不存在或不是文件夹。")
        )
    }

    private func showPhotoFolderCopyToast(selectedURLs: [URL], targetFolderURL: URL) {
        guard !selectedURLs.isEmpty else { return }
        let firstName = selectedURLs[0].lastPathComponent.removingPercentEncoding ?? selectedURLs[0].lastPathComponent
        let targetName = targetFolderURL.lastPathComponent.isEmpty ? targetFolderURL.path : targetFolderURL.lastPathComponent
        let message: String
        if selectedURLs.count == 1 {
            message = "\(firstName) -> \(targetName)"
        } else {
            message = "\(firstName) +\(selectedURLs.count - 1) -> \(targetName)"
        }
        DispatchQueue.main.async { [weak self] in
            self?.coreAreaView.showOperationToast(message, autoHide: 2.0)
        }
    }

    private func handleCopyToConfiguredFolder(selectedURLs: [URL], targetPath: String, emptyPathMessage: String, invalidPathMessage: String) {
        guard !selectedURLs.isEmpty else { return }

        let normalizedTargetPath = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTargetPath.isEmpty {
            showAlert(message: emptyPathMessage)
            return
        }

        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: normalizedTargetPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
            showAlert(message: invalidPathMessage)
            return
        }

        let targetFolderURL = URL(fileURLWithPath: normalizedTargetPath, isDirectory: true)
        if selectedURLs.contains(where: { isVirtualArchiveEntryPath($0.absoluteString) }) {
            var failedItems: [String] = []
            var successCount = 0
            for srcURL in selectedURLs {
                if isVirtualArchiveEntryPath(srcURL.absoluteString) {
                    guard let parsed = parseVirtualArchivePath(srcURL.absoluteString),
                          let entryPath = parsed.entryPath,
                          let data = getArchiveEntryData(archiveURL: parsed.archiveURL, entryPath: entryPath) else {
                        failedItems.append(srcURL.lastPathComponent.removingPercentEncoding ?? srcURL.lastPathComponent)
                        continue
                    }
                    let fileName = URL(fileURLWithPath: entryPath).lastPathComponent
                    let targetURL = getUniqueDestinationURL(for: targetFolderURL.appendingPathComponent(fileName), isInPlace: false)
                    do {
                        try data.write(to: targetURL, options: .atomic)
                        successCount += 1
                    } catch {
                        log("Copy archive entry failed: \(error)", level: .error)
                        failedItems.append(fileName)
                    }
                } else {
                    let targetURL = getUniqueDestinationURL(for: targetFolderURL.appendingPathComponent(srcURL.lastPathComponent), isInPlace: false)
                    do {
                        try FileManager.default.copyItem(at: srcURL, to: targetURL)
                        successCount += 1
                    } catch {
                        log("Copy file failed: \(error)", level: .error)
                        failedItems.append(srcURL.lastPathComponent)
                    }
                }
            }

            if successCount > 0 {
                publicVar.fileChangedCount += successCount
                scheduledRefresh()
                showPhotoFolderCopyToast(selectedURLs: selectedURLs, targetFolderURL: targetFolderURL)
            }
            if !failedItems.isEmpty {
                let preview = failedItems.prefix(3).joined(separator: ", ")
                showAlert(message: String(format: NSLocalizedString("Failed to copy some files: %@", comment: "部分文件复制失败：%@"), preview))
            }
            return
        }

        let backupItems = backupPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(selectedURLs as [NSPasteboardWriting])
        globalVar.isCutMode = false
        clearCutItemsDimEffect()
        handlePaste(targetURL: targetFolderURL)
        showPhotoFolderCopyToast(selectedURLs: selectedURLs, targetFolderURL: targetFolderURL)
        restorePasteboard(items: backupItems)
    }

    private func isVideoURLForFolder2Copy(_ url: URL) -> Bool {
        if isVirtualArchiveEntryPath(url.absoluteString),
           let parsed = parseVirtualArchivePath(url.absoluteString),
           let entryPath = parsed.entryPath {
            let ext = URL(fileURLWithPath: entryPath).pathExtension.lowercased()
            return globalVar.HandledVideoExtensions.contains(ext)
        }
        return globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased())
    }

    func promptCompressionPassword(initialValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Encrypt ZIP", comment: "加密压缩 ZIP")
        alert.informativeText = NSLocalizedString("Please input ZIP password:", comment: "请输入 ZIP 密码：")
        alert.alertStyle = .informational
        alert.icon = NSImage(named: NSImage.infoName)

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        passwordField.stringValue = initialValue
        alert.accessoryView = passwordField

        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

        let old = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        DispatchQueue.main.async { _ = passwordField.becomeFirstResponder() }
        let response = alert.runModal()
        publicVar.isKeyEventEnabled = old

        guard response == .alertFirstButtonReturn else { return nil }
        let password = passwordField.stringValue
        if password.isEmpty {
            showAlert(message: NSLocalizedString("Password cannot be empty.", comment: "密码不能为空。"))
            return nil
        }
        return password
    }

    private func makeZipDestinationURL(for urls: [URL]) -> URL? {
        guard !urls.isEmpty else { return nil }
        let parent = urls[0].deletingLastPathComponent()
        if urls.count == 1 {
            let base = urls[0].deletingPathExtension().lastPathComponent
            return getUniqueDestinationURL(for: parent.appendingPathComponent(base).appendingPathExtension("zip"), isInPlace: false)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        return getUniqueDestinationURL(for: parent.appendingPathComponent("Archive_\(stamp)").appendingPathExtension("zip"), isInPlace: false)
    }

    private func collectCompressMetrics(urls: [URL]) -> (totalBytes: Int64, totalFiles: Int) {
        let fm = FileManager.default
        var totalBytes: Int64 = 0
        var totalFiles = 0

        func addFile(_ url: URL) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            let size = values?.totalFileAllocatedSize
                ?? values?.fileAllocatedSize
                ?? values?.fileSize
                ?? 0
            totalBytes += Int64(size)
            totalFiles += 1
        }

        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: [], errorHandler: nil) {
                    while let subURL = enumerator.nextObject() as? URL {
                        let isDirectory = (try? subURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        if !isDirectory {
                            addFile(subURL)
                        }
                    }
                }
            } else {
                addFile(url)
            }
        }

        return (totalBytes, max(totalFiles, 1))
    }

    private func buildCompressCommand(urls: [URL], destination: URL, mode: CompressMode) -> (args: [String], workDir: URL)? {
        guard !urls.isEmpty else { return nil }
        let workDir = urls[0].deletingLastPathComponent()
        var relativeNames: [String] = []
        for url in urls {
            if url.deletingLastPathComponent() != workDir {
                return nil
            }
            relativeNames.append(url.lastPathComponent)
        }
        var args: [String] = ["-r", "-y"]
        switch mode {
        case .plainZip:
            break
        case .encryptedZip(let password):
            args += ["-P", password]
        }
        args.append(destination.path)
        args.append(contentsOf: relativeNames)
        return (args, workDir)
    }

    @discardableResult
    func handleCompress(urls inputUrls: [URL] = [], mode: CompressMode, deleteOriginal: Bool) -> Bool {
        var urls = inputUrls
        if urls.isEmpty {
            urls = publicVar.selectedUrls()
        }
        if urls.isEmpty { return false }

        if urls.contains(where: { isReadOnlyVirtualFolderPath($0.absoluteString) || isVirtualArchiveEntryPath($0.absoluteString) }) {
            showAlert(message: NSLocalizedString("Virtual entries cannot be compressed.", comment: "虚拟目录或压缩包内虚拟条目不支持压缩。"))
            return false
        }

        let sortedUrls = urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard let destinationURL = makeZipDestinationURL(for: sortedUrls) else { return false }
        guard let (args, workDir) = buildCompressCommand(urls: sortedUrls, destination: destinationURL, mode: mode) else {
            showAlert(message: NSLocalizedString("Please select items from the same folder.", comment: "请在同一目录下选择要压缩的项目。"))
            return false
        }

        let metrics = collectCompressMetrics(urls: sortedUrls)
        let shouldShowOverlayProgress = metrics.totalBytes >= 100 * 1024 * 1024

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workDir
        process.arguments = args
        let stdErr = Pipe()
        let stdOut = Pipe()
        process.standardError = stdErr
        process.standardOutput = stdOut

        if shouldShowOverlayProgress {
            DispatchQueue.main.async { [weak self] in
                self?.coreAreaView.showOperationProgress(NSLocalizedString("Compressing... 0%", comment: "压缩中... 0%"), progress: 0)
            }
        }

        let parseQueue = DispatchQueue(label: "flowvision.compress.stdout.parse")
        var processedFiles = 0
        let progressUpdateStep = max(1, metrics.totalFiles / 100)
        stdOut.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard shouldShowOverlayProgress else { return }
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            parseQueue.async {
                let lines = output.split(whereSeparator: \.isNewline)
                for line in lines {
                    if line.contains("adding:") {
                        processedFiles += 1
                    }
                }
                if processedFiles == 0 { return }
                if processedFiles % progressUpdateStep != 0 && processedFiles < metrics.totalFiles { return }
                let ratio = min(1.0, Double(processedFiles) / Double(metrics.totalFiles))
                DispatchQueue.main.async {
                    self?.coreAreaView.showOperationProgress(
                        String(format: NSLocalizedString("Compressing... %d%%", comment: "压缩中... %d%%"), Int(ratio * 100)),
                        progress: ratio
                    )
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            stdOut.fileHandleForReading.readabilityHandler = nil
            showAlert(message: NSLocalizedString("Failed to execute zip.", comment: "执行压缩失败。"))
            log("zip execute failed: \(error)", level: .error)
            if shouldShowOverlayProgress {
                DispatchQueue.main.async { [weak self] in
                    self?.coreAreaView.hideOperationOverlay()
                }
            }
            return false
        }
        stdOut.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            let errMsg = String(data: stdErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if !errMsg.isEmpty { log("zip failed: \(errMsg)", level: .error) }
            showAlert(message: NSLocalizedString("Compression failed.", comment: "压缩失败。"))
            if shouldShowOverlayProgress {
                DispatchQueue.main.async { [weak self] in
                    self?.coreAreaView.hideOperationOverlay()
                }
            }
            return false
        }

        if shouldShowOverlayProgress {
            DispatchQueue.main.async { [weak self] in
                self?.coreAreaView.showOperationProgress(NSLocalizedString("Compression complete", comment: "压缩完成"), progress: 1.0)
                self?.coreAreaView.hideOperationOverlay(delayed: 0.8)
            }
        }

        publicVar.fileChangedCount += 1
        publicVar.filesForLocateAfterChange = [destinationURL.absoluteString]
        var logText = "[Compress] \(sortedUrls.count) item(s) -> \(destinationURL.lastPathComponent)"
        if deleteOriginal {
            for url in sortedUrls {
                _ = try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            publicVar.fileChangedCount += sortedUrls.count
            logText += " + delete source"
        }
        globalVar.operationLogs.append(logText)
        scheduledRefresh()
        return true
    }

    @discardableResult
    func handleCompressByDefaultSetting(urls: [URL] = [], deleteOriginal: Bool = false) -> Bool {
        if globalVar.compressionUseDefaultPassword {
            let password = globalVar.compressionDefaultPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            if password.isEmpty {
                showAlert(message: NSLocalizedString("Default compression password is empty. Please set it in Settings.", comment: "默认压缩密码为空，请先在设置中配置。"))
                return false
            }
            return handleCompress(urls: urls, mode: .encryptedZip(password: password), deleteOriginal: deleteOriginal)
        }
        return handleCompress(urls: urls, mode: .plainZip, deleteOriginal: deleteOriginal)
    }

    private func archiveBaseName(for url: URL) -> String {
        let lowerName = url.lastPathComponent.lowercased()
        let multiExtensions = [".tar.gz", ".tar.bz2", ".tar.xz"]
        if let matched = multiExtensions.first(where: { lowerName.hasSuffix($0) }) {
            return String(url.lastPathComponent.dropLast(matched.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func makeExtractDestinationURL(for archiveURL: URL) -> URL {
        let parent = archiveURL.deletingLastPathComponent()
        let base = archiveBaseName(for: archiveURL)
        return getUniqueDestinationURL(for: parent.appendingPathComponent(base), isInPlace: false)
    }

    @discardableResult
    func handleExtractArchives(urls inputUrls: [URL] = [], deleteOriginal: Bool) -> Bool {
        var urls = inputUrls
        if urls.isEmpty {
            urls = publicVar.selectedUrls()
        }
        if urls.isEmpty { return false }

        let archiveURLs = urls.filter {
            !$0.absoluteString.isEmpty &&
            !isReadOnlyVirtualFolderPath($0.absoluteString) &&
            !isVirtualArchiveEntryPath($0.absoluteString) &&
            isSupportedArchiveURL($0)
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        guard !archiveURLs.isEmpty else {
            showAlert(message: NSLocalizedString("Please select archive files first.", comment: "请先选择压缩包文件。"))
            return false
        }

        var extractedDestinations: [URL] = []
        var failedArchives: [String] = []
        let fm = FileManager.default

        for archiveURL in archiveURLs {
            let destinationURL = makeExtractDestinationURL(for: archiveURL)
            do {
                try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } catch {
                log("create extract dir failed: \(error)", level: .error)
                failedArchives.append(archiveURL.lastPathComponent)
                continue
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
            process.arguments = ["-xf", archiveURL.path, "-C", destinationURL.path]
            let stdErr = Pipe()
            process.standardError = stdErr

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                log("extract execute failed: \(error)", level: .error)
                failedArchives.append(archiveURL.lastPathComponent)
                try? fm.removeItem(at: destinationURL)
                continue
            }

            guard process.terminationStatus == 0 else {
                let errMsg = String(data: stdErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if !errMsg.isEmpty {
                    log("extract failed: \(errMsg)", level: .error)
                }
                failedArchives.append(archiveURL.lastPathComponent)
                try? fm.removeItem(at: destinationURL)
                continue
            }

            extractedDestinations.append(destinationURL)
            if deleteOriginal {
                _ = try? fm.trashItem(at: archiveURL, resultingItemURL: nil)
            }
        }

        guard !extractedDestinations.isEmpty else {
            showAlert(message: NSLocalizedString("Extraction failed.", comment: "解压失败。"))
            return false
        }

        publicVar.fileChangedCount += extractedDestinations.count + (deleteOriginal ? archiveURLs.count : 0)
        publicVar.filesForLocateAfterChange = extractedDestinations.map { $0.absoluteString }
        var logText = "[Extract] \(archiveURLs.count) archive(s)"
        if deleteOriginal {
            logText += " + delete source"
        }
        globalVar.operationLogs.append(logText)
        scheduledRefresh()

        if !failedArchives.isEmpty {
            let preview = failedArchives.prefix(3).joined(separator: ", ")
            showAlert(message: String(format: NSLocalizedString("Failed to extract some archives: %@", comment: "部分压缩包解压失败：%@"), preview))
        }
        return true
    }

    func handleCaptureCurrentVideoFrameToCurrentFolder() {
        guard publicVar.isInLargeView,
              largeImageView.file.type == .video,
              let videoURL = URL(string: largeImageView.file.path),
              videoURL.isFileURL else {
            return
        }

        var captureTime = CMTime(seconds: largeImageView.videoCurrentTimeSeconds, preferredTimescale: 600)
        if !captureTime.isValid || captureTime == .indefinite {
            captureTime = CMTime(seconds: 0, preferredTimescale: 600)
        }

        let generator = AVAssetImageGenerator(asset: AVAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        do {
            let cgImage = try generator.copyCGImage(at: captureTime, actualTime: nil)
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                showAlert(message: NSLocalizedString("Failed to encode captured frame.", comment: "编码截图失败。"))
                return
            }

            let baseName = videoURL.deletingPathExtension().lastPathComponent
            let ms = max(0, Int(CMTimeGetSeconds(captureTime).isFinite ? CMTimeGetSeconds(captureTime) * 1000 : 0))
            let fileName = "\(baseName)_frame_\(ms)"
            let outputCandidate = videoURL.deletingLastPathComponent().appendingPathComponent(fileName).appendingPathExtension("png")
            let outputURL = getUniqueDestinationURL(for: outputCandidate)

            try pngData.write(to: outputURL, options: .atomic)
            publicVar.fileChangedCount += 1
            // Preserve the current video after refresh so the newly saved frame
            // doesn't take over the current large-view position and pause playback.
            publicVar.openFromFinderPath = videoURL.absoluteString
            scheduledRefresh()
            largeImageView.showInfo(NSLocalizedString("Frame Saved", comment: "视频帧已保存"))
        } catch {
            log("Capture video frame failed: \(error)", level: .error)
            showAlert(message: NSLocalizedString("Failed to capture current video frame.", comment: "抓取当前视频帧失败。"))
        }
    }

    @discardableResult
    func handleCollectFilesFromSubfolders() -> Bool {
        let selectedURLs = publicVar.selectedUrls()
        guard selectedURLs.count > 1 else { return false }

        if selectedURLs.contains(where: { isReadOnlyVirtualFolderPath($0.absoluteString) || isVirtualArchiveEntryPath($0.absoluteString) }) {
            showAlert(message: NSLocalizedString("Virtual entries are not supported for this operation.", comment: "该操作不支持虚拟目录或压缩包内虚拟条目。"))
            return false
        }

        let folderURLs = selectedURLs.filter { $0.hasDirectoryPath }
        guard folderURLs.count == selectedURLs.count else {
            showAlert(message: NSLocalizedString("Please select folders only.", comment: "请仅选择文件夹。"))
            return false
        }

        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()

        guard let currentFolderURL = URL(string: curFolder), currentFolderURL.isFileURL else {
            showAlert(message: NSLocalizedString("Invalid current path", comment: "当前路径无效"))
            return false
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let folderName = "CollectedFiles_\(formatter.string(from: Date()))"
        let targetFolderURL = getUniqueDestinationURL(for: currentFolderURL.appendingPathComponent(folderName), isInPlace: false)

        do {
            try FileManager.default.createDirectory(at: targetFolderURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            log("Create collected folder failed: \(error)", level: .error)
            showAlert(message: NSLocalizedString("Failed to create collection folder.", comment: "创建归集文件夹失败。"))
            return false
        }

        var copiedCount = 0
        var failedCount = 0
        var copiedURLs: [String] = []

        for folderURL in folderURLs {
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [],
                errorHandler: { url, error in
                    log("Enumerate failed \(url): \(error)", level: .warn)
                    return true
                }
            ) else { continue }

            while let itemURL = enumerator.nextObject() as? URL {
                let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isDirectory == true { continue }
                guard values?.isRegularFile == true else { continue }

                let targetURL = getUniqueDestinationURL(for: targetFolderURL.appendingPathComponent(itemURL.lastPathComponent), isInPlace: false)
                do {
                    try FileManager.default.copyItem(at: itemURL, to: targetURL)
                    copiedCount += 1
                    copiedURLs.append(targetURL.absoluteString)
                } catch {
                    failedCount += 1
                    log("Copy collected file failed: \(error)", level: .warn)
                }
            }
        }

        if copiedCount == 0 {
            try? FileManager.default.removeItem(at: targetFolderURL)
            let message = failedCount > 0
                ? NSLocalizedString("No files were collected from subfolders.", comment: "未能从子文件夹中归集到文件。")
                : NSLocalizedString("No files found in subfolders.", comment: "子文件夹中未找到可归集文件。")
            showAlert(message: message)
            return false
        }

        publicVar.fileChangedCount += copiedCount + 1
        publicVar.filesForLocateAfterChange = [targetFolderURL.absoluteString]
        globalVar.operationLogs.append("[Collect] \(copiedCount) files -> \(targetFolderURL.lastPathComponent)")
        scheduledRefresh()

        let infoText: String
        if failedCount > 0 {
            infoText = String(format: NSLocalizedString("Collected %d files (%d failed)", comment: "已归集 %d 个文件（%d 个失败）"), copiedCount, failedCount)
        } else {
            infoText = String(format: NSLocalizedString("Collected %d files", comment: "已归集 %d 个文件"), copiedCount)
        }
        coreAreaView.showOperationToast(infoText + " -> " + targetFolderURL.lastPathComponent, autoHide: 2.0)
        return true
    }

    func handlePaste(targetURL: URL? = nil, pasteboard: NSPasteboard = NSPasteboard.general) {
        // 如果是剪切模式，执行移动操作而非复制
        // If in cut mode, perform move operation instead of copy
        if globalVar.isCutMode {
            globalVar.isCutMode = false
            clearCutItemsDimEffect()
            handleMove(targetURL: targetURL, pasteboard: pasteboard)
            return
        }

        guard let items = pasteboard.pasteboardItems else { return }

        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        var destinationURL: URL? = nil
        if let targetURL = targetURL {
            destinationURL = targetURL
        } else {
            destinationURL = URL(string: curFolder)
        }
        guard let destinationURL = destinationURL else { return }

        // 检查待复制的文件/文件夹列表
        // Check list of files/folders to copy
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }

            // 检查是否包含目标目录自身或者它的父目录
            // Check if includes destination directory itself or its parent directory
            if fileURL == destinationURL || destinationURL.path.hasPrefix(fileURL.path) {
                showAlert(message: NSLocalizedString("cannot-copy-to-self", comment: "不能将文件/文件夹复制到自身或其子目录中。"))
                return
            }
        }

        // 检查来源是否有同名文件
        // Check if source has files with same name
        var ifAutoRenameWhenDifferentSource = false
        var fileNames = Set<String>()
        var hasDuplicates = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            let fileName = fileURL.lastPathComponent
            if fileNames.contains(fileName) {
                hasDuplicates = true
                break
            }
            fileNames.insert(fileName)
        }

        // 如果有同名文件,弹窗询问是否继续
        // If there are files with same name, show dialog asking whether to continue
        if hasDuplicates {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("has-same-name-files", comment: "发现同名文件")
            alert.informativeText = NSLocalizedString("has-same-name-files-info", comment: "来源文件中包含同名文件，是否自动重命名？")
            alert.alertStyle = .warning
            // 设置系统提示图标
            // Set system notification icon
            alert.icon = NSImage(named: NSImage.infoName)
            alert.addButton(withTitle: NSLocalizedString("Auto Rename", comment: "自动重命名"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

            let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled = false
            defer {
                publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
            }
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                ifAutoRenameWhenDifferentSource = true
            } else {
                return
            }
        }

        // 记录操作到日志
        // Record operation to log
        var sourceFiles = items.compactMap { item -> String? in
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { return nil }
            return fileURL.lastPathComponent
        }

        let sourceFilesStr: String
        if sourceFiles.count > 3 {
            sourceFilesStr = sourceFiles[0...2].joined(separator: ", ") + "..."
        } else {
            sourceFilesStr = sourceFiles.joined(separator: ", ")
        }

        let operationLog = "[Paste] \(sourceFilesStr) -> \(destinationURL.lastPathComponent)"
        globalVar.operationLogs.append(operationLog)

        // 在文件操作期间抑制文件系统监控触发的刷新，操作完成后主动刷新
        // Suppress FS watcher refreshes during file operations, refresh explicitly after completion
        publicVar.isInFileOperation = true
        // 记录成功粘贴的目标路径，用于刷新后选中
        // Record successfully pasted destination paths for selection after refresh
        var successfulDestURLs: [String] = []
        var indexCopyPairs: [(sourcePath: String, destPath: String)] = []
        defer {
            publicVar.isInFileOperation = false
            if !successfulDestURLs.isEmpty {
                triggerFinderSound()
                publicVar.filesForLocateAfterChange = successfulDestURLs
                publicVar.filesForLocateAfterChangeTime = .now()
                var ifRefresh = true
                if publicVar.isRecursiveMode || isVirtualFolderPath(curFolder) {
                    fileDB.lock()
                    ifRefresh = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
                    fileDB.unlock()
                }
                if !destinationURL.absoluteString.hasPrefix(curFolder)
                    && successfulDestURLs.allSatisfy({ urlStr in
                        if let url = URL(string: urlStr) {
                            var isDir: ObjCBool = false
                            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                            return !isDir.boolValue
                        }
                        return false
                    }) {
                    ifRefresh = false
                }
                if ifRefresh {
                    scheduledRefresh()
                }
            }
            if !indexCopyPairs.isEmpty {
                EnhancedIndex.handleFilesCopied(indexCopyPairs)
            }
        }

        var shouldReplaceAll = false
        var shouldMergeAll = false
        var shouldSkipAll = false
        var shouldAutoRenameAll = false
        let sharedMergeState = MergeConflictState()

        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            let prevSuccessCount = successfulDestURLs.count
            var destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)

            if ifAutoRenameWhenDifferentSource {
                destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
            }

            // 如果是在同一目录复制粘贴，则修改名称
            // If copying/pasting in same directory, modify name
            var isInSameFolder = fileURL.deletingLastPathComponent() == destinationURL
            if isInSameFolder {
                destURL = getUniqueDestinationURL(for: destURL, isInPlace: true)
            }

            if FileManager.default.fileExists(atPath: destURL.path) {
                // 检测源和目标是否都是文件夹
                // Check if both source and destination are folders
                var srcIsDir: ObjCBool = false
                FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &srcIsDir)
                var dstIsDir: ObjCBool = false
                FileManager.default.fileExists(atPath: destURL.path, isDirectory: &dstIsDir)
                let bothAreFolders = srcIsDir.boolValue && dstIsDir.boolValue

                if shouldReplaceAll {
                    do {
                        try FileManager.default.removeItem(at: destURL)
                        try FileManager.default.copyItem(at: fileURL, to: destURL)
                        successfulDestURLs.append(destURL.absoluteString)
                        publicVar.fileChangedCount += 1
                    } catch {
                        log("Failed to paste \(fileURL): \(error)", level: .error)
                    }
                } else if shouldMergeAll && bothAreFolders {
                    if mergeFolderByCopy(from: fileURL, to: destURL, state: sharedMergeState) {
                        successfulDestURLs.append(destURL.absoluteString)
                        publicVar.fileChangedCount += 1
                    }
                    if sharedMergeState.cancelled {
                        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                        return
                    }
                } else if shouldSkipAll {
                    continue
                } else if shouldAutoRenameAll {
                    destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                    do {
                        try FileManager.default.copyItem(at: fileURL, to: destURL)
                        successfulDestURLs.append(destURL.absoluteString)
                        publicVar.fileChangedCount += 1
                    } catch {
                        log("Failed to paste \(fileURL): \(error)", level: .error)
                    }
                } else {
                    let userChoice = showReplaceDialog(for: destURL, sourceURL: fileURL, isSingle: items.count == 1, isMove: false)
                    switch userChoice {
                    case .replace:
                        do {
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        } catch {
                            log("Failed to paste \(fileURL): \(error)", level: .error)
                        }
                    case .replaceAll:
                        shouldReplaceAll = true
                        do {
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        } catch {
                            log("Failed to paste \(fileURL): \(error)", level: .error)
                        }
                    case .merge:
                        if mergeFolderByCopy(from: fileURL, to: destURL, state: sharedMergeState) {
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        }
                        if sharedMergeState.cancelled {
                            publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                            return
                        }
                    case .mergeAll:
                        shouldMergeAll = true
                        if mergeFolderByCopy(from: fileURL, to: destURL, state: sharedMergeState) {
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        }
                        if sharedMergeState.cancelled {
                            publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                            return
                        }
                    case .autoRename:
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        do {
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        } catch {
                            log("Failed to paste \(fileURL): \(error)", level: .error)
                        }
                    case .autoRenameAll:
                        shouldAutoRenameAll = true
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        do {
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        } catch {
                            log("Failed to paste \(fileURL): \(error)", level: .error)
                        }
                    case .skip:
                        continue
                    case .skipAll:
                        shouldSkipAll = true
                        continue
                    case .cancel:
                        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                        return
                    }
                }
            } else {
                do {
                    try FileManager.default.copyItem(at: fileURL, to: destURL)
                    successfulDestURLs.append(destURL.absoluteString)
                    publicVar.fileChangedCount += 1
                } catch {
                    log("Failed to paste \(fileURL): \(error)", level: .error)
                }
            }
            if successfulDestURLs.count > prevSuccessCount,
               let destStr = successfulDestURLs.last,
               let destPath = URL(string: destStr)?.path {
                indexCopyPairs.append((sourcePath: fileURL.path, destPath: destPath))
            }
        }
        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
    }

    func handleMoveToDownload() {
        if publicVar.selectedUrls().isEmpty {return}

        // 备份剪贴板内容
        // Backup pasteboard content
        let backupItems = backupPasteboard()

        handleCopy()
        handleMove(targetURL: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)

        // 还原剪贴板内容
        // Restore pasteboard content
        restorePasteboard(items: backupItems)
    }

    func handleMove(targetURL: URL? = nil, pasteboard: NSPasteboard = NSPasteboard.general) {

        // 重置剪切模式，防止直接调用handleMove后isCutMode残留为true
        // Reset cut mode to prevent isCutMode remaining true after direct handleMove calls
        globalVar.isCutMode = false
        clearCutItemsDimEffect()

        // 按住Option则为复制
        // Hold Option to copy
        if isOptionKeyPressed() && !isCommandKeyPressed() {
            handlePaste(targetURL: targetURL, pasteboard: pasteboard)
            return
        }

        guard let items = pasteboard.pasteboardItems else { return }

        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        var destinationURL: URL? = nil
        if let targetURL = targetURL {
            destinationURL = targetURL
        } else {
            destinationURL = URL(string: curFolder)
        }
        guard let destinationURL = destinationURL else { return }

        // 检查待移动的文件/文件夹列表
        // Check list of files/folders to move
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }

            // 检查是否包含目标目录自身或者它的父目录
            // Check if includes destination directory itself or its parent directory
            if fileURL == destinationURL || destinationURL.path.hasPrefix(fileURL.path) {
                showAlert(message: NSLocalizedString("cannot-move-to-self", comment: "不能将文件/文件夹移动到自身或其子目录中。"))
                return
            }
        }

        // 检查来源是否有同名文件
        // Check if source has files with same name
        var ifAutoRenameWhenDifferentSource = false
        var fileNames = Set<String>()
        var hasDuplicates = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            let fileName = fileURL.lastPathComponent
            if fileNames.contains(fileName) {
                hasDuplicates = true
                break
            }
            fileNames.insert(fileName)
        }

        // 如果有同名文件,弹窗询问是否继续
        // If there are files with same name, show dialog asking whether to continue
        if hasDuplicates {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("has-same-name-files", comment: "发现同名文件")
            alert.informativeText = NSLocalizedString("has-same-name-files-info", comment: "来源文件中包含同名文件，是否自动重命名？")
            alert.alertStyle = .warning
            // 设置系统提示图标
            // Set system notification icon
            alert.icon = NSImage(named: NSImage.infoName)
            alert.addButton(withTitle: NSLocalizedString("Auto Rename", comment: "自动重命名"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

            let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled = false
            defer {
                publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
            }
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                ifAutoRenameWhenDifferentSource = true
            } else {
                return
            }
        }

        // 记录操作到日志
        // Record operation to log
        var sourceFiles = items.compactMap { item -> String? in
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { return nil }
            return fileURL.lastPathComponent
        }

        let sourceFilesStr: String
        if sourceFiles.count > 3 {
            sourceFilesStr = sourceFiles[0...2].joined(separator: ", ") + "..."
        } else {
            sourceFilesStr = sourceFiles.joined(separator: ", ")
        }

        let operationLog = "[Move] \(sourceFilesStr) -> \(destinationURL.lastPathComponent)"
        globalVar.operationLogs.append(operationLog)

        // 在文件操作期间抑制文件系统监控触发的刷新，操作完成后主动刷新
        // Suppress FS watcher refreshes during file operations, refresh explicitly after completion
        publicVar.isInFileOperation = true
        // 记录成功粘贴的目标路径，用于刷新后选中
        // Record successfully pasted destination paths for selection after refresh
        var successfulDestURLs: [String] = []
        var indexMovePairs: [(oldPath: String, newPath: String)] = []
        defer {
            publicVar.isInFileOperation = false
            if !successfulDestURLs.isEmpty {
                triggerFinderSound()
                publicVar.filesForLocateAfterChange = successfulDestURLs
                publicVar.filesForLocateAfterChangeTime = .now()
                // 移动完成后清空通用剪贴板，防止再次粘贴时操作已不存在的源文件
                // Clear general pasteboard after move to prevent pasting non-existent source files
                if pasteboard === NSPasteboard.general {
                    pasteboard.clearContents()
                }
                var ifRefresh = true
                if publicVar.isRecursiveMode || isVirtualFolderPath(curFolder) {
                    fileDB.lock()
                    ifRefresh = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
                    fileDB.unlock()
                }
                if ifRefresh {
                    scheduledRefresh()
                }
            }
            if !indexMovePairs.isEmpty {
                EnhancedIndex.handleFilesMoved(indexMovePairs)
            }
        }

        var shouldReplaceAll = false
        var shouldMergeAll = false
        var shouldSkipAll = false
        var shouldAutoRenameAll = false
        let sharedMergeState = MergeConflictState()

        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            let prevSuccessCount = successfulDestURLs.count
            var destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)

            // 如果是在同一目录移动，则不作动作
            // If moving in same directory, do nothing
            var isInSameFolder = fileURL.deletingLastPathComponent() == destinationURL
            if isInSameFolder {
                continue
            }

            if ifAutoRenameWhenDifferentSource {
                destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
            }

            if FileManager.default.fileExists(atPath: destURL.path) {
                // 检测源和目标是否都是文件夹
                // Check if both source and destination are folders
                var srcIsDir: ObjCBool = false
                FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &srcIsDir)
                var dstIsDir: ObjCBool = false
                FileManager.default.fileExists(atPath: destURL.path, isDirectory: &dstIsDir)
                let bothAreFolders = srcIsDir.boolValue && dstIsDir.boolValue

                if shouldReplaceAll {
                    do {
                        try FileManager.default.removeItem(at: destURL)
                        try FileManager.default.moveItem(at: fileURL, to: destURL)
                        successfulDestURLs.append(destURL.absoluteString)
                        publicVar.fileChangedCount += 1
                    } catch {
                        log("Failed to move \(fileURL): \(error)", level: .error)
                    }
                } else if shouldMergeAll && bothAreFolders {
                    if mergeFolderByMove(from: fileURL, to: destURL, state: sharedMergeState) {
                        successfulDestURLs.append(destURL.absoluteString)
                        publicVar.fileChangedCount += 1
                    }
                    if sharedMergeState.cancelled {
                        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                        return
                    }
                } else if shouldSkipAll {
                    continue
                } else if shouldAutoRenameAll {
                    destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                    do {
                        try FileManager.default.moveItem(at: fileURL, to: destURL)
                        successfulDestURLs.append(destURL.absoluteString)
                        publicVar.fileChangedCount += 1
                    } catch {
                        log("Failed to move \(fileURL): \(error)", level: .error)
                    }
                } else {
                    let userChoice = showReplaceDialog(for: destURL, sourceURL: fileURL, isSingle: items.count == 1, isMove: true)
                    switch userChoice {
                    case .replace:
                        do {
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        } catch {
                            log("Failed to move \(fileURL): \(error)", level: .error)
                        }
                    case .replaceAll:
                        shouldReplaceAll = true
                        do {
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        } catch {
                            log("Failed to move \(fileURL): \(error)", level: .error)
                        }
                    case .merge:
                        if mergeFolderByMove(from: fileURL, to: destURL, state: sharedMergeState) {
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        }
                        if sharedMergeState.cancelled {
                            publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                            return
                        }
                    case .mergeAll:
                        shouldMergeAll = true
                        if mergeFolderByMove(from: fileURL, to: destURL, state: sharedMergeState) {
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        }
                        if sharedMergeState.cancelled {
                            publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                            return
                        }
                    case .autoRename:
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        do {
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        } catch {
                            log("Failed to move \(fileURL): \(error)", level: .error)
                        }
                    case .autoRenameAll:
                        shouldAutoRenameAll = true
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        do {
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                            successfulDestURLs.append(destURL.absoluteString)
                            publicVar.fileChangedCount += 1
                        } catch {
                            log("Failed to move \(fileURL): \(error)", level: .error)
                        }
                    case .skip:
                        continue
                    case .skipAll:
                        shouldSkipAll = true
                        continue
                    case .cancel:
                        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                        return
                    }
                }
            } else {
                do {
                    try FileManager.default.moveItem(at: fileURL, to: destURL)
                    successfulDestURLs.append(destURL.absoluteString)
                    publicVar.fileChangedCount += 1
                } catch {
                    log("Failed to move \(fileURL): \(error)", level: .error)
                }
            }
            if successfulDestURLs.count > prevSuccessCount,
               let destStr = successfulDestURLs.last,
               let destPath = URL(string: destStr)?.path {
                indexMovePairs.append((oldPath: fileURL.path, newPath: destPath))
            }
        }
        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
    }

    func handleDelete(fileUrls: [URL] = [], isShowPrompt: Bool = true) -> Bool {
        var urls = fileUrls
        if urls.count == 0 {
            urls = publicVar.selectedUrls()
        }
        guard urls.count != 0 else {return false}

        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()

        let ifHasPermission = requestAppleEventsPermission()
        let isShiftPressed = isShiftKeyPressed()

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete", comment: "删除")
        if isShiftPressed {
            alert.informativeText = NSLocalizedString("ask-to-delete-shift", comment: "你确定要将这些文件永久删除吗？此操作无法撤销。")
        }else if VolumeManager.shared.isExternalVolume(urls.first!) {
            alert.informativeText = NSLocalizedString("ask-to-delete-external", comment: "此目录不支持移动到废纸篓。将立即删除这些项目，此操作无法撤销。")
        }else{
            if ifHasPermission{
                alert.informativeText = NSLocalizedString("ask-to-delete", comment: "你确定要将这些文件移动到废纸篓吗？")
            }else{
                alert.informativeText = NSLocalizedString("ask-to-delete-nopermission", comment: "你确定要将这些文件移动到废纸篓吗？(无权限)")
            }
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "删除"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        // 设置系统警告图标
        // Set system warning icon
        alert.icon = NSImage(named: NSImage.cautionName)

        var response: NSApplication.ModalResponse = .alertFirstButtonReturn
        if isShowPrompt || !ifHasPermission || VolumeManager.shared.isExternalVolume(urls.first!) {
            let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled=false
            response = alert.runModal()
            publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
        }

        // 在文件操作期间抑制文件系统监控触发的刷新，操作完成后主动刷新
        // Suppress FS watcher refreshes during file operations, refresh explicitly after completion
        publicVar.isInFileOperation = true
        defer {
            publicVar.isInFileOperation = false
        }

        if response == .alertFirstButtonReturn {
            // 用户确认删除
            // User confirmed deletion
            let fileManager = FileManager.default
            var urlsToDelete = [URL]()

            for url in urls {
                if fileManager.fileExists(atPath: url.path) {
                    urlsToDelete.append(url)
                } else {
                    log("File does not exist: \(url.path)")
                }
            }

            // 记录操作到日志
            // Record operation to log
            var sourceFiles = urlsToDelete.map { url -> String in
                return url.lastPathComponent
            }

            let sourceFilesStr: String
            if sourceFiles.count > 3 {
                sourceFilesStr = sourceFiles[0...2].joined(separator: ", ") + "..."
            } else {
                sourceFilesStr = sourceFiles.joined(separator: ", ")
            }

            let operationLog = "[Delete] \(sourceFilesStr)"
            globalVar.operationLogs.append(operationLog)

            if !urlsToDelete.isEmpty {
                // 永久删除
                // Permanently delete
                if isShiftPressed {
                    for url in urlsToDelete {
                        try? fileManager.removeItem(at: url)
                    }
                // 删除到回收站
                // Delete to trash
                } else {
                    var appleScriptURLs = ""
                    for url in urlsToDelete {
                        let escapedPath = url.path.replacingOccurrences(of: "\"", with: "\\\"")
                        appleScriptURLs += "\"\(escapedPath)\" as POSIX file, "
                    }

                    // Remove the trailing comma and space
                    if appleScriptURLs.hasSuffix(", ") {
                        appleScriptURLs = String(appleScriptURLs.dropLast(2))
                    }

                    let script = """
                            tell application "Finder"
                                move { \(appleScriptURLs) } to trash
                            end tell
                            """

                    var error: NSDictionary?
                    if let scriptObject = NSAppleScript(source: script) {
                        scriptObject.executeAndReturnError(&error)
                        if let error = error, let errorCode = error[NSAppleScript.errorNumber] as? Int, errorCode == -1743 {
                            // AppleScript 无权限，回退到 NSWorkspace.shared.recycle
                            NSWorkspace.shared.recycle(urlsToDelete, completionHandler: { (newURLs, error) in
                                if let error = error {
                                    log("Failed to delete: \(error)", level: .error)
                                } else {
                                    log("File moved to trash")
                                }
                            })
                        } else if let error = error {
                            log("Failed to delete: \(error)", level: .error)
                        } else {
                            log("File moved to trash")
                        }
                    }
                }

                EnhancedIndex.handleFilesDeleted(urlsToDelete.map { $0.path })

                // 文件更改计数
                // File change count
                publicVar.fileChangedCount += 1

                // 手动刷新
                // Manually refresh
                var ifRefresh = true
                if publicVar.isRecursiveMode || isVirtualFolderPath(curFolder) {
                    fileDB.lock()
                    ifRefresh = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
                    fileDB.unlock()
                }
                if ifRefresh {
                    scheduledRefresh()
                }

            } else {
                log("File to delete does not exist")
            }
            return true
        } else {
            // 用户取消操作
            // User cancelled operation
            log("Delete operation cancelled")
            return false
        }
    }

    enum ReplaceDialogUserChoice {
        case replace
        case replaceAll
        case merge
        case mergeAll
        case skip
        case skipAll
        case autoRename
        case autoRenameAll
        case cancel
    }

    func showReplaceDialog(for url: URL, sourceURL: URL? = nil, isSingle: Bool, isMove: Bool) -> ReplaceDialogUserChoice {
        var srcIsDir: ObjCBool = false
        let sourceIsFolder = sourceURL != nil && FileManager.default.fileExists(atPath: sourceURL!.path, isDirectory: &srcIsDir) && srcIsDir.boolValue
        var dstIsDir: ObjCBool = false
        let destIsFolder = FileManager.default.fileExists(atPath: url.path, isDirectory: &dstIsDir) && dstIsDir.boolValue
        let canMerge = sourceIsFolder && destIsFolder

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("has-exist-in-dest", comment: "目标文件夹中已存在名为xx的文件。"), url.lastPathComponent)
        if isMove {
            alert.informativeText = NSLocalizedString("do-you-want-replace(move)", comment: "你要用正在移动的文件替换它吗？")
        }else{
            alert.informativeText = NSLocalizedString("do-you-want-replace(paste)", comment: "你要用正在粘贴的文件替换它吗？")
        }
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.infoName)

        // Button order: Replace, [Merge if both folders], Auto Rename, [Skip if multiple], Cancel
        alert.addButton(withTitle: NSLocalizedString("Replace", comment: "替换"))
        if canMerge {
            alert.addButton(withTitle: NSLocalizedString("Merge", comment: "合并"))
        }
        alert.addButton(withTitle: NSLocalizedString("Auto Rename", comment: "自动重命名"))
        if !isSingle {
            alert.addButton(withTitle: NSLocalizedString("Skip", comment: "跳过"))
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

        let applyToAllCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Apply to all", comment: "应用到全部"), target: nil, action: nil)
        if !isSingle {
            alert.accessoryView = applyToAllCheckbox
        }

        let response = alert.runModal()
        let applyToAll = applyToAllCheckbox.state == .on

        if canMerge {
            // Buttons: Replace(1000), Merge(1001), AutoRename(1002), Skip?(1003), Cancel(1003 or 1004)
            switch response {
            case .alertFirstButtonReturn:
                return applyToAll ? .replaceAll : .replace
            case .alertSecondButtonReturn:
                return applyToAll ? .mergeAll : .merge
            case .alertThirdButtonReturn:
                return applyToAll ? .autoRenameAll : .autoRename
            case NSApplication.ModalResponse(rawValue: 1003):
                if !isSingle { return applyToAll ? .skipAll : .skip }
                return .cancel
            case NSApplication.ModalResponse(rawValue: 1004):
                return .cancel
            default:
                return .cancel
            }
        } else {
            switch response {
            case .alertFirstButtonReturn:
                return applyToAll ? .replaceAll : .replace
            case .alertSecondButtonReturn:
                return applyToAll ? .autoRenameAll : .autoRename
            case .alertThirdButtonReturn:
                return applyToAll ? .skipAll : .skip
            case NSApplication.ModalResponse(rawValue: 1003):
                return .cancel
            default:
                return .cancel
            }
        }
    }

    /// Tracks user choices across recursive merge operations so "apply to all" persists.
    class MergeConflictState {
        var shouldReplaceAll = false
        var shouldSkipAll = false
        var shouldAutoRenameAll = false
        var cancelled = false
    }

    @discardableResult
    func mergeFolderByCopy(from sourceURL: URL, to destURL: URL, state: MergeConflictState? = nil) -> Bool {
        let fm = FileManager.default
        let state = state ?? MergeConflictState()

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        if !fm.fileExists(atPath: destURL.path) {
            do {
                try fm.copyItem(at: sourceURL, to: destURL)
                return true
            } catch {
                log("Merge copy failed (create dest): \(error)", level: .error)
                return false
            }
        }

        guard let contents = try? fm.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return false
        }

        var allSuccess = true
        for itemURL in contents {
            if state.cancelled { return false }

            var destItemURL = destURL.appendingPathComponent(itemURL.lastPathComponent)

            var srcIsDir: ObjCBool = false
            fm.fileExists(atPath: itemURL.path, isDirectory: &srcIsDir)
            var dstIsDir: ObjCBool = false
            let destExists = fm.fileExists(atPath: destItemURL.path, isDirectory: &dstIsDir)

            if srcIsDir.boolValue && destExists && dstIsDir.boolValue {
                if !mergeFolderByCopy(from: itemURL, to: destItemURL, state: state) {
                    allSuccess = false
                }
            } else if destExists {
                if itemURL.lastPathComponent == ".DS_Store" {
                    do {
                        try fm.removeItem(at: destItemURL)
                        try fm.copyItem(at: itemURL, to: destItemURL)
                    } catch {
                        log("Merge copy failed (.DS_Store): \(error)", level: .error)
                    }
                    continue
                }
                if state.shouldReplaceAll {
                    do {
                        try fm.removeItem(at: destItemURL)
                        try fm.copyItem(at: itemURL, to: destItemURL)
                    } catch {
                        log("Merge copy failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                        allSuccess = false
                    }
                } else if state.shouldSkipAll {
                    continue
                } else if state.shouldAutoRenameAll {
                    destItemURL = getUniqueDestinationURL(for: destItemURL, isInPlace: false)
                    do {
                        try fm.copyItem(at: itemURL, to: destItemURL)
                    } catch {
                        log("Merge copy failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                        allSuccess = false
                    }
                } else {
                    let choice = showReplaceDialog(for: destItemURL, sourceURL: itemURL, isSingle: false, isMove: false)
                    switch choice {
                    case .replace:
                        do {
                            try fm.removeItem(at: destItemURL)
                            try fm.copyItem(at: itemURL, to: destItemURL)
                        } catch {
                            log("Merge copy failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .replaceAll:
                        state.shouldReplaceAll = true
                        do {
                            try fm.removeItem(at: destItemURL)
                            try fm.copyItem(at: itemURL, to: destItemURL)
                        } catch {
                            log("Merge copy failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .merge, .mergeAll:
                        if srcIsDir.boolValue {
                            if !mergeFolderByCopy(from: itemURL, to: destItemURL, state: state) {
                                allSuccess = false
                            }
                        } else {
                            do {
                                try fm.removeItem(at: destItemURL)
                                try fm.copyItem(at: itemURL, to: destItemURL)
                            } catch {
                                log("Merge copy failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                                allSuccess = false
                            }
                        }
                    case .autoRename:
                        destItemURL = getUniqueDestinationURL(for: destItemURL, isInPlace: false)
                        do {
                            try fm.copyItem(at: itemURL, to: destItemURL)
                        } catch {
                            log("Merge copy failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .autoRenameAll:
                        state.shouldAutoRenameAll = true
                        destItemURL = getUniqueDestinationURL(for: destItemURL, isInPlace: false)
                        do {
                            try fm.copyItem(at: itemURL, to: destItemURL)
                        } catch {
                            log("Merge copy failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .skip:
                        continue
                    case .skipAll:
                        state.shouldSkipAll = true
                        continue
                    case .cancel:
                        state.cancelled = true
                        return false
                    }
                }
            } else {
                do {
                    try fm.copyItem(at: itemURL, to: destItemURL)
                } catch {
                    log("Merge copy failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                    allSuccess = false
                }
            }
        }
        return allSuccess
    }

    @discardableResult
    func mergeFolderByMove(from sourceURL: URL, to destURL: URL, state: MergeConflictState? = nil) -> Bool {
        let fm = FileManager.default
        let state = state ?? MergeConflictState()

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        if !fm.fileExists(atPath: destURL.path) {
            do {
                try fm.moveItem(at: sourceURL, to: destURL)
                return true
            } catch {
                log("Merge move failed (create dest): \(error)", level: .error)
                return false
            }
        }

        guard let contents = try? fm.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return false
        }

        var allSuccess = true
        for itemURL in contents {
            if state.cancelled { return false }

            var destItemURL = destURL.appendingPathComponent(itemURL.lastPathComponent)

            var srcIsDir: ObjCBool = false
            fm.fileExists(atPath: itemURL.path, isDirectory: &srcIsDir)
            var dstIsDir: ObjCBool = false
            let destExists = fm.fileExists(atPath: destItemURL.path, isDirectory: &dstIsDir)

            if srcIsDir.boolValue && destExists && dstIsDir.boolValue {
                if !mergeFolderByMove(from: itemURL, to: destItemURL, state: state) {
                    allSuccess = false
                }
            } else if destExists {
                if itemURL.lastPathComponent == ".DS_Store" {
                    do {
                        try fm.removeItem(at: destItemURL)
                        try fm.moveItem(at: itemURL, to: destItemURL)
                    } catch {
                        log("Merge move failed (.DS_Store): \(error)", level: .error)
                    }
                    continue
                }
                if state.shouldReplaceAll {
                    do {
                        try fm.removeItem(at: destItemURL)
                        try fm.moveItem(at: itemURL, to: destItemURL)
                    } catch {
                        log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                        allSuccess = false
                    }
                } else if state.shouldSkipAll {
                    continue
                } else if state.shouldAutoRenameAll {
                    destItemURL = getUniqueDestinationURL(for: destItemURL, isInPlace: false)
                    do {
                        try fm.moveItem(at: itemURL, to: destItemURL)
                    } catch {
                        log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                        allSuccess = false
                    }
                } else {
                    let choice = showReplaceDialog(for: destItemURL, sourceURL: itemURL, isSingle: false, isMove: true)
                    switch choice {
                    case .replace:
                        do {
                            try fm.removeItem(at: destItemURL)
                            try fm.moveItem(at: itemURL, to: destItemURL)
                        } catch {
                            log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .replaceAll:
                        state.shouldReplaceAll = true
                        do {
                            try fm.removeItem(at: destItemURL)
                            try fm.moveItem(at: itemURL, to: destItemURL)
                        } catch {
                            log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .merge, .mergeAll:
                        if srcIsDir.boolValue {
                            if !mergeFolderByMove(from: itemURL, to: destItemURL, state: state) {
                                allSuccess = false
                            }
                        } else {
                            do {
                                try fm.removeItem(at: destItemURL)
                                try fm.moveItem(at: itemURL, to: destItemURL)
                            } catch {
                                log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                                allSuccess = false
                            }
                        }
                    case .autoRename:
                        destItemURL = getUniqueDestinationURL(for: destItemURL, isInPlace: false)
                        do {
                            try fm.moveItem(at: itemURL, to: destItemURL)
                        } catch {
                            log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .autoRenameAll:
                        state.shouldAutoRenameAll = true
                        destItemURL = getUniqueDestinationURL(for: destItemURL, isInPlace: false)
                        do {
                            try fm.moveItem(at: itemURL, to: destItemURL)
                        } catch {
                            log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .skip:
                        continue
                    case .skipAll:
                        state.shouldSkipAll = true
                        continue
                    case .cancel:
                        state.cancelled = true
                        return false
                    }
                }
            } else {
                do {
                    try fm.moveItem(at: itemURL, to: destItemURL)
                } catch {
                    log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                    allSuccess = false
                }
            }
        }

        // Remove source directory if it's now empty or all items were moved
        let remaining = try? fm.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: [])
        if remaining?.isEmpty ?? true {
            try? fm.removeItem(at: sourceURL)
        }

        return allSuccess
    }

    func handleRename(urls: [URL]) -> Bool {
        if urls.isEmpty { return false }

        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()

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
        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
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
        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled

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

                // 第一步：生成最终目标名字列表
                // Step 1: Generate final target name list
                var finalNames: [FileRenameMapping] = []
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
                        if originalUrl.path == newUrl.path {
                            // 名称完全未变，无需操作
                            // Name unchanged, nothing to do
                            return false
                        }
                        // 允许仅大小写变更的重命名（如 A.jpg -> a.jpg），因为在大小写不敏感文件系统上它们指向同一文件
                        // Allow case-only renames (e.g. A.jpg -> a.jpg) since they refer to the same file on case-insensitive filesystems
                        let isCaseOnlyRename = originalUrl.path.lowercased() == newUrl.path.lowercased()
                        if FileManager.default.fileExists(atPath: newUrl.path) && !isCaseOnlyRename {
                            showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                            return false
                        }
                    }

                    let finalUrl = originalUrl.deletingLastPathComponent().appendingPathComponent(newName)
                    finalNames.append(FileRenameMapping(from: originalUrl, to: finalUrl))
                }

                let actionName = urls.count > 1 ? NSLocalizedString("批量重命名", comment: "batch rename undo") : NSLocalizedString("重命名", comment: "rename undo")
                let renameResult = executeFileRenameMappings(finalNames, actionName: actionName)
                if renameResult {
                    for item in finalNames {
                        log("File renamed to \(item.to.lastPathComponent)")
                    }
                }
                return renameResult
            }
        }
        return false
    }

    func handleQuickRenameInCurrentFolder() -> Bool {
        fileDB.lock()
        let curFolder = fileDB.curFolder
        let keys: [(SortKeyFile, FileModel)]
        if let dirModel = fileDB.db[SortKeyDir(curFolder)] {
            keys = getMapKeysFile(dirModel.files)
        } else {
            keys = []
        }
        fileDB.unlock()

        let urls: [URL] = keys.compactMap { (_, file) in
            guard !file.isDir else { return nil }
            return URL(string: file.path)
        }

        if urls.isEmpty {
            showAlert(message: NSLocalizedString("No files to rename in current folder.", comment: "当前目录没有可重命名的文件。"))
            return false
        }

        let folderName: String = {
            guard let folderURL = URL(string: curFolder) else { return "Folder" }
            let name = folderURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Folder" : (name.removingPercentEncoding ?? name)
        }()

        let rule = {
            let trimmed = globalVar.quickRenameRule.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "{folder}_{index}" : trimmed
        }()

        let originalPathSet = Set(urls.map { $0.path.lowercased() })
        var plannedPathSet = Set<String>()
        var finalNames: [(originalUrl: URL, finalUrl: URL)] = []

        for (idx, originalUrl) in urls.enumerated() {
            let index = idx + 1
            var baseName = rule
                .replacingOccurrences(of: "{folder}", with: folderName)
                .replacingOccurrences(of: "{index}", with: "\(index)")

            baseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
            if baseName.isEmpty {
                baseName = "\(folderName)_\(index)"
            }

            let ext = originalUrl.pathExtension
            var suffix = 1
            var finalUrl = originalUrl

            while true {
                let candidateBase = (suffix == 1) ? baseName : "\(baseName)_\(suffix)"
                let candidateName = ext.isEmpty ? candidateBase : "\(candidateBase).\(ext)"
                let candidateURL = originalUrl.deletingLastPathComponent().appendingPathComponent(candidateName)
                let candidatePathLower = candidateURL.path.lowercased()

                let existsAndNotInOriginalSet =
                    FileManager.default.fileExists(atPath: candidateURL.path) &&
                    !originalPathSet.contains(candidatePathLower)
                let isPlannedConflict = plannedPathSet.contains(candidatePathLower)

                if !existsAndNotInOriginalSet && !isPlannedConflict {
                    finalUrl = candidateURL
                    plannedPathSet.insert(candidatePathLower)
                    break
                }
                suffix += 1
            }

            finalNames.append((originalUrl: originalUrl, finalUrl: finalUrl))
        }

        let operationLog = "[QuickRename] \(folderName) -> \(rule)"
        globalVar.operationLogs.append(operationLog)

        let mappings = finalNames.map { FileRenameMapping(from: $0.originalUrl, to: $0.finalUrl) }
        return executeFileRenameMappings(
            mappings,
            actionName: NSLocalizedString("快速重命名", comment: "quick rename undo")
        )
    }

    func applyCutItemsDimEffect() {
        for window in NSApp.windows {
            guard let vc = window.contentViewController as? ViewController else { continue }
            for item in vc.collectionView.visibleItems() {
                if let item = item as? CustomCollectionViewItem {
                    item.updateCutDimEffect()
                }
            }
            updateOutlineViewCutDimEffect(vc.outlineView)
        }
    }

    func clearCutItemsDimEffect() {
        let hadCutItems = !globalVar.cutItemPaths.isEmpty
        globalVar.cutItemPaths.removeAll()
        if hadCutItems {
            for window in NSApp.windows {
                guard let vc = window.contentViewController as? ViewController else { continue }
                for item in vc.collectionView.visibleItems() {
                    if let item = item as? CustomCollectionViewItem {
                        item.updateCutDimEffect()
                    }
                }
                updateOutlineViewCutDimEffect(vc.outlineView)
            }
        }
    }

    private func updateOutlineViewCutDimEffect(_ outlineView: CustomOutlineView) {
        let visibleRange = outlineView.rows(in: outlineView.visibleRect)
        for row in visibleRange.location..<(visibleRange.location + visibleRange.length) {
            guard let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) else { continue }
            if let treeNode = outlineView.item(atRow: row) as? TreeNode {
                let isCut = globalVar.cutItemPaths.contains(treeNode.fullPath)
                for col in 0..<outlineView.numberOfColumns {
                    if let cellView = rowView.view(atColumn: col) as? NSView {
                        cellView.alphaValue = isCut ? 0.4 : 1.0
                    }
                }
            }
        }
    }
}
