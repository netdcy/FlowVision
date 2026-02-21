//
//  LargeImage.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func switchToActualSizeForLargeImage(){
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "isLargeImageFitWindow")
        publicVar.isLargeImageFitWindow=false
        if publicVar.isInLargeView{
            changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
        }
    }
    
    func switchToFitToWindowForLargeImage(){
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "isLargeImageFitWindow")
        publicVar.isLargeImageFitWindow=true
        if publicVar.isInLargeView{
            changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
        }
    }
    
    @objc func doubleClickLargeImage(_ sender: Any) {
        if largeImageView.file.type == .video {
            closeLargeImage(0)
        }
    }
 
    @objc func closeLargeImage(_ sender: Any) {
        
//        if currLargeImagePos == -1 {
//            return
//        }
        
        if !publicVar.isInLargeView || !publicVar.isInLargeViewAfterAnimate {
            return
        }
        
        view.window?.makeFirstResponder(collectionView)
        
        // 继续自动滚动
        // Continue auto-scroll
        isAutoScrollPaused = false
        
        // 停止自动播放
        // Stop auto-play
        stopAutoPlay()
        
        // 停止播放视频
        // Stop playing video
        largeImageView.stopVideo()
        
        // 隐藏首次使用提示
        // Hide first-time use hint
        coreAreaView.hideInfo()
        globalVar.isFirstTimeUse = false
        UserDefaults.standard.set(false, forKey: "isFirstTimeUse")
        
        // 复原旋转
        // Restore rotation
        largeImageView.file.rotate=0
        
        // 复原镜像
        // Restore mirror
        if !publicVar.isMirrorLocked {
            largeImageView.imageView.isMirroredH=false
        }
        
        // 取消OCR
        // Cancel OCR
        largeImageView.unSetOcr()
        
        // 需要在reloadData前取消选择，否则不会调用相关函数
        // Need to deselect before reloadData, otherwise related functions won't be called
        collectionView.deselectAll(nil)
        
        // 隐藏动画
        // Hide animation
        // 便携模式下不使用动画，因为反倒有两次变化
        // Portable mode doesn't use animation, as it would cause two changes
        if globalVar.portableMode {
            largeImageView.alphaValue = 0
            largeImageBgEffectView.alphaValue = 0
            self.largeImageView.isHidden=true
            self.largeImageBgEffectView.isHidden=true
            // 从文件打开时初始模式不同
            // Initial mode differs when opening from file
            self.largeImageBgEffectView.blendingMode = .withinWindow
            // Initial mode differs when opening from file
            self.publicVar.isInLargeViewAfterAnimate=false
        }else{
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = OPEN_LARGEIMAGE_DURATION
                largeImageView.animator().alphaValue = 0
                largeImageBgEffectView.animator().alphaValue = 0
            }, completionHandler: {
                self.largeImageView.isHidden=true
                self.largeImageBgEffectView.isHidden=true
                // 从文件打开时初始模式不同
                // Initial mode differs when opening from file
                self.largeImageBgEffectView.blendingMode = .withinWindow
                self.publicVar.isInLargeViewAfterAnimate=false
            })
        }
        // 防止某些情况下此状态未重置，导致再打开大图时直接会滚动缩放
        // Prevent this state from not being reset in some cases, causing immediate scroll/zoom when reopening large image
        publicVar.isLeftMouseDown = false
        publicVar.isRightMouseDown = false
        largeImageView.longPressZoomTimer?.invalidate()
        largeImageView.longPressZoomTimer = nil
        
        // 注意，由于被选中的外观取决于这个状态，因此要先置状态再选择
        // Note: Since selected appearance depends on this state, set state before selecting
        // 另外，修改此值会触发重布局
        // Also, modifying this value will trigger re-layout
        publicVar.isInLargeView=false
        // view.window?.layoutIfNeeded() 修改时已经调用

            
//        let visibleRect = mainScrollView.contentView.visibleRect
//        let itemFrame = collectionView.layoutAttributesForItem(at: IndexPath(item: currLargeImagePos, section: 0))?.frame ?? .zero
//
//        // 判断缩略图是否全部可见
//        if visibleRect.contains(itemFrame) == false {
//            // 奇怪问题：用finder从manys末尾打开一个关闭，再用finder打开它的前一个再关闭（后一个不行），列表会为空，需要鼠标滚轮滚动几下才能显示
//            // reloadData可避免，不管是在滚动前、后，都可以
//            collectionView.reloadData()
//
//            // 在后面再统一滚动，考虑到即使图没变，但是窗口大小改变导致被选中对象不在视野
//            // collectionView.scrollToItems(at: [IndexPath(item: currLargeImagePos, section: 0)], scrollPosition: .nearestHorizontalEdge)
//
//            // collectionView.reloadData()
//            // setVisableItemPriority(indexPath: IndexPath(item: currLargeImagePos, section: 0))
//
//        }


//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//
//            // 滚动到选中项目
//            collectionView.scrollToItems(at: [IndexPath(item: currLargeImagePos, section: 0)], scrollPosition: .nearestHorizontalEdge)
//            setVisableItemPriority(indexPath: IndexPath(item: currLargeImagePos, section: 0))
//
//            // 选中新项目
//            let indexPath=IndexPath(item: currLargeImagePos, section: 0)
//            // 此处加if是因为前面说的从finder二次打开时，如果滚动到目标位置后collectionView显示是空的（目标位置附近对象未被创建），此时对象不存在不能调用选中函数
//            if let _ = collectionView.item(at: indexPath) as? CustomCollectionViewItem{
//                collectionView.selectItems(at: [indexPath], scrollPosition: [])
//                // collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
//            }
            
        
        if currLargeImagePos >= 0 && currLargeImagePos < collectionView.numberOfItems(inSection: 0) {
            
            let indexPath=IndexPath(item: currLargeImagePos, section: 0)
            
            let visibleRectRaw = mainScrollView.contentView.visibleRect
            let scrollPos = visibleRectRaw.origin
            let scrollWidth = visibleRectRaw.width
            let scrollHeight = visibleRectRaw.height
            let visibleRect = NSRect(origin: scrollPos, size: CGSize(width: scrollWidth, height: scrollHeight))
            let itemFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
            
            if !itemFrame.intersects(visibleRect) {
                collectionView.scrollToItems(at: [IndexPath(item: currLargeImagePos, section: 0)], scrollPosition: .nearestHorizontalEdge)
            }

            collectionView.reloadData()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [indexPath])
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
                collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
                setLoadThumbPriority(ifNeedVisable: true)
            }
        }

        largeImageView.updateTextItems([])
        setWindowTitle()
    }
    
    @objc func openLargeImageFromPos(_ gestureRecognizer: NSGestureRecognizer) {
        let pointInView = gestureRecognizer.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: pointInView) {
            openLargeImageFromIndexPath(indexPath)
        }
    }
    
    func openLargeImageFromIndexPath(_ indexPath: IndexPath) {
        if publicVar.isInLargeView || publicVar.isInLargeViewAfterAnimate {
            return
        }
        openLargeImage(indexPath)
    }
    
    func openLargeImage(_ indexPath: IndexPath) {
        if let item = collectionView.item(at: indexPath) as? CustomCollectionViewItem{
            let url=URL(string: item.file.path)!
            
            // 取消OCR
            // Cancel OCR
            largeImageView.unSetOcr()
            
            if(url.hasDirectoryPath){
                switchDirByDirection(direction: .zero, dest: item.file.path, stackDeep: 0)
            }
            else if !globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) &&
                !(globalVar.useInternalPlayer && globalVar.HandledNativeSupportedVideoExtensions.contains(item.file.ext)) {
                NSWorkspace.shared.open(url)
            }else{
                if largeImageView.isHidden {
                    
                    // 暂停自动滚动
                    // Pause auto-scroll
                    isAutoScrollPaused = true
                    
                    // 显示首次使用提示
                    // Show first-time use hint
                    if globalVar.isFirstTimeUse{
                        coreAreaView.showInfo(NSLocalizedString("first-time-use-prompt", comment: "首次使用提示..."), timeOut: .infinity, cannotBeCleard: false)
                    }
                    
                    currLargeImagePos=indexPath.item
                    initLargeImagePos=indexPath.item

                    lastDoNotGenResized=false
                    lastResizeFailed=false
                    lastUseHDR=false
                    lastLargeImageRotate=0
                    
                    // 为了使可见范围自动播放的视频停止
                    setLoadThumbPriority(ifNeedVisable: true, stopPlayVideo: true)

                    changeLargeImage(justChangeLargeImageViewFile: globalVar.portableMode)
                    largeImageView.isHidden=false
                    largeImageBgEffectView.isHidden=false
                    publicVar.isInLargeView=true
                    
                    // 便携模式下不使用动画，因为反倒有两次变化
                    // Portable mode doesn't use animation, as it would cause two changes
                    // 视频模式会有闪烁
                    // Video mode will have flicker
                    if globalVar.portableMode ||
                        (globalVar.useInternalPlayer && globalVar.HandledNativeSupportedVideoExtensions.contains(item.file.ext)) {
                        largeImageView.alphaValue = 1
                        largeImageBgEffectView.alphaValue = 1
                        publicVar.isInLargeViewAfterAnimate=true
                    }else{
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = OPEN_LARGEIMAGE_DURATION
                            largeImageView.animator().alphaValue = 1
                            largeImageBgEffectView.animator().alphaValue = 1
                        }, completionHandler: {
                            self.publicVar.isInLargeViewAfterAnimate=true
                        })
                    }
                    
                    // setWindowTitleOfLargeImage(file: item.file)
                    
                    // 选中打开的项目
                    // Select opened item
                    collectionView.deselectAll(nil)
                    let indexPath=IndexPath(item: currLargeImagePos, section: 0)
                    collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [indexPath])
                    collectionView.selectItems(at: [indexPath], scrollPosition: [])
                    collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
                }
            }
        }
    }
    
    func locateLargeImage(direction: Int, isShowReachEndPrompt: Bool = true, firstShowThumb: Bool = true, noLoopBrowsing: Bool = false){
        if largeImageView.isHidden {return}
        if publicVar.openFromFinderPath != "" {return}
        if currLargeImagePos == -1 {
            return
        }
        
        fileDB.lock()
        let curFolder=fileDB.curFolder
        let totalCount = fileDB.db[SortKeyDir(curFolder)]!.files.count
        let fileCount = fileDB.db[SortKeyDir(curFolder)]!.fileCount
        var nextLargeImagePos=currLargeImagePos
        var ifFoundNextImage=false
        // 向前
        // Forward
        if direction == -1 {
            while nextLargeImagePos >= 0 {
                nextLargeImagePos-=1
                if let file = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1,
                   file.type == .image || (file.type == .video && globalVar.useInternalPlayer) {
                    ifFoundNextImage=true
                    break
                }
            }
        // 向后
        // Backward
        }else if direction == 1 {
            while nextLargeImagePos < totalCount-1 {
                nextLargeImagePos+=1
                if let file = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1,
                   file.type == .image || (file.type == .video && globalVar.useInternalPlayer) {
                    ifFoundNextImage=true
                    break
                }
            }
        // 第一张
        // First image
        }else if direction == -2 {
            nextLargeImagePos = -1
            while nextLargeImagePos < totalCount-1 {
                nextLargeImagePos+=1
                if let file = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1,
                   file.type == .image || (file.type == .video && globalVar.useInternalPlayer) {
                    ifFoundNextImage=true
                    break
                }
            }
        // 最后一张
        // Last image
        }else if direction == 2 {
            nextLargeImagePos = totalCount
            while nextLargeImagePos >= 0 {
                nextLargeImagePos-=1
                if let file = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1,
                   file.type == .image || (file.type == .video && globalVar.useInternalPlayer) {
                    ifFoundNextImage=true
                    break
                }
            }
        }
        
        fileDB.unlock()
        
        if ifFoundNextImage {
            // 复原之前图片的旋转
            // Restore the rotation of the previous image
            largeImageView.file.rotate=0
            
            // 复原镜像
            // Restore mirror
            if !publicVar.isMirrorLocked {
                largeImageView.imageView.isMirroredH=false
            }
            
            currLargeImagePos=nextLargeImagePos

            lastDoNotGenResized=false
            lastResizeFailed=false
            lastUseHDR=false
            lastLargeImageRotate=0
            
            // 取消OCR
            // Cancel OCR
            largeImageView.unSetOcr()
            
            if globalVar.portableMode {
                fileDB.lock()
                let refSize = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1.originalSize
                fileDB.unlock()
                adjustWindowPortable(refSize: refSize, firstShowThumb: firstShowThumb, animate: false)
            }else{
                changeLargeImage(firstShowThumb: firstShowThumb)
            }
            
            // 选中新的项目
            // Select new item
            collectionView.deselectAll(nil)
            if currLargeImagePos < collectionView.numberOfItems(inSection: 0) {
                let indexPath=IndexPath(item: currLargeImagePos, section: 0)
                collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [indexPath])
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
                collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
            }
        }else {
            if direction == -1 {
                if globalVar.loopBrowsing && !noLoopBrowsing {
                    locateLargeImage(direction: 2, isShowReachEndPrompt: isShowReachEndPrompt, firstShowThumb: firstShowThumb)
                } else if isShowReachEndPrompt {
                    largeImageView.showInfo(NSLocalizedString("Have Reached the First", comment: "已经是第一张图片"))
                }
            }else if direction == 1 {
                if globalVar.loopBrowsing && !noLoopBrowsing {
                    locateLargeImage(direction: -2, isShowReachEndPrompt: isShowReachEndPrompt, firstShowThumb: firstShowThumb)
                }else if isShowReachEndPrompt {
                    largeImageView.showInfo(NSLocalizedString("Have Reached the Last", comment: "已经是最后一张图片"))
                }
            }
        }
    }
    
    func previousLargeImage(isShowReachEndPrompt: Bool = true, firstShowThumb: Bool = true, noLoopBrowsing: Bool = false){
        locateLargeImage(direction: -1, isShowReachEndPrompt: isShowReachEndPrompt, firstShowThumb: firstShowThumb, noLoopBrowsing: noLoopBrowsing)
    }
    
    func nextLargeImage(isShowReachEndPrompt: Bool = true, firstShowThumb: Bool = true, noLoopBrowsing: Bool = false){
        locateLargeImage(direction: 1, isShowReachEndPrompt: isShowReachEndPrompt, firstShowThumb: firstShowThumb, noLoopBrowsing: noLoopBrowsing)
    }
    
    func setWindowTitleOfLargeImage(file: FileModel){
        let url=URL(string:file.path)!
        var fullTitle=url.lastPathComponent
        // fullTitle += " | " + readableFileSize(file.fileSize ?? 0)
        if file.originalSize != nil {
            if file.originalSize!.width != 0 {
                // fullTitle += " | " + String(format: "%.0f", file.originalSize!.width) + " × " + String(format: "%.0f", file.originalSize!.height)
            }
        }
        
        fileDB.lock()
        let folderPath = fileDB.curFolder
        let imageCount = fileDB.db[SortKeyDir(folderPath)]?.imageCount ?? 0
        let videoCount = fileDB.db[SortKeyDir(folderPath)]?.videoCount ?? 0
        let rangeCount = globalVar.useInternalPlayer ? imageCount+videoCount : imageCount
        if rangeCount != 0 {
            if let file = fileDB.db[SortKeyDir(folderPath)]?.files[SortKeyFile(file.path, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)] {
                // fullTitle += " | " + String(format: "(%d/%d)",idInImage+1,imageCount)
                let idInRange = globalVar.useInternalPlayer ? file.idInImageAndVideo : file.idInImage
                fullTitle += " " + String(format: "(%d/%d)",idInRange+1,rangeCount)
                publicVar.lastLargeImageIdInImage=idInRange
            }
        }
        fileDB.unlock()
        
        let shortTitle = (file.path as NSString).lastPathComponent.removingPercentEncoding!
        view.window?.title = shortTitle
        publicVar.toolbarTitle = fullTitle
        // publicVar.toolbarTitle = shortTitle
        if let windowController = view.window?.windowController as? WindowController {
            windowController.updateToolbarSync()
        }
    }
    
    func OpenLargeImageFromFinder(path: String){
        currLargeImagePos = -1
        initLargeImagePos = -1
        
        lastDoNotGenResized=false
        lastResizeFailed=false
        lastUseHDR=false
        lastLargeImageRotate=0

        changeLargeImage(justChangeLargeImageViewFile: globalVar.portableMode)
        largeImageView.isHidden=false
        largeImageBgEffectView.isHidden=false
        publicVar.isInLargeView=true
        publicVar.isInLargeViewAfterAnimate=true
        largeImageView.alphaValue = 1
        largeImageBgEffectView.alphaValue = 1
        
        
        // setWindowTitleOfLargeImage(file: item.file)
    }
    
    func preloadLargeImage(){
        // 由于第一次打开的顺序问题，此处不能作判断
        // Due to order issue on first open, cannot make judgment here
        // if !publicVar.isInLargeView {return}
        if publicVar.openFromFinderPath != "" {return}
        if currLargeImagePos == -1 {
            return
        }

        fileDB.lock()
        let curFolder=fileDB.curFolder
        let totalCount = fileDB.db[SortKeyDir(curFolder)]!.files.count
        guard let path = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: currLargeImagePos)?.1.path,
              let url = URL(string: path)
        else{
            fileDB.unlock()
            return
        }
        fileDB.unlock()
        
        var threadNum: Int
        if VolumeManager.shared.isExternalVolume(url) {
            threadNum=globalVar.thumbThreadNum_External
        }else{
            threadNum=globalVar.thumbThreadNum
        }
//        let preloadNumNext=Int(ceil(Double(threadNum)*0.75))
//        let preloadNumPrevious=Int(ceil(Double(threadNum)*0.25))
        var preloadNumNext:Int
        var preloadNumPrevious:Int
        
        if threadNum == 1 {
            preloadNumNext = 0
            preloadNumPrevious = 0
        }else if threadNum <= 4 {
            preloadNumNext = 1
            preloadNumPrevious = 1
        }else{
            preloadNumNext = 3
            preloadNumPrevious = 2
        }
        
        var fileQueue = [(FileModel, Double)]()

        // 后面的图像
        // Images after current
        do{
            fileDB.lock()
            var nextLargeImagePos=currLargeImagePos
            var loadCount=0
            while nextLargeImagePos < totalCount-1 {
                nextLargeImagePos += 1
                if let file=fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1 {
                    if file.type == .image || (file.type == .video && globalVar.useInternalPlayer) {
                        loadCount += 1
                        // 预载入数量
                        // Preload count
                        if loadCount > preloadNumNext { break }
                    }
                    if file.type == .image {
                        fileQueue.append((file, Double(loadCount)-0.5))
                    }
                }
            }
            fileDB.unlock()
        }
        
        // 前面的图像
        // Images before current
        do{
            fileDB.lock()
            var nextLargeImagePos=currLargeImagePos
            var loadCount=0
            while nextLargeImagePos >= 0 {
                nextLargeImagePos -= 1
                if let file=fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1 {
                    if file.type == .image || (file.type == .video && globalVar.useInternalPlayer) {
                        loadCount += 1
                        // 预载入数量
                        // Preload count
                        if loadCount > preloadNumPrevious { break }
                    }
                    if file.type == .image {
                        fileQueue.append((file, Double(loadCount)))
                    }
                }
            }
            fileDB.unlock()
        }
        
        // 当前图像
        // Current image
        do{
            fileDB.lock()
            if let file=fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: currLargeImagePos)?.1,
               file.type == .image{
                fileQueue.append((file, 0))
            }
            fileDB.unlock()
        }
        
        // 排序后预载入
        // Preload after sorting
        fileDB.lock()
        fileQueue.sort { $0.1 > $1.1 }
        for (file,priority) in fileQueue {
            preloadLargeImageForFile(file: file, priority: priority)
        }
        fileDB.unlock()

    }
    
    func preloadLargeImageForFile(file: FileModel, priority: Double){
        if file.type != .image {return}

        let url=URL(string:file.path)!
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let maxBounds=largeImageView.bounds
        // print(maxBounds)
        
        var largeSize: NSSize
        var originalSize: NSSize? = file.originalSize
        
        // 当文件被修改，列表重新读取但大小还没来得及获取时可能为空，此时需要获取一下
        // When file is modified, list is re-read but size may not be obtained yet, need to get it
        // 或者由于外置卷，使用的默认大小 || VolumeManager.shared.isExternalVolume(url)
        // Or due to external volume, use default size || VolumeManager.shared.isExternalVolume(url)
        if originalSize == nil {
            let imageInfo = getImageInfo(url: url, needMetadata: true)
            originalSize = imageInfo?.size
            file.imageInfo = imageInfo
            file.originalSize = originalSize

            if originalSize == nil {
                originalSize = DEFAULT_SIZE
                file.isGetImageSizeFail = true
            }else{
                file.isGetImageSizeFail = false
            }
        }
        
        if let originalSize=originalSize{
            
            // 判断HDR
            // Determine HDR
            var isHDR = (file.imageInfo?.isHDR ?? false) && publicVar.isEnableHDR
            if globalVar.HandledRawExtensions.contains(url.pathExtension.lowercased()) && publicVar.isRawUseEmbeddedThumb {
                isHDR = false
            }
            
            // 计算宽高
            // Calculate width and height
            if originalSize.height/originalSize.width*maxBounds.width > maxBounds.height {
                largeSize=NSSize(width: originalSize.width/originalSize.height*maxBounds.height, height: maxBounds.height)
            }else{
                largeSize=NSSize(width: maxBounds.width, height: originalSize.height/originalSize.width*maxBounds.width)
            }
            
            // 当原图实际大小小于视图大小时，按实际大小显示
            // When original image actual size is smaller than view size, display at actual size
            if !publicVar.isLargeImageFitWindow && originalSize.width<largeSize.width*scale {
                largeSize=NSSize(width: originalSize.width/scale, height: originalSize.height/scale)
            }
            
            // 整数缩放
            // Integer scaling
            largeSize = NSSize(width: round(largeSize.width), height: round(largeSize.height))
            
            // 不进行过大缩放，内存炸了
            // Do not perform excessive scaling, memory will explode
            var doNotGenResized=false
            if largeSize.width*scale>=originalSize.width && largeSize.height*scale>=originalSize.height {
                doNotGenResized=true
            }
            
            // 如果RAW使用Exif内嵌缩略图，则不使用原图（进行缩放）
            // If RAW uses Exif embedded thumbnail, do not use original image (for scaling)
            if globalVar.HandledRawExtensions.contains(url.pathExtension.lowercased()) && publicVar.isRawUseEmbeddedThumb {
                doNotGenResized=false
            }
            
            // 使用原图的格式
            // The format of using original image
            if ["gif", "svg", "ai"].contains(url.pathExtension.lowercased()){
                doNotGenResized=true
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                _ = LargeImageProcessor.getImageCache(url: url, size: largeSize, rotate: 0, ver: file.ver, useOriginalImage: doNotGenResized, isHDR: isHDR, isRawUseEmbeddedThumb: publicVar.isRawUseEmbeddedThumb, needWaitWhenSame: false)
            }
            
        }
    }
    
    func changeLargeImage(firstShowThumb: Bool = true, resetSize: Bool = true, triggeredByLongPress: Bool = false, justChangeLargeImageViewFile: Bool = false, forceRefresh: Bool = false, isByZoom: Bool = false){
        let pos=currLargeImagePos
        var file=FileModel(path: "", ver: 0)
        var isThisFromFinder=false
        if publicVar.openFromFinderPath != "" {
            let url = URL(string: publicVar.openFromFinderPath)!
            file=FileModel(path: publicVar.openFromFinderPath, ver: 0)
            file.imageInfo=getImageInfo(url: url, needMetadata: true)
            file.originalSize=file.imageInfo?.size
            if !justChangeLargeImageViewFile {
                // 获取缩略图（以加快响应）
                // Get thumbnail (to speed up response)
                file.image = getImageThumb(url: url, refSize: file.originalSize)
            }
            if file.originalSize == nil {
                file.originalSize = DEFAULT_SIZE
                file.isGetImageSizeFail = true
            }
            getFileInfo(file: file)
            
            file.ext=URL(string: file.path)!.pathExtension.lowercased()
            if globalVar.HandledImageAndRawExtensions.contains(file.ext) {
                file.type = .image
            }else if globalVar.HandledVideoExtensions.contains(file.ext) {
                file.type = .video
            }else{
                file.type = .other
            }

            isThisFromFinder=true
            
        }else {
            fileDB.lock()
            if let fileInDb=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: pos)?.1{
                file=fileInDb
            }
            fileDB.unlock()
            
            setLoadThumbPriority(indexPath: IndexPath(item: pos, section: 0), ifNeedVisable: false)
            if !globalVar.portableMode {
                // 预载入附近图像（包括本张），此处对于便携模式计算似乎有一像素小数偏差，待完善
                // Preload nearby images (including current), calculation for portable mode seems to have one-pixel decimal deviation, to be improved
                preloadLargeImage()
            }
        }
        
        // 旋转锁定
        // Rotation lock
        if publicVar.isRotationLocked {
            file.rotate = publicVar.rotationLock
        }
        
        largeImageView.file=file
        
        if justChangeLargeImageViewFile {return}
  
        let url=URL(string:file.path)!
        
        if forceRefresh {
            getFileInfo(file: file)
            file.imageInfo = getImageInfo(url: url, needMetadata: true)
            file.originalSize=file.imageInfo?.size
        }
        
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        
        var maxBounds=largeImageView.imageView.bounds
        if resetSize{maxBounds=largeImageView.bounds}
        
        log("largeImageView.imageView",largeImageView.imageView.bounds)
        log("largeImageView",largeImageView.bounds)
        
        var largeSize: NSSize
        var originalSize: NSSize? = file.originalSize
        var imageInfo: ImageInfo? = file.imageInfo
        var rotate = file.rotate

        // 当文件被修改，列表重新读取但大小还没来得及获取时可能为空，此时需要获取一下
        // 或者由于外置卷，使用的默认大小 || VolumeManager.shared.isExternalVolume(url)
        if originalSize == nil {
            imageInfo = getImageInfo(url: url, needMetadata: true)
            originalSize = imageInfo?.size
            file.imageInfo = imageInfo
            file.originalSize = originalSize
            if originalSize == nil {
                originalSize = DEFAULT_SIZE
                file.isGetImageSizeFail = true
            }else{
                file.isGetImageSizeFail = false
            }
        }
        
        // 窗口标题
        // Window title
        setWindowTitleOfLargeImage(file: file)
        
        // 判断黑色背景
        // Determine black background
        largeImageView.determineBlackBg()
        
        if var originalSize=originalSize{
            
            // 判断HDR
            // Determine HDR
            var isHDR = (file.imageInfo?.isHDR ?? false) && publicVar.isEnableHDR
            if globalVar.HandledRawExtensions.contains(url.pathExtension.lowercased()) && publicVar.isRawUseEmbeddedThumb {
                isHDR = false
            }
            
            // 判断旋转
            // Determine rotation
            if rotate%2 == 1 {
                originalSize=NSSize(width: originalSize.height, height: originalSize.width)
            }
            
            // 由于首次打开图像时maxBounds可能为窗口大小，因此要按比例缩放到合适
            // When first opening image, maxBounds may be window size, so scale proportionally to fit
            if originalSize.height/originalSize.width*maxBounds.width > maxBounds.height {
                largeSize=NSSize(width: originalSize.width/originalSize.height*maxBounds.height, height: maxBounds.height)
            }else{
                largeSize=NSSize(width: maxBounds.width, height: originalSize.height/originalSize.width*maxBounds.width)
            }
            
            // 当原图实际大小小于视图大小时，按实际大小显示
            // When original image actual size is smaller than view size, display at actual size
            if !publicVar.isLargeImageFitWindow && originalSize.width<largeSize.width*scale && !triggeredByLongPress {
                largeSize=NSSize(width: originalSize.width/scale, height: originalSize.height/scale)
            }
            
            // 缩放锁定
            // Zoom lock
            if !isByZoom && publicVar.isZoomLocked,
               let ratio = publicVar.zoomLock {
                largeSize=NSSize(width: originalSize.width/scale*ratio, height: originalSize.height/scale*ratio)
            }
            
            // resetSize则在此处调整frame，否则在largeImageView中调整
            // If resetSize, adjust frame here, otherwise adjust in largeImageView
            if resetSize {
                let rectView=largeImageView.frame
                let rectImage=NSRect(origin: CGPoint(x: (rectView.width-largeSize.width)/2, y: (rectView.height-largeSize.height)/2), size: largeSize)
                largeImageView.imageView.frame=rectImage
            }
            
            // 整数缩放
            // Integer scaling
            largeSize = NSSize(width: round(largeSize.width), height: round(largeSize.height))
            
            // 不进行过大缩放，内存炸了
            // Do not perform excessive scaling, memory will explode
            var doNotGenResized=false
            if largeSize.width*scale>=originalSize.width && largeSize.height*scale>=originalSize.height {
                doNotGenResized=true
            }
            
            // 但如果是旋转，还是缩放占用更小
            // But if rotated, scaling still takes up less space
            if rotate != 0 {
                doNotGenResized=false
            }

            // 如果RAW使用Exif内嵌缩略图，则不使用原图（进行缩放）
            // If RAW uses Exif embedded thumbnail, do not use original image (for scaling)
            if globalVar.HandledRawExtensions.contains(url.pathExtension.lowercased()) && publicVar.isRawUseEmbeddedThumb {
                doNotGenResized=false
            }
            
            // 使用原图的格式
            // Use original image format
            if ["gif", "svg", "ai"].contains(url.pathExtension.lowercased()){
                doNotGenResized=true
            }
            
            // 如果上次生成Resize失败
            // If last Resize failed
            if lastResizeFailed {
                lastDoNotGenResized=true
                doNotGenResized=true
            }
            
            log("ori:",originalSize.width,originalSize.height)
            log("dest:",largeSize.width,largeSize.height)
            
            // 若上次已经用了原图，这次还用原图，则不重新载入
            // If original image was used last time and is still used this time, do not reload
            if lastDoNotGenResized && doNotGenResized && lastLargeImageRotate == rotate && lastUseHDR == isHDR {
                if file.type == .image {
                    return
                }
            }
            
            // 若上次已经是HDR，这次还是，则不重新载入
            // If last time was HDR and this time is still HDR, do not reload
            // if lastUseHDR && isHDR && lastLargeImageRotate == rotate {return}

            lastDoNotGenResized=doNotGenResized
            lastResizeFailed = false
            lastUseHDR=isHDR
            lastLargeImageRotate=rotate
            
            // 检查是否有大图缓存
            // Check for large image cache
            var preGetImageCache = file.type == .image ? LargeImageProcessor.isImageCachedAndGet(url: url, size: largeSize, rotate: rotate, ver: file.ver, isHDR: isHDR, isRawUseEmbeddedThumb: publicVar.isRawUseEmbeddedThumb) : nil
            if forceRefresh {preGetImageCache = nil}
            let isImageCached = preGetImageCache != nil
            
            // 先显示小图
            // First show thumbnail
            if firstShowThumb && !isImageCached {
                largeImageView.imageView.image=file.image?.rotated(by: CGFloat(-90*rotate))
            }
            
            // 有大图缓存则直接载入
            // If large image is cached, load directly
            if isImageCached {
                log("Cache hit:",url.absoluteString.removingPercentEncoding!)
                largeImageView.imageView.image=preGetImageCache
            }else{
                log("Instant load:",url.absoluteString.removingPercentEncoding!)
            }
            
            // 显示窗口
            // Show window
            if let windowController = self.view.window?.windowController,
               let window = windowController.window,
               !window.isVisible {
                windowController.showWindow(nil)
            }
            globalVar.useCreateWindowShowDelay = false
            
            // 加载Exif
            // Load Exif
            if publicVar.isShowExif && resetSize {
                let exifData = convertExifData(file: file)
                largeImageView.updateTextItems(formatExifData(exifData ?? [:], isVideo: globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()), needWarp: true))
            }
            
            // 用来对比异步任务是否过期
            // Used to compare if async task is expired
            largeImageView.file.largeSize = largeSize
            
            // 取消之前的加载大图任务
            // Cancel previous large image load task
            largeImageLoadTask?.cancel()

            // 判断是否是视频
            // Check if is video
            if file.type == .image {

                largeImageView.stopVideo()
                largeImageView.imageView.isHidden = false

                if isImageCached {
                    return
                }
                
                var task: DispatchWorkItem? = nil
                task = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if pos != currLargeImagePos && !isThisFromFinder {return}
                    
                    largeImageLoadQueueLock.lock()
                    
                    if task?.isCancelled ?? false {
                        log("1 - Load large image replace task was cancelled.")
                        largeImageLoadQueueLock.unlock()
                        return
                    }
                    
                    // 按实际目标分辨率绘制效果较差，观察到1080P屏幕双倍插值后绘制与直接使用原图效果才类似，因此即使scale==1，此处size也不除以2
                    // Rendering at actual target resolution has poor quality, observed that double interpolation on 1080P screen renders similar to using original image directly, so even if scale==1, size here is not divided by 2
                    var largeImage: NSImage?
                    if resetSize && !forceRefresh {
                        largeImage=LargeImageProcessor.getImageCache(url: url, size: largeSize, rotate: rotate, ver: file.ver, useOriginalImage: doNotGenResized, isHDR: isHDR, isRawUseEmbeddedThumb: publicVar.isRawUseEmbeddedThumb)
                    }else{
                        if isHDR {
                            largeImage = getHDRImage(url: url, size: doNotGenResized ? nil : largeSize, rotate: rotate)
                        }else if doNotGenResized {
                            // 先判断是否是动画并处理
                            // First check if animated and handle
                            if let animateImage = getAnimateImage(url: url, rotate: rotate) {
                                largeImage = animateImage
                            } else {
                                largeImage = NSImage(contentsOf: url)?.rotated(by: CGFloat(-90*rotate))
                            }
                        }else{
                            largeImage = getResizedImage(url: url, size: largeSize, rotate: rotate, isRawUseEmbeddedThumb: publicVar.isRawUseEmbeddedThumb)
                            if largeImage == nil {
                                lastResizeFailed = true
                                largeImage = NSImage(contentsOf: url)?.rotated(by: CGFloat(-90*rotate))
                            }
                        }
                    }
                    
                    if task?.isCancelled ?? false {
                        log("2 - Load large image replace task was cancelled.")
                        largeImageLoadQueueLock.unlock()
                        return
                    }
                    
                    largeImageLoadQueueLock.unlock()
                    
                    if largeImage != nil{
                        
                        func doReplace() {
                            if pos != currLargeImagePos && !isThisFromFinder {return}
                            if rotate != largeImageView.file.rotate {return}
                            if largeImageView.file.largeSize != nil && largeSize != largeImageView.file.largeSize {return}
                            largeImageView.imageView.image=largeImage
                            // log("replaced")
                        }
                        
                        if publicVar.isLaunchFromFile_changeLargeImage {
                            // 任务在主线程执行，可以直接更新 UI
                            // The task is executed on the main thread, so we can directly update the UI
                            doReplace()
                        } else {
                            DispatchQueue.main.async {
                                doReplace()
                            }
                        }
                    }
                }
                // 保存新的任务
                // Save new task
                largeImageLoadTask = task
                
                // 是否阻塞执行新的任务
                // Whether to block execution of new task
                if publicVar.isLaunchFromFile_changeLargeImage {
                    // 直接执行任务（当前已在主线程），避免死锁
                    // Execute task directly (currently on main thread) to avoid deadlock
                    task!.perform()
                    publicVar.isLaunchFromFile_changeLargeImage = false
                } else {
                    DispatchQueue.global(qos: .userInitiated).async(execute: task!)
                }
                
            } else if file.type == .video {
                largeImageView.imageView.isHidden = true
                largeImageView.playVideo(reload: forceRefresh)
            }
            
        }
    }
}
