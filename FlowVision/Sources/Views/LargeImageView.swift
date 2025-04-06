//
//  LargeImageView.swift
//  FlowVision
//
//  Created by netdcy on 2024/4/27.
//

import Foundation
import Cocoa
import VisionKit
import AVKit

class LargeImageView: NSView {

    var imageView: CustomLargeImageView!
    
    var snapshotQueue = [NSView?]()
    var videoView: LargeAVPlayerView!
    //var videoPlayer: AVPlayer?
    var playerItem: AVPlayerItem?
    var queuePlayer: AVQueuePlayer?
    var playerLooper: AVPlayerLooper?
    var currentPlayingURL: URL?
    var snapshotTimer: DispatchSourceTimer?
    var playcontrolTimer: DispatchSourceTimer?
    var videoOrderId: Int = 0
    var pausedBySeek = false
    
    private var blackOverlayView: NSView?
    
    var exifTextView: ExifTextView!
    var ratioView: InfoView!
    var infoView: InfoView!
    
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
    private let positionThreshold: CGFloat = 4.0 // 双击位置阈值，可以根据需要调整
    
    private var middleMouseInitialLocation: NSPoint?
    
    private var doNotPopRightMenu: Bool = false
    
    var isInOcrState: Bool = false
    
    private var magnificationGesture: NSMagnificationGestureRecognizer?
    
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
        
        magnificationGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        if let gesture = magnificationGesture {
            self.addGestureRecognizer(gesture)
        }
    }
    
    func updateTextItems(_ items: [(String, Any)]) {
        exifTextView.textItems = items
        exifTextView.invalidateIntrinsicContentSize()
    }
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        
        let newSize = self.bounds.size
        let imageViewSize = imageView.frame.size

        let deltaX = (newSize.width - oldSize.width) / 2
        let deltaY = (newSize.height - oldSize.height) / 2

        let newX = imageView.frame.origin.x + deltaX
        let newY = imageView.frame.origin.y + deltaY
        
        //窗口变化时大图随缩放居中
        imageView.frame = CGRect(x: newX, y: newY, width: imageViewSize.width, height: imageViewSize.height)
        
        if file.type == .video {
            determineBlackBg()
        }
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

    func playVideo() {
        if let url = URL(string: file.path) {
            // 检查当前播放的视频是否已经是目标视频
            if currentPlayingURL == url {
                return
            }
            
            // 快照
            if let snapshot = captureSnapshot(of: self) {
                self.addSubview(snapshot)
                snapshotQueue.append(snapshot)
            }
            
            playerLooper?.disableLooping()
            playerLooper = nil
            queuePlayer?.removeAllItems()
            playerItem = nil
            videoView.controlsStyle = .none
            videoOrderId += 1
            videoView.isHidden = false
            pausedBySeek = false

            if let timeRange = getCommonTimeRange(url: url) {
                playerItem = AVPlayerItem(url: url)
                if let playerItem = playerItem,
                   let queuePlayer = queuePlayer {
                    
                    // 根据 file.rotate 设置视频旋转角度
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
                    
                    queuePlayer.insert(playerItem, after: nil)
                    playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem, timeRange: timeRange)
                    queuePlayer.play()
                    currentPlayingURL = url
                    
                    // 开始计时器检查 playerItem.status
                    checkPlayerItemStatus(id: videoOrderId)
                }
            }else{
                while snapshotQueue.count > 0{
                    snapshotQueue.first??.removeFromSuperview()
                    snapshotQueue.removeFirst()
                }
                currentPlayingURL = nil
                showInfo(NSLocalizedString("Unsupported Video Format", comment: "不支持的视频格式"))
            }
        }
    }
    
    private func checkPlayerItemStatus(id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self = self, let playerItem = self.playerItem else { return }
            if id != videoOrderId { return }
            
            log("playerItem.status: ", playerItem.status.rawValue)
            
            //if playerItem.status == .readyToPlay || playerItem.status == .failed {
            let targetTime: CMTime = CMTime(seconds: 0.01, preferredTimescale: 600)
            if queuePlayer?.currentTime() ?? CMTime.zero >= targetTime {
                
                // 隐藏快照
                while snapshotQueue.count > 0{
                    snapshotQueue.first??.removeFromSuperview()
                    snapshotQueue.removeFirst()
                }
//                snapshotTimer?.cancel()
//                snapshotTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
//                snapshotTimer?.schedule(deadline: .now() + 0.05)
//                snapshotTimer?.setEventHandler { [weak self] in
//                    guard let self = self else { return }
//                    if id != videoOrderId { return }
//                    while snapshotQueue.count > 0 {
//                        let snapshot = snapshotQueue.first!
//                        snapshotQueue.removeFirst()
//                        
//                        NSAnimationContext.runAnimationGroup({ context in
//                            context.duration = 0.05
//                            snapshot?.animator().alphaValue = 0
//                        }, completionHandler: {
//                            snapshot?.removeFromSuperview()
//                        })
//                    }
//                }
//                snapshotTimer?.resume()
                
                // 显示控制
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
                checkPlayerItemStatus(id: id)
            }
        }
    }
    
    func stopVideo(){
        videoOrderId += 1
        videoView.isHidden = true
        playerLooper?.disableLooping()
        playerLooper = nil
        queuePlayer?.removeAllItems()
        playerItem = nil
        currentPlayingURL = nil
        pausedBySeek = false
        while snapshotQueue.count > 0{
            snapshotQueue.first??.removeFromSuperview()
            snapshotQueue.removeFirst()
        }
    }

    func seekVideoByDrag(deltaX: CGFloat) {
        // 如果拖动距离小于2像素则忽略
//        if abs(deltaX) < 2 {
//            return
//        }

        guard let player = queuePlayer else { 
            return 
        }
        
        // 获取视频总时长
        guard let duration = player.currentItem?.duration else { 
            return 
        }
        let totalSeconds = CMTimeGetSeconds(duration)
        
        // 计算当前视图宽度对应的总秒数比例
        let pixelsPerSecond = self.frame.width / CGFloat(totalSeconds)
        
        // 根据拖动距离计算需要调整的秒数
        let seekSeconds = deltaX / pixelsPerSecond
        
        // 获取当前播放时间
        let currentTime = player.currentTime()
        let currentSeconds = CMTimeGetSeconds(currentTime)
        
        // 计算目标时间,确保在有效范围内
        var targetSeconds = currentSeconds + Double(seekSeconds)
        targetSeconds = max(0, min(totalSeconds, targetSeconds))
        
        // 暂停
        if player.timeControlStatus == .playing {
            pausedBySeek = true
            pauseVideo()
        }
        
        // 转换为CMTime并执行跳转
        let targetTime = CMTimeMakeWithSeconds(Float64(targetSeconds), preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func seekVideo(direction: Int) {
        if direction == -1 {
            seekVideoBySeconds(seconds: -10)
        } else if direction == 1 {
            seekVideoBySeconds(seconds: 10)
        }
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
        var targetSeconds = currentSeconds + seconds
        targetSeconds = max(0, min(totalSeconds, targetSeconds))
        
        // 转换为CMTime并执行跳转
        let targetTime = CMTimeMakeWithSeconds(Float64(targetSeconds), preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func adjustVolume(by delta: Float) {
        guard let player = queuePlayer else { return }
        
        // 获取当前音量并计算新音量
        var newVolume = player.volume + delta
        
        // 限制音量在0-1之间
        newVolume = max(0, min(1.0, newVolume))
        
        // 设置新音量
        player.volume = newVolume
        
        // 显示音量信息
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
            let blackOverlayView = NSView(frame: effectView.bounds)
            blackOverlayView.wantsLayer = true
            blackOverlayView.layer?.backgroundColor = NSColor.black.cgColor
            
            // 保证前景视图在最前面显示
            effectView.addSubview(blackOverlayView)
            blackOverlayView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                blackOverlayView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
                blackOverlayView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
                blackOverlayView.topAnchor.constraint(equalTo: effectView.topAnchor),
                blackOverlayView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
            ])
            
            // 保存对黑色覆盖视图的引用
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
        
        //guard let originalSize = getViewController(self)?.getCurrentImageOriginalSizeInScreenScale() else { return }
        //let currentSize = imageView.bounds.size
//        var scale = 1.0
//        if direction == -1 {
//            scale = 0.8
//        }else if direction == +1 {
//            scale = 1.25
//        }
        //applyZoom(scale: scale, originalSize: currentSize, centerPoint: CGPoint(x: imageView.bounds.size.width/2, y: imageView.bounds.size.height/2))
        
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
        
        //重新绘制图像
        getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false)
        
        showRatio()
    }
    
    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
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
            getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false)
        default:
            break
        }
        
        //缩放后防止意外滚动
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
        
        showRatio()
    }
    
    func showRatio() {
        let ratio=String(Int(imageView.frame.size.width/customZoomSize().width*100))
        ratioView.showInfo(text: NSLocalizedString("Zoom", comment: "缩放")+": "+ratio+"%")
    }
    
    func showInfo(_ info: String, timeOut: Double = 1.0) {
        infoView.showInfo(text: info, timeOut: timeOut)
    }
    
    func customZoomSize() -> NSSize {
        // 返回您希望的缩放大小
        if let result=getViewController(self)?.getCurrentImageOriginalSizeInScreenScale(){
            return result
        }
        return NSSize(width: imageView.frame.width * 2, height: imageView.frame.height * 2)
    }
    
    override func mouseDown(with event: NSEvent) {
        getViewController(self)!.publicVar.isLeftMouseDown = true//临时按住左键也能缩放
        
        // 检测双击
        if !(getViewController(self)!.publicVar.isRightMouseDown) {
            let currentTime = event.timestamp
            let currentLocation = event.locationInWindow
            if currentTime - lastClickTime < NSEvent.doubleClickInterval,
               distanceBetweenPoints(lastClickLocation, currentLocation) < positionThreshold {
                getViewController(self)?.closeLargeImage(0)
            }
            lastClickTime = currentTime
            lastClickLocation = currentLocation
        }
        
        //如果是OCR则不执行后面操作
        if isInOcrState && !getViewController(self)!.publicVar.isRightMouseDown {return}
        
        initialPos =  self.convert(event.locationInWindow, from: nil)
        lastDragLocation = initialPos
        doNotPopRightMenu = false
        
        // 设置定时器实现长按检测
        longPressZoomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.performLongPressZoom(at: event.locationInWindow)
        }
        
        super.mouseDown(with: event)
    }

    private func performLongPressZoom(at point: NSPoint) {
        
        doNotPopRightMenu=true
        
        if !getViewController(self)!.publicVar.isInLargeView || !getViewController(self)!.publicVar.isInLargeViewAfterAnimate {
            //由于在大图状态下双击关闭又快速连击，会导致此处被异常调用，所以加以限制
            return
        }
        
        if file.type == .image {
            
            if !getViewController(self)!.publicVar.isRightMouseDown {
                let zoomSize=customZoomSize()
                let locationInView = self.convert(point, from: nil)
                let locationInImageView = imageView.convert(locationInView, from: self)
                
                let zoomFactorWidth = zoomSize.width / imageView.frame.width
                let zoomFactorHeight = zoomSize.height / imageView.frame.height
                
                // 计算新的图像尺寸和位置
                imageView.frame.size = zoomSize
                imageView.frame.origin.x -= (locationInImageView.x * (zoomFactorWidth - 1))
                imageView.frame.origin.y -= (locationInImageView.y * (zoomFactorHeight - 1))
                
                getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: true)
            }else{
                getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: true)
            }
            
            showRatio()
            
            //hasZoomed=true
        }else if file.type == .video {
            if !getViewController(self)!.publicVar.isRightMouseDown{
                pauseOrResumeVideo()
            }
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        getViewController(self)!.publicVar.isLeftMouseDown = false//临时按住左键也能缩放
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
            } else if file.type == .video {
                if getViewController(self)!.publicVar.isRightMouseDown {
                    seekVideoByDrag(deltaX: dx)
                }
            }
        }

        lastDragLocation = newLocation
    }
    
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { // 检查是否按下了鼠标中键
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
        //super.rightMouseDown(with: event)  // 继续传递事件
    }

    override func rightMouseUp(with event: NSEvent) {
        getViewController(self)!.publicVar.isRightMouseDown = false
        mouseUp(with: event)
        
        if !doNotPopRightMenu && event.locationInWindow.y < getViewController(self)!.mainScrollView.bounds.height {
            //弹出菜单
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
            
            let actionItemRename = menu.addItem(withTitle: NSLocalizedString("Rename", comment: "重命名"), action: #selector(actRename), keyEquivalent: "\r")
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
            
            let actionItemShowExif = menu.addItem(withTitle: NSLocalizedString("Show Exif", comment: "显示Exif信息"), action: #selector(actShowExif), keyEquivalent: "i")
            actionItemShowExif.keyEquivalentModifierMask = []
            actionItemShowExif.state = getViewController(self)!.publicVar.isShowExif ? .on : .off
            
            if file.type == .image {
                let actionItemOCR = menu.addItem(withTitle: NSLocalizedString("recognize-OCR", comment: "识别文本 (OCR)"), action: #selector(actOCR), keyEquivalent: "o")
                actionItemOCR.keyEquivalentModifierMask = []
            
                let actionItemQRCode = menu.addItem(withTitle: NSLocalizedString("recognize-QRCode", comment: "识别二维码"), action: #selector(actQRCode), keyEquivalent: "p")
                actionItemQRCode.keyEquivalentModifierMask = []
            } else if file.type == .video {
                let actionItemShowVideoMetadata = menu.addItem(withTitle: NSLocalizedString("Show Video Metadata", comment: "显示视频元数据"), action: #selector(actShowVideoMetadata), keyEquivalent: "u")
                actionItemShowVideoMetadata.keyEquivalentModifierMask = []
            }

            menu.addItem(NSMenuItem.separator())
            
            let actionItemRotateR = menu.addItem(withTitle: NSLocalizedString("Rotate Clockwise", comment: "顺时针旋转"), action: #selector(actRotateR), keyEquivalent: "e")
            actionItemRotateR.keyEquivalentModifierMask = []
            
            let actionItemRotateL = menu.addItem(withTitle: NSLocalizedString("Rotate Counterclockwise", comment: "逆时针旋转"), action: #selector(actRotateL), keyEquivalent: "q")
            actionItemRotateL.keyEquivalentModifierMask = []
            
            menu.addItem(NSMenuItem.separator())
            
            let actionItemRefresh = menu.addItem(withTitle: NSLocalizedString("Refresh", comment: "刷新"), action: #selector(actRefresh), keyEquivalent: "r")
            actionItemRefresh.keyEquivalentModifierMask = []
            
            menu.items.forEach { $0.target = self }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        
        //super.rightMouseDragged(with: event)  // 继续传递事件
    }
    
    override func scrollWheel(with event: NSEvent) {
        //保证鼠标在图像上才缩放
        //guard imageView.frame.contains(event.locationInWindow) else { return }

        if getViewController(self)!.publicVar.isRightMouseDown || getViewController(self)!.publicVar.isLeftMouseDown {
            
            //注意：触控板按下右键的同时会触发deltaY为0的滚动事件
            if abs(event.deltaY) > 0 {
                longPressZoomTimer?.invalidate()
                longPressZoomTimer = nil
                doNotPopRightMenu=true
            }
            
            do {
                wheelZoomRegenTimer?.invalidate()
                wheelZoomRegenTimer = nil
                wheelZoomRegenTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    guard let self=self else{return}
                    getViewController(self)?.changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false)
                    hasZoomedByWheel=false
                }
            }

            let zoomFactor: CGFloat = 1.1
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
            //log(imageView.frame.size,imageView.frame.origin)
            
            if abs(event.deltaY) > 0 {
                showRatio()
            }
        }
    }
    
    func isExceedZoomLimit(enlarge: Bool, width: Double, height: Double) -> Bool {
        guard let originalSize = getViewController(self)?.getCurrentImageOriginalSizeInScreenScale() else { return false }
        
//        if enlarge && width>originalSize.width && (min(width,height) > 20000) {
//            return true
//        }
//        if !enlarge && width<originalSize.width && (max(width,height) < 200) {
//            return true
//        }
        
        if enlarge && width>originalSize.width*8 {
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
        NSWorkspace.shared.selectFile(file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!, inFileViewerRootedAtPath: folderPath)
    }
    @objc func actRename() {
        renameAlert(url: URL(string: file.path)!);
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
        file.rotate = 0
        LargeImageProcessor.clearCache()
        getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false, forceRefresh: true)
    }
    
    @objc func actShowExif() {
        getViewController(self)!.publicVar.isShowExif.toggle()
        //exifTextView.isHidden = !getViewController(self)!.publicVar.isShowExif
    }
    
    @objc func actShowVideoMetadata() {
        getViewController(self)?.handleGetInfo()
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
              let image=LargeImageProcessor.getImageCache(url: url, size: size, rotate: file.rotate, ver: file.ver, useOriginalImage: true, isHDR: false)
        else {return}
        image.size = size
        
        if #available(macOS 13.0, *) {

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                log("无法从NSImage创建CGImage")
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
        file.rotate = (file.rotate+1)%4
        if file.type == .video {
            stopVideo()
        }else{
            unSetOcr()
        }
        getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false)
    }
    
    @objc func actRotateL() {
        file.rotate = (file.rotate+3)%4
        if file.type == .video {
            stopVideo()
        }else{
            unSetOcr()
        }
        getViewController(self)?.changeLargeImage(firstShowThumb: true, resetSize: true, triggeredByLongPress: false)
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
        if let gesture = magnificationGesture {
            self.removeGestureRecognizer(gesture)
        }
        magnificationGesture = nil
        
        longPressZoomTimer?.invalidate()
        longPressZoomTimer = nil
        wheelZoomRegenTimer?.invalidate()
        wheelZoomRegenTimer = nil
    }
}


class ExifTextView: NSView {

    var textItems: [(String, Any)] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

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

        for (key, value) in textItems {
            if key == "-" {
                // 绘制分割线
                let lineRect = NSRect(x: rect.origin.x + padding, y: yOffset - 7, width: rect.width - padding * 2, height: 1)
                NSColor.white.setFill()
                lineRect.fill()
                yOffset -= 14 // 分割线高度 + 间距
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
                additionalHeight += 18 // 分割线高度 + 间距
                numLines -= 1 // 分割线不算在内
            }
        }

        let height = numLines * lineHeight + (numLines - 1) * 5 + padding * 2 + additionalHeight
        let width = keyMaxWidth + valueMaxWidth + 35 + padding * 2

        return NSSize(width: width, height: height)
    }
}

class InfoView: NSView {

    private var label: NSTextField!
    private var hideTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        //setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        //setupView()
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
    
    func showInfo(text: String, timeOut: Double = 2.0) {
        // Update text
        label.stringValue = text

        // Invalidate previous timer
        hideTimer?.invalidate()
        
        // Stop any ongoing hide animation
        if isAnimating {
            layer?.removeAllAnimations() // Stop all animations
            isAnimating = false
        }
        
        isHidden = false
        
        // Calculate the remaining duration based on the current alpha value
        let currentAlpha = self.alphaValue
        let remainingDuration = 0.3 * Double(1.0 - currentAlpha)
        
        // Show the view with fade-in animation from the current alpha value
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = remainingDuration
            self.animator().alphaValue = 1.0
        })
        
        // Set a timer to hide the view after xx seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: timeOut, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
    
    private var isAnimating = false
    
    func hide() {
        // Check if the view is already hidden or currently animating
        guard !isAnimating, self.alphaValue != 0.0 else { return }
        
        isAnimating = true
        // Hide the view with fade-out animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0.0
        }) {
            // Animation completion handler
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
