//
//  LargeImageView.swift
//  FlowVision
//

import Foundation
import Cocoa
import VisionKit
import AVKit

class LargeImageView: NSView {

    var imageView: CustomLargeImageView!
    
    var snapshotQueue = [NSView?]()
    var videoView: LargeAVPlayerView!
    // var videoPlayer: AVPlayer?
    var playerItem: AVPlayerItem?
    var queuePlayer: AVQueuePlayer?
    var playerLooper: AVPlayerLooper?
    var currentPlayingURL: URL?
    var snapshotTimer: DispatchSourceTimer?
    var playcontrolTimer: DispatchSourceTimer?
    var videoOrderId: Int = 0
    var pausedBySeek = false
    var lastVolumeForPauseRef: Float?
    var restorePlayPosition: CMTime?
    var restorePlayURL: URL?
    var isVideoMetadataUpdated: Bool = false
    var abPlayPositionA: CMTime?
    var abPlayPositionB: CMTime?
    var videoEndObserver: NSObjectProtocol?
    var lastActionTriggerdReload: String?
    var isKeyWindowWhenMouseDown: Bool = true
    
    private var blackOverlayView: NSView?
    
    var exifTextView: ExifTextView!
    var ratioView: InfoView!
    var infoView: InfoView!
    var unsupportedVideoOverlay: NSView!
    
    // MARK: - 图片编辑相关属性
    // MARK: - Image editing related properties
    var imageEditingView: ImageEditingView?
    var isInEditMode: Bool = false
    
    /// 同步编辑画布的位置和大小与 imageView 保持一致
    /// Sync editing canvas position and size with imageView
    func syncEditingCanvasFrame() {
        guard isInEditMode, let editingView = imageEditingView else { return }
        editingView.setImageFrame(imageView.frame)
    }
    
    var file: FileModel = FileModel(path: "", ver: 0)
    private var lastDragLocation: CGPoint?
    private var hasZoomedByWheel: Bool = false
    var longPressZoomTimer: Timer?
    private var wheelZoomRegenTimer: Timer?
    private var initialPos: NSPoint? = nil
    
    private var initialScale: CGFloat = 1.0
    private var originalSize: CGSize?
    private let sensitivity: CGFloat = 1
    
    private var lastClickTime: TimeInterval = 0
    private var lastClickLocation: NSPoint = NSPoint.zero
    // 双击位置阈值，可以根据需要调整
    // Double-click position threshold, can be adjusted as needed
    private let positionThreshold: CGFloat = 4.0
    
    private var middleMouseInitialLocation: NSPoint?
    
    private var doNotPopRightMenu: Bool = false
    
    var isInOcrState: Bool = false
    
    private var magnificationGesture: NSMagnificationGestureRecognizer?
    
    // 边缘切换箭头视图
    // Edge switching arrow views
    private var leftArrowImageView: NSImageView?
    private var rightArrowImageView: NSImageView?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        imageView = CustomLargeImageView(frame: self.bounds)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.animates=true
        self.addSubview(imageView)

        videoView = LargeAVPlayerView(frame: self.bounds)
        queuePlayer = AVQueuePlayer()
        videoView.player = queuePlayer
        videoView.controlsStyle = .none
        videoView.showsFullScreenToggleButton = false
        videoView.videoGravity = .resizeAspect
        videoView.isHidden = true
        self.addSubview(videoView)
//        if #available(macOS 13.0, *) {
//            videoView.allowsVideoFrameAnalysis = false
//        }
        
        exifTextView = ExifTextView(frame: .zero)
        exifTextView.translatesAutoresizingMaskIntoConstraints = false
        exifTextView.isHidden=true
        addSubview(exifTextView)
        NSLayoutConstraint.activate([
            exifTextView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
            exifTextView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5)
        ])
        
        ratioView = InfoView(frame: .zero)
        ratioView.setupView(fontSize: 14, fontWeight: .regular, cornerRadius: 6.0, edge: (8,8))
        ratioView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ratioView)
        NSLayoutConstraint.activate([
            ratioView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -15),
            ratioView.topAnchor.constraint(equalTo: self.topAnchor, constant: 15)
        ])
        
        infoView = InfoView(frame: .zero)
        infoView.setupView(fontSize: 20, fontWeight: .light, cornerRadius: 6.0, edge: (18,8))
        infoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoView)
        NSLayoutConstraint.activate([
            infoView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            infoView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        
        // 不支持的视频格式覆盖视图
        // Unsupported video format overlay view
        unsupportedVideoOverlay = NSView(frame: .zero)
        unsupportedVideoOverlay.wantsLayer = true
        unsupportedVideoOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        unsupportedVideoOverlay.layer?.cornerRadius = 10
        unsupportedVideoOverlay.translatesAutoresizingMaskIntoConstraints = false
        unsupportedVideoOverlay.isHidden = true
        addSubview(unsupportedVideoOverlay)
        
        let overlayLabel = NSTextField(labelWithString: NSLocalizedString("Unsupported Video Format", comment: "不支持的视频格式"))
        overlayLabel.textColor = .white
        overlayLabel.alignment = .center
        overlayLabel.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        overlayLabel.translatesAutoresizingMaskIntoConstraints = false
        unsupportedVideoOverlay.addSubview(overlayLabel)
        
        let openExternalView = ClickableLabel(
            title: NSLocalizedString("Open with External Player", comment: "使用外部播放器打开"),
            onClick: { [weak self] in self?.actOpenWithExternalPlayer() }
        )
        openExternalView.translatesAutoresizingMaskIntoConstraints = false
        unsupportedVideoOverlay.addSubview(openExternalView)
        
        NSLayoutConstraint.activate([
            unsupportedVideoOverlay.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            unsupportedVideoOverlay.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            
            overlayLabel.topAnchor.constraint(equalTo: unsupportedVideoOverlay.topAnchor, constant: 20),
            overlayLabel.centerXAnchor.constraint(equalTo: unsupportedVideoOverlay.centerXAnchor),
            overlayLabel.leadingAnchor.constraint(greaterThanOrEqualTo: unsupportedVideoOverlay.leadingAnchor, constant: 24),
            overlayLabel.trailingAnchor.constraint(lessThanOrEqualTo: unsupportedVideoOverlay.trailingAnchor, constant: -24),
            
            openExternalView.topAnchor.constraint(equalTo: overlayLabel.bottomAnchor, constant: 16),
            openExternalView.centerXAnchor.constraint(equalTo: unsupportedVideoOverlay.centerXAnchor),
            openExternalView.leadingAnchor.constraint(greaterThanOrEqualTo: unsupportedVideoOverlay.leadingAnchor, constant: 24),
            openExternalView.trailingAnchor.constraint(lessThanOrEqualTo: unsupportedVideoOverlay.trailingAnchor, constant: -24),
            openExternalView.bottomAnchor.constraint(equalTo: unsupportedVideoOverlay.bottomAnchor, constant: -20),
        ])
        
        magnificationGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        if let gesture = magnificationGesture {
            self.addGestureRecognizer(gesture)
        }
        
        // 创建边缘切换箭头视图
        // Create edge switching arrow views
        createEdgeArrowViews()
        
        // 设置鼠标跟踪
        // Set up mouse tracking
        setupMouseTracking()
        
        // 延迟更新箭头视图位置，确保视图已完全加载
        // Delay updating arrow view positions to ensure view is fully loaded
        DispatchQueue.main.async { [weak self] in
            self?.updateArrowViewPositions()
        }
    }
    
    func updateTextItems(_ items: [(String, Any)]) {
        exifTextView.textItems = items
        exifTextView.invalidateIntrinsicContentSize()
    }
    
    // MARK: - 边缘切换箭头视图
    // MARK: - Edge Switching Arrow Views
    
    private func createEdgeArrowViews() {
        // 定义箭头视图的样式
        // Define arrow view style
        let arrowBackgroundColor = NSColor.black.withAlphaComponent(0.2)
        let arrowBorderColor = NSColor.black.withAlphaComponent(0.3)
        let arrowTintColor = NSColor.black.withAlphaComponent(0.5)
        
        // 创建左侧箭头视图（尺寸由 updateArrowViewPositions 动态计算）
        // Create left arrow view (size calculated dynamically by updateArrowViewPositions)
        leftArrowImageView = NSImageView(frame: .zero)
        leftArrowImageView?.wantsLayer = true
        leftArrowImageView?.layer?.backgroundColor = arrowBackgroundColor.cgColor
        leftArrowImageView?.layer?.borderColor = arrowBorderColor.cgColor
        leftArrowImageView?.imageScaling = .scaleNone
        leftArrowImageView?.imageAlignment = .alignCenter
        leftArrowImageView?.contentTintColor = arrowTintColor
        leftArrowImageView?.alphaValue = 0
        leftArrowImageView?.isHidden = true
        
        // 创建右侧箭头视图（尺寸由 updateArrowViewPositions 动态计算）
        // Create right arrow view (size calculated dynamically by updateArrowViewPositions)
        rightArrowImageView = NSImageView(frame: .zero)
        rightArrowImageView?.wantsLayer = true
        rightArrowImageView?.layer?.backgroundColor = arrowBackgroundColor.cgColor
        rightArrowImageView?.layer?.borderColor = arrowBorderColor.cgColor
        rightArrowImageView?.imageScaling = .scaleNone
        rightArrowImageView?.imageAlignment = .alignCenter
        rightArrowImageView?.contentTintColor = arrowTintColor
        rightArrowImageView?.alphaValue = 0
        rightArrowImageView?.isHidden = true
        
        // 添加视图到视图，确保在最上层
        // Add views to view, ensure they are on top
        if let leftImageView = leftArrowImageView {
            addSubview(leftImageView, positioned: .above, relativeTo: nil)
        }
        if let rightImageView = rightArrowImageView {
            addSubview(rightImageView, positioned: .above, relativeTo: nil)
        }
    }
    
    private func updateArrowViewPositions() {
        // 基于视图短边按比例缩放，参考值900点（标准MacBook窗口高度）
        // Scale proportionally based on view's shorter side, reference: 900pt (standard MacBook window height)
        let referenceShortSide: CGFloat = 900
        let shortSide = min(bounds.width, bounds.height)
        let scaleFactor = max(shortSide / referenceShortSide, 0.75)
        
        let buttonSize = round(60 * scaleFactor)
        let margin = round(30 * scaleFactor)
        let cornerRadius = buttonSize / 2
        let borderWidth: CGFloat = max(1, round(scaleFactor))
        // 使用 SymbolConfiguration 控制 SF Symbol 实际渲染尺寸
        // Use SymbolConfiguration to control SF Symbol rendering size
        let symbolPointSize = round(20 * scaleFactor)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
        
        // 左侧箭头位置与尺寸
        // Left arrow position and size
        leftArrowImageView?.frame = NSRect(
            x: margin,
            y: (bounds.height - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )
        leftArrowImageView?.layer?.cornerRadius = cornerRadius
        leftArrowImageView?.layer?.borderWidth = borderWidth
        if let leftImage = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")?.withSymbolConfiguration(symbolConfig) {
            leftArrowImageView?.image = leftImage
        }
        
        // 右侧箭头位置与尺寸
        // Right arrow position and size
        rightArrowImageView?.frame = NSRect(
            x: bounds.width - margin - buttonSize,
            y: (bounds.height - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )
        rightArrowImageView?.layer?.cornerRadius = cornerRadius
        rightArrowImageView?.layer?.borderWidth = borderWidth
        if let rightImage = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")?.withSymbolConfiguration(symbolConfig) {
            rightArrowImageView?.image = rightImage
        }
    }
    
    private func showArrowView(_ imageView: NSImageView?, animated: Bool = true) {
        guard let imageView = imageView else { return }
        
        imageView.isHidden = false
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                imageView.animator().alphaValue = 1.0
            })
        } else {
            imageView.alphaValue = 1.0
        }
    }
    
    private func hideArrowView(_ imageView: NSImageView?, animated: Bool = true) {
        guard let imageView = imageView else { return }
        
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                imageView.animator().alphaValue = 0.0
            }) {
                imageView.isHidden = true
            }
        } else {
            imageView.alphaValue = 0.0
            imageView.isHidden = true
        }
    }
    
    private func checkMousePositionAndUpdateArrows() {
        // 获取当前鼠标位置
        // Get current mouse position
        guard let window = self.window else { return }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        
        let locationInView = self.convert(mouseLocation, from: nil)
        let viewWidth = self.bounds.width
        // 先按百分比计算
        // Calculate by percentage first
        var leftThreshold: CGFloat = viewWidth * 0.12
        var rightThreshold: CGFloat = viewWidth * 0.88
        
        // 限制最小最大阈值（按比例缩放，参考宽度1440点）
        // Limit min/max thresholds (proportionally scaled, reference width: 1440pt)
        let referenceWidth: CGFloat = 1440
        let widthScale = max(viewWidth / referenceWidth, 0.75)
        let minThreshold = round(100 * widthScale)
        let maxThreshold = round(200 * widthScale)
        leftThreshold = min(max(leftThreshold, minThreshold), maxThreshold)
        rightThreshold = max(min(rightThreshold, viewWidth - minThreshold), viewWidth - maxThreshold)
        
        // 检查是否在左侧区域
        // Check if in left area
        if locationInView.x <= leftThreshold && locationInView.x >= 0 {
            showArrowView(leftArrowImageView)
            hideArrowView(rightArrowImageView)
        }
        // 检查是否在右侧区域
        // Check if in right area
        else if locationInView.x >= rightThreshold && locationInView.x <= viewWidth {
            showArrowView(rightArrowImageView)
            hideArrowView(leftArrowImageView)
        }
        // 在中间区域，隐藏所有箭头
        // In middle area, hide all arrows
        else {
            hideArrowView(leftArrowImageView)
            hideArrowView(rightArrowImageView)
        }
    }
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        
        let newSize = self.bounds.size
        let imageViewSize = imageView.frame.size

        let deltaX = (newSize.width - oldSize.width) / 2
        let deltaY = (newSize.height - oldSize.height) / 2

        let newX = imageView.frame.origin.x + deltaX
        let newY = imageView.frame.origin.y + deltaY
        
        // 窗口变化时大图随缩放居中
        // Center large image when window size changes
        imageView.frame = CGRect(x: newX, y: newY, width: imageViewSize.width, height: imageViewSize.height)
        
        // 同步编辑画布位置
        // Sync editing canvas position
        syncEditingCanvasFrame()
        
        if file.type == .video {
            determineBlackBg()
        }
        
        // 更新箭头视图位置
        // Update arrow view positions
        updateArrowViewPositions()
        
        // 重新设置鼠标跟踪区域
        // Reset mouse tracking area
        self.trackingAreas.forEach { self.removeTrackingArea($0) }
        setupMouseTracking()
    }
    
    func pauseOrResumeVideo() {
        if let queuePlayer = queuePlayer {
            if queuePlayer.timeControlStatus == .playing {
                queuePlayer.pause()
            } else {
                queuePlayer.play()
            }
        }
    }
    
    func pauseVideo() {
        if let queuePlayer = queuePlayer {
            if queuePlayer.timeControlStatus == .playing {
                queuePlayer.pause()
            }
        }
    }
    
    func resumeVideo() {
        if let queuePlayer = queuePlayer {
            if queuePlayer.timeControlStatus == .paused {
                queuePlayer.play()
            }
        }
    }

    func specifyABPlayPositionA(){
        if let queuePlayer = queuePlayer {
            abPlayPositionA = queuePlayer.currentTime()
            if abPlayPositionA != nil && abPlayPositionB != nil {
                if CMTimeGetSeconds(abPlayPositionA!) > CMTimeGetSeconds(abPlayPositionB!) {
                    showInfo(NSLocalizedString("A-B Loop: A Greater than B", comment: "（视频）A-B循环：A点大于B点"))
                }else{
                    lastActionTriggerdReload = "ABPlay"
                    playVideo(reloadForAB: true)
                }
            } else {
                showInfo(NSLocalizedString("A-B Loop: A", comment: "（视频）A-B循环：A"))
            }
        }
    }

    func specifyABPlayPositionB(){
        if let queuePlayer = queuePlayer {
            abPlayPositionB = queuePlayer.currentTime()
            if abPlayPositionA != nil && abPlayPositionB != nil {
                if CMTimeGetSeconds(abPlayPositionA!) > CMTimeGetSeconds(abPlayPositionB!) {
                    showInfo(NSLocalizedString("A-B Loop: A Greater than B", comment: "（视频）A-B循环：A点大于B点"))
                }else{
                    lastActionTriggerdReload = "ABPlay"
                    playVideo(reloadForAB: true)
                }
            } else {
                showInfo(NSLocalizedString("A-B Loop: B", comment: "（视频）A-B循环：B"))
            }
        }
    }

    func specifyABPlayPositionAuto(){
        if file.type != .video {return}
        if let queuePlayer = queuePlayer {
            if abPlayPositionA == nil {
                specifyABPlayPositionA()
            } else if abPlayPositionB == nil {
                specifyABPlayPositionB()
            } else {
                playVideo(reload: true)
            }
        }
    }

    func saveCurrentPlayPosition(){
        if globalVar.videoPlayRememberPosition,
        let currentURL = currentPlayingURL,
           let currentTime = queuePlayer?.currentTime() {
            UserDefaults.standard.set(currentTime.seconds, forKey: "videoPosition_\(currentURL.absoluteString)")
        }
    }
    
    func stopVideo(savePosition: Bool = false){
        if globalVar.videoPlayRememberPosition {
            saveCurrentPlayPosition()
        }
        restorePlayPosition = savePosition ? queuePlayer?.currentTime() : nil
        restorePlayURL = savePosition ? currentPlayingURL : nil
        if !savePosition {
            abPlayPositionA = nil
            abPlayPositionB = nil
        }
        videoOrderId += 1
        videoView.isHidden = true
        hideUnsupportedVideoOverlay()
        if let observer = videoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            videoEndObserver = nil
        }
        playerLooper?.disableLooping()
        playerLooper = nil
        queuePlayer?.removeAllItems()
        playerItem = nil
        currentPlayingURL = nil
        pausedBySeek = false
        isVideoMetadataUpdated = false
        while snapshotQueue.count > 0{
            snapshotQueue.first??.removeFromSuperview()
            snapshotQueue.removeFirst()
        }
    }

    func playVideo(reload: Bool = false, reloadForAB: Bool = false) {
        hideUnsupportedVideoOverlay()
        
        if let url = URL(string: file.path) {
            // 检查当前播放的视频是否已经是目标视频
            // Check if currently playing video is already the target video
            if currentPlayingURL == url && !reload && !reloadForAB {
                return
            }

            if currentPlayingURL != url && globalVar.videoPlayRememberPosition {
                // 保存当前视频的播放进度
                // Save current video playback position
                saveCurrentPlayPosition()
                
                // 读取新视频的播放进度
                // Load new video playback position
                if let savedPosition = UserDefaults.standard.value(forKey: "videoPosition_\(url.absoluteString)") as? Double {
                    restorePlayPosition = CMTime(seconds: savedPosition, preferredTimescale: 1)
                    restorePlayURL = url
                }
            }
            
            // 快照
            // Snapshot
            if let snapshot = captureSnapshot(of: self) {
                self.addSubview(snapshot)
                snapshotQueue.append(snapshot)
            }
            
            if reload && abPlayPositionA != nil && abPlayPositionB != nil {
                showInfo(NSLocalizedString("A-B Loop Cancel", comment: "（视频）A-B循环取消"))
            }

            if reload || reloadForAB {
                restorePlayPosition = queuePlayer?.currentTime()
                restorePlayURL = currentPlayingURL
            }
            
            if let observer = videoEndObserver {
                NotificationCenter.default.removeObserver(observer)
                videoEndObserver = nil
            }
            playerLooper?.disableLooping()
            playerLooper = nil
            queuePlayer?.removeAllItems()
            playerItem = nil
            videoView.controlsStyle = .none
            videoOrderId += 1
            videoView.isHidden = false
            pausedBySeek = false
            isVideoMetadataUpdated = false
            if !reloadForAB {
                abPlayPositionA = nil
                abPlayPositionB = nil
            }
            
            // 读取元信息
            // Read metadata
            if getViewController(self)?.publicVar.isShowExif == true {
                updateVideoMetadata(url: url)
            }

            if let timeRange = getCommonTimeRange(url: url) {
                playerItem = AVPlayerItem(url: url)
                if let playerItem = playerItem,
                   let queuePlayer = queuePlayer {
                    
                    // 根据 file.rotate 设置视频旋转角度
                    // Set video rotation angle based on file.rotate
                    let rotation: Double
                    switch file.rotate {
                        case 1: rotation = 90
                        case 2: rotation = 180
                        case 3: rotation = 270
                        default: rotation = 0
                    }
                    
                    if rotation != 0,
                       let videoTrack = playerItem.asset.tracks(withMediaType: .video).first {
                        let composition = AVMutableVideoComposition()
                        composition.renderSize = rotation == 90 || rotation == 270 ?
                            CGSize(width: videoTrack.naturalSize.height, height: videoTrack.naturalSize.width) :
                            videoTrack.naturalSize
                        composition.frameDuration = CMTime(value: 1, timescale: 30)
                        
                        let instruction = AVMutableVideoCompositionInstruction()
                        instruction.timeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
                        
                        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                        var transform = CGAffineTransform.identity
                        
                        // 先平移再旋转，确保视频在正确位置
                        // Translate first then rotate to ensure video is in correct position
                        if rotation == 90 {
                            transform = transform.translatedBy(x: videoTrack.naturalSize.height, y: 0)
                            transform = transform.rotated(by: .pi/2)
                        } else if rotation == 270 {
                            transform = transform.translatedBy(x: 0, y: videoTrack.naturalSize.width)
                            transform = transform.rotated(by: -.pi/2)
                        } else if rotation == 180 {
                            transform = transform.translatedBy(x: videoTrack.naturalSize.width, y: videoTrack.naturalSize.height)
                            transform = transform.rotated(by: .pi)
                        }
                        
                        transformer.setTransform(transform, at: .zero)
                        instruction.layerInstructions = [transformer]
                        composition.instructions = [instruction]
                        
                        playerItem.videoComposition = composition
                    }

                    // 根据AB播放点计算最终的播放范围
                    // Calculate final playback range based on AB playback points
                    var finalTimeRange = timeRange
                    if let positionA = abPlayPositionA?.seconds,
                       let positionB = abPlayPositionB?.seconds,
                       positionA < positionB {
                        let start = CMTime(seconds: positionA, preferredTimescale: 600)
                        let duration = CMTime(seconds: positionB - positionA, preferredTimescale: 600)
                        finalTimeRange = CMTimeRange(start: start, duration: duration)
                    }
                    
                    queuePlayer.insert(playerItem, after: nil)
                    
                    if globalVar.videoPlaySequentialPlay && abPlayPositionA == nil && abPlayPositionB == nil {
                        // 列表播放模式：播放完当前视频后自动切换到下一个
                        // List play mode: automatically switch to next video after current one finishes
                        videoEndObserver = NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: playerItem,
                            queue: .main
                        ) { [weak self] _ in
                            guard let self = self else { return }
                            getViewController(self)?.nextLargeImage(isShowReachEndPrompt: true, firstShowThumb: true)
                        }
                    } else {
                        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem, timeRange: finalTimeRange)
                    }
                    
                    queuePlayer.play()
                    currentPlayingURL = url
                    
                    // 开始计时器检查 playerItem.status
                    // Start timer to check playerItem.status
                    checkPlayerItemStatus(id: videoOrderId)
                }
            }else{
                while snapshotQueue.count > 0{
                    snapshotQueue.first??.removeFromSuperview()
                    snapshotQueue.removeFirst()
                }
                currentPlayingURL = nil
                showUnsupportedVideoOverlay()
            }
        }
    }
    
    func updateVideoMetadata(url: URL?){
        if !isVideoMetadataUpdated,
           let url = url,
           let specificMetadata = getVideoMetadataFormatedFFmpeg(for: url) {
            let exifData = convertExifData(file: file)
            updateTextItems(formatExifData(exifData ?? [:], isVideo: true, needWarp: true) + [("-","-")] + specificMetadata)
            isVideoMetadataUpdated = true
        }
    }
    
    private func checkPlayerItemStatus(id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self = self, let playerItem = self.playerItem else { return }
            if id != videoOrderId { return }
            
            // log("playerItem.status: ", playerItem.status.rawValue)
            
            // if playerItem.status == .readyToPlay || playerItem.status == .failed {
            let targetTime: CMTime = CMTime(seconds: 0.01, preferredTimescale: 600)
            if queuePlayer?.currentTime() ?? CMTime.zero >= targetTime {
                
                // 恢复之前的进度
                // Restore previous progress
                if restorePlayPosition != nil,
                   restorePlayURL == currentPlayingURL {
                    queuePlayer?.seek(to: restorePlayPosition!, toleranceBefore: .zero, toleranceAfter: .zero)
                    restorePlayPosition = nil
                    restorePlayURL = nil
                    // 延迟隐藏快照
                    // Delay hiding snapshot
                    snapshotTimer?.cancel()
                    snapshotTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
                    snapshotTimer?.schedule(deadline: .now() + 0.1)
                    snapshotTimer?.setEventHandler { [weak self] in
                        guard let self = self else { return }
                        if id != videoOrderId { return }
                        while snapshotQueue.count > 0{
                            snapshotQueue.first??.removeFromSuperview()
                            snapshotQueue.removeFirst()
                        }
                        if abPlayPositionA != nil && abPlayPositionB != nil && lastActionTriggerdReload == "ABPlay" {
                            showInfo(NSLocalizedString("A-B Loop Active", comment: "（视频）A-B循环启用"))
                            lastActionTriggerdReload = nil
                        } else if lastActionTriggerdReload == "Rotate" {
                            showInfo(String(format: NSLocalizedString("Rotate %d°", comment: "（视频）旋转%d°"), file.rotate*90))
                            lastActionTriggerdReload = nil
                        }
                    }
                    snapshotTimer?.resume()
                } else {
                    // 立即隐藏快照
                    // Hide snapshot immediately
                    while snapshotQueue.count > 0{
                        snapshotQueue.first??.removeFromSuperview()
                        snapshotQueue.removeFirst()
                    }
                }
                
                // 显示控制
                // Show controls
                playcontrolTimer?.cancel()
                playcontrolTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
                playcontrolTimer?.schedule(deadline: .now() + 0.5)
                playcontrolTimer?.setEventHandler { [weak self] in
                    guard let self = self else { return }
                    if id != videoOrderId { return }
                    videoView.controlsStyle = .inline
                }
                playcontrolTimer?.resume()
            } else {
                // 如果还没有准备好，继续检查
                // If not ready yet, continue checking
                checkPlayerItemStatus(id: id)
            }
        }
    }

    func seekVideoByDrag(deltaX: CGFloat) {
        // 如果拖动距离小于2像素则忽略
        // Ignore if drag distance is less than 2 pixels
//        if abs(deltaX) < 2 {
//            return
//        }

        guard let player = queuePlayer else { 
            return 
        }
        
        // 获取视频总时长
        // Get total video duration
        guard let duration = player.currentItem?.duration else { 
            return 
        }
        
        // 计算实际可播放时长
        // Calculate actual playable duration
        var startTime: Double = 0
        var endTime = CMTimeGetSeconds(duration)
        
        // 如果设置了AB播放点,使用AB点之间的时长
        // If AB playback points are set, use duration between AB points
        if let positionA = abPlayPositionA,
           let positionB = abPlayPositionB,
           CMTimeGetSeconds(positionA) < CMTimeGetSeconds(positionB) {
            startTime = CMTimeGetSeconds(positionA)
            endTime = CMTimeGetSeconds(positionB)
        }
        
        let totalSeconds = endTime - startTime
        
        // 计算当前视图宽度对应的总秒数比例
        // Calculate total seconds ratio corresponding to current view width
        let pixelsPerSecond = self.frame.width / CGFloat(totalSeconds)
        
        // 根据拖动距离计算需要调整的秒数
        // Calculate seconds to adjust based on drag distance
        let seekSeconds = deltaX / pixelsPerSecond
        
        // 获取当前播放时间
        // Get current playback time
        let currentTime = player.currentTime()
        let currentSeconds = CMTimeGetSeconds(currentTime)
        
        // 计算目标时间,确保在有效范围内
        // Calculate target time, ensure within valid range
        var targetSeconds = currentSeconds + Double(seekSeconds)
        
        // 如果是AB播放,限制在AB点之间
        // If AB playback, limit between AB points
        if abPlayPositionA != nil && abPlayPositionB != nil,
           CMTimeGetSeconds(abPlayPositionA!) < CMTimeGetSeconds(abPlayPositionB!) {
            targetSeconds = max(startTime, min(endTime, targetSeconds))
        } else {
            targetSeconds = max(0, min(CMTimeGetSeconds(duration), targetSeconds))
        }
        
        // 暂停
        // Pause
        if player.timeControlStatus == .playing {
            pausedBySeek = true
            pauseVideo()
        }
        
        // 转换为CMTime并执行跳转
        let targetTime = CMTimeMakeWithSeconds(Float64(targetSeconds), preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekVideoByFrame(direction: Int) {
        guard let player = queuePlayer,
              let asset = player.currentItem?.asset else {
            return
        }
        
        // 获取视频帧率
        // Get video frame rate
        let tracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = tracks.first else { return }
        let frameRate = videoTrack.nominalFrameRate
        
        // 计算每帧的时长(秒)
        // Calculate duration per frame (in seconds)
        let frameDuration = 1.0 / Double(frameRate)
        
        // 根据方向决定前进还是后退一帧
        // Determine forward or backward one frame based on direction
        let seekDuration = direction > 0 ? frameDuration : -frameDuration
        
        // 暂停视频
        // Pause video
        pauseVideo()
        
        // 获取当前时间并计算目标时间
        // Get current time and calculate target time
        let currentTime = player.currentTime()
        let targetTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(seekDuration, preferredTimescale: 600))
        
        // 执行跳转
        // Perform seek
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // 显示帧信息
        // Display frame information
        // let currentFrame = Int(CMTimeGetSeconds(currentTime) * Double(frameRate))
        // showInfo("Frame: \(currentFrame)")
    }
    
    func seekVideo(direction: Int) {
        guard let player = queuePlayer,
              let duration = player.currentItem?.duration else {
            return
        }
        
        let totalSeconds = CMTimeGetSeconds(duration)
        let currentTime = player.currentTime()
        let currentSeconds = CMTimeGetSeconds(currentTime)
        
        // 计算目标时间,确保在有效范围内
        // Calculate target time, ensure within valid range
        let seekSeconds = totalSeconds < 30 ? 5.0 : 10.0
        var seconds = 0.0
        if direction == -1 {
            seconds = -seekSeconds
        } else if direction == 1 {
            seconds = seekSeconds
        }
        var targetSeconds = currentSeconds + seconds
        targetSeconds = max(0, min(totalSeconds, targetSeconds))
        
        // 转换为CMTime并执行跳转
        let targetTime = CMTimeMakeWithSeconds(Float64(targetSeconds), preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func seekVideoBySeconds(seconds: Double) {
        guard let player = queuePlayer,
              let duration = player.currentItem?.duration else {
            return
        }
        
        let totalSeconds = CMTimeGetSeconds(duration)
        let currentTime = player.currentTime()
        let currentSeconds = CMTimeGetSeconds(currentTime)
        
        // 计算目标时间,确保在有效范围内
        // Calculate target time, ensure within valid range
        var targetSeconds = currentSeconds + seconds
        targetSeconds = max(0, min(totalSeconds, targetSeconds))
        
        // 转换为CMTime并执行跳转
        // Convert to CMTime and perform seek
        let targetTime = CMTimeMakeWithSeconds(Float64(targetSeconds), preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func adjustVolume(by delta: Float) {
        guard let player = queuePlayer else { return }
        
        // 获取当前音量并计算新音量
        // Get current volume and calculate new volume
        var newVolume = round((player.volume + delta) * 100) / 100
        
        // 限制音量在0-1之间
        // Limit volume between 0-1
        newVolume = max(0, min(1.0, newVolume))
        
        // 设置新音量
        // Set new volume
        player.volume = newVolume
        
        // 显示音量信息
        // Display volume information
        let volumePercent = Int(newVolume * 100)
        showInfo(NSLocalizedString("Volume", comment: "音量") + ": \(volumePercent)%")
    }
    
    func increaseVolume() {
        adjustVolume(by: 0.1)
    }
    
    func decreaseVolume() {
        adjustVolume(by: -0.1)
    }
    
    func enableBlackBg() {
        if let effectView = getViewController(self)?.largeImageBgEffectView,
           blackOverlayView == nil {

            // 添加一个黑色的前景视图
            // Add a black foreground view
            let blackOverlayView = NSView(frame: effectView.bounds)
            blackOverlayView.wantsLayer = true
            blackOverlayView.layer?.backgroundColor = NSColor.black.cgColor
            
            // 保证前景视图在最前面显示
            // Ensure foreground view is displayed on top
            effectView.addSubview(blackOverlayView)
            blackOverlayView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                blackOverlayView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
                blackOverlayView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
                blackOverlayView.topAnchor.constraint(equalTo: effectView.topAnchor),
                blackOverlayView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
            ])
            
            // 保存对黑色覆盖视图的引用
            // Save reference to black overlay view
            self.blackOverlayView = blackOverlayView
        }
    }

    func disableBlackBg() {
        blackOverlayView?.removeFromSuperview()
        blackOverlayView = nil
    }
    
    func enableBlackBgForVideo() {
        videoView.frame = self.frame
    }
    
    func disableBlackBgForVideo() {
        let originalSize = file.originalSize ?? imageView.frame.size
        let zoomFrame = AVMakeRect(aspectRatio: originalSize, insideRect: self.frame)
        videoView.frame = NSRect(x: round(zoomFrame.origin.x), y: round(zoomFrame.origin.y), width: round(zoomFrame.width), height: round(zoomFrame.height))
    }
    
    func determineBlackBg() {
        if file.type == .video {
            disableBlackBg()
            
            if let window = self.window,
               window.styleMask.contains(.fullScreen) {
                if globalVar.blackBgInFullScreenForVideo || globalVar.blackBgAlwaysForVideo {
                    enableBlackBgForVideo()
                } else {
                    disableBlackBgForVideo()
                }
            } else {
                if globalVar.blackBgAlwaysForVideo {
                    enableBlackBgForVideo()
                } else {
                    disableBlackBgForVideo()
                }
            }
            
        } else {
            if let window = self.window,
               window.styleMask.contains(.fullScreen) {
                if globalVar.blackBgInFullScreen || globalVar.blackBgAlways {
                    enableBlackBg()
                } else {
                    disableBlackBg()
                }
            } else {
                if globalVar.blackBgAlways {
                    enableBlackBg()
                } else {
                    disableBlackBg()
                }
            }
        }
    }
    
    func zoom(direction: Int = 0){
        if file.type == .video {return}
        
        // guard let originalSize = getViewController(self)?.getCurrentImageOriginalSizeInScreenScale() else { return }
        // let currentSize = imageView.bounds.size
//        var scale = 1.0
//        if direction == -1 {
//            scale = 0.8
//        }else if direction == +1 {
//            scale = 1.25
//        }
        // applyZoom(scale: scale, originalSize: currentSize, centerPoint: CGPoint(x: imageView.bounds.size.width/2, y: imageView.bounds.size.height/2))
        
        let zoomFactor: CGFloat = 1.25
        let locationInView = self.convert(NSPoint(x: self.frame.size.width / 2, y: self.frame.size.height / 2), from: nil)
        let locationInImageView = imageView.convert(locationInView, from: self)
        
        if direction > 0 {
            if isExceedZoomLimit(enlarge: true, width: imageView.frame.size.width, height: imageView.frame.size.height){
                return
            }
            hasZoomedByWheel=true
            
            imageView.frame.size.width *= zoomFactor
            imageView.frame.size.height *= zoomFactor
            imageView.frame.origin.x -= (locationInImageView.x * (zoomFactor - 1))
            imageView.frame.origin.y -= (locationInImageView.y * (zoomFactor - 1))
        } else if direction < 0 {
            if isExceedZoomLimit(enlarge: false, width: imageView.frame.size.width, height: imageView.frame.size.height){
                return
            }
            hasZoomedByWheel=true
            
            imageView.frame.size.width /= zoomFactor
            imageView.frame.size.height /= zoomFactor
            imageView.frame.origin.x += (locationInImageView.x * (1 - 1/zoomFactor))
            imageView.frame.origin.y += (locationInImageView.y * (1 - 1/zoomFactor))
        }
        
        // 同步编辑画布位置和大小
        // Sync editing canvas position and size
        syncEditingCanvasFrame()
        
        // 重新绘制图像
        // Redraw image
        getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false, isByZoom: true)
        
        calcRatio(isShowPrompt: true)
    }

    func zoomFit() {
        if file.type == .image {
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: true, isByZoom: true)
            
            // 同步编辑画布位置和大小
            // Sync editing canvas position and size
            syncEditingCanvasFrame()
            
            calcRatio(isShowPrompt: true)
        }
    }
    
    func zoom100(point _point: NSPoint? = nil) {
        if file.type == .image{
            let point = _point ?? NSPoint(x: self.frame.size.width / 2, y: self.frame.size.height / 2)
            let zoomSize=customZoomSize()
            let locationInView = self.convert(point, from: nil)
            let locationInImageView = imageView.convert(locationInView, from: self)
            
            let zoomFactorWidth = zoomSize.width / imageView.frame.width
            let zoomFactorHeight = zoomSize.height / imageView.frame.height
            
            imageView.frame.size = zoomSize
            imageView.frame.origin.x -= (locationInImageView.x * (zoomFactorWidth - 1))
            imageView.frame.origin.y -= (locationInImageView.y * (zoomFactorHeight - 1))
            
            // 同步编辑画布位置和大小
            // Sync editing canvas position and size
            syncEditingCanvasFrame()
            
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: true, isByZoom: true)
            calcRatio(isShowPrompt: true)
        }
    }
    
    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        if file.type == .video {return}
        
        let magnification = 1 + gesture.magnification * sensitivity
        
        switch gesture.state {
        case .began:
            initialScale = imageView.frame.width / imageView.bounds.width
            originalSize = imageView.bounds.size
        case .changed:
            if let originalSize = originalSize {
                let scale = initialScale * magnification
                applyZoom(scale: scale, originalSize: originalSize, centerPoint: gesture.location(in: imageView))
            }
        case .ended:
            initialScale *= magnification
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false, isByZoom: true)
        default:
            break
        }
        
        // 缩放后防止意外滚动
        // Prevent accidental scrolling after zoom
        _ = getViewController(self)?.publicVar.timer.intervalSafe(name: "largeImageZoomForbidSwitch", second: -1)
    }
    
    private func applyZoom(scale: CGFloat, originalSize: CGSize, centerPoint: CGPoint) {
        let newWidth = originalSize.width * scale
        let newHeight = originalSize.height * scale
        
        if scale>1{
            if isExceedZoomLimit(enlarge: true, width: newWidth, height: newHeight){
                return
            }
        }else{
            if isExceedZoomLimit(enlarge: false, width: newWidth, height: newHeight){
                return
            }
        }
        
        
        let deltaWidth = newWidth - imageView.frame.width
        let deltaHeight = newHeight - imageView.frame.height
        
        let newOriginX = imageView.frame.origin.x - deltaWidth * (centerPoint.x / imageView.frame.width)
        let newOriginY = imageView.frame.origin.y - deltaHeight * (centerPoint.y / imageView.frame.height)
        
        imageView.frame = CGRect(x: newOriginX, y: newOriginY, width: newWidth, height: newHeight)
        
        // 同步编辑画布位置和大小
        // Sync editing canvas position and size
        syncEditingCanvasFrame()
        
        calcRatio(isShowPrompt: true)
    }
    
    func calcRatio(isShowPrompt: Bool) {
        let ratio = imageView.frame.size.width/customZoomSize().width
        getViewController(self)!.publicVar.zoomLock = ratio
        
        if isShowPrompt {
            let text = String(Int(ratio*100))
            ratioView.showInfo(text: NSLocalizedString("Zoom", comment: "缩放")+": "+text+"%")
        }
    }
    
    func showInfo(_ info: String, timeOut: Double = 1.0) {
        infoView.showInfo(text: info, timeOut: timeOut)
    }
    
    func showUnsupportedVideoOverlay() {
        unsupportedVideoOverlay.isHidden = false
    }
    
    func hideUnsupportedVideoOverlay() {
        unsupportedVideoOverlay.isHidden = true
    }
    
    @objc func actOpenWithExternalPlayer() {
        guard let url = URL(string: file.path) else { return }
        NSWorkspace.shared.open(url)
    }
    
    func getCurrentImageOriginalSizeInScreenScale() -> NSSize? {
        var result: NSSize?
        if let originalSize=file.originalSize{
            // 判断是否Retina，NSScreen.main是当前具有键盘焦点的屏幕，通常是用户正在与之交互的屏幕
            // Determine if Retina, NSScreen.main is the screen with keyboard focus, usually the screen user is interacting with
            let scale = NSScreen.main?.backingScaleFactor ?? 1
            result=NSSize(width: originalSize.width/scale, height: originalSize.height/scale)
            if file.rotate%2 == 1 {
                result=NSSize(width: originalSize.height/scale, height: originalSize.width/scale)
            }
        }
        return result
    }
    
    func customZoomSize() -> NSSize {
        // 返回您希望的缩放大小
        // Return desired zoom size
        if let result=getCurrentImageOriginalSizeInScreenScale(){
            return result
        }
        return NSSize(width: imageView.frame.width * 2, height: imageView.frame.height * 2)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        
        // 鼠标离开视图，隐藏箭头
        // Mouse left view, hide arrows
        hideArrowView(leftArrowImageView)
        hideArrowView(rightArrowImageView)
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        
        // 只在启用边缘切换功能且在大图模式下才处理
        // Only process when edge switching is enabled and in large image mode
        guard globalVar.clickEdgeToSwitchImage,
              let viewController = getViewController(self),
              viewController.publicVar.isInLargeView,
              !isInEditMode else {
            return
        }
        
        checkMousePositionAndUpdateArrows()
    }
    
    private func setupMouseTracking() {
        // 设置鼠标跟踪区域，包含mouseMoved事件
        // Set up mouse tracking area, including mouseMoved events
        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }
    
    override func mouseDown(with event: NSEvent) {
        // 临时按住左键也能缩放
        // Temporarily hold left button to enable zoom
        getViewController(self)!.publicVar.isLeftMouseDown = true
        
        isKeyWindowWhenMouseDown = self.window?.isKeyWindow ?? true
        
        // 通过音量记录来标识是否完整点击事件，而且避免点击音量条时触发暂停
        // Use volume record to identify complete click event and avoid triggering pause when clicking volume bar
        if !(getViewController(self)!.publicVar.isRightMouseDown),
           file.type == .video,
           let player = queuePlayer {
            lastVolumeForPauseRef = player.volume
        }

        // 检测点击左侧、右侧区域来切换图像
        // Detect clicks on left/right areas to switch images
        if globalVar.clickEdgeToSwitchImage && !(getViewController(self)!.publicVar.isRightMouseDown) {
            let clickLocation = self.convert(event.locationInWindow, from: nil)
            let viewWidth = self.bounds.width
            // 先按百分比计算
            var leftThreshold: CGFloat = viewWidth * 0.15
            var rightThreshold: CGFloat = viewWidth * 0.85
            
            // 限制最小最大阈值
            leftThreshold = min(max(leftThreshold, 100), 200)
            rightThreshold = max(min(rightThreshold, viewWidth - 100), viewWidth - 200)
            
            if clickLocation.x <= leftThreshold {
                // 点击左侧，切换到上一张图像
                // Click left side, switch to previous image
                if leftArrowImageView?.isHidden == false {
                    getViewController(self)?.previousLargeImage()
                    return
                }
            } else if clickLocation.x >= rightThreshold {
                // 点击右侧，切换到下一张图像
                // Click right side, switch to next image
                if rightArrowImageView?.isHidden == false {
                    getViewController(self)?.nextLargeImage()
                    return
                }
            }
        }
        
        // 检测双击
        // Detect double click
        if !(getViewController(self)!.publicVar.isRightMouseDown) {
            let currentTime = event.timestamp
            let currentLocation = event.locationInWindow
            if currentTime - lastClickTime < NSEvent.doubleClickInterval,
               distanceBetweenPoints(lastClickLocation, currentLocation) < positionThreshold {
                getViewController(self)?.closeLargeImage(0)
                lastVolumeForPauseRef = nil
            }
            lastClickTime = currentTime
            lastClickLocation = currentLocation
        }
        
        // 如果是OCR则不执行后面操作
        // If in OCR state, do not execute subsequent operations
        if isInOcrState && !getViewController(self)!.publicVar.isRightMouseDown {return}
        
        initialPos =  self.convert(event.locationInWindow, from: nil)
        lastDragLocation = initialPos
        doNotPopRightMenu = false
        
        // 设置定时器实现长按检测
        // Set timer to implement long press detection
        // 先取消之前的定时器，避免重复添加
        // Cancel previous timer first to avoid duplicate addition
        longPressZoomTimer?.invalidate()
        longPressZoomTimer = nil
        
        longPressZoomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.performLongPressZoom(at: event.locationInWindow)
        }
        // 确保定时器在所有 RunLoop 模式下都能运行
        // Ensure timer runs in all RunLoop modes
        RunLoop.current.add(longPressZoomTimer!, forMode: .common)
        
        super.mouseDown(with: event)
    }

    private func performLongPressZoom(at point: NSPoint) {
        
        doNotPopRightMenu=true
        
        if !getViewController(self)!.publicVar.isInLargeView || !getViewController(self)!.publicVar.isInLargeViewAfterAnimate {
            // 由于在大图状态下双击关闭又快速连击，会导致此处被异常调用，所以加以限制
            // Due to double-click close and rapid consecutive clicks in large image state, this may be abnormally called, so add restriction
            return
        }
        
        if file.type == .image {
            
            if !getViewController(self)!.publicVar.isRightMouseDown {
                zoom100(point: point)
            }else{
                zoomFit()
            }
            
            // hasZoomed=true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        // 临时按住左键也能缩放
        // Temporarily hold left button to enable zoom
        getViewController(self)!.publicVar.isLeftMouseDown = false
        initialPos=nil
        longPressZoomTimer?.invalidate()
        longPressZoomTimer = nil
        wheelZoomRegenTimer?.invalidate()
        wheelZoomRegenTimer = nil
        
        if hasZoomedByWheel {
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false)
        }
        hasZoomedByWheel=false
        
        if pausedBySeek {
            resumeVideo()
            pausedBySeek = false
        }

        // 暂停/恢复视频
        // Pause/resume video
        if !(getViewController(self)!.publicVar.isRightMouseDown) && isKeyWindowWhenMouseDown {
            let currentLocation = event.locationInWindow
            if distanceBetweenPoints(lastClickLocation, currentLocation) < positionThreshold {
                if file.type == .video,let player = queuePlayer,
                   lastVolumeForPauseRef == player.volume {
                    pauseOrResumeVideo()
                    lastVolumeForPauseRef = nil
                }
            }
        }

        super.mouseUp(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let lastLocation = lastDragLocation else { return }
        if isInOcrState && !getViewController(self)!.publicVar.isRightMouseDown {return}
        
        let newLocation = self.convert(event.locationInWindow, from: nil)
        if initialPos != nil{
            if abs(initialPos!.x-newLocation.x) + abs(initialPos!.y-newLocation.y) > 2 {
                longPressZoomTimer?.invalidate()
                longPressZoomTimer = nil
                doNotPopRightMenu = true
            }
            
            let dx = newLocation.x - lastLocation.x
            let dy = newLocation.y - lastLocation.y

            if file.type == .image {
                imageView.frame.origin.x += dx
                imageView.frame.origin.y += dy
                
                // 限制图片不能完全移出视野范围
                // Limit image from being completely moved out of view
                let imageFrame = imageView.frame
                let viewFrame = self.frame
                
                // 检查是否完全超出视野
                // Check if completely out of view
                if imageFrame.maxX < 0 {
                    imageView.frame.origin.x = -imageFrame.width
                }
                if imageFrame.minX > viewFrame.width {
                    imageView.frame.origin.x = viewFrame.width
                }
                if imageFrame.maxY < 0 {
                    imageView.frame.origin.y = -imageFrame.height
                }
                if imageFrame.minY > viewFrame.height {
                    imageView.frame.origin.y = viewFrame.height
                }
                
                // 同步编辑画布位置
                // Sync editing canvas position
                syncEditingCanvasFrame()
            } else if file.type == .video {
                if getViewController(self)!.publicVar.isRightMouseDown {
                    seekVideoByDrag(deltaX: dx)
                }
            }
        }

        lastDragLocation = newLocation
    }
    
    override func otherMouseDown(with event: NSEvent) {
        // 检查是否按下了鼠标中键
        // Check if middle mouse button is pressed
        if event.buttonNumber == 2 {
            middleMouseInitialLocation = event.locationInWindow
        } else {
            super.otherMouseDown(with: event)
        }
    }
    
    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == 2, let middleMouseInitialLocation = middleMouseInitialLocation {
            let newLocation = event.locationInWindow
            let deltaX = newLocation.x - middleMouseInitialLocation.x
            let deltaY = newLocation.y - middleMouseInitialLocation.y
            
            if let window = self.window {
                var frame = window.frame
                frame.origin.x += deltaX
                frame.origin.y += deltaY
                window.setFrame(frame, display: true)
            }
        } else {
            super.otherMouseDragged(with: event)
        }
    }
    
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            middleMouseInitialLocation = nil
        } else {
            super.otherMouseUp(with: event)
        }
    }
    
    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        getViewController(self)!.publicVar.isRightMouseDown = true
        mouseDown(with: event)
        // super.rightMouseDown(with: event)  // 继续传递事件
    }

    override func rightMouseUp(with event: NSEvent) {
        getViewController(self)!.publicVar.isRightMouseDown = false
        mouseUp(with: event)
        
        if !doNotPopRightMenu && event.locationInWindow.y < getViewController(self)!.mainScrollView.bounds.height {
            // 弹出菜单
            // Pop up menu
            let menu = NSMenu(title: "Custom Menu")
            menu.autoenablesItems = false
            
            let actionItemClose = menu.addItem(withTitle: NSLocalizedString("Close (Double Click)", comment: "关闭 (双击)"), action: #selector(actClose), keyEquivalent: "\u{1b}")
            actionItemClose.keyEquivalentModifierMask = []
            
            let actionItemOpenInNewTab = menu.addItem(withTitle: NSLocalizedString("Open in New Tab", comment: "在新标签页中打开"), action: #selector(actOpenInNewTab), keyEquivalent: "")
            if isWindowNumMax() {
                actionItemOpenInNewTab.isEnabled=false
            }else{
                actionItemOpenInNewTab.isEnabled=true
            }
            
            menu.addItem(NSMenuItem.separator())
            
            if URL(string: file.path)!.hasDirectoryPath == false {
                addOpenWithSubMenu(to: menu, for: URL(string: file.path)!)
            }
            
            menu.addItem(withTitle: NSLocalizedString("Show in Finder", comment: "在Finder中显示"), action: #selector(actShowInFinder), keyEquivalent: "")
            
            let actionItemRename = menu.addItem(withTitle: NSLocalizedString("Rename", comment: "重命名"), action: #selector(actRename), keyEquivalent: "r")
            actionItemRename.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemDelete = menu.addItem(withTitle: NSLocalizedString("Move to Trash", comment: "移动到废纸篓"), action: #selector(actDelete), keyEquivalent: "\u{8}")
            actionItemDelete.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemCopy = menu.addItem(withTitle: NSLocalizedString("Copy", comment: "复制"), action: #selector(actCopy), keyEquivalent: "c")

            let actionItemCopyPath = menu.addItem(withTitle: NSLocalizedString("Copy Path", comment: "复制路径"), action: #selector(actCopyPath), keyEquivalent: "")
            
            let actionItemShare = menu.addItem(withTitle: NSLocalizedString("Share...", comment: "共享..."), action: #selector(actShare(_:)), keyEquivalent: "")
            
            menu.addItem(NSMenuItem.separator())
                        
            let actionItemCopyToDownload = menu.addItem(withTitle: NSLocalizedString("copy-to-download", comment: "复制到\"下载\"文件夹"), action: #selector(actCopyToDownload), keyEquivalent: "n")
            actionItemCopyToDownload.keyEquivalentModifierMask = []
            
            let actionItemMoveToDownload = menu.addItem(withTitle: NSLocalizedString("move-to-download", comment: "移动到\"下载\"文件夹"), action: #selector(actMoveToDownload), keyEquivalent: "m")
            actionItemMoveToDownload.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            var textForExif = NSLocalizedString("Show Exif", comment: "显示Exif信息")
            if file.type == .video {
                textForExif = NSLocalizedString("Show Video Metadata", comment: "显示视频元数据")
            }
            let actionItemShowExif = menu.addItem(withTitle: textForExif, action: #selector(actShowExif), keyEquivalent: "i")
            actionItemShowExif.keyEquivalentModifierMask = []
            actionItemShowExif.state = getViewController(self)!.publicVar.isShowExif ? .on : .off
            
            if file.type == .image {
                let actionItemOCR = menu.addItem(withTitle: NSLocalizedString("recognize-OCR", comment: "识别文本"), action: #selector(actOCR), keyEquivalent: "o")
                actionItemOCR.keyEquivalentModifierMask = []
            
                let actionItemQRCode = menu.addItem(withTitle: NSLocalizedString("recognize-QRCode", comment: "识别二维码"), action: #selector(actQRCode), keyEquivalent: "p")
                actionItemQRCode.keyEquivalentModifierMask = []
            } else if file.type == .video {
                let actionItemRememberPosition = menu.addItem(withTitle: NSLocalizedString("Remember Position", comment: "（视频）记忆位置"), action: #selector(actRememberPlayPosition), keyEquivalent: "k")
                actionItemRememberPosition.keyEquivalentModifierMask = []
                actionItemRememberPosition.state = globalVar.videoPlayRememberPosition ? .on : .off

                let actionItemABPlay = menu.addItem(withTitle: NSLocalizedString("A-B Loop", comment: "（视频）A-B循环"), action: #selector(actABPlay), keyEquivalent: "l")
                actionItemABPlay.keyEquivalentModifierMask = []
                if let positionA = abPlayPositionA?.seconds,
                       let positionB = abPlayPositionB?.seconds,
                       positionA < positionB {
                    actionItemABPlay.state = .on
                } else {
                    actionItemABPlay.state = .off
                }
                
                let actionItemSequentialPlay = menu.addItem(withTitle: NSLocalizedString("Sequential Playback", comment: "（视频）顺序播放"), action: #selector(actSequentialPlay), keyEquivalent: "")
                actionItemSequentialPlay.state = globalVar.videoPlaySequentialPlay ? .on : .off
            }

            menu.addItem(NSMenuItem.separator())
            
            let actionItemRotateR = menu.addItem(withTitle: NSLocalizedString("Rotate Clockwise", comment: "顺时针旋转"), action: #selector(actRotateR), keyEquivalent: "e")
            actionItemRotateR.keyEquivalentModifierMask = []
            
            let actionItemRotateL = menu.addItem(withTitle: NSLocalizedString("Rotate Counterclockwise", comment: "逆时针旋转"), action: #selector(actRotateL), keyEquivalent: "q")
            actionItemRotateL.keyEquivalentModifierMask = []

            if file.type == .image {
                // 镜像图像
                // Mirror image
                let actionItemMirrorH = menu.addItem(withTitle: NSLocalizedString("Mirror Flip", comment: "镜像翻转"), action: #selector(actMirrorH), keyEquivalent: "f")
                actionItemMirrorH.keyEquivalentModifierMask = []
                actionItemMirrorH.state = imageView.isMirroredH ? .on : .off
            }
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemRefresh = menu.addItem(withTitle: NSLocalizedString("Refresh", comment: "刷新"), action: #selector(actRefresh), keyEquivalent: "r")
            actionItemRefresh.keyEquivalentModifierMask = [.command]
            
            menu.items.forEach { $0.target = self }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        
        // super.rightMouseDragged(with: event)  // 继续传递事件
    }
    
    override func scrollWheel(with event: NSEvent) {
        // 保证鼠标在图像上才缩放
        // Only zoom when mouse is on image
        // guard imageView.frame.contains(event.locationInWindow) else { return }
        
        // 注意：触控板按下右键的同时会触发deltaY为0的滚动事件
        // Note: Pressing right button on trackpad simultaneously triggers scroll event with deltaY=0
        if abs(event.deltaY) > 0 {
            longPressZoomTimer?.invalidate()
            longPressZoomTimer = nil
            doNotPopRightMenu=true
        }

        if getViewController(self)!.publicVar.isRightMouseDown || getViewController(self)!.publicVar.isLeftMouseDown || globalVar.scrollMouseWheelToZoom || isCommandKeyPressed() {
            
            do {
                wheelZoomRegenTimer?.invalidate()
                wheelZoomRegenTimer = nil
                wheelZoomRegenTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    guard let self=self else{return}
                    getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false, isByZoom: true)
                    hasZoomedByWheel=false
                }
            }

            let zoomFactor: CGFloat = 1.0 + (0.1 * globalVar.scrollSensitivityRatio)
            let locationInView = self.convert(event.locationInWindow, from: nil)
            let locationInImageView = imageView.convert(locationInView, from: self)
            
            if event.deltaY > 0 {
                if isExceedZoomLimit(enlarge: true, width: imageView.frame.size.width, height: imageView.frame.size.height){
                    return
                }
                hasZoomedByWheel=true
                
                imageView.frame.size.width *= zoomFactor
                imageView.frame.size.height *= zoomFactor
                imageView.frame.origin.x -= (locationInImageView.x * (zoomFactor - 1))
                imageView.frame.origin.y -= (locationInImageView.y * (zoomFactor - 1))
            } else if event.deltaY < 0 {
                if isExceedZoomLimit(enlarge: false, width: imageView.frame.size.width, height: imageView.frame.size.height){
                    return
                }
                hasZoomedByWheel=true
                
                imageView.frame.size.width /= zoomFactor
                imageView.frame.size.height /= zoomFactor
                imageView.frame.origin.x += (locationInImageView.x * (1 - 1/zoomFactor))
                imageView.frame.origin.y += (locationInImageView.y * (1 - 1/zoomFactor))
            }
            // log(imageView.frame.size,imageView.frame.origin)
            
            // 同步编辑画布位置和大小
            // Sync editing canvas position and size
            syncEditingCanvasFrame()
            
            if abs(event.deltaY) > 0 {
                calcRatio(isShowPrompt: true)
            }
        }
    }
    
    func isExceedZoomLimit(enlarge: Bool, width: Double, height: Double) -> Bool {
        guard let originalSize = getCurrentImageOriginalSizeInScreenScale() else { return false }
        
//        if enlarge && width>originalSize.width && (min(width,height) > 20000) {
//            return true
//        }
//        if !enlarge && width<originalSize.width && (max(width,height) < 200) {
//            return true
//        }
        
        if enlarge && width>originalSize.width * 10 {
            return true
        }
        if !enlarge && width<originalSize.width/2 && (max(width,height) < 200)  {
            return true
        }
        
        return false
    }
    
    func addOpenWithSubMenu(to menu: NSMenu, for fileUrl: URL) {
        let openWithMenu = NSMenu(title: "openWith")
        let openWithMenuItem = NSMenuItem(title: NSLocalizedString("Open With", comment: "打开方式"), action: nil, keyEquivalent: "")
        openWithMenuItem.submenu = openWithMenu
        
        // 获取可以打开文件的应用程序列表
        // Get list of applications that can open the file
        let cfFileUrl = fileUrl as CFURL
        let appURLs = LSCopyApplicationURLsForURL(cfFileUrl, .all)?.takeRetainedValue() as? [URL] ?? []
        
        for appURL in appURLs {
            let appName = FileManager.default.displayName(atPath: appURL.path)
            let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            let appMenuItem = NSMenuItem(title: appName.replacingOccurrences(of: ".app", with: " "), action: #selector(openFileWithApp(_:)), keyEquivalent: "")
            appMenuItem.representedObject = appURL
            appMenuItem.target = self
            appMenuItem.image = appIcon
            appMenuItem.image?.size = NSSize(width: 16, height: 16)  // Optionally resize the icon if needed
            openWithMenu.addItem(appMenuItem)
        }
        
        // 添加到主菜单
        // Add to main menu
        menu.addItem(openWithMenuItem)
    }
    
    @objc func openFileWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL, let fileUrl = URL(string: file.path)
            else { return }
        
        NSWorkspace.shared.open([fileUrl], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: { (app, error) in
            if let error = error {
                log("Error opening file: \(error.localizedDescription)")
            } else if let app = app {
                log("Application \(app.localizedName ?? "Unknown") opened")
            }
        })
    }
    
    @objc func actOpenInNewTab() {
        if let appDelegate=NSApplication.shared.delegate as? AppDelegate {
            globalVar.isLaunchFromFile=true
            if let windowController = appDelegate.createNewWindow(file.path) {
                appDelegate.openImageInTargetWindow(file.path, windowController: windowController)
            }
        }
    }
    
    @objc func actShowInFinder() {
        let folderPath = (file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding! as NSString).deletingLastPathComponent
        // 使用NSWorkspace的实例来显示文件
        // Use NSWorkspace instance to show file
        NSWorkspace.shared.selectFile(file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!, inFileViewerRootedAtPath: folderPath)
    }
    @objc func actRename() {
        renameAlert(urls: [URL(string: file.path)!]);
    }
    
    @objc func actCopy() {
        if isInOcrState {
            if let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: #selector(NSText.copy(_:))) {
                responder.perform(#selector(NSText.copy(_:)), with: nil)
            }
        }else if file.type == .video,
                 let responder = self.window?.firstResponder,
                 responder.responds(to: #selector(NSText.copy(_:))) {
            responder.perform(#selector(NSText.copy(_:)), with: nil)
        }else{
            getViewController(self)?.handleCopy()
        }
    }
    
    @objc func actCopyToDownload() {
        getViewController(self)?.handleCopyToDownload()
    }
    
    @objc func actMoveToDownload() {
        getViewController(self)?.handleMoveToDownload()
    }

    @objc func actCopyPath() {
        guard let url=URL(string: file.path) else{return}
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    @objc func actDelete() {
        getViewController(self)?.handleDelete(isShowPrompt: false)
    }
    
    @objc func actRefresh() {
        // file.rotate = 0
        LargeImageProcessor.clearCache()
        getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false, forceRefresh: true)
    }
    
    @objc func actShowExif() {
        getViewController(self)!.publicVar.isShowExif.toggle()
        if file.type == .video,
           getViewController(self)!.publicVar.isShowExif {
            updateVideoMetadata(url: URL(string: file.path))
        }
        // exifTextView.isHidden = !getViewController(self)!.publicVar.isShowExif
    }
    
    @objc func actShowVideoMetadata() {
        getViewController(self)?.handleGetInfo()
    }

    @objc func actABPlay() {
        specifyABPlayPositionAuto()
    }

    @objc func actRememberPlayPosition() {
        globalVar.videoPlayRememberPosition.toggle()
        UserDefaults.standard.set(globalVar.videoPlayRememberPosition, forKey: "videoPlayRememberPosition")
        if globalVar.videoPlayRememberPosition {
            showInfo(NSLocalizedString("Remember Position: Enabled", comment: "（视频）记忆位置启用"))
        } else {
            showInfo(NSLocalizedString("Remember Position: Disabled", comment: "（视频）记忆位置禁用"))
        }
    }
    
    @objc func actSequentialPlay() {
        globalVar.videoPlaySequentialPlay.toggle()
        UserDefaults.standard.set(globalVar.videoPlaySequentialPlay, forKey: "videoPlaySequentialPlay")
        if globalVar.videoPlaySequentialPlay {
            showInfo(NSLocalizedString("Sequential Playback: Enabled", comment: "（视频）顺序播放启用"))
        } else {
            showInfo(NSLocalizedString("Sequential Playback: Disabled", comment: "（视频）顺序播放禁用"))
        }
        // 重新加载当前视频以应用新的播放模式
        // Reload current video to apply new playback mode
        playVideo(reload: true)
    }
    
    @objc func actQRCode() {
        if file.type == .video {return}
        if let image=file.image,
           let qrCodes = recognizeQRCode(from: image) {
            let text=qrCodes.joined(separator: "\n")
            showInformationCopy(title: NSLocalizedString("qrcode-recog-result", comment: "二维码识别结果"), message: text)
        } else {
            showAlert(message: NSLocalizedString("qrcode-recog-fail", comment: "未能识别到二维码"))
        }
    }
    
    @objc func actOCR() {
        if file.type == .video {return}
        guard let url=URL(string:file.path),
              let size=imageView.image?.size,
              let image=LargeImageProcessor.getImageCache(url: url, size: size, rotate: file.rotate, ver: file.ver, useOriginalImage: true, isHDR: false, isRawUseEmbeddedThumb: false)
        else {return}
        image.size = size
        
        if #available(macOS 13.0, *) {

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                log("Failed to create CGImage from NSImage")
                return
            }
            
            unSetOcr()
            
            let analyzer = ImageAnalyzer()
            let overlayView = ImageAnalysisOverlayView()
            
            overlayView.autoresizingMask = [.width, .height]
            overlayView.frame = imageView.bounds
            overlayView.trackingImageView = imageView
            imageView.addSubview(overlayView)
            
            Task {
                let configuration = ImageAnalyzer.Configuration([.text])
                if let analysis = try? await analyzer.analyze(cgImage, orientation: .up, configuration: configuration) {
                    overlayView.preferredInteractionTypes = .automatic
                    overlayView.analysis = analysis
                    isInOcrState = true
                }
            }
            
        } else {
            // Fallback
            showAlert(message: NSLocalizedString("ocr-recog-fail", comment: "OCR功能需要macOS 13.0及以上版本"))
//            performLegacyOCR(on: image) { result in
//                switch result {
//                case .success(let recognizedTexts):
//                    for text in recognizedTexts {
//                        print("Recognized text: \(text)")
//                    }
//                case .failure(let error):
//                    print("Error recognizing text: \(error.localizedDescription)")
//                }
//            }
        }
    }
    
    func unSetOcr() {
        if #available(macOS 13.0, *) {
            for subview in imageView.subviews {
                if let overlayView = subview as? ImageAnalysisOverlayView {
                    overlayView.analysis = nil
                    overlayView.removeFromSuperview()
                }
            }
            isInOcrState = false
        }
    }

    
    @objc func actRotateR() {
        // 镜像时视觉旋转方向相反
        // Visual rotation direction is reversed when mirrored
        if imageView.isMirroredH {
            doRotateL()
        } else {
            doRotateR()
        }
    }
    
    @objc func actRotateL() {
        // 镜像时视觉旋转方向相反
        // Visual rotation direction is reversed when mirrored
        if imageView.isMirroredH {
            doRotateR()
        } else {
            doRotateL()
        }
    }
    
    func doRotateR() {
        file.rotate = (file.rotate+1)%4
        getViewController(self)?.publicVar.rotationLock = file.rotate
        if file.type == .video {
            lastActionTriggerdReload = "Rotate"
            playVideo(reloadForAB: true)
        }else{
            unSetOcr()
            // 同步旋转编辑画布内容
            // Sync rotate editing canvas content
            imageEditingView?.rotateClockwise()
            // 旋转后重新绘制图像
            // Redraw image after rotation
            getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false)
            // 旋转后同步画布位置
            // Sync canvas position after rotation
            syncEditingCanvasFrame()
        }
    }
    
    func doRotateL() {
        file.rotate = (file.rotate+3)%4
        getViewController(self)?.publicVar.rotationLock = file.rotate
        if file.type == .video {
            lastActionTriggerdReload = "Rotate"
            playVideo(reloadForAB: true)
        }else{
            unSetOcr()
            // 同步旋转编辑画布内容
            // Sync rotate editing canvas content
            imageEditingView?.rotateCounterclockwise()
            // 旋转后重新绘制图像
            // Redraw image after rotation
            getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false)
            // 旋转后同步画布位置
            // Sync canvas position after rotation
            syncEditingCanvasFrame()
        }
    }
    
    @objc func actMirrorH() {
        if file.type == .video {return}
        imageView.isMirroredH.toggle()
        imageView.updateMirror()
    }
    
    @objc func actClose() {
        getViewController(self)?.closeLargeImage(0)
    }
    
    @objc func actShare(_ sender: NSMenuItem) {
        guard let fileUrl = URL(string: file.path) else { return }
        let sharingServicePicker = NSSharingServicePicker(items: [fileUrl])
        let centerPoint = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
        let rect = NSRect(origin: NSPoint(x: centerPoint.x - 5, y: centerPoint.y - 5), size: NSSize(width: 10, height: 10))
        sharingServicePicker.show(relativeTo: rect, of: self, preferredEdge: .maxX)
    }
    
    func prepareForDeinit() {
        if globalVar.videoPlayRememberPosition {
            saveCurrentPlayPosition()
        }
        if let observer = videoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            videoEndObserver = nil
        }

        if let gesture = magnificationGesture {
            self.removeGestureRecognizer(gesture)
        }
        magnificationGesture = nil
        
        longPressZoomTimer?.invalidate()
        longPressZoomTimer = nil
        wheelZoomRegenTimer?.invalidate()
        wheelZoomRegenTimer = nil
    }
    
    // MARK: - 图片编辑模式
    // MARK: - Image Editing Mode
    
    /// 进入编辑模式 - 调用此函数开始编辑当前图片
    /// Enter edit mode - Call this function to start editing the current image
    /// - Parameter completion: 保存完成后的回调，参数为编辑后的图片
    /// - Parameter completion: Callback after saving, parameter is the edited image
    func enterEditMode(completion: ((NSImage) -> Void)? = nil) {
        // 只有图片才能编辑
        // Only images can be edited
        guard file.type == .image else {
            showInfo(NSLocalizedString("Only images can be edited", comment: "只有图片才能编辑"))
            return
        }
        
        // 如果已经在编辑模式，则返回
        // If already in edit mode, return
        guard !isInEditMode else { return }
        
        isInEditMode = true
        
        // 创建编辑视图
        // Create editing view
        imageEditingView = ImageEditingView(frame: self.bounds)
        imageEditingView?.autoresizingMask = [.width, .height]
        imageEditingView?.originalImage = imageView.image
        
        // 设置画布与图片对齐
        // Set canvas aligned with image
        imageEditingView?.setImageFrame(imageView.frame)
        
        // 设置保存回调
        // Set save callback
        imageEditingView?.onSave = { [weak self] editedImage in
            guard let self = self else { return }
            completion?(editedImage)
            self.exitEditMode()
        }
        
        // 设置取消回调
        // Set cancel callback
        imageEditingView?.onCancel = { [weak self] in
            self?.exitEditMode()
        }
        
        // 添加编辑视图
        // Add editing view
        if let editingView = imageEditingView {
            addSubview(editingView, positioned: .above, relativeTo: nil)
        }
        
        // 隐藏其他UI元素
        // Hide other UI elements
        hideArrowView(leftArrowImageView)
        hideArrowView(rightArrowImageView)
        
        showInfo(NSLocalizedString("Edit Mode", comment: "编辑模式"), timeOut: 1.5)
    }
    
    /// 退出编辑模式
    /// Exit edit mode
    func exitEditMode() {
        guard isInEditMode else { return }
        
        isInEditMode = false
        
        // 移除编辑视图
        // Remove editing view
        imageEditingView?.removeFromSuperview()
        imageEditingView = nil
        
        // 恢复其他UI元素
        // Restore other UI elements
        
        showInfo(NSLocalizedString("Exit Edit Mode", comment: "退出编辑模式"), timeOut: 1.0)
    }
    
    /// 获取当前是否处于编辑模式
    /// Get whether currently in edit mode
    var isEditing: Bool {
        return isInEditMode
    }
}

// MARK: - ExifTextView
class ExifTextView: NSView {

    var textItems: [(String, Any)] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
            updateMapButtonVisibility()
        }
    }
    
    private var mapButton: NSButton?
    private var gpsCoordinates: (latitude: Double, longitude: Double, altitude: Double)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !textItems.isEmpty else { return }

        let backgroundColor = NSColor.black.withAlphaComponent(0.5)
        backgroundColor.setFill()

        let padding: CGFloat = 10
        let rect = NSInsetRect(self.bounds, padding, padding)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        path.fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle
        ]

        let keyAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle
        ]

        var yOffset: CGFloat = rect.origin.y + rect.height - padding

        let keyMaxWidth = textItems.map { $0.0.size(withAttributes: keyAttributes).width }.max() ?? 0
        // 根据keyMaxWidth设置mapButton的左边距
        // Set mapButton left margin based on keyMaxWidth
        if let mapButton = mapButton {
            if let superview = mapButton.superview {
                mapButton.removeFromSuperview()
                superview.addSubview(mapButton)
                mapButton.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    mapButton.leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: rect.origin.x + padding + keyMaxWidth + 10),
                    mapButton.centerYAnchor.constraint(equalTo: superview.topAnchor, constant: rect.origin.y + rect.height - padding - 8)
                ])
            }
        }

        for (key, value) in textItems {
            if key == "-" {
                // 绘制分割线
                // Draw separator line
                let lineRect = NSRect(x: rect.origin.x + padding, y: yOffset - 7, width: rect.width - padding * 2, height: 1)
                NSColor.white.setFill()
                lineRect.fill()
                // 分割线高度 + 间距
                // Separator line height + spacing
                yOffset -= 14
                continue
            }

            let keyString = NSString(string: key)
            let valueString = NSString(string: String(describing: value))
            
            let keySize = keyString.size(withAttributes: keyAttributes)
            let valueSize = valueString.size(withAttributes: attributes)

            let keyX = rect.origin.x + padding
            let valueX = keyX + keyMaxWidth + 10

            keyString.draw(at: CGPoint(x: keyX, y: yOffset - keySize.height), withAttributes: keyAttributes)
            valueString.draw(at: CGPoint(x: valueX, y: yOffset - valueSize.height), withAttributes: attributes)

            yOffset -= max(keySize.height, valueSize.height) + 5
        }

        // 如果有GPS坐标信息,添加一行"Open"
        // If GPS coordinate information exists, add an "Open" row
        if gpsCoordinates != nil {
            let openKey = NSLocalizedString("Location", comment: "位置")
            let openValue = ""
            
            let openKeySize = openKey.size(withAttributes: keyAttributes)
            let openValueSize = openValue.size(withAttributes: attributes)
            
            let openKeyX = rect.origin.x + padding
            let openValueX = openKeyX + keyMaxWidth + 10
            
            openKey.draw(at: CGPoint(x: openKeyX, y: yOffset - openKeySize.height), withAttributes: keyAttributes)
            openValue.draw(at: CGPoint(x: openValueX, y: yOffset - openValueSize.height), withAttributes: attributes)
            
            yOffset -= max(openKeySize.height, openValueSize.height) + 5
        }
    }

    override var intrinsicContentSize: NSSize {
        let padding: CGFloat = 10
        let keyMaxWidth = textItems.map { $0.0.size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: 14)]).width }.max() ?? 0
        let valueMaxWidth = textItems.map { String(describing: $0.1).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width }.max() ?? 0

        let lineHeight = "Sample".size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).height
        var numLines = CGFloat(textItems.count) + 1
        var additionalHeight: CGFloat = 0
        
        for (key, _) in textItems {
            if key == "-" {
                // 分割线高度 + 间距
                // Separator line height + spacing
                additionalHeight += 15
                // 分割线不算在内
                // Separator line doesn't count
                numLines -= 1
            }
        }
        
        // 如果有GPS坐标信息，为按钮预留额外空间
        // If GPS coordinate information exists, reserve extra space for button
        if gpsCoordinates != nil {
            additionalHeight += 20
        }

        let height = numLines * lineHeight + (numLines - 1) * 5 + padding * 2 + additionalHeight
        let width = keyMaxWidth + valueMaxWidth + 35 + padding * 2

        return NSSize(width: width, height: height)
    }
    
    private func updateMapButtonVisibility() {
        // 检查是否有GPS坐标信息
        // Check if GPS coordinate information exists
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        
        for (key, value) in textItems {
            if key == NSLocalizedString("Exif-GPSLatitude", comment: "GPS纬度") {
                if let latString = value as? String {
                    // 提取数字部分，去掉"°"符号
                    // Extract numeric part, remove "°" symbol
                    let cleanString = latString.replacingOccurrences(of: "°", with: "")
                    latitude = Double(cleanString)
                }
            } else if key == NSLocalizedString("Exif-GPSLongitude", comment: "GPS经度") {
                if let lonString = value as? String {
                    // 提取数字部分，去掉"°"符号
                    // Extract numeric part, remove "°" symbol
                    let cleanString = lonString.replacingOccurrences(of: "°", with: "")
                    longitude = Double(cleanString)
                }
            } else if key == NSLocalizedString("Exif-GPSAltitude", comment: "GPS海拔") {
                if let altString = value as? String {
                    // 提取数字部分，去掉"m"符号
                    // Extract numeric part, remove "m" symbol
                    let cleanString = altString.replacingOccurrences(of: "m", with: "")
                    altitude = Double(cleanString)
                }
            }
        }
        
        if latitude != nil || longitude != nil || altitude != nil {
            gpsCoordinates = (
                latitude: latitude ?? 0,
                longitude: longitude ?? 0,
                altitude: altitude ?? 0
            )
            createMapButton()
        } else {
            gpsCoordinates = nil
            removeMapButton()
        }
    }
    
    private func createMapButton() {
        guard mapButton == nil else { return }
        
        mapButton = NSButton(title: NSLocalizedString("Open in Map", comment: "在地图中打开"), target: self, action: #selector(openInMap))
        mapButton?.bezelStyle = .rounded
        mapButton?.font = NSFont.systemFont(ofSize: 12)
        
        addSubview(mapButton!)
    }
    
    private func removeMapButton() {
        mapButton?.removeFromSuperview()
        mapButton = nil
    }
    
    @objc private func openInMap() {
        guard let coordinates = gpsCoordinates else { return }
        
        // 构建地图URL，使用Apple Maps
        // Build map URL, using Apple Maps
        let mapURLString = "http://maps.apple.com/?q=\(coordinates.latitude),\(coordinates.longitude)"
        
        if let mapURL = URL(string: mapURLString) {
            NSWorkspace.shared.open(mapURL)
        }
    }
}

// MARK: - InfoView
class InfoView: NSView {

    private var label: NSTextField!
    private var hideTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        // setupView()
    }
    
    func setupView(fontSize: Double = 14, fontWeight: NSFont.Weight = .regular, cornerRadius: Double = 5.0, edge: (Double,Double) = (8,8)) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = cornerRadius
        
        label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        addSubview(label)
        
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: edge.0),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -edge.0),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: edge.1),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -edge.1)
        ])
        
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0
        isHidden = true
    }
    
    func showInfo(text: String, timeOut: Double = 2.0, duration: Double = INFO_VIEW_DURATION) {
        // 更新文本
        // Update text
        label.stringValue = text

        // 使之前的定时器失效
        // Invalidate previous timer
        hideTimer?.invalidate()
        
        // 停止正在进行的隐藏动画
        // Stop ongoing hide animation
        if isAnimating {
            // 停止所有动画
            // Stop all animations
            layer?.removeAllAnimations()
            isAnimating = false
        }
        
        isHidden = false
        
        // 根据当前alpha值计算剩余动画时间
        // Calculate remaining animation time based on current alpha value
        let currentAlpha = self.alphaValue
        let remainingDuration = duration * Double(1.0 - currentAlpha)
        
        // 从当前alpha值开始淡入动画显示视图
        // Start fade-in animation from current alpha value to display view
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = remainingDuration
            self.animator().alphaValue = 1.0
        })
        
        // 设置定时器在指定时间后隐藏视图
        // Set timer to hide view after specified time
        hideTimer = Timer.scheduledTimer(withTimeInterval: timeOut, repeats: false) { [weak self] _ in
            self?.hide(duration: duration)
        }
    }
    
    private var isAnimating = false
    
    func hide(duration: Double = INFO_VIEW_DURATION) {
        // 检查视图是否已经隐藏或正在动画中
        // Check if view is already hidden or animating
        guard !isAnimating, self.alphaValue != 0.0 else { return }
        
        isAnimating = true
        
        // 根据当前alpha值计算剩余动画时间
        // Calculate remaining animation time based on current alpha value
        let currentAlpha = self.alphaValue
        let remainingDuration = duration * Double(currentAlpha)
        
        // 从当前alpha值开始淡出动画
        // Start fade-out animation from current alpha value
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = remainingDuration
            self.animator().alphaValue = 0.0
        }) {
            // 动画完成处理
            // Animation completion handling
            if self.isAnimating {
                self.isAnimating = false
                self.isHidden = true
            }
        }
    }
    
    deinit {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}

// MARK: - ClickableLabel
// 不抢焦点的可点击标签视图
// Clickable label view that does not steal focus

class ClickableLabel: NSView {
    
    private var label: NSTextField!
    private var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private let normalColor = NSColor.white.withAlphaComponent(0.2)
    private let hoverColor = NSColor.white.withAlphaComponent(0.35)
    private let pressedColor = NSColor.white.withAlphaComponent(0.5)
    
    convenience init(title: String, onClick: (() -> Void)?) {
        self.init(frame: .zero)
        self.onClick = onClick
        
        wantsLayer = true
        layer?.backgroundColor = normalColor.cgColor
        layer?.cornerRadius = 6
        
        label = NSTextField(labelWithString: title)
        label.textColor = .white
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }
    
    // 不接受第一响应者，避免抢焦点
    // Do not accept first responder to avoid stealing focus
    override var acceptsFirstResponder: Bool { false }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverColor.cgColor
        //NSCursor.pointingHand.push()
    }
    
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalColor.cgColor
        //NSCursor.pop()
    }
    
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = pressedColor.cgColor
    }
    
    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            layer?.backgroundColor = hoverColor.cgColor
            onClick?()
        } else {
            layer?.backgroundColor = normalColor.cgColor
        }
    }
}
