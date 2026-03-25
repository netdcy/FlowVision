//
//  CustomCollectionViewItem.swift
//  FlowVision
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
    var finderTagDotsView: NSView?
    var ratingStarsView: NSView?
    var aliasBadgeView: NSImageView?
    private var mouseDownLocation: NSPoint? = nil
    
    private var lastClickTime: TimeInterval = 0
    private var lastClickLocation: NSPoint = NSPoint.zero
    // 双击位置阈值，可以根据需要调整
    // Double-click position threshold, can be adjusted as needed
    private let positionThreshold: CGFloat = 4.0
    
    private var middleMouseLastLocation: NSPoint = NSPoint.zero
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        view.wantsLayer = true
        view.layer?.cornerRadius = 5.0
        view.layer?.masksToBounds = false
        
        // 图像容器
        // Image container
        imageViewObj.imageScaling = .scaleAxesIndependently
        imageViewObj.wantsLayer = true
        imageViewObj.layer?.borderWidth = 0.0
        imageViewObj.layer?.borderColor = nil
        // 这里可以根据需要调整圆角的半径
        // Corner radius can be adjusted here as needed
        imageViewObj.layer?.cornerRadius = 5.0
        imageViewObj.layer?.masksToBounds = true
        imageViewObj.animates=true
        if #available(macOS 14.0, *) {
            imageViewObj.preferredImageDynamicRange = .standard
        }
        
        // 文件名标签
        // Filename label
        imageNameField.cell?.lineBreakMode = .byTruncatingTail
        
        // 右上角标签
        // Top-right corner label
        imageLabel.wantsLayer = true
        imageLabel.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.6).cgColor
        imageLabel.layer?.cornerRadius = 4
//        imageLabel.layer?.borderWidth = 0.5
//        imageLabel.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
        
        // 视频图标
        // Video icon
        let playImage = NSImage(systemSymbolName: "play.circle", accessibilityDescription: "Video")?.withSymbolConfiguration(.init(pointSize: 0, weight: .regular, scale: .large))
        playImage?.isTemplate = true
        videoFlag.image = playImage
        videoFlag.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        videoFlag.imageScaling = .scaleAxesIndependently
        videoFlag.wantsLayer = true

        // 视频播放器
        // Video player
        queuePlayer = AVQueuePlayer()
        queuePlayer?.isMuted = true
        
        // 初始化 AVPlayerLayer
        // Initialize AVPlayerLayer
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
//            // 阴影
//            shadowView.layer?.shadowColor = NSColor.black.cgColor
//            shadowView.layer?.shadowOpacity = 0.8
//            shadowView.layer?.shadowOffset = CGSize(width: 3, height: -3)
//            shadowView.layer?.shadowRadius = 5
//            // 边框
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
//            // contentView.layer?.backgroundColor = NSColor.white.cgColor // 背景颜色，对于透明png？
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
            // Handle selected state
            selectedColor()
        } else {
            // 未选中状态的处理代码
            // Handle unselected state
            deselectedColor()
        }
        lastClickTime=0
        updateCutDimEffect()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopVideo()
    }
    
    override var isSelected: Bool {
        didSet {
            super.isSelected = isSelected
            // 在这里处理选中状态变化
            // Handle selection state change here
            if isSelected && !getViewController(collectionView!)!.publicVar.isInLargeView {
                // 选中状态的处理代码
                // Handle selected state
                selectedColor()
            } else {
                // 未选中状态的处理代码
                // Handle unselected state
                deselectedColor()
            }

            if (getViewController(collectionView!)!.publicVar.autoPlayVisibleVideo ||
                (isSelected && getViewController(collectionView!)!.publicVar.autoPlaySelectedVideo)) &&
                isItemVisible() &&
                !getViewController(collectionView!)!.publicVar.isInLargeView {
                playVideo()
            }else{
                stopVideo()
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
    
    private func tagScaleFactor() -> CGFloat {
        guard let vc = getViewController(collectionView!) else { return 1.0 }
        let thumbSize = CGFloat(vc.publicVar.profile.thumbSize)
        let baseScale = thumbSize / 512.0 * 1.0

        let layoutCoefficient: CGFloat
        switch vc.publicVar.profile.layoutType {
        case .justified:
            layoutCoefficient = 1.3
        case .waterfall:
            layoutCoefficient = 1.2
        case .grid:
            layoutCoefficient = 1.1
        case .detail:
            layoutCoefficient = 1.0
        }

        return max(1.0, min(2.5, baseScale * layoutCoefficient))
    }

    /// 根据评级返回对应颜色（1–5 星：灰 → 银 → 橙 → 黄 → 金，便于区分）
    private static func color(forRating rating: Int) -> NSColor {
        switch rating {
        case 1: return NSColor(calibratedWhite: 0.5, alpha: 1)           // 灰
        case 2: return NSColor(calibratedWhite: 0.7, alpha: 1)             // 浅灰/银
        case 3: return NSColor.systemOrange                                // 橙
        case 4: return NSColor(calibratedRed: 1, green: 0.88, blue: 0.2, alpha: 1)  // 黄
        case 5: return NSColor(calibratedRed: 1, green: 0.68, blue: 0, alpha: 1)     // 金
        default: return NSColor.systemGray
        }
    }

    func refreshRatingStars() {
        ratingStarsView?.removeFromSuperview()
        ratingStarsView = nil

        let isShowThumbnailTag = getViewController(collectionView!)!.publicVar.profile.getValue(forKey: "isShowThumbnailTag") == "true"
        guard isShowThumbnailTag, let rating = file.imageInfo?.rating, rating >= 1, rating <= 5 else { return }

        let scale = tagScaleFactor()
        let starSize: CGFloat = round(13 * scale)
        let spacing: CGFloat = round(2 * scale)
        let inset: CGFloat = round(5 * scale)
        let starCount = rating
        let color = Self.color(forRating: rating)

        let totalWidth = CGFloat(starCount) * starSize + CGFloat(starCount - 1) * spacing
        let containerHeight = starSize

        let container = NSView()
        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: imageViewObj.leadingAnchor, constant: inset),
            container.topAnchor.constraint(equalTo: imageViewObj.topAnchor, constant: inset-1),
            container.widthAnchor.constraint(equalToConstant: totalWidth),
            container.heightAnchor.constraint(equalToConstant: containerHeight),
        ])

        let config = NSImage.SymbolConfiguration(pointSize: starSize - 2, weight: .medium, scale: .medium)
        let fillImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Star")?.withSymbolConfiguration(config)
        fillImage?.isTemplate = true
        let outlineImage = NSImage(systemSymbolName: "star", accessibilityDescription: "Star outline")?.withSymbolConfiguration(config)
        outlineImage?.isTemplate = true

        for i in 0..<starCount {
            let starFrame = NSRect(x: CGFloat(i) * (starSize + spacing), y: 0, width: starSize, height: starSize)
            let starContainer = NSView(frame: starFrame)

            let fillView = NSImageView(frame: starContainer.bounds)
            fillView.image = fillImage
            fillView.contentTintColor = color
            fillView.imageScaling = .scaleProportionallyDown

            let outlineView = NSImageView(frame: starContainer.bounds)
            outlineView.image = outlineImage
            outlineView.contentTintColor = .white
            outlineView.imageScaling = .scaleProportionallyDown

            starContainer.addSubview(fillView)
            starContainer.addSubview(outlineView)
            container.addSubview(starContainer)
        }

        ratingStarsView = container
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        finderTagDotsView?.removeFromSuperview()
        finderTagDotsView = nil
        ratingStarsView?.removeFromSuperview()
        ratingStarsView = nil
        aliasBadgeView?.removeFromSuperview()
        aliasBadgeView = nil
    }

    func refreshFinderTagDots() {
        finderTagDotsView?.removeFromSuperview()
        finderTagDotsView = nil

        let isShowThumbnailTag = getViewController(collectionView!)!.publicVar.profile.getValue(forKey: "isShowThumbnailTag") == "true"
        if !isShowThumbnailTag { return }

        let tags = file.finderTags.compactMap { FinderTag.byName($0) }
        guard !tags.isEmpty else { return }

        let colorTags = tags.filter { $0.isSystemColorLabel }
        let textTags = tags.filter { !$0.isSystemColorLabel }
        let sortedTags = colorTags + textTags

        let scale = tagScaleFactor()
        let dotSize: CGFloat = round(8 * scale)
        let spacing: CGFloat = round(2 * scale)
        let fontSize: CGFloat = round(9 * scale)
        let textPaddingH: CGFloat = round(4 * scale)
        let textPaddingV: CGFloat = round(2 * scale)
        let inset: CGFloat = round(6 * scale)
        let textFont = NSFont.systemFont(ofSize: fontSize)

        var totalWidth: CGFloat = 0
        for (i, tag) in sortedTags.enumerated() {
            if i > 0 { totalWidth += spacing }
            if tag.isSystemColorLabel {
                totalWidth += dotSize
            } else {
                let textWidth = (tag.name as NSString).size(withAttributes: [.font: textFont]).width
                totalWidth += ceil(textWidth) + textPaddingH * 2
            }
        }

        let containerHeight = dotSize + textPaddingV * 2

        let container = NSView()
        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: imageViewObj.leadingAnchor, constant: inset),
            container.bottomAnchor.constraint(equalTo: imageViewObj.bottomAnchor, constant: -(inset-1)),
            container.widthAnchor.constraint(equalToConstant: totalWidth),
            container.heightAnchor.constraint(equalToConstant: containerHeight),
        ])

        var xOffset: CGFloat = 0
        for tag in sortedTags {
            if tag.isSystemColorLabel {
                let dotY = (containerHeight - dotSize) / 2
                let dot = NSView(frame: NSRect(x: xOffset, y: dotY, width: dotSize, height: dotSize))
                dot.wantsLayer = true
                dot.layer?.backgroundColor = tag.color.cgColor
                dot.layer?.cornerRadius = dotSize / 2
                let isLight = (tag.color.usingColorSpace(.genericGray)?.whiteComponent ?? 0) > 0.9
                dot.layer?.borderColor = (isLight ? NSColor.gray : NSColor.white).cgColor
                dot.layer?.borderWidth = round(0.5 * scale * 2) / 2
                container.addSubview(dot)
                xOffset += dotSize + spacing
            } else {
                let textWidth = (tag.name as NSString).size(withAttributes: [.font: textFont]).width
                let labelWidth = ceil(textWidth) + textPaddingH * 2
                let label = NSTextField(labelWithString: tag.name)
                label.font = textFont
                label.textColor = .black
                label.alignment = .center
                label.wantsLayer = true
                label.layer?.borderColor = NSColor.gray.cgColor
                label.layer?.borderWidth = round(1 * scale * 2) / 2
                label.layer?.cornerRadius = round(3 * scale)
                label.layer?.backgroundColor = tag.color.withAlphaComponent(0.7).cgColor
                label.frame = NSRect(x: xOffset, y: 0, width: labelWidth, height: containerHeight)
                container.addSubview(label)
                xOffset += labelWidth + spacing
            }
        }

        finderTagDotsView = container
    }

    func refreshAliasBadge() {
        aliasBadgeView?.removeFromSuperview()
        aliasBadgeView = nil

        guard file.isAlias, let badgeImage = NSImage(named: "AliasBadge") else { return }

        let badgeRatio = badgeImage.size.width / badgeImage.size.height
        let scale = tagScaleFactor() * 1.8
        let badgeHeight = round(16 * scale)
        let badgeWidth = round(badgeHeight * badgeRatio)
        let inset: CGFloat = round(0 * scale)

        let badge = NSImageView()
        badge.image = badgeImage
        badge.imageScaling = .scaleProportionallyUpOrDown
        badge.wantsLayer = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(badge)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: imageViewObj.leadingAnchor, constant: inset),
            badge.bottomAnchor.constraint(equalTo: imageViewObj.bottomAnchor, constant: -inset),
            badge.widthAnchor.constraint(equalToConstant: badgeWidth),
            badge.heightAnchor.constraint(equalToConstant: badgeHeight),
        ])

        aliasBadgeView = badge
    }

    func configureWithImage(_ fileModel: FileModel, playAnimation: Bool = false) {
        
        stopVideo()
        
        self.file=fileModel
        
        setTooltip()
        
        imageNameField.stringValue=getViewController(collectionView!)!.publicVar.profile.isShowThumbnailFilename ? URL(string:file.path)!.lastPathComponent : ""

        if isSelected {
            // 选中状态的处理代码
            // Handle selected state
            selectedColor()
        } else {
            // 未选中状态的处理代码
            // Handle unselected state
            deselectedColor()
        }
        
        imageViewObj.url = URL(string: file.path)
        if file.isDir {
            imageViewObj.isFolder = true
        }else{
            imageViewObj.isFolder = false
        }

        // 左下角替身徽章
        // Bottom-left alias badge
        refreshAliasBadge()

        // 左上角评级
        // Top-left rating stars
        refreshRatingStars()

        // 左下角Finder标签
        // Bottom-left finder tag dots
        refreshFinderTagDots()

        // 右上角HDR/RAW标签
        // Top-right corner HDR/RAWlabel
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
            // 先调整文字大小
            // Adjust text size first
            imageLabel.sizeToFit()
            imageLabel.frame.origin.x = imageViewObj.frame.origin.x + imageViewObj.frame.width - imageLabel.frame.width - 5
            imageLabel.frame.origin.y = imageViewObj.frame.origin.y + imageViewObj.frame.height - imageLabel.frame.height - 5
            imageLabel.isHidden=false
        } else {
            imageLabel.isHidden=true
        }
        
        guard let style = getViewController(collectionView!)?.publicVar.profile else {return}
        if file.type == .video && (getViewController(collectionView!)!.publicVar.profile.layoutType == .grid || style.ThumbnailBorderThickness == 0) {
            // 设置视频播放图标的大小为视图宽度的1/4
            // Set video play icon size to 1/4 of view width
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
        
        if (getViewController(collectionView!)!.publicVar.autoPlayVisibleVideo || (getViewController(collectionView!)!.publicVar.autoPlaySelectedVideo && isSelected)) && isItemVisible() {
            playVideo()
        }
        
        if(playAnimation){
            NSAnimationContext.runAnimationGroup({ context in
                // 设置动画持续时间秒
                // Set animation duration in seconds
                context.duration = 0.1
                
                // 使用Core Animation的crossfade效果
                // Use Core Animation crossfade effect
                // 确保imageView使用了CALayer
                // Ensure imageView uses CALayer
                imageViewObj.wantsLayer = true
                let transition = CATransition()
                transition.type = CATransitionType.fade
                transition.duration = context.duration
                imageViewObj.layer?.add(transition, forKey: kCATransition)
                
                // 设置新图像
                // Set new image
                imageViewObj.image = file.image
                // imageViewObj.sd_setImage(with: URL(string: path), placeholderImage: nil)
                
//                if file.folderImages.count>0{
//                    folderViews[0].isHidden=false
//                    folderImageViews[0].image=file.folderImages[0]
//                }else{
//                    folderViews[0].isHidden=true
//                    folderImageViews[0].image=nil
//                }

            }, completionHandler: {
                // 动画完成后的操作（如果有）
                // Operations after animation completes (if any)
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
        
        updateCutDimEffect()
    }
    
    func updateCutDimEffect() {
        let isCut = globalVar.cutItemPaths.contains(file.path)
        let targetAlpha: CGFloat = isCut ? 0.4 : 1.0
        // 由于布局过程中alpha值可能会被重置，需要等待布局完成后再设置
        // Since the alpha value may be reset during layout, it needs to be set after layout is complete
        DispatchQueue.main.async { [weak self] in
            self?.view.alphaValue = targetAlpha
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
        // 当前目录
        // Current directory
        let curFolder = getViewController(collectionView!)!.fileDB.curFolder.removingPercentEncoding!

        // 获取文件名
        // Get filename
        let fileName = (filePath as NSString).lastPathComponent
        
        // 获取相对路径
        // Get relative path
        var relativePath = "./" + filePath.replacingOccurrences(of: curFolder, with: "")
        if relativePath.hasSuffix("/") {
            relativePath = String(relativePath.dropLast())
        }
        relativePath = relativePath.replacingOccurrences(of: fileName, with: "")
        
        // 准备局部化字符串
        // Prepare localized strings
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
        // Generate array of Tooltip strings
        var tooltipParts: [String] = []
        
        // 添加文件名
        // Add filename
        tooltipParts.append("\(nameLabel): \(fileName)")
        
        // 添加相对路径
        // Add relative path
        if getViewController(collectionView!)!.publicVar.isRecursiveMode {
            tooltipParts.append("\(relativePathLabel): \(relativePath)")
        }

        if curFolder.hasPrefix("file:///VirtualFinderTagsFolder") {
            let parentDirectoryLabel = NSLocalizedString("Location", comment: "位置")
            var parentDirectory = (filePath as NSString).deletingLastPathComponent
            if parentDirectory.hasPrefix("file:") {
                parentDirectory = String(parentDirectory.dropFirst("file:".count))
            }
            tooltipParts.append("\(parentDirectoryLabel): \(parentDirectory)")
        }

        // 如果文件大小存在，添加文件大小
        // If file size exists, add file size
        if let fileSize = fileSize {
            let byteCountFormatter = ByteCountFormatter()
            byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
            byteCountFormatter.countStyle = .file
            let formattedFileSize = byteCountFormatter.string(fromByteCount: Int64(fileSize))
            tooltipParts.append("\(sizeLabel): \(formattedFileSize)")
        }
        
        // 如果图像尺寸存在，添加图像尺寸
        // If image size exists, add image size
        if let imageSize = imageSize {
            let formattedImageSize = "\(Int(imageSize.width)) x \(Int(imageSize.height))"
            tooltipParts.append("\(dimensionsLabel): \(formattedImageSize)")
        }
        
        // 日期格式化器
        // Date formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        // 如果创建日期存在，添加创建日期
        // If creation date exists, add creation date
        if let creationDate = creationDate {
            let formattedCreationDate = dateFormatter.string(from: creationDate)
            tooltipParts.append("\(creationDateLabel): \(formattedCreationDate)")
        }
        
        // 如果修改日期存在，添加修改日期
        // If modification date exists, add modification date
        if let modificationDate = modificationDate {
            let formattedModificationDate = dateFormatter.string(from: modificationDate)
            tooltipParts.append("\(modificationDateLabel): \(formattedModificationDate)")
        }
        
        // 如果添加日期存在，添加添加日期
        // If add date exists, add add date
        if let addDate = addDate {
            let formattedAddDate = dateFormatter.string(from: addDate)
            tooltipParts.append("\(addDateLabel): \(formattedAddDate)")
        }
        
        // 将所有部分连接成最终的Tooltip字符串
        // Join all parts into final Tooltip string
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
            // Check if currently playing video is already the target video
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
        
        // 设置frame
        // Set frame
        setCustomFrameSize()
        
        let theme=NSApp.effectiveAppearance.name
        
        // 定义失去焦点时的边框颜色
        // Define border color when losing focus
        // 失焦
        // Out of focus
        var focusColor = NSColor.systemGray
        if getViewController(collectionView!)!.publicVar.isCollectionViewFirstResponder || getViewController(collectionView!)!.publicVar.isInSearchState {
            // 聚焦
            // In focus
            focusColor = NSColor.controlAccentColor
        } else if style.ThumbnailBorderThickness == 0 {
            focusColor = NSColor.black
        }
        
        // 文件名颜色
        // Filename color
        if style.ThumbnailBorderThickness == 0 {
            imageNameField.textColor = focusColor
        }else{
            imageNameField.textColor = hexToNSColor(hex: "#FFFFFF")
        }
        
        // 占位背景色
        // Placeholder background color
        if file.isDir {
            // 填充
            // Fill
            imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
        }else{
            if theme == .darkAqua {
                // 填充
                // Fill
                // imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#505050").cgColor
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#404040").cgColor
            }else{
                // 填充
                // Fill
                // imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#CECECE").cgColor
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#DDDDDD").cgColor
            }
        }
        
        // 边框颜色
        // Border color
        view.layer?.backgroundColor = focusColor.cgColor
        
        // 边框为0时不显示底色
        // Don't show background color when border thickness is 0
        if style.ThumbnailBorderThickness == 0 {
            view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            if file.getThumbFailed || !(file.type == .image || file.type == .video || file.ext == "pdf") {
                imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            }
        }
        
        // 图像高亮-选中
        // Image highlight - selected
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
        
        // 设置frame
        // Set frame
        setCustomFrameSize()
        
        let theme=NSApp.effectiveAppearance.name
        
        // 文件名颜色
        // Filename color
        imageNameField.textColor = hexToNSColor(hex: "#7E7E7E")
        
        // 占位背景色和边框颜色
        // Placeholder background color and border color
        if file.isDir {
            imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
        // 文件
        // File
        }else{
            // 黑暗模式
            // Dark mode
            if theme == .darkAqua {
                // 填充
                // Fill
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#404040").cgColor
                if file.type == .video
                {
                    // 视频边框
                    // Video border
                    view.layer?.backgroundColor = hexToNSColor(hex: "#DDDDDD").cgColor
                }else{
                    // 图片边框
                    // Image border
                    view.layer?.backgroundColor = hexToNSColor(hex: "#3A3A3A").cgColor
                }
            }else{
                // 浅色模式
                // Light mode
                // 填充
                // Fill
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#DDDDDD").cgColor
                if file.type == .video
                {
                    // 视频边框
                    // Video border
                    view.layer?.backgroundColor = hexToNSColor(hex: "#404040").cgColor
                }else{
                    // 图片边框
                    // Image border
                    view.layer?.backgroundColor = hexToNSColor(hex: "#F4F5F5").cgColor
                }
            }
        }
        
        // 边框为0时不显示底色
        // Don't show background color when border thickness is 0
        if style.ThumbnailBorderThickness == 0 {
            view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            if file.getThumbFailed || !(file.type == .image || file.type == .video || file.ext == "pdf") {
                imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            }
        }
        
        // 图像高亮-取消选中
        // Image highlight - deselected
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
        // Limit corner radius to not exceed half of view size
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
        
        // 阴影效果
        // Shadow effect
        if (style.ThumbnailShowShadow || style.layoutType == .grid) && (file.type == .image || file.type == .video || file.ext == "pdf") && !file.getThumbFailed {
            view.layer?.shadowColor = NSColor.black.withAlphaComponent(0.4).cgColor
            view.layer?.shadowOffset = CGSize(width: 1.3, height: -1.3)
            view.layer?.shadowRadius = 2.5
            view.layer?.shadowOpacity = 1
            // 添加shadowPath以提高性能
            // Add shadowPath to improve performance
            let cutoff = (style.ThumbnailBorderThickness == 0 && style.layoutType != .grid) ? style.ThumbnailFilenamePadding : 0
            let rect = CGRect(x: view.bounds.origin.x, y: view.bounds.origin.y + cutoff, width: view.bounds.width, height: view.bounds.height - cutoff)
            let path = CGMutablePath()
            if borderRadius > 0 {
                // 限制圆角半径不超过视图尺寸的一半
                // Limit corner radius to not exceed half of view size
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
        // print("mouseDownItem: ",file.id)
        let currentTime = event.timestamp
        let currentLocation = event.locationInWindow
        if currentTime - lastClickTime < NSEvent.doubleClickInterval &&
            distanceBetweenPoints(lastClickLocation, currentLocation) < positionThreshold {
            if let collectionView = collectionView,
               var selfIndexPath=collectionView.indexPath(for: self),
               let viewController = getViewController(collectionView) {
                
                // 由于连续点击事件的处理会触发上个目录在当前位置item的事件，其id是随机的，因此需要做此修正
                // Since handling consecutive click events will trigger events from the previous directory's item at the current position, whose id is random, this correction is needed
                if let clickedIndexPath = collectionView.indexPathForItem(at: collectionView.convert(event.locationInWindow, from: nil)) {
                    selfIndexPath = clickedIndexPath
                }
                
                if !viewController.publicVar.isInLargeView && !viewController.publicVar.isInLargeViewAfterAnimate {
                    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
                        actOpenInNewTab()
                    }else{
                        viewController.openLargeImageFromIndexPath(selfIndexPath)
                        viewController.largeImageView.videoPreventDoubleClickOpenPauseFlag = true
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
        // 检查是否按下了鼠标中键
        // Check if middle mouse button is pressed
        if event.buttonNumber == 2 {
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
            // 允许的最大移动距离
            // Maximum allowed movement distance
            let maxDistance: CGFloat = 5.0
            let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)
            
            // 鼠标移动距离在允许范围内，弹出菜单
            // If mouse movement is within allowed range, show context menu
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

                let curFolder = getViewController(collectionView!)!.fileDB.curFolder
                let isVirtualFinderTagsFolder = curFolder.hasPrefix("file:///VirtualFinderTagsFolder")
                
                // 弹出菜单
                // Show context menu
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

                let isRecursive = getViewController(collectionView!)?.publicVar.isRecursiveMode ?? false
                let canShowParent = selectedCount == 1 && (isRecursive || getViewController(collectionView!)!.fileDB.curFolder.hasPrefix("file:///VirtualFinderTagsFolder"))
                if canShowParent, let url = URL(string: file.path) {
                    let parentURL = url.deletingLastPathComponent()
                    if !parentURL.path.isEmpty && parentURL.absoluteString != url.absoluteString {
                        let actionItemShowParent = menu.addItem(withTitle: NSLocalizedString("Show in Original Folder", comment: "在原文件夹中显示"), action: #selector(actShowParentInNewTab), keyEquivalent: "")
                        if isWindowNumMax() {
                            actionItemShowParent.isEnabled = false
                        } else {
                            actionItemShowParent.isEnabled = true
                        }
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
                // actionItemDelete.isEnabled = (items.count>0)
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemRename = menu.addItem(withTitle: NSLocalizedString("Rename", comment: "重命名"), action: #selector(actRename), keyEquivalent: "r")
                actionItemRename.keyEquivalentModifierMask = []
                
                let actionItemCopy = menu.addItem(withTitle: NSLocalizedString("Copy", comment: "复制"), action: #selector(actCopy), keyEquivalent: "c")
                
                let actionItemCopyPath = menu.addItem(withTitle: NSLocalizedString("Copy Path", comment: "复制路径"), action: #selector(actCopyPath), keyEquivalent: "")
                
                let actionItemPaste = menu.addItem(withTitle: NSLocalizedString("Paste", comment: "粘贴"), action: #selector(actPaste), keyEquivalent: "v")
                actionItemPaste.isEnabled = canPasteOrMove && !isVirtualFinderTagsFolder
                
                let actionItemMove = menu.addItem(withTitle: NSLocalizedString("Move Here", comment: "移动到此"), action: #selector(actMove), keyEquivalent: "v")
                actionItemMove.keyEquivalentModifierMask = [.command,.option]
                actionItemMove.isEnabled = canPasteOrMove && !isVirtualFinderTagsFolder
                
                let actionItemShare = menu.addItem(withTitle: NSLocalizedString("Share...", comment: "共享..."), action: #selector(actShare(_:)), keyEquivalent: "")

                menu.addItem(NSMenuItem.separator())

                let selectedURLs = getViewController(collectionView!)?.publicVar.selectedUrls() ?? []
                let tagsPerURL = selectedURLs.map { FinderTagHelper.readTags(from: $0) }
                let allTags = FinderTag.all
                let activeTagNames: Set<String> = {
                    guard !selectedURLs.isEmpty else { return [] }
                    return Set(allTags.filter { tag in
                        tagsPerURL.allSatisfy { $0.contains(tag.name) }
                    }.map { $0.name })
                }()

                let finderTagMenu = NSMenu()
                let finderTagTitle = NSLocalizedString("Finder Tags", comment: "Finder标签")
                let finderTagMenuItem = NSMenuItem(title: finderTagTitle, action: nil, keyEquivalent: "")
                finderTagMenuItem.submenu = finderTagMenu

                for (i, tag) in allTags.enumerated() {
                    let item = finderTagMenu.addItem(withTitle: NSLocalizedString(tag.name, comment: ""), action: #selector(actToggleFinderTag(_:)), keyEquivalent: (i + 1 <= 9) ? "\(i + 1)" : "")
                    item.keyEquivalentModifierMask = [.command]
                    item.representedObject = tag.name
                    if activeTagNames.contains(tag.name) {
                        item.state = .on
                    }
                    item.image = tag.dotImage
                }

                finderTagMenu.addItem(NSMenuItem.separator())
                finderTagMenu.addItem(withTitle: NSLocalizedString("Remove All Tags", comment: "移除所有标签"), action: #selector(actRemoveAllFinderTags), keyEquivalent: "")

                if file.isDir {
                    finderTagMenu.addItem(NSMenuItem.separator())
                    finderTagMenu.addItem(withTitle: NSLocalizedString("Scan & Update Enhanced Index", comment: "扫描并更新增强索引"), action: #selector(actScanEnhancedIndex), keyEquivalent: "")
                }

                finderTagMenu.addItem(NSMenuItem.separator())
                finderTagMenu.addItem(withTitle: NSLocalizedString("Learn More...", comment: "了解更多..."), action: #selector(actTagLearnMore), keyEquivalent: "")

                let colorTags = allTags//.filter { $0.colorIndex != nil && $0.colorIndex != 0 }
                if !colorTags.isEmpty {
                    let dotsItem = NSMenuItem()
                    let dotsView = FinderTagDotsView(tags: colorTags, activeTags: activeTagNames) { [weak self, weak menu] tagName in
                        guard let self = self, let menu = menu else { return }
                        getViewController(self.collectionView!)?.handleToggleFinderTag(tagName)
                        menu.cancelTracking()
                    }
                    dotsView.onHoverChanged = { [weak finderTagMenuItem] index in
                        guard let finderTagMenuItem = finderTagMenuItem else { return }
                        if index >= 0 && index < colorTags.count {
                            let tag = colorTags[index]
                            if activeTagNames.contains(tag.name) {
                                finderTagMenuItem.title = NSLocalizedString("Remove", comment: "移除") + "\"\(tag.name)\""
                            } else {
                                finderTagMenuItem.title = NSLocalizedString("Add", comment: "添加") + "\"\(tag.name)\""
                            }
                            let attrTitle = NSAttributedString(
                                string: finderTagMenuItem.title,
                                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                            )
                            finderTagMenuItem.attributedTitle = attrTitle
                        } else {
                            finderTagMenuItem.attributedTitle = nil
                            finderTagMenuItem.title = finderTagTitle
                        }
                    }
                    dotsItem.view = dotsView
                    menu.addItem(dotsItem)
                }

                menu.addItem(finderTagMenuItem)
                
                let rateSubMenu = NSMenu(title: NSLocalizedString("Rating", comment: "评级"))
                let rateMenuItem = NSMenuItem(title: NSLocalizedString("Rating", comment: "评级"), action: nil, keyEquivalent: "")
                rateMenuItem.submenu = rateSubMenu
                rateMenuItem.isEnabled = file.type == .image

                // 5~1 星，带星形预览
                for rating in (1...5).reversed() {
                    let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
                    let title = "\(stars)  (\(rating))"
                    let item = NSMenuItem(title: title, action: #selector(actRate(_:)), keyEquivalent: "\(rating)")
                    item.keyEquivalentModifierMask = [.control]
                    item.tag = rating
                    item.target = self
                    rateSubMenu.addItem(item)
                }

                // 无评级
                let clearTitle = NSLocalizedString("No Rating", comment: "无评级")
                let clearItem = NSMenuItem(title: clearTitle, action: #selector(actRate(_:)), keyEquivalent: "0")
                clearItem.keyEquivalentModifierMask = [.control]
                clearItem.tag = 0
                clearItem.target = self
                rateSubMenu.addItem(clearItem)

                rateSubMenu.addItem(NSMenuItem.separator())
                
                let rateReadmeItem = NSMenuItem(title: NSLocalizedString("Readme...", comment: "说明..."), action: #selector(actRateReadmeAction), keyEquivalent: "")
                rateReadmeItem.target = self
                rateSubMenu.addItem(rateReadmeItem)
                
                menu.addItem(rateMenuItem)
                
                menu.addItem(NSMenuItem.separator())
                                
                let actionItemCopyToDownload = menu.addItem(withTitle: NSLocalizedString("copy-to-download", comment: "复制到\"下载\"文件夹"), action: #selector(actCopyToDownload), keyEquivalent: "n")
                actionItemCopyToDownload.keyEquivalentModifierMask = []

                let actionItemMoveToDownload = menu.addItem(withTitle: NSLocalizedString("move-to-download", comment: "移动到\"下载\"文件夹"), action: #selector(actMoveToDownload), keyEquivalent: "m")
                actionItemMoveToDownload.keyEquivalentModifierMask = []

                menu.addItem(NSMenuItem.separator())

                // 创建"新建"子菜单
                // Create "New" submenu
                let newMenu = NSMenu()
                let newMenuItem = NSMenuItem(title: NSLocalizedString("New", comment: "新建"), action: nil, keyEquivalent: "")
                newMenuItem.submenu = newMenu
                newMenuItem.isEnabled = !isVirtualFinderTagsFolder
                
                // 添加新建文件夹选项
                // Add new folder option
                let newFolderItem = newMenu.addItem(withTitle: NSLocalizedString("Folder", comment: "文件夹"), 
                                                    action: #selector(actNewFolder), 
                                                    keyEquivalent: "n")
                newFolderItem.keyEquivalentModifierMask = [.command, .shift]

                newMenu.addItem(NSMenuItem.separator())
                
                // 添加新建文本文件选项
                // Add new text file option
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
        // 重置按下位置
        // Reset mouse down location
        self.mouseDownLocation = nil
        super.rightMouseUp(with: event)
    }

    @objc func actToggleFinderTag(_ sender: NSMenuItem) {
        guard let tagName = sender.representedObject as? String else { return }
        getViewController(collectionView!)?.handleToggleFinderTag(tagName)
    }

    @objc func actRemoveAllFinderTags() {
        let urls = getViewController(collectionView!)?.publicVar.selectedUrls() ?? []
        guard !urls.isEmpty else { return }
        FinderTagHelper.removeAllTags(from: urls)
        getViewController(collectionView!)?.refreshFinderTagsForVisibleItems(urls: urls)
    }

    @objc func actScanEnhancedIndex() {
        guard file.isDir, let url = URL(string: file.path) else { return }
        getViewController(collectionView!)?.handleScanEnhancedIndex(url: url)
    }

    @objc func actScanEnhancedIndexReadmeAction() {
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("scan-enhanced-index-info", comment: "扫描并更新增强索引说明..."))
    }

    @objc func actTagLearnMore() {
        getViewController(collectionView!)?.handleTagLearnMore()
    }
    
    @objc func actRate(_ sender: NSMenuItem) {
        let rating = sender.tag
        getViewController(collectionView!)?.handleRating(rating: rating)
    }
    
    @objc func actRateReadmeAction() {
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("rating-info", comment: "对于评级的说明..."))
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

    @objc func actShowParentInNewTab() {
        guard let url = URL(string: file.path) else { return }
        let parentURL = url.deletingLastPathComponent()
        guard !parentURL.path.isEmpty, parentURL.absoluteString != url.absoluteString else { return }
        var parentPath = parentURL.absoluteString
        if !parentPath.hasSuffix("/") {
            parentPath += "/"
        }
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            _ = appDelegate.createNewWindow(parentPath)
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
        getViewController(collectionView!)?.handleRename(urls: urls);
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
        // Get a representative URL for each file type
        let representativeUrls = getRepresentativeUrls(for: fileUrls)
        
        // 获取代表 URL 的可用应用程序并计算交集
        // Get available applications for representative URLs and calculate intersection
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
        // Add to main menu
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
    
    private func resolveAliasIfNeeded(_ url: URL) -> URL {
        if let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]),
           values.isAliasFile == true,
           let resolved = try? URL(resolvingAliasFileAt: url) {
            return resolved
        }
        return url
    }
    
    private func getRepresentativeUrls(for fileUrls: [URL]) -> [URL] {
        var representativeUrls: [String: URL] = [:]
        
        for fileUrl in fileUrls {
            let resolved = resolveAliasIfNeeded(fileUrl)
            let fileExtension = resolved.pathExtension.lowercased()
            if representativeUrls[fileExtension] == nil {
                representativeUrls[fileExtension] = resolved
            }
        }
        
        return Array(representativeUrls.values)
    }
    
    private func calculateCommonApplications(for representativeUrls: [URL]) -> [URL] {
        guard !representativeUrls.isEmpty else { return [] }
        
        // 获取每个代表 URL 的应用程序列表
        // Get application list for each representative URL
        var appURLLists: [[URL]] = []
        
        for fileUrl in representativeUrls {
            let cfFileUrl = fileUrl as CFURL
            let appURLs = LSCopyApplicationURLsForURL(cfFileUrl, .all)?.takeRetainedValue() as? [URL] ?? []
            appURLLists.append(appURLs)
        }
        
        // 计算交集并保留顺序
        // Calculate intersection and preserve order
        guard let firstList = appURLLists.first else { return [] }
        
        // 从第一个列表开始，过滤出在所有列表中都存在的应用程序
        // Starting from first list, filter out applications that exist in all lists
        let commonApps = firstList.filter { appURL in
            appURLLists.dropFirst().allSatisfy { $0.contains(appURL) }
        }
        
        return commonApps
    }

    @objc func openFileWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL else { return }
        guard let fileUrls = getViewController(collectionView!)?.getSelectedURLs() else { return }
        
        let resolvedUrls = fileUrls.map { resolveAliasIfNeeded($0) }
        NSWorkspace.shared.open(resolvedUrls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: { (app, error) in
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
