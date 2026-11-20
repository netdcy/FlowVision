//
//  FileOperation.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration
import ImageIO
import BTree

// Kept independent of AppKit so retry and recovery can be fault-injected.
enum RenameIO {
    static func errorChain(_ error: Error) -> String {
        var current: NSError? = error as NSError
        var parts: [String] = []
        for _ in 0..<8 {
            guard let value = current else { break }
            parts.append("\(value.domain):\(value.code)")
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " → ")
    }

    static func move(from: URL, to: URL, retryBusy: Bool,
                     operation: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
                     wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) throws {
        for attempt in 0..<3 {
            do {
                try operation(from, to)
                return
            } catch {
                var underlying = error as NSError
                for _ in 0..<8 {
                    guard let next = underlying.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
                    underlying = next
                }
                // Do not retry permission denial or uncertain network outcomes
                // (timeout/disconnect): the server may already have moved it.
                let busy = underlying.domain == NSPOSIXErrorDomain
                    && [Int(EBUSY), Int(EAGAIN)].contains(underlying.code)
                guard retryBusy, busy, attempt < 2 else {
                    throw NSError(domain: "FlowVision.Rename", code: underlying.code, userInfo: [
                        NSLocalizedDescriptionKey: "\(error.localizedDescription)\n\(from.path) → \(to.path)\n[\(errorChain(error))]",
                        NSUnderlyingErrorKey: error
                    ])
                }
                wait(0.15 * Double(attempt + 1))
            }
        }
    }

    // Restore completed targets to their staging slots first. Moving directly
    // to the original names can collide in swaps and longer rename cycles.
    static func rollback(_ pending: [(source: URL, temp: URL, target: URL)], completed: Int,
                         move: (URL, URL) throws -> Void) -> [String] {
        var failures: [String] = []
        var staged = Set(completed..<pending.count)
        for index in (0..<completed).reversed() {
            let item = pending[index]
            do { try move(item.target, item.temp); staged.insert(index) }
            catch { failures.append("\(item.target.path): \(error.localizedDescription)") }
        }
        for index in staged.sorted().reversed() {
            let item = pending[index]
            do { try move(item.temp, item.source) }
            catch { failures.append("\(item.temp.path): \(error.localizedDescription)") }
        }
        return failures
    }
}

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

private final class BatchRenamePreviewDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let rows: [(original: String, renamed: String)]

    init(mappings: [(original: String, renamed: String)]) {
        self.rows = mappings
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn = tableColumn else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("BatchRenamePreviewCell-\(tableColumn.identifier.rawValue)")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = identifier

        if cell.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.textField = textField
        }

        cell.textField?.stringValue = tableColumn.identifier.rawValue == "original" ? rows[row].original : rows[row].renamed
        return cell
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
        let sourceURL: URL
        let tempURL: URL
        let targetURL: URL
    }

    struct VideoCropRect: Equatable {
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
            presentVideoEditor(initialMode: .crop)
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

    func handleLosslessTrimCurrentVideo() {
        presentVideoEditor(initialMode: .trim)
    }

    private func presentVideoEditor(initialMode: VideoTrimEditorMode) {
        guard publicVar.isInLargeView,
              largeImageView.file.type == .video,
              let videoURL = URL(string: largeImageView.file.path),
              isEditableVideoURL(videoURL) else {
            showAlert(message: NSLocalizedString("Please open a video first.", comment: "请先打开一个视频。"))
            return
        }
        if let activeVideoTrimEditor {
            activeVideoTrimEditor.present()
            return
        }
        guard !publicVar.isInFileOperation else { return }

        let duration = largeImageView.videoDurationSeconds
        guard duration.isFinite, duration > 0 else {
            showAlert(message: NSLocalizedString("The video duration is not available yet.", comment: "暂时无法读取视频时长。"))
            return
        }

        // A trim editor should start non-destructively: until the user moves a
        // handle, the selected range is the complete source video.
        let suggestedRange = VideoTrimSegment(start: 0, end: duration)

        // Release the main viewer's mpv render context before creating the
        // editor preview. Keeping both contexts attached to the same window
        // can leave the second one permanently black on some GPUs.
        largeImageView.stopVideo(savePosition: true)
        let editor = VideoTrimEditorWindowController(
            sourceURL: videoURL,
            duration: duration,
            sourceSize: largeImageView.file.originalSize,
            initialSegment: suggestedRange,
            initialMode: initialMode,
            onClose: { [weak self] in
                guard let self else { return }
                self.activeVideoTrimEditor = nil
                guard !self.willTerminate,
                      URL(string: self.largeImageView.file.path) == videoURL else { return }
                self.largeImageView.playVideo(reload: true)
            }
        ) { [weak self] segments, cropRect in
            self?.exportVideoSegments(
                sourceURL: videoURL,
                segments: segments,
                cropRect: cropRect
            )
        }
        activeVideoTrimEditor = editor
        editor.present()
    }

    private func exportVideoSegments(
        sourceURL videoURL: URL,
        segments: [VideoTrimSegment],
        cropRect: VideoCropRect?
    ) {
        guard !segments.isEmpty, !publicVar.isInFileOperation else { return }

        publicVar.isInFileOperation = true
        let initialProgress: String
        if cropRect == nil {
            initialProgress = String(
                format: NSLocalizedString("Exporting lossless clips 0/%d", comment: "正在导出无损片段 0/%d"),
                segments.count
            )
        } else {
            initialProgress = String(
                format: NSLocalizedString("Exporting cropped clips 0/%d", comment: "正在导出裁剪片段 0/%d"),
                segments.count
            )
        }
        coreAreaView.showOperationProgress(initialProgress, progress: 0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var outputURLs: [URL] = []
            var failedIndices: [Int] = []

            for (index, segment) in segments.enumerated() {
                let outputURL: URL
                let succeeded: Bool
                if let cropRect {
                    outputURL = self.makeCroppedVideoOutputURL(
                        sourceURL: videoURL,
                        segment: segment,
                        index: index
                    )
                    succeeded = self.exportCroppedVideoSegment(
                        sourceURL: videoURL,
                        outputURL: outputURL,
                        segment: segment,
                        cropRect: cropRect
                    )
                } else {
                    outputURL = self.makeLosslessTrimOutputURL(
                        sourceURL: videoURL,
                        segment: segment,
                        index: index
                    )
                    succeeded = self.exportLosslessVideoSegment(
                        sourceURL: videoURL,
                        outputURL: outputURL,
                        segment: segment
                    )
                }
                if succeeded {
                    outputURLs.append(outputURL)
                } else {
                    failedIndices.append(index + 1)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let finished = index + 1
                    let message: String
                    if cropRect == nil {
                        message = String(
                            format: NSLocalizedString("Exporting lossless clips %d/%d", comment: "正在导出无损片段 %d/%d"),
                            finished,
                            segments.count
                        )
                    } else {
                        message = String(
                            format: NSLocalizedString("Exporting cropped clips %d/%d", comment: "正在导出裁剪片段 %d/%d"),
                            finished,
                            segments.count
                        )
                    }
                    self.coreAreaView.showOperationProgress(
                        message,
                        progress: Double(finished) / Double(segments.count)
                    )
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.publicVar.isInFileOperation = false
                self.publicVar.fileChangedCount += outputURLs.count

                if !outputURLs.isEmpty {
                    // Keep the source video open. The exported clips are new
                    // siblings and must not interrupt current playback.
                    self.publicVar.openFromFinderPath = videoURL.absoluteString
                    self.scheduledRefresh()
                }

                if failedIndices.isEmpty {
                    let completionMessage: String
                    let infoMessage: String
                    if cropRect == nil {
                        completionMessage = String(
                            format: NSLocalizedString("Exported %d lossless clips", comment: "已导出 %d 个无损片段"),
                            outputURLs.count
                        )
                        infoMessage = String(
                            format: NSLocalizedString("Exported %d clips", comment: "已导出 %d 个片段"),
                            outputURLs.count
                        )
                    } else {
                        completionMessage = String(
                            format: NSLocalizedString("Exported %d cropped clips", comment: "已导出 %d 个裁剪片段"),
                            outputURLs.count
                        )
                        infoMessage = completionMessage
                    }
                    self.coreAreaView.showOperationProgress(
                        completionMessage,
                        progress: 1
                    )
                    self.coreAreaView.hideOperationOverlay(delayed: 1.0)
                    self.largeImageView.showInfo(infoMessage)
                } else {
                    self.coreAreaView.hideOperationOverlay(delayed: 0.2)
                    let failedText = failedIndices.map(String.init).joined(separator: ", ")
                    let failureMessage: String
                    if cropRect == nil {
                        failureMessage = String(
                            format: NSLocalizedString("Some clips failed to export (segments: %@).", comment: "部分片段导出失败（片段：%@）。"),
                            failedText
                        )
                    } else {
                        failureMessage = String(
                            format: NSLocalizedString("Some cropped clips failed to export (segments: %@).", comment: "部分裁剪片段导出失败（片段：%@）。"),
                            failedText
                        )
                    }
                    showAlert(
                        message: failureMessage
                    )
                }
            }
        }
    }

    private func makeLosslessTrimOutputURL(
        sourceURL: URL,
        segment: VideoTrimSegment,
        index: Int
    ) -> URL {
        let startMilliseconds = Int64((segment.start * 1000).rounded())
        let endMilliseconds = Int64((segment.end * 1000).rounded())
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let clipName = String(
            format: "%@_clip_%02d_%09lld-%09lld",
            baseName,
            index + 1,
            startMilliseconds,
            endMilliseconds
        )
        let candidate = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(clipName)
            .appendingPathExtension(sourceURL.pathExtension)
        return getUniqueDestinationURL(for: candidate)
    }

    private func makeCroppedVideoOutputURL(
        sourceURL: URL,
        segment: VideoTrimSegment,
        index: Int
    ) -> URL {
        let startMilliseconds = Int64((segment.start * 1000).rounded())
        let endMilliseconds = Int64((segment.end * 1000).rounded())
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let fileName = String(
            format: "%@_crop_%02d_%09lld-%09lld",
            baseName,
            index + 1,
            startMilliseconds,
            endMilliseconds
        )
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let outputExtension = ["mp4", "mov", "m4v"].contains(sourceExtension) ? "mp4" : "mkv"
        let candidate = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(fileName)
            .appendingPathExtension(outputExtension)
        return getUniqueDestinationURL(for: candidate)
    }

    private func exportLosslessVideoSegment(
        sourceURL: URL,
        outputURL: URL,
        segment: VideoTrimSegment
    ) -> Bool {
        guard FFmpegKitWrapper.shared.getIfLoaded() else { return false }
        let tempURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".flowvision_trim_\(UUID().uuidString)")
            .appendingPathExtension(sourceURL.pathExtension)
        let posixLocale = Locale(identifier: "en_US_POSIX")
        let start = String(format: "%.3f", locale: posixLocale, segment.start)
        let duration = String(format: "%.3f", locale: posixLocale, segment.duration)
        let args = [
            // The temporary sibling has a UUID name, so overwrite is safe and
            // avoids FFmpegKit's conflicting no-overwrite state.
            "-y",
            "-ss", start,
            "-i", sourceURL.path,
            "-t", duration,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map_metadata", "0",
            "-c", "copy",
            // Stream copy preserves every packet and the input frame cadence.
            // copytb makes that intent explicit for variable-frame-rate input.
            "-copytb", "1",
            "-avoid_negative_ts", "make_zero",
            tempURL.path
        ]

        guard let session = FFmpegKitWrapper.shared.executeFFmpegCommand(args),
              FFmpegKitWrapper.shared.isSuccess(FFmpegKitWrapper.shared.getReturnCode(from: session)) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
        do {
            try FileManager.default.moveItem(at: tempURL, to: outputURL)
            return true
        } catch {
            log("Failed to finalize lossless trim output: \(error)", level: .error)
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }

    private func exportCroppedVideoSegment(
        sourceURL: URL,
        outputURL: URL,
        segment: VideoTrimSegment,
        cropRect: VideoCropRect
    ) -> Bool {
        guard FFmpegKitWrapper.shared.getIfLoaded() else { return false }
        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".flowvision_crop_\(UUID().uuidString)")
            .appendingPathExtension(outputURL.pathExtension)
        let posix = Locale(identifier: "en_US_POSIX")
        let start = String(format: "%.3f", locale: posix, segment.start)
        let clipDuration = String(format: "%.3f", locale: posix, segment.duration)
        let filter = "crop=\(cropRect.width):\(cropRect.height):\(cropRect.x):\(cropRect.y),setsar=1"
        var args = [
            "-y",
            "-ss", start,
            "-i", sourceURL.path,
            "-t", clipDuration,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map_metadata", "0",
            "-vf", filter,
            // Preserve source timestamps and cadence. In particular, do not
            // synthesize a fixed `-r` for variable-frame-rate phone videos.
            "-fps_mode", "passthrough",
            "-c:v", "h264_videotoolbox",
            "-allow_sw", "1",
            "-b:v", "0",
            "-q:v", "65",
            "-pix_fmt", "yuv420p",
            "-c:a", "copy",
            "-avoid_negative_ts", "make_zero"
        ]
        if outputURL.pathExtension.lowercased() == "mp4" {
            args += ["-movflags", "+faststart"]
        }
        args.append(tempURL.path)

        guard let session = FFmpegKitWrapper.shared.executeFFmpegCommand(args),
              FFmpegKitWrapper.shared.isSuccess(FFmpegKitWrapper.shared.getReturnCode(from: session)) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        do {
            try FileManager.default.moveItem(at: tempURL, to: outputURL)
            return true
        } catch {
            log("Failed to finalize cropped video output: \(error)", level: .error)
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
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

    private func remappedURLAfterRename(
        _ url: URL,
        mappings: [FileRenameMapping]
    ) -> URL? {
        let oldPath = url.standardizedFileURL.path
        guard let mapping = mappings
            .sorted(by: { $0.from.standardizedFileURL.path.count > $1.from.standardizedFileURL.path.count })
            .first(where: { mapping in
                let sourcePath = mapping.from.standardizedFileURL.path
                return oldPath.lowercased() == sourcePath.lowercased() ||
                    oldPath.lowercased().hasPrefix(sourcePath.lowercased() + "/")
            }) else {
            return nil
        }

        let sourcePath = mapping.from.standardizedFileURL.path
        let relativeSuffix = String(oldPath.dropFirst(sourcePath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativeSuffix.isEmpty else { return mapping.to }
        return URL(fileURLWithPath: mapping.to.standardizedFileURL.path, isDirectory: true)
            .appendingPathComponent(relativeSuffix, isDirectory: url.hasDirectoryPath)
    }

    private func preserveCollectionScrollPosition(for folderPath: String) {
        guard let clipView = collectionView.enclosingScrollView?.contentView else { return }
        publicVar.collectionScrollRestoreAfterRefresh = (folderPath, clipView.bounds.origin)
    }

    private func preserveViewportAnchorForMove(_ sourceURLs: [URL], folderPath: String) {
        publicVar.collectionViewportAnchorAfterRefresh = nil
        guard let scrollView = collectionView.enclosingScrollView else { return }

        let sourcePaths = Set(sourceURLs.map { $0.standardizedFileURL.path.lowercased() })
        let selectedIndexes = collectionView.selectionIndexPaths.map(\.item).sorted()
        guard !selectedIndexes.isEmpty else { return }
        let displayedItemCount = collectionView.numberOfItems(inSection: 0)

        fileDB.lock()
        guard fileDB.curFolder == folderPath,
              let files = fileDB.db[SortKeyDir(folderPath)]?.files else {
            fileDB.unlock()
            return
        }
        let loadedItemCount = min(files.count, displayedItemCount)
        let removedIndexes = selectedIndexes.compactMap { index -> Int? in
            guard index < loadedItemCount,
                  let path = files.elementSafe(atOffset: index)?.1.path,
                  let url = URL(string: path),
                  sourcePaths.contains(url.standardizedFileURL.path.lowercased()) else { return nil }
            return index
        }.sorted()
        guard let firstRemoved = removedIndexes.first,
              let lastRemoved = removedIndexes.last else {
            fileDB.unlock()
            return
        }

        let removedSet = Set(removedIndexes)
        let successor = ((lastRemoved + 1)..<loadedItemCount).first { !removedSet.contains($0) }
        let predecessor = stride(from: firstRemoved - 1, through: 0, by: -1).first { !removedSet.contains($0) }
        guard let anchorIndex = successor ?? predecessor,
              let anchorPath = files.elementSafe(atOffset: anchorIndex)?.1.path else {
            fileDB.unlock()
            return
        }
        fileDB.unlock()

        collectionView.layoutSubtreeIfNeeded()
        let mouseIndex: Int? = view.window.flatMap { window in
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let collectionPoint = collectionView.convert(windowPoint, from: nil)
            return collectionView.indexPathForItem(at: collectionPoint)?.item
        }
        let referenceIndex = mouseIndex.map { removedIndexes.contains($0) ? $0 : firstRemoved } ?? firstRemoved
        guard referenceIndex < loadedItemCount,
              let referenceFrame = collectionView.layoutAttributesForItem(
                at: IndexPath(item: referenceIndex, section: 0)
              )?.frame else { return }

        let clipOrigin = scrollView.contentView.bounds.origin
        publicVar.collectionViewportAnchorAfterRefresh = (
            folderPath: folderPath,
            filePath: anchorPath,
            offset: NSPoint(x: referenceFrame.minX - clipOrigin.x, y: referenceFrame.minY - clipOrigin.y)
        )
    }

    private func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path.lowercased()
        let ancestorPath = ancestor.standardizedFileURL.path.lowercased()
        let ancestorPrefix = ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/"
        return candidatePath == ancestorPath || candidatePath.hasPrefix(ancestorPrefix)
    }

    private func normalizedFilePathKey(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }

    private func hasOverlappingSourcePaths(_ urls: [URL]) -> Bool {
        let paths = urls.map { $0.standardizedFileURL.path.lowercased() }
        for (index, path) in paths.enumerated() {
            for otherPath in paths[(index + 1)...] {
                let pathPrefix = path.hasSuffix("/") ? path : path + "/"
                let otherPrefix = otherPath.hasSuffix("/") ? otherPath : otherPath + "/"
                if path == otherPath ||
                    path.hasPrefix(otherPrefix) ||
                    otherPath.hasPrefix(pathPrefix) {
                    return true
                }
            }
        }
        return false
    }

    private func renameValidationFailure(_ mappings: [FileRenameMapping]) -> String? {
        let fileManager = FileManager.default
        var sourcePathKeys = Set<String>()
        var targetPathKeys = Set<String>()

        for mapping in mappings {
            let sourceKey = normalizedFilePathKey(mapping.from)
            let targetKey = normalizedFilePathKey(mapping.to)
            guard sourcePathKeys.insert(sourceKey).inserted else {
                return String(format: NSLocalizedString("Duplicate rename source: %@", comment: "重复的重命名来源：%@"), mapping.from.lastPathComponent)
            }
            guard targetPathKeys.insert(targetKey).inserted else {
                return String(format: NSLocalizedString("Duplicate target name: %@", comment: "目标名称重复：%@"), mapping.to.lastPathComponent)
            }
        }

        if hasOverlappingSourcePaths(mappings.map(\.from)) {
            return NSLocalizedString("A folder and one of its descendants cannot be renamed together.", comment: "不能同时重命名文件夹及其子项目。")
        }

        for mapping in mappings {
            guard fileManager.fileExists(atPath: mapping.from.path) else {
                return String(format: NSLocalizedString("Rename source missing: %@", comment: "重命名源文件不存在：%@"), mapping.from.lastPathComponent)
            }
            guard mapping.from.path != mapping.to.path else { continue }
            let targetKey = normalizedFilePathKey(mapping.to)
            if fileManager.fileExists(atPath: mapping.to.path),
               !sourcePathKeys.contains(targetKey) {
                return String(format: NSLocalizedString("A file or folder already exists: %@", comment: "文件或文件夹已存在：%@"), mapping.to.lastPathComponent)
            }
        }
        return nil
    }

    /// Replaces a move destination without deleting it until the source has
    /// reached the final path. If the source move fails, the old destination is
    /// restored from a sibling temporary path.
    private func moveItemSafelyReplacingDestination(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let backupURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".flowvision_replace_backup_\(UUID().uuidString)")

        try fileManager.moveItem(at: destinationURL, to: backupURL)
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            var restoreError: Error?
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: backupURL, to: destinationURL)
            } catch {
                restoreError = error
            }
            if let restoreError {
                throw NSError(
                    domain: "netdcy.FlowVision.SafeMoveReplace",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(error.localizedDescription); failed to restore destination: \(restoreError.localizedDescription)"
                    ]
                )
            }
            throw error
        }

        do {
            try fileManager.removeItem(at: backupURL)
        } catch {
            log("Moved item but failed to remove replacement backup at \(backupURL.path): \(error)", level: .error)
        }
    }

    @discardableResult
    private func performTrackedMove(
        from sourceURL: URL,
        to destinationURL: URL,
        replacingDestination: Bool,
        successfulDestURLs: inout [String],
        movePairs: inout [(oldPath: String, newPath: String)],
        failedCount: inout Int
    ) -> Bool {
        do {
            if replacingDestination {
                try moveItemSafelyReplacingDestination(from: sourceURL, to: destinationURL)
            } else {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            }
            successfulDestURLs.append(destinationURL.absoluteString)
            movePairs.append((oldPath: sourceURL.path, newPath: destinationURL.path))
            publicVar.fileChangedCount += 1
            return true
        } catch {
            failedCount += 1
            log("Failed to move \(sourceURL.path) to \(destinationURL.path): \(error)", level: .error)
            return false
        }
    }

    private func finishMoveOperation(
        successfulDestURLs: [String],
        movePairs: [(oldPath: String, newPath: String)],
        failedCount: Int,
        destinationURL: URL,
        originalFolderPath: String,
        pasteboard: NSPasteboard,
        pasteboardChangeCount: Int
    ) {
        guard !successfulDestURLs.isEmpty else {
            publicVar.collectionViewportAnchorAfterRefresh = nil
            if failedCount > 0 {
                coreAreaView.showOperationToast(
                    String(format: NSLocalizedString("Move failed for %d item(s)", comment: "有 %d 个项目移动失败"), failedCount),
                    autoHide: 2.0
                )
                scheduledRefresh()
            }
            return
        }

        triggerFinderSound()
        let completedMappings = movePairs.compactMap { pair -> FileRenameMapping? in
            guard !FileManager.default.fileExists(atPath: pair.oldPath) else { return nil }
            return FileRenameMapping(
                from: URL(fileURLWithPath: pair.oldPath),
                to: URL(fileURLWithPath: pair.newPath)
            )
        }
        let didMoveCurrentFolder = updateCurrentFolderPathAfterRename(completedMappings)
        updateVideoPlaybackPathsAfterRename(completedMappings)

        fileDB.lock()
        let currentFolderPath = fileDB.curFolder
        fileDB.unlock()
        let currentFolderURL = URL(string: currentFolderPath)?.standardizedFileURL
        let standardizedDestination = destinationURL.standardizedFileURL
        let movedItemsAreVisible = currentFolderURL.map { currentURL in
            standardizedDestination.path == currentURL.path ||
                ((publicVar.isRecursiveMode || publicVar.isMediaUnit(currentFolderPath)) &&
                 isSameOrDescendant(standardizedDestination, of: currentURL))
        } ?? false
        let destinationFolderIsVisible = currentFolderURL.map { currentURL in
            standardizedDestination.deletingLastPathComponent().path == currentURL.path
        } ?? false

        if didMoveCurrentFolder {
            publicVar.filesForLocateAfterChange.removeAll()
            publicVar.collectionViewportAnchorAfterRefresh = nil
        } else if movedItemsAreVisible {
            publicVar.filesForLocateAfterChange = successfulDestURLs
            publicVar.filesForLocateAfterChangeTime = .now()
            publicVar.collectionViewportAnchorAfterRefresh = nil
        } else if currentFolderPath == originalFolderPath {
            publicVar.filesForLocateAfterChange.removeAll()
            preserveCollectionScrollPosition(for: originalFolderPath)
        } else {
            // The user navigated elsewhere while the background move was
            // running. Do not apply the old folder's selection or scroll state.
            publicVar.filesForLocateAfterChange.removeAll()
            publicVar.collectionViewportAnchorAfterRefresh = nil
        }

        // A wrapper such as "Move to Downloads" may already have restored the
        // user's clipboard while an asynchronous move was running.
        if pasteboard === NSPasteboard.general,
           pasteboard.changeCount == pasteboardChangeCount {
            pasteboard.clearContents()
        }

        var shouldRefresh = didMoveCurrentFolder ||
            currentFolderPath == originalFolderPath ||
            movedItemsAreVisible ||
            destinationFolderIsVisible
        if shouldRefresh,
           !didMoveCurrentFolder,
           (publicVar.isRecursiveMode || isVirtualFolderPath(currentFolderPath)) {
            fileDB.lock()
            shouldRefresh = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
            fileDB.unlock()
        }
        if shouldRefresh {
            scheduledRefresh()
        }

        if failedCount > 0 {
            coreAreaView.showOperationToast(
                String(format: NSLocalizedString("Moved %d item(s), %d failed", comment: "已移动 %d 个项目，%d 个失败"), successfulDestURLs.count, failedCount),
                autoHide: 2.0
            )
        }
    }

    private func executeUnconflictedMovesAsync(
        _ plans: [(source: URL, destination: URL)],
        destinationURL: URL,
        originalFolderPath: String,
        pasteboard: NSPasteboard,
        checkConflictsBeforeMoving: Bool = false
    ) {
        let pasteboardChangeCount = pasteboard.changeCount
        publicVar.isInFileOperation = true
        coreAreaView.showOperationIndeterminate(
            String(format: NSLocalizedString("Moving %d item(s)…", comment: "正在移动 %d 个项目…"), plans.count)
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if checkConflictsBeforeMoving {
                let existingTargetPaths = Set(plans.compactMap { plan -> String? in
                    FileManager.default.fileExists(atPath: plan.destination.path)
                        ? plan.destination.standardizedFileURL.path.lowercased()
                        : nil
                })
                if !existingTargetPaths.isEmpty {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.publicVar.isInFileOperation = false
                        self.coreAreaView.hideOperationOverlay(delayed: 0)

                        let snapshotPasteboard = NSPasteboard(
                            name: NSPasteboard.Name("FlowVision.Move.\(UUID().uuidString)")
                        )
                        snapshotPasteboard.clearContents()
                        snapshotPasteboard.writeObjects(plans.map(\.source) as [NSPasteboardWriting])
                        self.handleMove(
                            targetURL: destinationURL,
                            pasteboard: snapshotPasteboard,
                            allowBackgroundPreflight: false,
                            knownExistingTargetPaths: existingTargetPaths
                        )
                    }
                    return
                }
            }

            var successfulURLs: [String] = []
            var movePairs: [(oldPath: String, newPath: String)] = []
            var failedCount = 0

            for plan in plans {
                do {
                    try FileManager.default.moveItem(at: plan.source, to: plan.destination)
                    successfulURLs.append(plan.destination.absoluteString)
                    movePairs.append((oldPath: plan.source.path, newPath: plan.destination.path))
                } catch {
                    failedCount += 1
                    log("Failed to move \(plan.source): \(error)", level: .error)
                }
            }
            if !movePairs.isEmpty {
                EnhancedIndex.handleFilesMoved(movePairs)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.publicVar.isInFileOperation = false }
                self.publicVar.fileChangedCount += successfulURLs.count
                self.finishMoveOperation(
                    successfulDestURLs: successfulURLs,
                    movePairs: movePairs,
                    failedCount: failedCount,
                    destinationURL: destinationURL,
                    originalFolderPath: originalFolderPath,
                    pasteboard: pasteboard,
                    pasteboardChangeCount: pasteboardChangeCount
                )
                if failedCount == 0 {
                    self.coreAreaView.showOperationProgress(
                        NSLocalizedString("Move complete", comment: "移动完成"),
                        progress: 1.0
                    )
                }
                self.coreAreaView.hideOperationOverlay(delayed: 0.8)
            }
        }
    }

    /// Keeps active video players associated with the renamed file so a fallback
    /// collection refresh does not reload playback from the beginning.
    private func updateVideoPlaybackPathsAfterRename(_ mappings: [FileRenameMapping]) {
        for case let item as CustomCollectionViewItem in collectionView.visibleItems() {
            guard let playingURL = item.currentPlayingURL,
                  let newURL = remappedURLAfterRename(playingURL, mappings: mappings) else { continue }
            item.currentPlayingURL = newURL
        }

        var didUpdateLargeImagePath = false
        if let fileURL = URL(string: largeImageView.file.path),
           let newURL = remappedURLAfterRename(fileURL, mappings: mappings) {
            largeImageView.file.path = newURL.absoluteString
            largeImageView.file.ext = newURL.pathExtension.lowercased()
            didUpdateLargeImagePath = true
        }
        if let playingURL = largeImageView.currentPlayingURL,
           let newURL = remappedURLAfterRename(playingURL, mappings: mappings) {
            largeImageView.currentPlayingURL = newURL
        }
        if let restoreURL = largeImageView.restorePlayURL,
           let newURL = remappedURLAfterRename(restoreURL, mappings: mappings) {
            largeImageView.restorePlayURL = newURL
        }
        if let finderURL = URL(string: publicVar.openFromFinderPath),
           let newURL = remappedURLAfterRename(finderURL, mappings: mappings) {
            publicVar.openFromFinderPath = newURL.absoluteString
        }
        if didUpdateLargeImagePath {
            setWindowTitleOfLargeImage(file: largeImageView.file)
        }
    }

    /// Keeps the active browser pointed at the same directory when that directory,
    /// or one of its ancestors, is renamed.
    private func updateCurrentFolderPathAfterRename(_ mappings: [FileRenameMapping]) -> Bool {
        fileDB.lock()
        let oldFolderPath = fileDB.curFolder
        fileDB.unlock()

        guard let oldFolderURL = URL(string: oldFolderPath), oldFolderURL.isFileURL else {
            return false
        }

        // Keep the persisted media hierarchy attached to the renamed folder,
        // including when the active view is outside that hierarchy.
        if publicVar.isMediaUnitMode,
           let mediaRootPath = publicVar.mediaUnitRootPath,
           let mediaRootURL = URL(string: mediaRootPath),
           let remappedRootURL = remappedURLAfterRename(mediaRootURL, mappings: mappings) {
            publicVar.mediaUnitRootPath = remappedRootURL.absoluteString
            UserDefaults.standard.set(remappedRootURL.absoluteString, forKey: "mediaUnitRootPath")
        }
        if let pendingPath = publicVar.mediaUnitPendingPath,
           let pendingURL = URL(string: pendingPath),
           let remappedPendingURL = remappedURLAfterRename(pendingURL, mappings: mappings) {
            publicVar.mediaUnitPendingPath = remappedPendingURL.absoluteString
        }

        let oldPath = oldFolderURL.standardizedFileURL.path
        let matchingMapping = mappings
            .sorted { $0.from.standardizedFileURL.path.count > $1.from.standardizedFileURL.path.count }
            .first { mapping in
                let sourcePath = mapping.from.standardizedFileURL.path
                return oldPath.lowercased() == sourcePath.lowercased() ||
                    oldPath.lowercased().hasPrefix(sourcePath.lowercased() + "/")
            }
        guard let matchingMapping else { return false }

        let sourcePath = matchingMapping.from.standardizedFileURL.path
        let relativeSuffix = String(oldPath.dropFirst(sourcePath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetFolderURL = URL(
            fileURLWithPath: matchingMapping.to.standardizedFileURL.path,
            isDirectory: true
        )
        let newFolderURL = relativeSuffix.isEmpty
            ? targetFolderURL
            : targetFolderURL.appendingPathComponent(relativeSuffix, isDirectory: true)
        let newFolderPath = newFolderURL.absoluteString

        fileDB.lock()
        guard fileDB.curFolder == oldFolderPath else {
            fileDB.unlock()
            return false
        }
        fileDB.curFolder = newFolderPath
        fileDB.unlock()

        preserveCollectionScrollPosition(for: newFolderPath)
        publicVar.filesForLocateAfterChange.removeAll()
        return true
    }

    /// Updates rename-only state without rebuilding collection items or media players.
    /// Returns false when the collection is not fully loaded and a normal refresh is required.
    private func applyRenameMappingsInPlace(
        _ mappings: [FileRenameMapping],
        folderPath: String
    ) -> Bool {
        guard !mappings.isEmpty else { return true }
        var mappingBySourcePath: [String: FileRenameMapping] = [:]
        for mapping in mappings {
            mappingBySourcePath[normalizedFilePathKey(mapping.from)] = mapping
        }
        let largeViewOldPath = largeImageView.file.path

        fileDB.lock()
        guard fileDB.curFolder == folderPath,
              let dirModel = fileDB.db[SortKeyDir(folderPath)] else {
            fileDB.unlock()
            return false
        }

        let oldEntries = getMapKeysFile(dirModel.files)
        guard collectionView.numberOfItems(inSection: 0) == oldEntries.count else {
            fileDB.unlock()
            return false
        }

        let availablePaths = Set(oldEntries.compactMap { entry in
            URL(string: entry.1.path)?.path.lowercased()
        })
        guard Set(mappingBySourcePath.keys).isSubset(of: availablePaths) else {
            fileDB.unlock()
            return false
        }

        let oldModels = oldEntries.map(\.1)
        let selectedModelIDs = Set(collectionView.selectionIndexPaths.compactMap { indexPath -> ObjectIdentifier? in
            guard oldModels.indices.contains(indexPath.item) else { return nil }
            return ObjectIdentifier(oldModels[indexPath.item])
        })
        var preparedEntries: [(key: SortKeyFile, model: FileModel, newURL: URL?)] = []
        preparedEntries.reserveCapacity(oldEntries.count)
        for (oldKey, model) in oldEntries {
            guard let modelURL = URL(string: model.path),
                  let mapping = mappingBySourcePath[normalizedFilePathKey(modelURL)] else {
                preparedEntries.append((oldKey, model, nil))
                continue
            }

            let newPath = mapping.to.absoluteString
            guard let newKey = oldKey.copy() as? SortKeyFile else {
                fileDB.unlock()
                return false
            }
            newKey.path = newPath
            newKey.pathCmp = newPath.lowercased()
            newKey.exifDate = oldKey.exifDate
            newKey.exifPixel = oldKey.exifPixel
            newKey.rating = oldKey.rating
            newKey.tag = oldKey.tag
            newKey.isTagLoaded = oldKey.isTagLoaded
            preparedEntries.append((newKey, model, mapping.to))
        }

        var rebuiltFiles = Map<SortKeyFile, FileModel>()
        for entry in preparedEntries {
            if let newURL = entry.newURL {
                entry.model.path = newURL.absoluteString
                entry.model.ext = newURL.pathExtension.lowercased()
            }
            rebuiltFiles[entry.key] = entry.model
        }
        dirModel.files = rebuiltFiles
        let newModels = getMapKeysFile(rebuiltFiles).map(\.1)
        fileDB.unlock()

        var oldIndexByModel: [ObjectIdentifier: Int] = [:]
        for (index, model) in oldModels.enumerated() {
            oldIndexByModel[ObjectIdentifier(model)] = index
        }
        var newIndexByModel: [ObjectIdentifier: Int] = [:]
        for (index, model) in newModels.enumerated() {
            newIndexByModel[ObjectIdentifier(model)] = index
        }
        guard Set(oldIndexByModel.keys) == Set(newIndexByModel.keys) else { return false }

        for case let item as CustomCollectionViewItem in collectionView.visibleItems() {
            guard let oldURL = item.imageViewObj.url,
                  let mapping = mappingBySourcePath[oldURL.path.lowercased()] else { continue }
            let newURL = mapping.to
            item.imageViewObj.url = newURL
            if item.currentPlayingURL?.path.lowercased() == oldURL.path.lowercased() {
                item.currentPlayingURL = newURL
            }
            item.imageNameField.stringValue = publicVar.profile.isShowThumbnailFilename ? newURL.lastPathComponent : ""
            item.setTooltip()
        }

        let moves = oldIndexByModel.compactMap { modelID, oldIndex -> (IndexPath, IndexPath)? in
            guard let newIndex = newIndexByModel[modelID], newIndex != oldIndex else { return nil }
            return (IndexPath(item: oldIndex, section: 0), IndexPath(item: newIndex, section: 0))
        }
        if !moves.isEmpty {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                collectionView.performBatchUpdates {
                    for move in moves {
                        collectionView.moveItem(at: move.0, to: move.1)
                    }
                }
            }
        }
        if !selectedModelIDs.isEmpty {
            collectionView.selectionIndexPaths = Set(newModels.enumerated().compactMap { index, model in
                selectedModelIDs.contains(ObjectIdentifier(model))
                    ? IndexPath(item: index, section: 0)
                    : nil
            })
        }

        if let oldLargeURL = URL(string: largeViewOldPath),
           let mapping = mappingBySourcePath[oldLargeURL.path.lowercased()] {
            let newURL = mapping.to
            largeImageView.file.path = newURL.absoluteString
            largeImageView.file.ext = newURL.pathExtension.lowercased()
            if largeImageView.currentPlayingURL?.path.lowercased() == oldLargeURL.path.lowercased() {
                largeImageView.currentPlayingURL = newURL
            }
            if largeImageView.restorePlayURL?.path.lowercased() == oldLargeURL.path.lowercased() {
                largeImageView.restorePlayURL = newURL
            }
            if let openURL = URL(string: publicVar.openFromFinderPath),
               openURL.path.lowercased() == oldLargeURL.path.lowercased() {
                publicVar.openFromFinderPath = newURL.absoluteString
            }
            setWindowTitleOfLargeImage(file: largeImageView.file)
        }

        return true
    }

    private func prepareNetworkRename(_ mappings: [FileRenameMapping]) -> [NetworkIOCoordinator.PlaybackLease] {
        let networkURLs = mappings.map(\.from).filter { VolumeManager.shared.isNetworkVolume($0) }
        guard !networkURLs.isEmpty else { return [] }
        // Reuse the coordinator's foreground lease to pause optional reads.
        // This does not stop/reload any player or discard its playback position.
        let leases = networkURLs.compactMap { NetworkIOCoordinator.shared.beginPlayback(for: $0) }
        mediaPreheatManager.beginWindow(retaining: [])
        return leases
    }

    private func moveRenameItem(from: URL, to: URL) throws {
        do {
            try RenameIO.move(from: from, to: to,
                              retryBusy: !Thread.isMainThread && VolumeManager.shared.isNetworkVolume(from))
        } catch {
            log("Rename I/O failed: \(error.localizedDescription)", level: .error)
            if VolumeManager.shared.isNetworkVolume(from),
               (error as NSError).code == Int(EACCES) || (error as NSError).code == Int(EPERM) {
                throw NSError(domain: "FlowVision.Rename", code: (error as NSError).code, userInfo: [
                    NSLocalizedDescriptionKey: error.localizedDescription + "\nSMB 服务器拒绝改名：目录内有文件正在播放或被其他程序打开时也可能出现此错误。请关闭相关文件后重试；若仍失败，再检查共享权限。",
                    NSUnderlyingErrorKey: error
                ])
            }
            throw error
        }
    }

    private func rollbackRename(_ pending: [PendingTempRename], completed: Int) -> String {
        let failures = RenameIO.rollback(pending.map { ($0.sourceURL, $0.tempURL, $0.targetURL) },
                                         completed: completed, move: moveRenameItem)
        return failures.isEmpty ? "" : "\n恢复失败（保留现存文件）：\n" + failures.joined(separator: "\n")
    }

    @discardableResult
    private func executeFileRenameMappings(
        _ mappings: [FileRenameMapping],
        actionName: String,
        registerUndo: Bool = true,
        locateTargets: [URL]? = nil,
        inPlaceFolderPath: String? = nil
    ) -> Bool {
        guard !mappings.isEmpty else { return true }

        if let failureMessage = renameValidationFailure(mappings) {
            log("Rename validation failed: \(failureMessage)", level: .error)
            showAlert(message: failureMessage)
            return false
        }

        publicVar.isInFileOperation = true
        defer { publicVar.isInFileOperation = false }

        let networkLeases = prepareNetworkRename(mappings)
        defer { networkLeases.forEach { $0.end() } }
        var pendingMoves: [PendingTempRename] = []

        for mapping in mappings {
            if mapping.from.path == mapping.to.path {
                continue
            }

            let tempURL = mapping.from.deletingLastPathComponent().appendingPathComponent("temp_rename_\(UUID().uuidString)")
            do {
                try moveRenameItem(from: mapping.from, to: tempURL)
                pendingMoves.append(PendingTempRename(sourceURL: mapping.from, tempURL: tempURL, targetURL: mapping.to))
            } catch {
                let recovery = rollbackRename(pendingMoves, completed: 0)
                log("Failed to create temp rename path: \(error)", level: .error)
                showAlert(message: String(format: NSLocalizedString("重命名失败：%@", comment: "rename failed"), error.localizedDescription + recovery))
                scheduledRefresh()
                return false
            }
        }

        var appliedMoves: [FileRenameMapping] = []
        for pending in pendingMoves {
            do {
                try moveRenameItem(from: pending.tempURL, to: pending.targetURL)
                publicVar.fileChangedCount += 1
                appliedMoves.append(FileRenameMapping(from: pending.sourceURL, to: pending.targetURL))
            } catch {
                let recovery = rollbackRename(pendingMoves, completed: appliedMoves.count)
                log("Failed to complete rename: \(error)", level: .error)
                showAlert(message: String(format: NSLocalizedString("重命名失败：%@", comment: "rename failed"), (error.localizedDescription + recovery)))
                scheduledRefresh()
                return false
            }
        }

        guard !appliedMoves.isEmpty else { return true }

        EnhancedIndex.handleFilesMoved(appliedMoves.map { (oldPath: $0.from.path, newPath: $0.to.path) })
        let didRenameCurrentFolder = updateCurrentFolderPathAfterRename(appliedMoves)
        let didUpdateInPlace = inPlaceFolderPath.map {
            applyRenameMappingsInPlace(appliedMoves, folderPath: $0)
        } ?? false
        updateVideoPlaybackPathsAfterRename(appliedMoves)
        if didUpdateInPlace || didRenameCurrentFolder {
            publicVar.filesForLocateAfterChange.removeAll()
            if !didRenameCurrentFolder {
                publicVar.collectionScrollRestoreAfterRefresh = nil
            }
        } else {
            publicVar.filesForLocateAfterChange = (locateTargets ?? appliedMoves.map(\.to)).map(\.absoluteString)
            publicVar.filesForLocateAfterChangeTime = .now()
        }

        if registerUndo, let undoManager = fileOperationUndoManager() {
            let inverseMappings = appliedMoves.map { FileRenameMapping(from: $0.to, to: $0.from) }
            undoManager.registerUndo(withTarget: self) { target in
                _ = target.executeFileRenameMappings(
                    inverseMappings,
                    actionName: actionName,
                    registerUndo: true,
                    locateTargets: appliedMoves.map(\.from),
                    inPlaceFolderPath: inPlaceFolderPath
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
        if didRenameCurrentFolder || (!didUpdateInPlace && ifRefresh) {
            scheduledRefresh()
        }

        return true
    }

    private func executeFileRenameMappingsAsync(
        _ mappings: [FileRenameMapping],
        actionName: String,
        locateTargets: [URL]? = nil,
        inPlaceFolderPath: String? = nil
    ) {
        guard !mappings.isEmpty else {
            publicVar.isInFileOperation = false
            coreAreaView.hideOperationOverlay(delayed: 0.2)
            return
        }

        publicVar.isInFileOperation = true
        coreAreaView.showOperationIndeterminate(NSLocalizedString("Preparing rename…", comment: "正在准备重命名…"))

        let networkLeases = prepareNetworkRename(mappings)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { networkLeases.forEach { $0.end() } }
            guard let self = self else { return }

            var failureMessage = self.renameValidationFailure(mappings)

            let changedMappings = mappings.filter { $0.from.path != $0.to.path }
            var pendingMoves: [PendingTempRename] = []
            var appliedMoves: [FileRenameMapping] = []
            let total = max(changedMappings.count, 1)

            if failureMessage == nil {
                for (index, mapping) in changedMappings.enumerated() {
                    if index == 0 || index == changedMappings.count - 1 || index % max(1, total / 100) == 0 {
                        DispatchQueue.main.async { [weak self] in
                            self?.coreAreaView.showOperationProgress(
                                "正在准备重命名 \(index + 1)/\(changedMappings.count)",
                                progress: Double(index) / Double(total) * 0.5
                            )
                        }
                    }

                    let tempURL = mapping.from.deletingLastPathComponent().appendingPathComponent("temp_rename_\(UUID().uuidString)")
                    do {
                        try self.moveRenameItem(from: mapping.from, to: tempURL)
                        pendingMoves.append(PendingTempRename(sourceURL: mapping.from, tempURL: tempURL, targetURL: mapping.to))
                    } catch {
                        failureMessage = error.localizedDescription
                        for pending in pendingMoves.reversed() {
                            do {
                                try self.moveRenameItem(from: pending.tempURL, to: pending.sourceURL)
                            } catch {
                                log("Failed to roll back temp rename \(pending.tempURL.path): \(error)", level: .error)
                                failureMessage = (failureMessage ?? "") + "\n恢复失败：\(pending.tempURL.path): \(error.localizedDescription)"
                            }
                        }
                        pendingMoves.removeAll()
                        break
                    }
                }
            }

            if failureMessage == nil {
                for (index, pending) in pendingMoves.enumerated() {
                    if index == 0 || index == pendingMoves.count - 1 || index % max(1, total / 100) == 0 {
                        DispatchQueue.main.async { [weak self] in
                            self?.coreAreaView.showOperationProgress(
                                "正在重命名 \(index + 1)/\(pendingMoves.count)",
                                progress: 0.5 + Double(index) / Double(total) * 0.5
                            )
                        }
                    }

                    do {
                        try self.moveRenameItem(from: pending.tempURL, to: pending.targetURL)
                        appliedMoves.append(FileRenameMapping(from: pending.sourceURL, to: pending.targetURL))
                    } catch {
                        failureMessage = error.localizedDescription
                        failureMessage = error.localizedDescription + self.rollbackRename(pendingMoves, completed: appliedMoves.count)
                        appliedMoves.removeAll()
                        break
                    }
                }
            }

            if failureMessage == nil, !appliedMoves.isEmpty {
                EnhancedIndex.handleFilesMoved(
                    appliedMoves.map { (oldPath: $0.from.path, newPath: $0.to.path) }
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                defer { self.publicVar.isInFileOperation = false }

                if let failureMessage = failureMessage {
                    self.publicVar.collectionScrollRestoreAfterRefresh = nil
                    self.coreAreaView.hideOperationOverlay(delayed: 0.2)
                    showAlert(message: "重命名失败：\(failureMessage)")
                    self.scheduledRefresh()
                    return
                }

                guard !appliedMoves.isEmpty else {
                    self.publicVar.collectionScrollRestoreAfterRefresh = nil
                    self.coreAreaView.showOperationToast("文件名无需更改", autoHide: 1.5)
                    return
                }

                self.publicVar.fileChangedCount += appliedMoves.count
                let didRenameCurrentFolder = self.updateCurrentFolderPathAfterRename(appliedMoves)
                let didUpdateInPlace = inPlaceFolderPath.map {
                    self.applyRenameMappingsInPlace(appliedMoves, folderPath: $0)
                } ?? false
                self.updateVideoPlaybackPathsAfterRename(appliedMoves)
                if didUpdateInPlace || didRenameCurrentFolder {
                    self.publicVar.filesForLocateAfterChange.removeAll()
                    if !didRenameCurrentFolder {
                        self.publicVar.collectionScrollRestoreAfterRefresh = nil
                    }
                } else {
                    self.publicVar.filesForLocateAfterChange = (locateTargets ?? appliedMoves.map(\.to)).map(\.absoluteString)
                    self.publicVar.filesForLocateAfterChangeTime = .now()
                }

                if let undoManager = self.fileOperationUndoManager() {
                    let inverseMappings = appliedMoves.map { FileRenameMapping(from: $0.to, to: $0.from) }
                    undoManager.registerUndo(withTarget: self) { target in
                        _ = target.executeFileRenameMappings(
                            inverseMappings,
                            actionName: actionName,
                            registerUndo: true,
                            locateTargets: appliedMoves.map(\.from),
                            inPlaceFolderPath: inPlaceFolderPath
                        )
                    }
                    undoManager.setActionName(actionName)
                }

                var shouldRefresh = true
                self.fileDB.lock()
                let currentFolder = self.fileDB.curFolder
                if self.publicVar.isRecursiveMode || isVirtualFolderPath(currentFolder) {
                    shouldRefresh = self.fileDB.db[SortKeyDir(currentFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
                }
                self.fileDB.unlock()
                if didRenameCurrentFolder || (!didUpdateInPlace && shouldRefresh) {
                    self.scheduledRefresh()
                }

                self.coreAreaView.showOperationProgress("重命名完成", progress: 1.0)
                self.coreAreaView.hideOperationOverlay(delayed: 0.8)
            }
        }
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
        for sourceURL in selectedURLs where !isVirtualArchiveEntryPath(sourceURL.absoluteString) {
            if sourceURL == targetFolderURL || targetFolderURL.path.hasPrefix(sourceURL.path + "/") {
                showAlert(message: NSLocalizedString("cannot-copy-to-self", comment: "不能将文件/文件夹复制到自身或其子目录中。"))
                return
            }
        }
        publicVar.isInFileOperation = true
        coreAreaView.showOperationIndeterminate("正在复制到 \(targetFolderURL.lastPathComponent)…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let fileManager = FileManager.default
            var reservedTargetPaths = Set<String>()
            var copiedURLs: [URL] = []
            var failedItems: [String] = []

            func uniqueDestination(for fileName: String) -> URL {
                let candidate = targetFolderURL.appendingPathComponent(fileName)
                var destination = candidate
                var index = 2
                while fileManager.fileExists(atPath: destination.path) || reservedTargetPaths.contains(destination.path.lowercased()) {
                    let stem = candidate.deletingPathExtension().lastPathComponent
                    let ext = candidate.pathExtension
                    let renamed = ext.isEmpty ? "\(stem)_\(index)" : "\(stem)_\(index).\(ext)"
                    destination = targetFolderURL.appendingPathComponent(renamed)
                    index += 1
                }
                reservedTargetPaths.insert(destination.path.lowercased())
                return destination
            }

            for (offset, sourceURL) in selectedURLs.enumerated() {
                DispatchQueue.main.async { [weak self] in
                    self?.coreAreaView.showOperationProgress(
                        "正在复制 \(offset + 1)/\(selectedURLs.count)：\(sourceURL.lastPathComponent)",
                        progress: Double(offset) / Double(selectedURLs.count)
                    )
                }

                if isVirtualArchiveEntryPath(sourceURL.absoluteString) {
                    guard let parsed = parseVirtualArchivePath(sourceURL.absoluteString),
                          let entryPath = parsed.entryPath,
                          let data = getArchiveEntryData(archiveURL: parsed.archiveURL, entryPath: entryPath) else {
                        failedItems.append(sourceURL.lastPathComponent.removingPercentEncoding ?? sourceURL.lastPathComponent)
                        continue
                    }
                    let fileName = URL(fileURLWithPath: entryPath).lastPathComponent
                    let destinationURL = uniqueDestination(for: fileName)
                    do {
                        try data.write(to: destinationURL, options: .atomic)
                        copiedURLs.append(destinationURL)
                    } catch {
                        log("Copy archive entry failed: \(error)", level: .error)
                        failedItems.append(fileName)
                    }
                } else {
                    let destinationURL = uniqueDestination(for: sourceURL.lastPathComponent)
                    do {
                        try fileManager.copyItem(at: sourceURL, to: destinationURL)
                        copiedURLs.append(destinationURL)
                    } catch {
                        log("Copy file failed: \(error)", level: .error)
                        failedItems.append(sourceURL.lastPathComponent)
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.publicVar.isInFileOperation = false

                if !copiedURLs.isEmpty {
                    self.publicVar.fileChangedCount += copiedURLs.count
                    self.publicVar.filesForLocateAfterChange = copiedURLs.map(\.absoluteString)
                    self.publicVar.filesForLocateAfterChangeTime = .now()
                    triggerFinderSound()
                    self.scheduledRefresh()
                    self.showPhotoFolderCopyToast(selectedURLs: selectedURLs, targetFolderURL: targetFolderURL)
                    self.coreAreaView.showOperationProgress("复制完成", progress: 1.0)
                    self.coreAreaView.hideOperationOverlay(delayed: 0.8)
                } else {
                    self.coreAreaView.hideOperationOverlay(delayed: 0.2)
                }

                if !failedItems.isEmpty {
                    let preview = failedItems.prefix(3).joined(separator: ", ")
                    showAlert(message: String(format: NSLocalizedString("Failed to copy some files: %@", comment: "部分文件复制失败：%@"), preview))
                }
            }
        }
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

        guard !publicVar.isInFileOperation else { return }

        let currentSeconds = largeImageView.videoCurrentTimeSeconds
        let captureSeconds = currentSeconds.isFinite && currentSeconds >= 0 ? currentSeconds : 0
        let captureTime = CMTime(seconds: captureSeconds, preferredTimescale: 600)
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let milliseconds = Int(captureSeconds * 1000)
        let outputCandidate = videoURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_frame_\(milliseconds)")
            .appendingPathExtension("png")
        let outputURL = getUniqueDestinationURL(for: outputCandidate)
        let mpvPlayer = largeImageView.isUsingMPVPlayer ? largeImageView.mpvPlayer : nil
        let shouldResumeMPV = mpvPlayer != nil && largeImageView.videoIsPlaying
        if shouldResumeMPV {
            // Freeze the displayed frame before handing the screenshot command
            // to the background queue. Otherwise playback can advance between
            // the shortcut and mpv writing the file.
            largeImageView.setVideoPaused(true)
        }

        publicVar.isInFileOperation = true
        coreAreaView.showOperationIndeterminate(
            NSLocalizedString("Capturing current frame…", comment: "正在截存当前画面…")
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var captureError: Error?
            var succeeded = false

            if let mpvPlayer {
                succeeded = mpvPlayer.captureCurrentVideoFrame(to: outputURL)
            }
            if !succeeded {
                try? FileManager.default.removeItem(at: outputURL)
                do {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
                    generator.appliesPreferredTrackTransform = true
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = .zero
                    let cgImage = try generator.copyCGImage(at: captureTime, actualTime: nil)
                    let bitmap = NSBitmapImageRep(cgImage: cgImage)
                    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                        throw NSError(
                            domain: "netdcy.FlowVision.VideoFrameCapture",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to encode the captured frame as PNG."]
                        )
                    }
                    try pngData.write(to: outputURL, options: .atomic)
                    succeeded = true
                } catch {
                    captureError = error
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.publicVar.isInFileOperation = false
                self.coreAreaView.hideOperationOverlay(delayed: succeeded ? 0.6 : 0)
                if shouldResumeMPV,
                   URL(string: self.largeImageView.file.path) == videoURL {
                    self.largeImageView.setVideoPaused(false)
                }

                guard succeeded else {
                    if let captureError {
                        log("Capture video frame failed: \(captureError)", level: .error)
                    } else {
                        log("Capture video frame through mpv failed", level: .error)
                    }
                    showAlert(message: NSLocalizedString("Failed to capture current video frame.", comment: "抓取当前视频帧失败。"))
                    return
                }

                self.publicVar.fileChangedCount += 1
                // Preserve the current video after refresh so the newly saved
                // image does not replace it or interrupt playback.
                self.publicVar.openFromFinderPath = videoURL.absoluteString
                self.scheduledRefresh()
                self.largeImageView.showInfo(
                    String(
                        format: NSLocalizedString("Frame saved: %@", comment: "画面已保存：%@"),
                        outputURL.lastPathComponent
                    )
                )
            }
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
            if isSameOrDescendant(destinationURL, of: fileURL) {
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
                let destinationIsInsideCurrent = URL(string: curFolder).map {
                    isSameOrDescendant(destinationURL.standardizedFileURL, of: $0.standardizedFileURL)
                } ?? false
                if !destinationIsInsideCurrent
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

    func handleMove(
        targetURL: URL? = nil,
        pasteboard: NSPasteboard = NSPasteboard.general,
        allowBackgroundPreflight: Bool = true,
        knownExistingTargetPaths: Set<String>? = nil
    ) {
        guard !publicVar.isInFileOperation else { return }

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
        var seenSourcePaths = Set<String>()
        let sourceURLs = items.compactMap { item -> URL? in
            guard let value = item.string(forType: .fileURL),
                  let url = URL(string: value) else { return nil }
            return seenSourcePaths.insert(normalizedFilePathKey(url)).inserted ? url : nil
        }
        guard !sourceURLs.isEmpty else { return }
        if hasOverlappingSourcePaths(sourceURLs) {
            showAlert(message: NSLocalizedString("A folder and one of its descendants cannot be moved together.", comment: "不能同时移动文件夹及其子项目。"))
            return
        }

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
        for fileURL in sourceURLs {
            // 检查是否包含目标目录自身或者它的父目录
            // Check if includes destination directory itself or its parent directory
            if isSameOrDescendant(destinationURL, of: fileURL) {
                showAlert(message: NSLocalizedString("cannot-move-to-self", comment: "不能将文件/文件夹移动到自身或其子目录中。"))
                return
            }
        }

        // 检查来源是否有同名文件
        // Check if source has files with same name
        var ifAutoRenameWhenDifferentSource = false
        var fileNames = Set<String>()
        var hasDuplicates = false
        for fileURL in sourceURLs {
            let fileName = fileURL.lastPathComponent.lowercased()
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
        let sourceFiles = sourceURLs.map(\.lastPathComponent)

        let sourceFilesStr: String
        if sourceFiles.count > 3 {
            sourceFilesStr = sourceFiles[0...2].joined(separator: ", ") + "..."
        } else {
            sourceFilesStr = sourceFiles.joined(separator: ", ")
        }

        let operationLog = "[Move] \(sourceFilesStr) -> \(destinationURL.lastPathComponent)"
        globalVar.operationLogs.append(operationLog)

        preserveViewportAnchorForMove(sourceURLs, folderPath: curFolder)
        let unconflictedPlans = sourceURLs.compactMap { source -> (source: URL, destination: URL)? in
            guard source.deletingLastPathComponent().standardizedFileURL != destinationURL.standardizedFileURL else {
                return nil
            }
            let target = destinationURL.appendingPathComponent(source.lastPathComponent)
            return (source: source, destination: target)
        }
        if !sourceURLs.isEmpty,
           unconflictedPlans.count == sourceURLs.count,
           !ifAutoRenameWhenDifferentSource,
           allowBackgroundPreflight {
            executeUnconflictedMovesAsync(
                unconflictedPlans,
                destinationURL: destinationURL,
                originalFolderPath: curFolder,
                pasteboard: pasteboard,
                checkConflictsBeforeMoving: true
            )
            return
        }

        // 在文件操作期间抑制文件系统监控触发的刷新，操作完成后主动刷新
        // Suppress FS watcher refreshes during file operations, refresh explicitly after completion
        publicVar.isInFileOperation = true
        // 记录成功粘贴的目标路径，用于刷新后选中
        // Record successfully pasted destination paths for selection after refresh
        var successfulDestURLs: [String] = []
        var indexMovePairs: [(oldPath: String, newPath: String)] = []
        var failedCount = 0
        let pasteboardChangeCount = pasteboard.changeCount
        defer {
            if !successfulDestURLs.isEmpty || failedCount > 0 {
                finishMoveOperation(
                    successfulDestURLs: successfulDestURLs,
                    movePairs: indexMovePairs,
                    failedCount: failedCount,
                    destinationURL: destinationURL,
                    originalFolderPath: curFolder,
                    pasteboard: pasteboard,
                    pasteboardChangeCount: pasteboardChangeCount
                )
            } else {
                publicVar.collectionViewportAnchorAfterRefresh = nil
            }
            if !indexMovePairs.isEmpty {
                let pairs = indexMovePairs
                DispatchQueue.global(qos: .utility).async {
                    EnhancedIndex.handleFilesMoved(pairs)
                }
            }
            publicVar.isInFileOperation = false
        }

        var shouldReplaceAll = false
        var shouldMergeAll = false
        var shouldSkipAll = false
        var shouldAutoRenameAll = false
        let sharedMergeState = MergeConflictState()

        func performTrackedMerge(from sourceURL: URL, to destURL: URL) {
            let completedMoveStart = indexMovePairs.count
            let allSucceeded = mergeFolderByMove(
                from: sourceURL,
                to: destURL,
                state: sharedMergeState,
                completedMoves: &indexMovePairs
            )
            let movedCount = indexMovePairs.count - completedMoveStart
            if movedCount > 0 {
                successfulDestURLs.append(destURL.absoluteString)
                publicVar.fileChangedCount += movedCount
            }
            if !allSucceeded && !sharedMergeState.cancelled {
                failedCount += 1
            }
        }

        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        defer { publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled }
        for fileURL in sourceURLs {
            var destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)

            // 如果是在同一目录移动，则不作动作
            // If moving in same directory, do nothing
            let isInSameFolder = fileURL.deletingLastPathComponent().standardizedFileURL == destinationURL.standardizedFileURL
            if isInSameFolder {
                continue
            }

            if ifAutoRenameWhenDifferentSource {
                destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
            }

            let targetExists = knownExistingTargetPaths?.contains(
                destURL.standardizedFileURL.path.lowercased()
            ) ?? FileManager.default.fileExists(atPath: destURL.path)
            if targetExists {
                // 检测源和目标是否都是文件夹
                // Check if both source and destination are folders
                var srcIsDir: ObjCBool = false
                FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &srcIsDir)
                var dstIsDir: ObjCBool = false
                FileManager.default.fileExists(atPath: destURL.path, isDirectory: &dstIsDir)
                let bothAreFolders = srcIsDir.boolValue && dstIsDir.boolValue

                if shouldReplaceAll {
                    performTrackedMove(
                        from: fileURL,
                        to: destURL,
                        replacingDestination: true,
                        successfulDestURLs: &successfulDestURLs,
                        movePairs: &indexMovePairs,
                        failedCount: &failedCount
                    )
                } else if shouldMergeAll && bothAreFolders {
                    performTrackedMerge(from: fileURL, to: destURL)
                    if sharedMergeState.cancelled {
                        return
                    }
                } else if shouldSkipAll {
                    continue
                } else if shouldAutoRenameAll {
                    destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                    performTrackedMove(
                        from: fileURL,
                        to: destURL,
                        replacingDestination: false,
                        successfulDestURLs: &successfulDestURLs,
                        movePairs: &indexMovePairs,
                        failedCount: &failedCount
                    )
                } else {
                    let userChoice = showReplaceDialog(for: destURL, sourceURL: fileURL, isSingle: sourceURLs.count == 1, isMove: true)
                    switch userChoice {
                    case .replace:
                        performTrackedMove(
                            from: fileURL,
                            to: destURL,
                            replacingDestination: true,
                            successfulDestURLs: &successfulDestURLs,
                            movePairs: &indexMovePairs,
                            failedCount: &failedCount
                        )
                    case .replaceAll:
                        shouldReplaceAll = true
                        performTrackedMove(
                            from: fileURL,
                            to: destURL,
                            replacingDestination: true,
                            successfulDestURLs: &successfulDestURLs,
                            movePairs: &indexMovePairs,
                            failedCount: &failedCount
                        )
                    case .merge:
                        performTrackedMerge(from: fileURL, to: destURL)
                        if sharedMergeState.cancelled {
                            return
                        }
                    case .mergeAll:
                        shouldMergeAll = true
                        performTrackedMerge(from: fileURL, to: destURL)
                        if sharedMergeState.cancelled {
                            return
                        }
                    case .autoRename:
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        performTrackedMove(
                            from: fileURL,
                            to: destURL,
                            replacingDestination: false,
                            successfulDestURLs: &successfulDestURLs,
                            movePairs: &indexMovePairs,
                            failedCount: &failedCount
                        )
                    case .autoRenameAll:
                        shouldAutoRenameAll = true
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        performTrackedMove(
                            from: fileURL,
                            to: destURL,
                            replacingDestination: false,
                            successfulDestURLs: &successfulDestURLs,
                            movePairs: &indexMovePairs,
                            failedCount: &failedCount
                        )
                    case .skip:
                        continue
                    case .skipAll:
                        shouldSkipAll = true
                        continue
                    case .cancel:
                        return
                    }
                }
            } else {
                performTrackedMove(
                    from: fileURL,
                    to: destURL,
                    replacingDestination: false,
                    successfulDestURLs: &successfulDestURLs,
                    movePairs: &indexMovePairs,
                    failedCount: &failedCount
                )
            }
        }
    }

    private func invalidatePlaybackForDeletion(_ urls: [URL], currentFolderPath: String) {
        let currentFolderURL = URL(string: currentFolderPath)
        let largeImageFileURL = URL(string: largeImageView.file.path)
        let currentFolderIsAffected = currentFolderURL.map { folder in
            urls.contains { isSameOrDescendant(folder, of: $0) }
        } ?? false
        let largeImageIsOpenOrPlaying = publicVar.isInLargeView || largeImageView.currentPlayingURL != nil
        let largeImageIsAffected = largeImageIsOpenOrPlaying && (
            currentFolderIsAffected
            || largeImageFileURL.map { file in urls.contains { isSameOrDescendant(file, of: $0) } } ?? false
            || largeImageView.currentPlayingURL.map { file in urls.contains { isSameOrDescendant(file, of: $0) } } ?? false
        )

        var didInvalidatePlayback = currentFolderIsAffected
        if largeImageIsAffected {
            largeImageView.invalidateForDeletedContent()
            publicVar.isInLargeView = false
            publicVar.isInLargeViewAfterAnimate = false
            publicVar.openFromFinderPath = ""
            currLargeImagePos = -1
            largeImageBgEffectView.isHidden = true
            didInvalidatePlayback = true
        }

        for case let item as CustomCollectionViewItem in collectionView.visibleItems() {
            guard let playingURL = item.currentPlayingURL,
                  urls.contains(where: { isSameOrDescendant(playingURL, of: $0) }) else { continue }
            item.stopVideo()
            didInvalidatePlayback = true
        }

        if didInvalidatePlayback {
            // Cancel all neighbor reads before the deleted SMB subtree can be
            // touched by a stale preheat operation.
            mediaPreheatManager.beginWindow(retaining: [])
        }
    }

    private func fallbackDirectoryPath(afterDeleting deletedURLs: [URL], currentFolderPath: String) -> String? {
        guard let currentFolderURL = URL(string: currentFolderPath), currentFolderURL.isFileURL,
              deletedURLs.contains(where: { isSameOrDescendant(currentFolderURL, of: $0) }) else {
            return nil
        }

        var candidate = currentFolderURL.deletingLastPathComponent()
        while candidate.path != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate.absoluteString
            }
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break }
            candidate = parent
        }
        return URL(fileURLWithPath: "/", isDirectory: true).absoluteString
    }

    func handleDelete(fileUrls: [URL] = [], isShowPrompt: Bool = true, fromDirectoryTree: Bool = false, completion: (() -> Void)? = nil) -> Bool {
        guard !publicVar.isInFileOperation else { return false }
        var urls = fileUrls
        if urls.isEmpty {
            urls = publicVar.selectedUrls()
        }
        guard !urls.isEmpty else { return false }

        fileDB.lock()
        let currentFolderPath = fileDB.curFolder
        fileDB.unlock()

        let isShiftPressed = isShiftKeyPressed()
        let isExternalVolume = urls.first.map { VolumeManager.shared.isExternalVolume($0) } ?? false
        let isPermanentDelete = isShiftPressed

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete", comment: "删除")
        if isShiftPressed {
            alert.informativeText = NSLocalizedString("ask-to-delete-shift", comment: "你确定要将这些文件永久删除吗？此操作无法撤销。")
        } else {
            alert.informativeText = NSLocalizedString("ask-to-delete", comment: "你确定要将这些文件移动到废纸篓吗？")
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "删除"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        // 设置系统警告图标
        // Set system warning icon
        alert.icon = NSImage(named: NSImage.cautionName)

        var response: NSApplication.ModalResponse = .alertFirstButtonReturn
        if isShowPrompt || isPermanentDelete || isExternalVolume {
            let storeIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled = false
            response = alert.runModal()
            publicVar.isKeyEventEnabled = storeIsKeyEventEnabled
        }

        guard !publicVar.isInFileOperation else { return false }
        guard response == .alertFirstButtonReturn else {
            // 用户取消操作
            // User cancelled operation
            log("Delete operation cancelled")
            return false
        }

        // Capture the actual display order, including the active sort/filter,
        // before disk I/O starts. Do not guess a neighbor from filenames.
        fileDB.lock()
        let deletionVersion = fileDB.ver
        let collectionOrder = fileDB.db[SortKeyDir(currentFolderPath)]?.files.compactMap {
            URL(string: $0.1.path)
        } ?? []
        fileDB.unlock()
        let selectionAtDeletion = collectionView.selectionIndexPaths
        let selectionOrder: [URL] = fromDirectoryTree
            ? (0..<outlineView.numberOfRows).compactMap { row in
                guard let node = outlineView.item(atRow: row) as? TreeNode else { return nil }
                return URL(string: node.fullPath)
            }
            : collectionOrder

        // 在文件操作期间抑制文件系统监控触发的刷新，操作完成后主动刷新
        // Suppress FS watcher refreshes during file operations, refresh explicitly after completion
        publicVar.isInFileOperation = true
        invalidatePlaybackForDeletion(urls, currentFolderPath: currentFolderPath)

        let sourceFiles = urls.map { $0.lastPathComponent }
        let sourceFilesStr = sourceFiles.count > 3
            ? sourceFiles[0...2].joined(separator: ", ") + "..."
            : sourceFiles.joined(separator: ", ")
        globalVar.operationLogs.append("[Delete] \(sourceFilesStr)")
        coreAreaView.showOperationIndeterminate(NSLocalizedString("Deleting…", comment: "正在删除…"))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fileManager = FileManager.default
            let urlsToDelete = urls.filter { url in
                let exists = fileManager.fileExists(atPath: url.path)
                if !exists { log("File does not exist: \(url.path)") }
                return exists
            }

            func finish(succeeded: [URL], failedItems: [String]) {
                if !succeeded.isEmpty {
                    EnhancedIndex.handleFilesDeleted(succeeded.map(\.path))
                }
                let fallbackPath = succeeded.isEmpty
                    ? nil
                    : self.fallbackDirectoryPath(afterDeleting: succeeded, currentFolderPath: currentFolderPath)
                let selectionTarget = selectionTargetAfterDeletion(in: selectionOrder, deletedURLs: succeeded)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }

                    if !failedItems.isEmpty {
                        let preview = failedItems.prefix(3).joined(separator: ", ")
                        self.coreAreaView.showOperationToast(
                            String(format: NSLocalizedString("Failed to delete some files: %@", comment: "部分文件删除失败：%@"), preview),
                            autoHide: 3.0
                        )
                    }

                    if !succeeded.isEmpty {
                        self.publicVar.fileChangedCount += succeeded.count
                        self.fileDB.lock()
                        let currentFolder = self.fileDB.curFolder
                        let canRestoreSelection = currentFolder == currentFolderPath
                            && self.fileDB.ver == deletionVersion
                            && (fromDirectoryTree || self.collectionView.selectionIndexPaths == selectionAtDeletion)
                        self.fileDB.unlock()
                        let currentFolderIsAffected = URL(string: currentFolder).map { folder in
                            succeeded.contains { self.isSameOrDescendant(folder, of: $0) }
                        } ?? false

                        if canRestoreSelection, fromDirectoryTree, let selectionTarget {
                            self.publicVar.filesForLocateAfterChange.removeAll()
                            self.publicVar.folderStepForLocate.removeAll()
                            self.refreshTreeView()
                            self.switchDirByDirection(direction: .zero, dest: selectionTarget.absoluteString, doCollapse: false, expandLast: false, stackDeep: 0)
                            self.treeReLocate(path: selectionTarget.absoluteString, doCollapse: false, expandLast: false)
                            self.view.window?.makeFirstResponder(self.outlineView)
                        } else if currentFolderIsAffected, let fallbackPath {
                            self.publicVar.filesForLocateAfterChange.removeAll()
                            self.switchDirByDirection(direction: .zero, dest: fallbackPath, stackDeep: 0)
                        } else {
                            if canRestoreSelection, !fromDirectoryTree {
                                self.publicVar.filesForLocateAfterChange.removeAll()
                                self.publicVar.folderStepForLocate.removeAll()
                                self.publicVar.selectionAfterDeletion = selectionTarget.map { (currentFolder, $0.absoluteString) }
                            }
                            // Deletion must rebuild even a large recursive list,
                            // otherwise both deleted rows and selection stay stale.
                            self.scheduledRefresh()
                        }
                    }

                    self.publicVar.isInFileOperation = false
                    if failedItems.isEmpty {
                        self.coreAreaView.hideOperationOverlay(delayed: succeeded.isEmpty ? 0.2 : 0.8)
                    }
                    completion?()
                }
            }

            guard !urlsToDelete.isEmpty else {
                finish(succeeded: [], failedItems: urls.map(\.lastPathComponent))
                return
            }

            if isPermanentDelete {
                var succeeded = [URL]()
                var failedItems = [String]()
                for url in urlsToDelete {
                    do {
                        try fileManager.removeItem(at: url)
                        succeeded.append(url)
                    } catch {
                        failedItems.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                finish(succeeded: succeeded, failedItems: failedItems)
            } else {
                NSWorkspace.shared.recycle(urlsToDelete) { newURLs, error in
                    // NSWorkspace may return a partial URL mapping when a
                    // provider cannot recycle every item. Resolve each source
                    // separately so the fallback only touches unresolved URLs.
                    DispatchQueue.global(qos: .userInitiated).async {
                        var succeeded = [URL]()
                        var unresolved = [URL]()
                        let mappedPathKeys = Set(newURLs.keys.map { $0.standardizedFileURL.path })
                        for url in urlsToDelete {
                            let sourceWasRemoved = !fileManager.fileExists(atPath: url.path)
                            let hasMapping = mappedPathKeys.contains(url.standardizedFileURL.path)
                            if hasMapping || (error == nil && sourceWasRemoved) {
                                succeeded.append(url)
                            } else {
                                unresolved.append(url)
                            }
                        }

                        guard !unresolved.isEmpty else {
                            finish(succeeded: succeeded, failedItems: [])
                            return
                        }

                        var failedItems = [String]()
                        for url in unresolved {
                            do {
                                try fileManager.trashItem(at: url, resultingItemURL: nil)
                                succeeded.append(url)
                            } catch {
                                failedItems.append("\(url.lastPathComponent): \(error.localizedDescription)")
                            }
                        }
                        finish(succeeded: succeeded, failedItems: failedItems)
                    }
                }
            }
        }
        return true
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
        var completedMoves: [(oldPath: String, newPath: String)] = []
        return mergeFolderByMove(
            from: sourceURL,
            to: destURL,
            state: state ?? MergeConflictState(),
            completedMoves: &completedMoves
        )
    }

    @discardableResult
    private func mergeFolderByMove(
        from sourceURL: URL,
        to destURL: URL,
        state: MergeConflictState,
        completedMoves: inout [(oldPath: String, newPath: String)]
    ) -> Bool {
        let fm = FileManager.default
        let completedMoveStart = completedMoves.count

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        if !fm.fileExists(atPath: destURL.path) {
            do {
                try fm.moveItem(at: sourceURL, to: destURL)
                completedMoves.append((oldPath: sourceURL.path, newPath: destURL.path))
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
                if !mergeFolderByMove(from: itemURL, to: destItemURL, state: state, completedMoves: &completedMoves) {
                    allSuccess = false
                }
            } else if destExists {
                if itemURL.lastPathComponent == ".DS_Store" {
                    do {
                        try moveItemSafelyReplacingDestination(from: itemURL, to: destItemURL)
                        completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
                    } catch {
                        log("Merge move failed (.DS_Store): \(error)", level: .error)
                        allSuccess = false
                    }
                    continue
                }
                if state.shouldReplaceAll {
                    do {
                        try moveItemSafelyReplacingDestination(from: itemURL, to: destItemURL)
                        completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
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
                        completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
                    } catch {
                        log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                        allSuccess = false
                    }
                } else {
                    let choice = showReplaceDialog(for: destItemURL, sourceURL: itemURL, isSingle: false, isMove: true)
                    switch choice {
                    case .replace:
                        do {
                            try moveItemSafelyReplacingDestination(from: itemURL, to: destItemURL)
                            completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
                        } catch {
                            log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .replaceAll:
                        state.shouldReplaceAll = true
                        do {
                            try moveItemSafelyReplacingDestination(from: itemURL, to: destItemURL)
                            completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
                        } catch {
                            log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .merge, .mergeAll:
                        if srcIsDir.boolValue {
                            if !mergeFolderByMove(from: itemURL, to: destItemURL, state: state, completedMoves: &completedMoves) {
                                allSuccess = false
                            }
                        } else {
                            do {
                                try moveItemSafelyReplacingDestination(from: itemURL, to: destItemURL)
                                completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
                            } catch {
                                log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                                allSuccess = false
                            }
                        }
                    case .autoRename:
                        destItemURL = getUniqueDestinationURL(for: destItemURL, isInPlace: false)
                        do {
                            try fm.moveItem(at: itemURL, to: destItemURL)
                            completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
                        } catch {
                            log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                            allSuccess = false
                        }
                    case .autoRenameAll:
                        state.shouldAutoRenameAll = true
                        destItemURL = getUniqueDestinationURL(for: destItemURL, isInPlace: false)
                        do {
                            try fm.moveItem(at: itemURL, to: destItemURL)
                            completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
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
                    completedMoves.append((oldPath: itemURL.path, newPath: destItemURL.path))
                } catch {
                    log("Merge move failed (\(itemURL.lastPathComponent)): \(error)", level: .error)
                    allSuccess = false
                }
            }
        }

        // Remove source directory if it's now empty or all items were moved
        let remaining = try? fm.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: [])
        if remaining?.isEmpty ?? true {
            do {
                try fm.removeItem(at: sourceURL)
                completedMoves.removeSubrange(completedMoveStart...)
                completedMoves.append((oldPath: sourceURL.path, newPath: destURL.path))
            } catch {
                log("Merge move could not remove empty source folder \(sourceURL.path): \(error)", level: .error)
                allSuccess = false
            }
        }

        return allSuccess
    }

    func handleRename(urls: [URL]) -> Bool {
        guard !publicVar.isInFileOperation, !urls.isEmpty else { return false }

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

            if !newBaseName.isEmpty {
                guard newBaseName != ".", newBaseName != "..", !newBaseName.contains("/") else {
                    showAlert(message: String(format: NSLocalizedString("Invalid file name: %@", comment: "无效的文件名：%@"), newBaseName))
                    return false
                }

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
                if finalNames.count > 1 || finalNames.contains(where: { VolumeManager.shared.isNetworkVolume($0.from) }) {
                    executeFileRenameMappingsAsync(
                        finalNames,
                        actionName: actionName,
                        inPlaceFolderPath: curFolder
                    )
                    return true
                }
                let renameResult = executeFileRenameMappings(
                    finalNames,
                    actionName: actionName,
                    inPlaceFolderPath: curFolder
                )
                return renameResult
            }
        }
        return false
    }

    func handleBatchRenameFolders(urls: [URL]) -> Bool {
        guard !publicVar.isInFileOperation else { return false }
        let fileManager = FileManager.default
        let folders = urls.filter { url in
            var isDirectory: ObjCBool = false
            return !isReadOnlyVirtualFolderPath(url.absoluteString) &&
                !isVirtualArchiveEntryPath(url.absoluteString) &&
                fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) &&
                isDirectory.boolValue
        }
        guard folders.count > 1, folders.count == urls.count else {
            showAlert(message: NSLocalizedString("Please select at least two folders.", comment: "请至少选择两个文件夹。"))
            return false
        }

        let normalizedPaths = folders.map { $0.standardizedFileURL.path + "/" }
        for (index, path) in normalizedPaths.enumerated() {
            if normalizedPaths.enumerated().contains(where: { otherIndex, otherPath in
                otherIndex != index && otherPath.hasPrefix(path)
            }) {
                showAlert(message: NSLocalizedString("A parent folder and its subfolder cannot be renamed together.", comment: "不能同时重命名父文件夹及其子文件夹。"))
                return false
            }
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Batch Rename Folders", comment: "批量重命名文件夹")
        alert.informativeText = NSLocalizedString("Rules are applied in this order: replace, format, prefix, suffix.", comment: "规则应用顺序：替换、格式化、前缀、后缀。")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Preview", comment: "预览"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

        let form = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 166))
        let rows: [(String, String, String)] = [
            (NSLocalizedString("Prefix", comment: "前缀"), "", NSLocalizedString("Optional text before the name", comment: "名称前的可选文本")),
            (NSLocalizedString("Suffix", comment: "后缀"), "", NSLocalizedString("Optional text after the name", comment: "名称后的可选文本")),
            (NSLocalizedString("Find", comment: "查找"), "", NSLocalizedString("Text to replace", comment: "要替换的文本")),
            (NSLocalizedString("Replace With", comment: "替换为"), "", NSLocalizedString("Leave empty to remove matches", comment: "留空可删除匹配文本")),
            (NSLocalizedString("Format", comment: "格式化"), "{name}", "{name}, {index}, {index:03}")
        ]
        var fields: [NSTextField] = []
        for (index, row) in rows.enumerated() {
            let y = 136 - CGFloat(index * 33)
            let label = NSTextField(labelWithString: row.0)
            label.frame = NSRect(x: 0, y: y + 2, width: 100, height: 22)
            label.alignment = .right
            let field = NSTextField(frame: NSRect(x: 108, y: y, width: 332, height: 24))
            field.stringValue = row.1
            field.placeholderString = row.2
            form.addSubview(label)
            form.addSubview(field)
            fields.append(field)
        }
        alert.accessoryView = form

        let storedKeyState = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        defer { publicVar.isKeyEventEnabled = storedKeyState }
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let prefix = fields[0].stringValue
        let suffix = fields[1].stringValue
        let findText = fields[2].stringValue
        let replacement = fields[3].stringValue
        let format = fields[4].stringValue.isEmpty ? "{name}" : fields[4].stringValue
        let sourcePathSet = Set(folders.map { $0.path.lowercased() })
        var targetPathSet = Set<String>()
        var mappings: [FileRenameMapping] = []

        for (offset, folder) in folders.enumerated() {
            var name = folder.lastPathComponent
            if !findText.isEmpty {
                name = name.replacingOccurrences(of: findText, with: replacement)
            }
            var formatted = format.replacingOccurrences(of: "{name}", with: name)
            formatted = formatted.replacingOccurrences(of: "{index}", with: "\(offset + 1)")
            if let regex = try? NSRegularExpression(pattern: #"\{index:0?(\d+)\}"#) {
                let matches = regex.matches(in: formatted, range: NSRange(formatted.startIndex..., in: formatted))
                for match in matches.reversed() {
                    guard let widthRange = Range(match.range(at: 1), in: formatted),
                          let tokenRange = Range(match.range, in: formatted),
                          let width = Int(formatted[widthRange]) else { continue }
                    let value = String(format: "%0*d", width, offset + 1)
                    formatted.replaceSubrange(tokenRange, with: value)
                }
            }
            let newName = (prefix + formatted + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty, newName != ".", newName != "..", !newName.contains("/") else {
                showAlert(message: String(format: NSLocalizedString("Invalid folder name: %@", comment: "无效的文件夹名称：%@"), newName))
                return false
            }

            let target = folder.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: true)
            let targetPath = target.path.lowercased()
            guard targetPathSet.insert(targetPath).inserted else {
                showAlert(message: String(format: NSLocalizedString("Duplicate target name: %@", comment: "目标名称重复：%@"), newName))
                return false
            }
            if fileManager.fileExists(atPath: target.path) && !sourcePathSet.contains(targetPath) {
                showAlert(message: String(format: NSLocalizedString("A file or folder already exists: %@", comment: "文件或文件夹已存在：%@"), newName))
                return false
            }
            mappings.append(FileRenameMapping(from: folder, to: target))
        }

        let changedMappings = mappings.filter { $0.from.path != $0.to.path }
        guard !changedMappings.isEmpty else {
            showAlert(message: NSLocalizedString("The rules do not change any folder names.", comment: "这些规则未改变任何文件夹名称。"))
            return false
        }

        let preview = NSAlert()
        preview.messageText = NSLocalizedString("Confirm Batch Rename", comment: "确认批量重命名")
        preview.informativeText = String(format: NSLocalizedString("%d folders will be renamed.", comment: "将重命名 %d 个文件夹。"), changedMappings.count)
        preview.alertStyle = .warning
        preview.addButton(withTitle: NSLocalizedString("Rename", comment: "重命名"))
        preview.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: min(260, CGFloat(changedMappings.count * 24 + 12))))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = changedMappings.map { "\($0.from.lastPathComponent)  ->  \($0.to.lastPathComponent)" }.joined(separator: "\n")
        scrollView.documentView = textView
        preview.accessoryView = scrollView
        guard preview.runModal() == .alertFirstButtonReturn else { return false }

        globalVar.operationLogs.append("[BatchRenameFolders] \(changedMappings.count) folders")
        fileDB.lock()
        let inPlaceFolderPath = fileDB.curFolder
        fileDB.unlock()
        executeFileRenameMappingsAsync(
            changedMappings,
            actionName: NSLocalizedString("Batch Rename Folders", comment: "批量重命名文件夹"),
            inPlaceFolderPath: inPlaceFolderPath
        )
        return true
    }

    /// Shows a rename toolbox for any multi-selection, preserving file extensions by default.
    func handleBatchRenameSelectedItems(urls: [URL]) -> Bool {
        guard !publicVar.isInFileOperation else { return false }
        let fileManager = FileManager.default
        var seenPaths = Set<String>()
        let items = urls.filter { url in
            guard !isReadOnlyVirtualFolderPath(url.absoluteString),
                  !isVirtualArchiveEntryPath(url.absoluteString),
                  fileManager.fileExists(atPath: url.path) else {
                return false
            }
            return seenPaths.insert(url.standardizedFileURL.path.lowercased()).inserted
        }

        guard items.count > 1 else {
            showAlert(message: "请至少选择两个可重命名的文件或文件夹。")
            return false
        }

        // A selected parent cannot be renamed together with one of its selected children.
        let selectedPaths = items.map { $0.standardizedFileURL.path }
        let directoryPaths = Set(items.compactMap { item -> String? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return item.standardizedFileURL.path
        })
        for folderPath in directoryPaths {
            let folderPrefix = folderPath + "/"
            if selectedPaths.contains(where: { $0 != folderPath && $0.hasPrefix(folderPrefix) }) {
                showAlert(message: "不能同时重命名父文件夹及其已选中的子项目。")
                return false
            }
        }

        let alert = NSAlert()
        alert.messageText = "批量重命名所选项目"
        alert.informativeText = "按“替换 → 格式 → 前缀 → 后缀”的顺序处理。默认保留文件扩展名。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "预览")
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))

        let form = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 202))
        let rows: [(String, String, String)] = [
            ("前缀", "", "添加在名称前（扩展名之前）"),
            ("后缀", "", "添加在名称后（扩展名之前）"),
            ("查找", "", "在原文件名中查找的文字"),
            ("替换为", "", "留空可删除匹配内容"),
            ("格式", "{name}", "变量：{name}、{index}、{index:03}、{folder}、{ext}")
        ]
        var fields: [NSTextField] = []
        for (index, row) in rows.enumerated() {
            let y = 166 - CGFloat(index * 32)
            let label = NSTextField(labelWithString: row.0)
            label.frame = NSRect(x: 0, y: y + 2, width: 100, height: 22)
            label.alignment = .right
            let field = NSTextField(frame: NSRect(x: 108, y: y, width: 372, height: 24))
            field.stringValue = row.1
            field.placeholderString = row.2
            form.addSubview(label)
            form.addSubview(field)
            fields.append(field)
        }
        let hint = NSTextField(wrappingLabelWithString: "{name} 为原名称（不含扩展名）；{index:03} 可补零。格式中包含 {ext} 时由格式决定完整文件名，例如 {name}_{index}.{ext}。")
        hint.frame = NSRect(x: 108, y: 0, width: 372, height: 36)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        form.addSubview(hint)
        alert.accessoryView = form

        let storedKeyState = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        defer { publicVar.isKeyEventEnabled = storedKeyState }
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let prefix = fields[0].stringValue
        let suffix = fields[1].stringValue
        let findText = fields[2].stringValue
        let replacement = fields[3].stringValue
        let format = fields[4].stringValue.isEmpty ? "{name}" : fields[4].stringValue
        let formatControlsExtension = format.contains("{ext}")
        let sourcePathSet = Set(items.map { $0.path.lowercased() })
        var targetPathSet = Set<String>()
        var mappings: [FileRenameMapping] = []

        for (offset, item) in items.enumerated() {
            let index = offset + 1
            var baseName = item.deletingPathExtension().lastPathComponent
            if !findText.isEmpty {
                baseName = baseName.replacingOccurrences(of: findText, with: replacement)
            }

            let parentName = item.deletingLastPathComponent().lastPathComponent
            var formatted = format
                .replacingOccurrences(of: "{name}", with: baseName)
                .replacingOccurrences(of: "{folder}", with: parentName)
                .replacingOccurrences(of: "{ext}", with: item.pathExtension)
                .replacingOccurrences(of: "{index}", with: "\(index)")
            if let regex = try? NSRegularExpression(pattern: #"\{index:0?(\d+)\}"#) {
                let matches = regex.matches(in: formatted, range: NSRange(formatted.startIndex..., in: formatted))
                for match in matches.reversed() {
                    guard let widthRange = Range(match.range(at: 1), in: formatted),
                          let tokenRange = Range(match.range, in: formatted),
                          let width = Int(formatted[widthRange]) else { continue }
                    formatted.replaceSubrange(tokenRange, with: String(format: "%0*d", width, index))
                }
            }

            var newName = (prefix + formatted + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatControlsExtension, !item.pathExtension.isEmpty {
                newName += ".\(item.pathExtension)"
            }
            guard !newName.isEmpty, newName != ".", newName != "..", !newName.contains("/") else {
                showAlert(message: "无效的目标名称：\(newName)")
                return false
            }

            let target = item.deletingLastPathComponent().appendingPathComponent(
                newName,
                isDirectory: directoryPaths.contains(item.standardizedFileURL.path)
            )
            let targetPath = target.path.lowercased()
            guard targetPathSet.insert(targetPath).inserted else {
                showAlert(message: "目标名称重复：\(newName)")
                return false
            }
            if fileManager.fileExists(atPath: target.path) && !sourcePathSet.contains(targetPath) {
                showAlert(message: "已有同名文件或文件夹：\(newName)")
                return false
            }
            mappings.append(FileRenameMapping(from: item, to: target))
        }

        let changedMappings = mappings.filter { $0.from.path != $0.to.path }
        guard !changedMappings.isEmpty else {
            showAlert(message: "这些规则未改变任何名称。")
            return false
        }

        let preview = NSAlert()
        preview.messageText = "确认批量重命名"
        preview.informativeText = "将重命名 \(changedMappings.count) 个所选项目。"
        preview.alertStyle = .warning
        preview.addButton(withTitle: NSLocalizedString("Rename", comment: "重命名"))
        preview.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        let previewHeight = min(260, max(92, CGFloat(changedMappings.count * 24 + 26)))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: previewHeight))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 500, height: previewHeight))
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]

        let originalColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("original"))
        originalColumn.title = "原名称"
        originalColumn.width = 250
        originalColumn.minWidth = 140
        let renamedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("renamed"))
        renamedColumn.title = "新名称"
        renamedColumn.width = 250
        renamedColumn.minWidth = 140
        tableView.addTableColumn(originalColumn)
        tableView.addTableColumn(renamedColumn)

        let previewDataSource = BatchRenamePreviewDataSource(
            mappings: changedMappings.map { ($0.from.lastPathComponent, $0.to.lastPathComponent) }
        )
        tableView.dataSource = previewDataSource
        tableView.delegate = previewDataSource
        scrollView.documentView = tableView
        preview.accessoryView = scrollView
        guard preview.runModal() == .alertFirstButtonReturn else { return false }

        globalVar.operationLogs.append("[BatchRenameSelected] \(changedMappings.count) items")
        fileDB.lock()
        let inPlaceFolderPath = fileDB.curFolder
        fileDB.unlock()
        executeFileRenameMappingsAsync(
            changedMappings,
            actionName: "批量重命名",
            inPlaceFolderPath: inPlaceFolderPath
        )
        return true
    }

    func handleQuickRenameInCurrentFolder() -> Bool {
        guard !publicVar.isInFileOperation else { return false }

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

        let operationLog = "[QuickRename] \(folderName) -> \(rule)"
        globalVar.operationLogs.append(operationLog)
        publicVar.collectionScrollRestoreAfterRefresh = nil
        if let clipView = collectionView.enclosingScrollView?.contentView {
            publicVar.collectionScrollRestoreAfterRefresh = (curFolder, clipView.bounds.origin)
        }
        publicVar.isInFileOperation = true
        coreAreaView.showOperationIndeterminate("正在生成重命名方案…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let originalPathSet = Set(urls.map { $0.path.lowercased() })
            var plannedPathSet = Set<String>()
            var mappings: [FileRenameMapping] = []

            for (idx, originalURL) in urls.enumerated() {
                let index = idx + 1
                var baseName = rule
                    .replacingOccurrences(of: "{folder}", with: folderName)
                    .replacingOccurrences(of: "{index}", with: "\(index)")

                baseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
                if baseName.isEmpty {
                    baseName = "\(folderName)_\(index)"
                }

                let ext = originalURL.pathExtension
                var suffix = 1
                var finalURL = originalURL
                while true {
                    let candidateBase = suffix == 1 ? baseName : "\(baseName)_\(suffix)"
                    let candidateName = ext.isEmpty ? candidateBase : "\(candidateBase).\(ext)"
                    let candidateURL = originalURL.deletingLastPathComponent().appendingPathComponent(candidateName)
                    let candidatePath = candidateURL.path.lowercased()
                    let existsOutsideSelection = FileManager.default.fileExists(atPath: candidateURL.path) &&
                        !originalPathSet.contains(candidatePath)

                    if !existsOutsideSelection && plannedPathSet.insert(candidatePath).inserted {
                        finalURL = candidateURL
                        break
                    }
                    suffix += 1
                }
                mappings.append(FileRenameMapping(from: originalURL, to: finalURL))
            }

            DispatchQueue.main.async { [weak self] in
                self?.executeFileRenameMappingsAsync(
                    mappings,
                    actionName: NSLocalizedString("快速重命名", comment: "quick rename undo"),
                    locateTargets: [],
                    inPlaceFolderPath: curFolder
                )
            }
        }
        return true
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
