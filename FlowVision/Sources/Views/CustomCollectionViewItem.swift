//
//  ImageCollectionViewItem.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/17.
//

import Cocoa
import AVKit
import AVFoundation

class CustomCollectionViewItem: NSCollectionViewItem {
    
    @IBOutlet weak var imageViewObj: CustomThumbImageView!
    @IBOutlet weak var imageNameField: NSTextField!
    @IBOutlet weak var imageLabel: NSTextField!
    @IBOutlet weak var videoFlag: NSImageView!
    @IBOutlet weak var videoView: NSView!
    
    var avPlayerLayer: AVPlayerLayer?
    
    var queuePlayer: AVQueuePlayer?
    var playerLooper: AVPlayerLooper?
    var currentPlayingURL: URL?
    
    var folderViews=[NSView]()
    var folderImageViews=[CustomImageView]()
    
    var file = FileModel(path: "", ver: 0)
    private var mouseDownLocation: NSPoint? = nil
    
    private var lastClickTime: TimeInterval = 0
    private var lastClickLocation: NSPoint = NSPoint.zero
    private let positionThreshold: CGFloat = 4.0 // 双击位置阈值，可以根据需要调整
    
    private var middleMouseLastLocation: NSPoint = NSPoint.zero
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        view.wantsLayer = true
        view.layer?.cornerRadius = 5.0
        view.layer?.masksToBounds = false
        
        //图像容器
        imageViewObj.imageScaling = .scaleAxesIndependently
        imageViewObj.wantsLayer = true
        imageViewObj.layer?.borderWidth = 0.0
        imageViewObj.layer?.borderColor = nil
        imageViewObj.layer?.cornerRadius = 5.0 // 这里可以根据需要调整圆角的半径
        imageViewObj.layer?.masksToBounds = true
        imageViewObj.animates=true
        if #available(macOS 14.0, *) {
            imageViewObj.preferredImageDynamicRange = .standard
        }
        
        //文件名标签
        imageNameField.cell?.lineBreakMode = .byTruncatingTail
        
        //右上角标签
        imageLabel.wantsLayer = true
        imageLabel.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.6).cgColor
        imageLabel.layer?.cornerRadius = 4
//        imageLabel.layer?.borderWidth = 0.5
//        imageLabel.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
        
        //视频图标
        let playImage = NSImage(systemSymbolName: "play.circle", accessibilityDescription: "Video")?.withSymbolConfiguration(.init(pointSize: 0, weight: .regular, scale: .large))
        playImage?.isTemplate = true
        videoFlag.image = playImage
        videoFlag.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        videoFlag.imageScaling = .scaleAxesIndependently
        videoFlag.wantsLayer = true

        //视频播放器
        queuePlayer = AVQueuePlayer()
        queuePlayer?.isMuted = true
        
        // 初始化 AVPlayerLayer
        avPlayerLayer = AVPlayerLayer(player: queuePlayer)
        avPlayerLayer?.isHidden = true
        avPlayerLayer?.frame = videoView.bounds
        avPlayerLayer?.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        videoView.wantsLayer = true
        videoView.layer?.cornerRadius = 5.0
        videoView.layer?.addSublayer(avPlayerLayer!)
        
//        for _ in 0...0 {
//            // 父视图 - 用于阴影和边框
//            let shadowView = NSView(frame: CGRect(x: 100, y: 100, width: 200, height: 200))
//            shadowView.wantsLayer = true
//            //阴影
//            shadowView.layer?.shadowColor = NSColor.black.cgColor
//            shadowView.layer?.shadowOpacity = 0.8
//            shadowView.layer?.shadowOffset = CGSize(width: 3, height: -3)
//            shadowView.layer?.shadowRadius = 5
//            //边框
//            shadowView.layer?.masksToBounds = false
//            shadowView.layer?.borderColor = NSColor.white.cgColor
//            shadowView.layer?.borderWidth = 2.0
//            shadowView.layer?.cornerRadius = 4.0
//            
//            shadowView.rotate(byDegrees: 15)
//            
//            // 子视图 - 用于内容和裁切圆角
//            let contentView = NSImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
//            contentView.wantsLayer = true
//            contentView.layer?.cornerRadius = 4.0
//            contentView.layer?.masksToBounds = true
//            //contentView.layer?.backgroundColor = NSColor.white.cgColor // 背景颜色，对于透明png？
//            contentView.imageScaling = .scaleAxesIndependently
//            
//            shadowView.autoresizingMask=[.width, .height, .minXMargin, .minYMargin, .maxXMargin, .maxXMargin]
//            shadowView.autoresizesSubviews=true
//            contentView.autoresizingMask=[.width, .height, .minXMargin, .minYMargin, .maxXMargin, .maxXMargin]
//            
////            contentView.translatesAutoresizingMaskIntoConstraints = false // 禁用自动转换为约束
//            
//            folderViews.append(shadowView)
//            folderImageViews.append(contentView)
//            
//            // 添加视图
//            shadowView.addSubview(contentView)
//            self.view.addSubview(shadowView)
//            
////            NSLayoutConstraint.activate([
////                contentView.topAnchor.constraint(equalTo: shadowView.topAnchor),
////                contentView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),
////                contentView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
////                contentView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor)
////            ])
//        }
        
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        if isSelected && !getViewController(collectionView!)!.publicVar.isInLargeView {
            // 选中状态的处理代码
            selectedColor()
        } else {
            // 未选中状态的处理代码
            deselectedColor()
        }
        lastClickTime=0
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopVideo()
    }
    
    override var isSelected: Bool {
        didSet {
            super.isSelected = isSelected
            // 在这里处理选中状态变化
            if isSelected && !getViewController(collectionView!)!.publicVar.isInLargeView {
                // 选中状态的处理代码
                selectedColor()
            } else {
                // 未选中状态的处理代码
                deselectedColor()
            }
        }
    }

    func isItemVisible() -> Bool {
        guard let collectionView = collectionView else { return false }
        let visibleRectRaw = collectionView.visibleRect
        let scrollPos = visibleRectRaw.origin
        let scrollWidth = visibleRectRaw.width
        let scrollHeight = visibleRectRaw.height
        let visibleRectExtended = NSRect(origin: scrollPos, size: CGSize(width: scrollWidth, height: scrollHeight))

        let itemFrame = self.view.frame
        return itemFrame.intersects(visibleRectExtended)
    }
    
    func configureWithImage(_ fileModel: FileModel, playAnimation: Bool = false) {
        
        stopVideo()
        
        self.file=fileModel
        
        setTooltip()
        
        imageNameField.stringValue=getViewController(collectionView!)!.publicVar.profile.isShowThumbnailFilename ? URL(string:file.path)!.lastPathComponent : ""

        if isSelected {
            // 选中状态的处理代码
            selectedColor()
        } else {
            // 未选中状态的处理代码
            deselectedColor()
        }
        
        imageViewObj.url = URL(string: file.path)
        if file.isDir {
            imageViewObj.isFolder = true
        }else{
            imageViewObj.isFolder = false
        }

        let isShowThumbnailBadge = getViewController(collectionView!)!.publicVar.profile.getValue(forKey: "isShowThumbnailBadge") == "true"
        let isRawImage = globalVar.HandledRawExtensions.contains(imageViewObj.url?.pathExtension.lowercased() ?? "noExtention")
        if isRawImage {
            imageLabel.stringValue="RAW"
        }else if (file.imageInfo?.isHDR ?? false) {
            imageLabel.stringValue="HDR"
        }else{
            imageLabel.stringValue=""
        }
        if imageLabel.stringValue != "" && isShowThumbnailBadge {
            imageLabel.sizeToFit() // 先调整文字大小
            imageLabel.frame.origin.x = imageViewObj.frame.origin.x + imageViewObj.frame.width - imageLabel.frame.width - 5
            imageLabel.frame.origin.y = imageViewObj.frame.origin.y + imageViewObj.frame.height - imageLabel.frame.height - 5
            imageLabel.isHidden=false
        } else {
            imageLabel.isHidden=true
        }
        
        guard let style = getViewController(collectionView!)?.publicVar.profile else {return}
        if file.type == .video && (getViewController(collectionView!)!.publicVar.profile.layoutType == .grid || style.ThumbnailBorderThickness == 0) {
            // 设置视频播放图标的大小为视图宽度的1/4
            let iconSize = max(imageViewObj.frame.width, imageViewObj.frame.height) * 0.25
            let iconPoint = NSPoint(
                x: imageViewObj.frame.origin.x + (imageViewObj.frame.width - iconSize) / 2,
                y: imageViewObj.frame.origin.y + (imageViewObj.frame.height - iconSize) / 2
            )
            videoFlag.frame = NSRect(origin: iconPoint, size: NSSize(width: iconSize, height: iconSize))
            videoFlag.layer?.shadowColor = NSColor.black.cgColor
            videoFlag.layer?.shadowOffset = CGSize(width: 0, height: 0)
            videoFlag.layer?.shadowRadius = 3
            videoFlag.layer?.shadowOpacity = 0.5
            videoFlag.isHidden = false
        }else{
            videoFlag.isHidden = true
        }
        
        if getViewController(collectionView!)!.publicVar.autoPlayVisibleVideo && isItemVisible() {
            playVideo()
        }
        
        if(playAnimation){
            NSAnimationContext.runAnimationGroup({ context in
                // 设置动画持续时间秒
                context.duration = 0.1
                
                // 使用Core Animation的crossfade效果
                imageViewObj.wantsLayer = true // 确保imageView使用了CALayer
                let transition = CATransition()
                transition.type = CATransitionType.fade
                transition.duration = context.duration
                imageViewObj.layer?.add(transition, forKey: kCATransition)
                
                // 设置新图像
                imageViewObj.image = file.image
                //imageViewObj.sd_setImage(with: URL(string: path), placeholderImage: nil)
                
//                if file.folderImages.count>0{
//                    folderViews[0].isHidden=false
//                    folderImageViews[0].image=file.folderImages[0]
//                }else{
//                    folderViews[0].isHidden=true
//                    folderImageViews[0].image=nil
//                }

            }, completionHandler: {
                // 动画完成后的操作（如果有）
            })
        }else{
            if file.image != nil {
                imageViewObj.image=file.image
            }else{
                if file.isDir {
                    imageViewObj.image=NSImage(named: NSImage.folderName)
                }else{
                    imageViewObj.image=nil
                }
            }
            
//            if file.folderImages.count>0{
//                folderViews[0].isHidden=false
//                folderImageViews[0].image=file.folderImages[0]
//            }else{
//                folderViews[0].isHidden=true
//                folderImageViews[0].image=nil
//            }
        }
        
        
    }
    
    func setTooltip(){
        if !getViewController(collectionView!)!.publicVar.isInLargeView {
            if file.isDir {
                self.view.toolTip = generateTooltip(filePath: file.path.removingPercentEncoding!, type: file.type, fileSize: nil, imageSize: nil, creationDate: file.createDate, modificationDate: file.modDate, addDate: file.addDate)
            }else{
                var imageSize = file.isGetImageSizeFail ? nil : file.originalSize
                if file.type == .other { imageSize = nil }
                self.view.toolTip = generateTooltip(filePath: file.path.removingPercentEncoding!, type: file.type, fileSize: file.fileSize, imageSize: imageSize, creationDate: file.createDate, modificationDate: file.modDate, addDate: file.addDate)
            }
        }else{
            self.view.toolTip = nil
        }
        
    }
    
    func generateTooltip(filePath: String, type: FileType, fileSize: Int?, imageSize: NSSize?, creationDate: Date?, modificationDate: Date?, addDate: Date?) -> String {
        //当前目录
        let curFolder = getViewController(collectionView!)!.fileDB.curFolder.removingPercentEncoding!

        // 获取文件名
        let fileName = (filePath as NSString).lastPathComponent
        
        //获取相对路径
        var relativePath = "./" + filePath.replacingOccurrences(of: curFolder, with: "")
        if relativePath.hasSuffix("/") {
            relativePath = String(relativePath.dropLast())
        }
        relativePath = relativePath.replacingOccurrences(of: fileName, with: "")
        
        // 准备局部化字符串
        let nameLabel = NSLocalizedString("Name", comment: "名称")
        let sizeLabel = NSLocalizedString("file-size", comment: "文件大小")
        var dimensionsLabel = ""
        if type == .video {
            dimensionsLabel = NSLocalizedString("video-dimensions", comment: "视频尺寸")
        }else{
            dimensionsLabel = NSLocalizedString("image-dimensions", comment: "图像尺寸")
        }
        let creationDateLabel = NSLocalizedString("Date Created", comment: "创建日期")
        let modificationDateLabel = NSLocalizedString("Date Modified", comment: "修改日期")
        let addDateLabel = NSLocalizedString("Date Added", comment: "添加日期")
        let relativePathLabel = NSLocalizedString("Relative Path", comment: "相对路径")
        
        // 生成Tooltip字符串的数组
        var tooltipParts: [String] = []
        
        // 添加文件名
        tooltipParts.append("\(nameLabel): \(fileName)")
        
        // 添加相对路径
        if getViewController(collectionView!)!.publicVar.isRecursiveMode {
            tooltipParts.append("\(relativePathLabel): \(relativePath)")
        }
        
        // 如果文件大小存在，添加文件大小
        if let fileSize = fileSize {
            let byteCountFormatter = ByteCountFormatter()
            byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
            byteCountFormatter.countStyle = .file
            let formattedFileSize = byteCountFormatter.string(fromByteCount: Int64(fileSize))
            tooltipParts.append("\(sizeLabel): \(formattedFileSize)")
        }
        
        // 如果图像尺寸存在，添加图像尺寸
        if let imageSize = imageSize {
            let formattedImageSize = "\(Int(imageSize.width)) x \(Int(imageSize.height))"
            tooltipParts.append("\(dimensionsLabel): \(formattedImageSize)")
        }
        
        // 日期格式化器
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        // 如果创建日期存在，添加创建日期
        if let creationDate = creationDate {
            let formattedCreationDate = dateFormatter.string(from: creationDate)
            tooltipParts.append("\(creationDateLabel): \(formattedCreationDate)")
        }
        
        // 如果修改日期存在，添加修改日期
        if let modificationDate = modificationDate {
            let formattedModificationDate = dateFormatter.string(from: modificationDate)
            tooltipParts.append("\(modificationDateLabel): \(formattedModificationDate)")
        }
        
        // 如果添加日期存在，添加添加日期
        if let addDate = addDate {
            let formattedAddDate = dateFormatter.string(from: addDate)
            tooltipParts.append("\(addDateLabel): \(formattedAddDate)")
        }
        
        // 将所有部分连接成最终的Tooltip字符串
        let tooltip = tooltipParts.joined(separator: "\n")
        
        return tooltip
    }

    func playVideo() {
        guard let viewController = getViewController(collectionView!) else {return}
        if viewController.publicVar.isInFindingClosestState {return}
        if viewController.publicVar.isInLargeView {
            stopVideo()
            return
        }
        
        if file.type == .video && globalVar.HandledNativeSupportedVideoExtensions.contains(file.ext) {
            // 检查当前播放的视频是否已经是目标视频
            if currentPlayingURL == URL(string: file.path) {
                return
            }
            
            playerLooper?.disableLooping()
            playerLooper = nil
            queuePlayer?.removeAllItems()
            
            if let url = URL(string: file.path),
               let timeRange = getCommonTimeRange(url: url) {
                
                let playerItem = AVPlayerItem(url: url)
                queuePlayer?.insert(playerItem, after: nil)
                playerLooper = AVPlayerLooper(player: queuePlayer!, templateItem: playerItem, timeRange: timeRange)
                queuePlayer?.play()
                currentPlayingURL = URL(string: file.path)
                avPlayerLayer?.isHidden = false
            }
        } else {
            avPlayerLayer?.isHidden = true
        }
    }
    
    func stopVideo() {
        guard let viewController = getViewController(collectionView!) else {return}
        if viewController.publicVar.isInFindingClosestState {return}
        if avPlayerLayer?.isHidden == false {
            playerLooper?.disableLooping()
            playerLooper = nil
            queuePlayer?.removeAllItems()
            currentPlayingURL = nil
            avPlayerLayer?.isHidden = true
        }
    }
    
    func selectedColor(){
        guard let style = getViewController(collectionView!)?.publicVar.profile else {return}
        
        //设置frame
        setCustomFrameSize()
        
        let theme=NSApp.effectiveAppearance.name
        
        //定义失去焦点时的边框颜色
        var focusColor = NSColor.systemGray //失焦
        if getViewController(collectionView!)!.publicVar.isCollectionViewFirstResponder || getViewController(collectionView!)!.publicVar.isInSearchState {
            focusColor = NSColor.controlAccentColor //聚焦
        } else if style.ThumbnailBorderThickness == 0 {
            focusColor = NSColor.black
        }
        
        //文件名颜色
        if style.ThumbnailBorderThickness == 0 {
            imageNameField.textColor = focusColor
        }else{
            imageNameField.textColor = hexToNSColor(hex: "#FFFFFF")
        }
        
        //占位背景色
        if file.isDir {
            imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor //填充
        }else{
            if theme == .darkAqua {
                //imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#505050").cgColor //填充
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#404040").cgColor //填充
            }else{
                //imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#CECECE").cgColor //填充
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#DDDDDD").cgColor //填充
            }
        }
        
        //边框颜色
        view.layer?.backgroundColor = focusColor.cgColor
        
        //边框为0时不显示底色
        if style.ThumbnailBorderThickness == 0 {
            view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            if file.getThumbFailed || !(file.type == .image || file.type == .video || file.ext == "pdf") {
                imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            }
        }
        
        //图像高亮-选中
        if style.ThumbnailBorderThickness == 0 {
            let overlayLayerName = "highlightOverlay"
            videoView.layer?.sublayers?.forEach { sublayer in
                if sublayer.name == overlayLayerName {
                    sublayer.removeFromSuperlayer()
                }
            }
            let overlay = CALayer()
            overlay.frame = videoView.bounds
            overlay.backgroundColor = focusColor.withAlphaComponent(0.4).cgColor
            overlay.name = overlayLayerName
            overlay.zPosition = 10
            videoView.layer?.addSublayer(overlay)
            videoView.needsDisplay = true
        }
    }

    func deselectedColor(){
        guard let style = getViewController(collectionView!)?.publicVar.profile else {return}
        
        //设置frame
        setCustomFrameSize()
        
        let theme=NSApp.effectiveAppearance.name
        
        //文件名颜色
        imageNameField.textColor = hexToNSColor(hex: "#7E7E7E")
        
        //占位背景色和边框颜色
        if file.isDir {
            imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
        }else{//文件
            //黑暗模式
            if theme == .darkAqua {
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#404040").cgColor //填充
                if file.type == .video
                {
                    view.layer?.backgroundColor = hexToNSColor(hex: "#DDDDDD").cgColor //视频边框
                }else{
                    view.layer?.backgroundColor = hexToNSColor(hex: "#3A3A3A").cgColor //图片边框
                }
            }else{//浅色模式
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#DDDDDD").cgColor //填充
                if file.type == .video
                {
                    view.layer?.backgroundColor = hexToNSColor(hex: "#404040").cgColor //视频边框
                }else{
                    view.layer?.backgroundColor = hexToNSColor(hex: "#F4F5F5").cgColor //图片边框
                }
            }
        }
        
        //边框为0时不显示底色
        if style.ThumbnailBorderThickness == 0 {
            view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            if file.getThumbFailed || !(file.type == .image || file.type == .video || file.ext == "pdf") {
                imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            }
        }
        
        //图像高亮-取消选中
        let overlayLayerName = "highlightOverlay"
        videoView.layer?.sublayers?.forEach { sublayer in
            if sublayer.name == overlayLayerName {
                sublayer.removeFromSuperlayer()
                videoView.needsDisplay = true
            }
        }
        videoView.needsDisplay = true
    }
    
    func setCustomFrameSize(){
        guard let style = getViewController(collectionView!)?.publicVar.profile else {return}
        var tmpFilenamePadding = style.ThumbnailFilenamePadding
        var girdFilenameCompensation = 0.0
        if style.layoutType == .grid {
            girdFilenameCompensation = tmpFilenamePadding
            tmpFilenamePadding = 0
        }
        let newX = style.ThumbnailBorderThickness
        let newY = style.ThumbnailBorderThickness + tmpFilenamePadding
        let refWidth = view.frame.width - 12.0
        let refHeight = view.frame.height - 12.0 - 18.0
        let newWidth = refWidth + 12.0 - 2*style.ThumbnailBorderThickness
        let newHeight = refHeight + 12.0 + 18.0 - 2*style.ThumbnailBorderThickness - tmpFilenamePadding
        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
        
        imageViewObj.frame = newFrame
        videoView.frame = newFrame
        
        let borderRadius = style.layoutType == .grid ? style.ThumbnailBorderRadiusInGrid : style.ThumbnailBorderRadius
        // 限制圆角半径不超过视图尺寸的一半
        let maxRadius = min(newFrame.width, newFrame.height) / 2
        let safeRadius = min(borderRadius, maxRadius)
        view.layer?.cornerRadius = safeRadius
        view.layer?.masksToBounds = false
        imageViewObj.layer?.cornerRadius = safeRadius
        videoView.layer?.cornerRadius = safeRadius
        
        var textX = newX
        var textY = round(newX/2)+1 - girdFilenameCompensation
        var textWidth = newWidth
        if style.layoutType == .grid {
            textWidth = max(newWidth, newHeight)
            textX -= round((textWidth-newWidth)/2)
            textY -= round((textWidth-newHeight)/2)
        }
        
        let textFrame = NSRect(x: textX, y: textY, width: textWidth, height: round(style.ThumbnailFilenameSize*1.3))
        imageNameField.font = NSFont.systemFont(ofSize: style.ThumbnailFilenameSize, weight: .light)
        imageNameField.frame = textFrame
        
        //阴影效果
        if (style.ThumbnailShowShadow || style.layoutType == .grid) && (file.type == .image || file.type == .video || file.ext == "pdf") && !file.getThumbFailed {
            view.layer?.shadowColor = NSColor.black.withAlphaComponent(0.4).cgColor
            view.layer?.shadowOffset = CGSize(width: 1.3, height: -1.3)
            view.layer?.shadowRadius = 2.5
            view.layer?.shadowOpacity = 1
            // 添加shadowPath以提高性能
            let cutoff = (style.ThumbnailBorderThickness == 0 && style.layoutType != .grid) ? style.ThumbnailFilenamePadding : 0
            let rect = CGRect(x: view.bounds.origin.x, y: view.bounds.origin.y + cutoff, width: view.bounds.width, height: view.bounds.height - cutoff)
            let path = CGMutablePath()
            if borderRadius > 0 {
                // 限制圆角半径不超过视图尺寸的一半
                let maxRadius = min(rect.width, rect.height) / 2
                let safeRadius = min(borderRadius, maxRadius)
                path.addRoundedRect(in: rect, cornerWidth: safeRadius, cornerHeight: safeRadius)
            }else{
                path.addRect(rect)
            }
            view.layer?.shadowPath = path
        }else{
            view.layer?.shadowOpacity = 0
        }
    }
    
    func select(){
        
    }
    func deselect(){
        
    }
    
    override func mouseDown(with event: NSEvent) {
        //print("mouseDownItem: ",file.id)
        let currentTime = event.timestamp
        let currentLocation = event.locationInWindow
        if currentTime - lastClickTime < NSEvent.doubleClickInterval &&
            distanceBetweenPoints(lastClickLocation, currentLocation) < positionThreshold {
            if let collectionView = collectionView,
               var selfIndexPath=collectionView.indexPath(for: self),
               let viewController = getViewController(collectionView) {
                
                // 由于连续点击事件的处理会触发上个目录在当前位置item的事件，其id是随机的，因此需要做此修正
                if collectionView.selectionIndexPaths.count == 1 {
                    selfIndexPath = collectionView.selectionIndexPaths.first!
                }
                
                if !viewController.publicVar.isInLargeView && !viewController.publicVar.isInLargeViewAfterAnimate {
                    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
                        actOpenInNewTab()
                    }else{
                        viewController.openLargeImageFromIndexPath(selfIndexPath)
                    }
                }else if viewController.publicVar.isInLargeView && viewController.publicVar.isInLargeViewAfterAnimate {
                    viewController.closeLargeImage([])
                }
                
                lastClickTime=0
                return
            }
        }
        lastClickTime = currentTime
        lastClickLocation = currentLocation
        super.mouseDown(with: event)
    }
    
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { // 检查是否按下了鼠标中键
            middleMouseLastLocation = event.locationInWindow
        }
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 && !globalVar.isInMiddleMouseDrag {
            if distanceBetweenPoints(middleMouseLastLocation, event.locationInWindow) < positionThreshold {
                if let collectionView = collectionView,
                   let selfIndexPath=collectionView.indexPath(for: self),
                   let viewController=getViewController(collectionView){
                    
                    if !viewController.publicVar.isInLargeView && !viewController.publicVar.isInLargeViewAfterAnimate {
                        actOpenInNewTab()
                    }
                }
            }
        }
        super.otherMouseUp(with: event)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        self.mouseDownLocation = event.locationInWindow
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        getViewController(collectionView!)!.publicVar.isColllectionViewItemRightClicked=true
          
        let mouseUpLocation = event.locationInWindow
        if let mouseDownLocation = self.mouseDownLocation {
            let maxDistance: CGFloat = 5.0 // 允许的最大移动距离
            let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)
            
            // 鼠标移动距离在允许范围内，弹出菜单
            if distance <= maxDistance {
                
                if !isSelected{
                    if let collectionView = self.collectionView {
                        if !(isCommandKeyPressed() || isShiftKeyPressed()) {
                            collectionView.deselectAll(nil)
                        }
                        if let indexPath = collectionView.indexPath(for: self),
                           let toSelect = collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [indexPath]) {
                            collectionView.selectItems(at: toSelect, scrollPosition: [])
                            collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: toSelect)
                        }
                    }
                }
                
                var selectedCount = 0
                if let collectionView = collectionView {
                    selectedCount=collectionView.selectionIndexPaths.count
                }
                
                var canPasteOrMove=true
                let pasteboard = NSPasteboard.general
                let types = pasteboard.types ?? []
                if !types.contains(.fileURL) {
                    canPasteOrMove=false
                }
                
                //弹出菜单
                let menu = NSMenu(title: "Custom Menu")
                menu.autoenablesItems = false
                
                if selectedCount > 1 {
                    let title = String(format: NSLocalizedString("(Multiselect)", comment: "(多选)"), selectedCount)
                    let actionItemMultiselect = menu.addItem(withTitle: title, action: #selector(actNewFolderWithSelection), keyEquivalent: "")
                    
                    menu.addItem(NSMenuItem.separator())
                }
                
                if selectedCount == 1 {
                    let actionItemOpen = menu.addItem(withTitle: NSLocalizedString("Open", comment: "打开"), action: #selector(actOpen), keyEquivalent: " ")
                    actionItemOpen.keyEquivalentModifierMask = []
                }
                
                if (file.type == .folder || file.type == .image || (file.type == .video && globalVar.useInternalPlayer && globalVar.HandledNativeSupportedVideoExtensions.contains(file.ext.lowercased()))) {
                    var titleTmp = NSLocalizedString("Open in New Tab", comment: "在新标签页中打开")
                    if selectedCount > 1 {
                        titleTmp = NSLocalizedString("open-in-new-tab-this", comment: "在新标签页中打开此项")
                    }
                    let actionItemOpenInNewTab = menu.addItem(withTitle: titleTmp, action: #selector(actOpenInNewTab), keyEquivalent: "")
                    if isWindowNumMax() {
                        actionItemOpenInNewTab.isEnabled=false
                    }else{
                        actionItemOpenInNewTab.isEnabled=true
                    }
                }
                
                menu.addItem(NSMenuItem.separator())
                
                addOpenWithSubMenu(to: menu)
                
                menu.addItem(withTitle: NSLocalizedString("Show in Finder", comment: "在Finder中显示"), action: #selector(actShowInFinder), keyEquivalent: "")
                
                var getInfoTitle = NSLocalizedString("file-rightmenu-get-info", comment: "显示简介")
                if selectedCount > 1 {
                    getInfoTitle = NSLocalizedString("file-rightmenu-get-statistic", comment: "显示统计")
                }
                let actionItemGetInfo = menu.addItem(withTitle: getInfoTitle, action: #selector(actGetInfo), keyEquivalent: "i")
                actionItemGetInfo.keyEquivalentModifierMask = []
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemDelete = menu.addItem(withTitle: NSLocalizedString("Move to Trash", comment: "移动到废纸篓"), action: #selector(actDelete), keyEquivalent: "\u{8}")
                actionItemDelete.keyEquivalentModifierMask = []
                //actionItemDelete.isEnabled = (items.count>0)
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemRename = menu.addItem(withTitle: NSLocalizedString("Rename", comment: "重命名"), action: #selector(actRename), keyEquivalent: "r")
                actionItemRename.keyEquivalentModifierMask = []
                
                let actionItemCopy = menu.addItem(withTitle: NSLocalizedString("Copy", comment: "复制"), action: #selector(actCopy), keyEquivalent: "c")
                
                let actionItemCopyPath = menu.addItem(withTitle: NSLocalizedString("Copy Path", comment: "复制路径"), action: #selector(actCopyPath), keyEquivalent: "")
                
                let actionItemPaste = menu.addItem(withTitle: NSLocalizedString("Paste", comment: "粘贴"), action: #selector(actPaste), keyEquivalent: "v")
                actionItemPaste.isEnabled = canPasteOrMove
                
                let actionItemMove = menu.addItem(withTitle: NSLocalizedString("Move Here", comment: "移动到此"), action: #selector(actMove), keyEquivalent: "v")
                actionItemMove.keyEquivalentModifierMask = [.command,.option]
                actionItemMove.isEnabled = canPasteOrMove
                
                let actionItemShare = menu.addItem(withTitle: NSLocalizedString("Share...", comment: "共享..."), action: #selector(actShare(_:)), keyEquivalent: "")
                
                menu.addItem(NSMenuItem.separator())
                                
                let actionItemCopyToDownload = menu.addItem(withTitle: NSLocalizedString("copy-to-download", comment: "复制到\"下载\"文件夹"), action: #selector(actCopyToDownload), keyEquivalent: "n")
                actionItemCopyToDownload.keyEquivalentModifierMask = []

                let actionItemMoveToDownload = menu.addItem(withTitle: NSLocalizedString("move-to-download", comment: "移动到\"下载\"文件夹"), action: #selector(actMoveToDownload), keyEquivalent: "m")
                actionItemMoveToDownload.keyEquivalentModifierMask = []
                
                menu.addItem(NSMenuItem.separator())
                
                // 创建"新建"子菜单
                let newMenu = NSMenu()
                let newMenuItem = NSMenuItem(title: NSLocalizedString("New", comment: "新建"), action: nil, keyEquivalent: "")
                newMenuItem.submenu = newMenu
                
                // 添加新建文件夹选项
                let newFolderItem = newMenu.addItem(withTitle: NSLocalizedString("Folder", comment: "文件夹"), 
                                                    action: #selector(actNewFolder), 
                                                    keyEquivalent: "n")
                newFolderItem.keyEquivalentModifierMask = [.command, .shift]

                newMenu.addItem(NSMenuItem.separator())
                
                // 添加新建文本文件选项
                let newTextFileItem = newMenu.addItem(withTitle: NSLocalizedString("Text File", comment: "文本文件"), 
                                                    action: #selector(actNewTextFile), 
                                                    keyEquivalent: "")

                menu.addItem(newMenuItem)
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemRefresh = menu.addItem(withTitle: NSLocalizedString("Refresh", comment: "刷新"), action: #selector(actRefresh), keyEquivalent: "r")
                actionItemRefresh.keyEquivalentModifierMask = [.command]
                
                menu.items.forEach { $0.target = self }
                NSMenu.popUpContextMenu(menu, with: event, for: self.view)
            }
        }
        self.mouseDownLocation = nil // 重置按下位置
        super.rightMouseUp(with: event)
    }
    
    @objc func actRefresh() {
        getViewController(collectionView!)?.handleUserRefresh()
    }
    
    @objc func actOpen() {
        if let collectionView = collectionView,
           let indexPath=collectionView.indexPath(for: self){
            getViewController(collectionView)?.openLargeImageFromIndexPath(indexPath)
        }
    }
    
    @objc func actOpenInNewTab() {
        if let appDelegate=NSApplication.shared.delegate as? AppDelegate {
            if file.type == .folder {
                _ = appDelegate.createNewWindow(file.path)
            }else if file.type == .image || (file.type == .video && globalVar.useInternalPlayer && globalVar.HandledNativeSupportedVideoExtensions.contains(file.ext.lowercased())){
                globalVar.isLaunchFromFile=true
                if let windowController = appDelegate.createNewWindow(file.path) {
                    appDelegate.openImageInTargetWindow(file.path, windowController: windowController)
                }
            }else{
                actOpen()
            }
        }
    }

    @objc func actShowInFinder() {
//        let folderPath = (file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding! as NSString).deletingLastPathComponent
//        NSWorkspace.shared.selectFile(file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!, inFileViewerRootedAtPath: folderPath)
        
        guard let urls = getViewController(collectionView!)?.publicVar.selectedUrls() else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    
    @objc func actNewFolderWithSelection() {
        getViewController(collectionView!)?.handleNewFolderWithSelection()
    }
    
    @objc func actGetInfo() {
        getViewController(collectionView!)?.handleGetInfo()
    }
    
    @objc func actRename() {
        guard let urls = getViewController(collectionView!)?.publicVar.selectedUrls() else { return }
        renameAlert(urls: urls);
    }
    
    @objc func actNewFolder() {
        getViewController(collectionView!)?.handleNewFolder()
    }

    @objc func actNewTextFile() {
        getViewController(collectionView!)?.handleNewTextFile()
    }

    @objc func actCopyPath() {
        guard let urls = getViewController(collectionView!)?.getSelectedURLs() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let paths = urls.map { $0.path }.joined(separator: "\n")
        pasteboard.setString(paths, forType: .string)
    }
    
    @objc func actCopy() {
        getViewController(collectionView!)?.handleCopy()
    }
    
    @objc func actCopyToDownload() {
        getViewController(collectionView!)?.handleCopyToDownload()
    }
    
    @objc func actMoveToDownload() {
        getViewController(collectionView!)?.handleMoveToDownload()
    }

    @objc func actDelete() {
        getViewController(collectionView!)?.handleDelete(isShowPrompt: false)
    }
    
    @objc func actPaste() {
        getViewController(collectionView!)?.handlePaste()
    }
    
    @objc func actMove() {
        getViewController(collectionView!)?.handleMove()
    }
    
    func addOpenWithSubMenu(to menu: NSMenu) {
        guard let fileUrls = getViewController(collectionView!)?.getSelectedURLs() else { return }

        let openWithMenu = NSMenu(title: "openWith")
        let openWithMenuItem = NSMenuItem(title: NSLocalizedString("Open With", comment: "打开方式"), action: nil, keyEquivalent: "")
        openWithMenuItem.submenu = openWithMenu
        
        // 获取每种文件类型的一个代表 URL
        let representativeUrls = getRepresentativeUrls(for: fileUrls)
        
        // 获取代表 URL 的可用应用程序并计算交集
        let commonAppURLs = calculateCommonApplications(for: representativeUrls)
        
        for appURL in commonAppURLs {
            let appName = FileManager.default.displayName(atPath: appURL.path)
            let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            let appMenuItem = NSMenuItem(title: appName.replacingOccurrences(of: ".app", with: " "), action: #selector(openFileWithApp(_:)), keyEquivalent: "")
            appMenuItem.representedObject = appURL
            appMenuItem.target = self
            appMenuItem.image = appIcon
            appMenuItem.image?.size = NSSize(width: 16, height: 16)  // Optionally resize the icon if needed
            openWithMenu.addItem(appMenuItem)
        }
        
        if commonAppURLs.isEmpty {
            let emptyMenuItem = NSMenuItem(
                title: NSLocalizedString("empty-enclose", comment: "菜单当内容为空时显示的东西"),
                action: nil,
                keyEquivalent: ""
            )
            openWithMenu.addItem(emptyMenuItem)
        }
        
        // 添加到主菜单
        menu.addItem(openWithMenuItem)
    }
    
    @objc private func selectApplication(_ sender: NSMenuItem) {
        guard let fileUrls = getViewController(collectionView!)?.getSelectedURLs() else { return }
        if let appURL = sender.representedObject as? URL {
            NSWorkspace.shared.open(fileUrls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: { (app, error) in
                if let error = error {
                    log("Error opening file: \(error.localizedDescription)")
                } else if let app = app {
                    log("Application \(app.localizedName ?? "Unknown") opened")
                }
            })
        }
    }
    
    private func getRepresentativeUrls(for fileUrls: [URL]) -> [URL] {
        var representativeUrls: [String: URL] = [:]
        
        for fileUrl in fileUrls {
            let fileExtension = fileUrl.pathExtension.lowercased()
            if representativeUrls[fileExtension] == nil {
                representativeUrls[fileExtension] = fileUrl
            }
        }
        
        return Array(representativeUrls.values)
    }
    
    private func calculateCommonApplications(for representativeUrls: [URL]) -> [URL] {
        guard !representativeUrls.isEmpty else { return [] }
        
        // 获取每个代表 URL 的应用程序列表
        var appURLLists: [[URL]] = []
        
        for fileUrl in representativeUrls {
            let cfFileUrl = fileUrl as CFURL
            let appURLs = LSCopyApplicationURLsForURL(cfFileUrl, .all)?.takeRetainedValue() as? [URL] ?? []
            appURLLists.append(appURLs)
        }
        
        // 计算交集并保留顺序
        guard let firstList = appURLLists.first else { return [] }
        
        // 从第一个列表开始，过滤出在所有列表中都存在的应用程序
        let commonApps = firstList.filter { appURL in
            appURLLists.dropFirst().allSatisfy { $0.contains(appURL) }
        }
        
        return commonApps
    }

    @objc func openFileWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL else { return }
        guard let fileUrls = getViewController(collectionView!)?.getSelectedURLs() else { return }
        
        NSWorkspace.shared.open(fileUrls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: { (app, error) in
            if let error = error {
                log("Error opening file: \(error.localizedDescription)")
            } else if let app = app {
                log("Application \(app.localizedName ?? "Unknown") opened")
            }
        })
    }
    
    @objc func actShare(_ sender: NSMenuItem) {
        guard let urls = getViewController(collectionView!)?.getSelectedURLs() else { return }
        let sharingServicePicker = NSSharingServicePicker(items: urls)
        sharingServicePicker.show(relativeTo: view.bounds, of: self.view, preferredEdge: .maxX)
    }

}
