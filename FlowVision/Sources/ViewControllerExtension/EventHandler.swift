//
//  EventHandler.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func handleReopenClosedTabs(){
        if let lastPath = globalVar.closedPaths.last {
            globalVar.closedPaths.removeLast()
            if let appDelegate=NSApplication.shared.delegate as? AppDelegate {
                if lastPath.hasSuffix("/") {
                    _ = appDelegate.createNewWindow(lastPath)
                } else {
                    globalVar.isLaunchFromFile=true
                    if let windowController = appDelegate.createNewWindow(lastPath) {
                        appDelegate.openImageInTargetWindow(lastPath, windowController: windowController)
                    }
                }
            }
        }
    }

    func handleHistoryBack(){
        switchDirByDirection(direction: .back, stackDeep: 0)
    }

    func handleHistoryForward(){
        switchDirByDirection(direction: .forward, stackDeep: 0)
    }

    func handlePrint(){
        if publicVar.isInLargeView {
            printContent(largeImageView.imageView)
        } else {
            // 临时隐藏滚动条
            // Temporarily hide scrollbars
            let originalVerticalScroller = mainScrollView.verticalScroller
            let originalHorizontalScroller = mainScrollView.horizontalScroller
            mainScrollView.verticalScroller=nil
            mainScrollView.horizontalScroller=nil
            
            printContent(mainScrollView)
            
            // 恢复原始滚动条状态
            // Restore original scrollbar state
            mainScrollView.verticalScroller = originalVerticalScroller
            mainScrollView.horizontalScroller = originalHorizontalScroller
        }
    }
    
    func changeSortType(sortType: SortType, isSortFolderFirst: Bool, isSortUseFullPath: Bool, doNotRefresh: Bool = false){
        
        // Exif排序时间警告
        // Exif sort time warning
        if sortType == .exifDateA || sortType == .exifDateZ
            || sortType == .exifPixelA || sortType == .exifPixelZ {
            
            var imageCount = 0
            var videoCount = 0
            
            fileDB.lock()
            let curFolder = fileDB.curFolder
            if let dirModel = fileDB.db[SortKeyDir(curFolder)] {
                imageCount = dirModel.imageCount
                videoCount = dirModel.videoCount
            }
            fileDB.unlock()
            
            if let folderURL = URL(string: curFolder), isExifSortTimeExceedCancel(folderURL: folderURL, imageCount: imageCount, videoCount: videoCount) {
                // 提前结束
                // Early exit
                return
            }
        }
        
        fileDB.lock()
        publicVar.profile.sortType = sortType
        publicVar.profile.isSortFolderFirst = isSortFolderFirst
        publicVar.profile.isSortUseFullPath = isSortUseFullPath
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        publicVar.randomSeed = Int.random(in: 0...Int.max)
        for dirModel in fileDB.db {
            dirModel.1.changeSortType(publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)
        }
        fileDB.unlock()
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }

    func changeDirSortType(sortType: SortType){
        publicVar.profile.setValue(forKey: "dirTreeSortType", value: String(sortType.rawValue))
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        refreshTreeView()
    }

    func toggleSidebar(){
        hasManualToggleSidebar=true
        publicVar.profile.isDirTreeHidden.toggle()
        if !publicVar.profile.isDirTreeHidden{
            splitView.setPosition(270, ofDividerAt: 0)
        }else{
            splitView.setPosition(0, ofDividerAt: 0)
        }

//        let defaults = UserDefaults.standard
//        defaults.set(publicVar.profile.isDirTreeHidden, forKey: "isDirTreeHidden")
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
    }
    
    func toggleRecursiveMode(){
        publicVar.isRecursiveMode.toggle()
        var showText = NSLocalizedString("Exit Recursive Mode", comment: "退出递归模式")
        if publicVar.isRecursiveMode {
            showText = NSLocalizedString("Enable Recursive Mode", comment: "开启递归模式")
        }
        coreAreaView.showInfo(showText, timeOut: 1.0, cannotBeCleard: true)
        refreshCollectionView(needLoadThumbPriority: true)
        if publicVar.isInSearchState {
            closeSearchOverlay()
            showSearchOverlay()
        }
    }
    
    func toggleRecursiveContainFolder(){
        publicVar.isRecursiveContainFolder.toggle()
        UserDefaults.standard.set(publicVar.isRecursiveContainFolder, forKey: "isRecursiveContainFolder")
        var showText = NSLocalizedString("Not Include Folders", comment: "不包含文件夹")
        if publicVar.isRecursiveContainFolder {
            showText = NSLocalizedString("Include Folders", comment: "包含文件夹")
        }
        coreAreaView.showInfo(showText, timeOut: 1.0, cannotBeCleard: true)
        if publicVar.isRecursiveMode {
            refreshCollectionView(needLoadThumbPriority: true)
        }
    }
    
    func toggleIsShowHiddenFile(){
        publicVar.isShowHiddenFile.toggle()
        UserDefaults.standard.set(publicVar.isShowHiddenFile, forKey: "isShowHiddenFile")
        var showText = NSLocalizedString("Not Show Hidden Files", comment: "不显示隐藏文件")
        if publicVar.isShowHiddenFile {
            showText = NSLocalizedString("Show Hidden Files", comment: "显示隐藏文件")
        }
        coreAreaView.showInfo(showText, timeOut: 1.0, cannotBeCleard: true)
        refreshAll(needLoadThumbPriority: true)
    }
    
    func toggleIsShowAllTypeFile(){
        publicVar.isShowAllTypeFile.toggle()
        UserDefaults.standard.set(publicVar.isShowAllTypeFile, forKey: "isShowAllTypeFile")
        var showText = NSLocalizedString("Not Show All Types of Files", comment: "不显示所有类型文件")
        if publicVar.isShowAllTypeFile {
            showText = NSLocalizedString("Show All Types of Files", comment: "显示所有类型文件")
        }
        coreAreaView.showInfo(showText, timeOut: 1.0, cannotBeCleard: true)
        refreshAll(needLoadThumbPriority: true)
    }
    
    func toggleIsShowImageFile(){
        publicVar.isShowImageFile.toggle()
        UserDefaults.standard.set(publicVar.isShowImageFile, forKey: "isShowImageFile")
        publicVar.setFileExtensions()
        refreshCollectionView(needLoadThumbPriority: true)
    }
    
    func toggleIsShowRawFile(){
        publicVar.isShowRawFile.toggle()
        UserDefaults.standard.set(publicVar.isShowRawFile, forKey: "isShowRawFile")
        publicVar.setFileExtensions()
        refreshCollectionView(needLoadThumbPriority: true)
    }
    
    func toggleIsShowVideoFile(){
        publicVar.isShowVideoFile.toggle()
        UserDefaults.standard.set(publicVar.isShowVideoFile, forKey: "isShowVideoFile")
        publicVar.setFileExtensions()
        refreshCollectionView(needLoadThumbPriority: true)
    }

    func togglePanWhenZoomed(){
        publicVar.isPanWhenZoomed.toggle()
        UserDefaults.standard.set(publicVar.isPanWhenZoomed, forKey: "isPanWhenZoomed")
    }

    func toggleLockRotation(){
        publicVar.isRotationLocked.toggle()
        UserDefaults.standard.set(publicVar.isRotationLocked, forKey: "isRotationLocked")
        if publicVar.isRotationLocked {
            publicVar.rotationLock = largeImageView.file.rotate
        }
    }

    func toggleLockZoom(){
        publicVar.isZoomLocked.toggle()
        UserDefaults.standard.set(publicVar.isZoomLocked, forKey: "isZoomLocked")
        if publicVar.isZoomLocked {
            largeImageView.calcRatio(isShowPrompt: true)
        }
    }

    func toggleRawUseEmbeddedThumb(){
        publicVar.isRawUseEmbeddedThumb.toggle()
        UserDefaults.standard.set(publicVar.isRawUseEmbeddedThumb, forKey: "isRawUseEmbeddedThumb")
        if publicVar.isRawUseEmbeddedThumb {
            coreAreaView.showInfo(NSLocalizedString("RAW Uses Exif Embedded Thumbnail", comment: "RAW使用Exif内嵌缩略图"), timeOut: 1.0, cannotBeCleard: true)
        }else{
            coreAreaView.showInfo(NSLocalizedString("Render Original RAW", comment: "渲染原始RAW"), timeOut: 1.0, cannotBeCleard: true)
        }
        if publicVar.isInLargeView {
            changeLargeImage(firstShowThumb: false, resetSize: false, triggeredByLongPress: false, forceRefresh: true)
            publicVar.updateToolbar()
        }
    }
    
    func handleChangeCurrentTag(tag: String){
        publicVar.currentTag = tag
        UserDefaults.standard.setValue(tag, forKey: "currentTag")
    }
    
    func handleTagging(){
        
        let urls = publicVar.selectedUrls()
        guard urls.count != 0 else {return}

        if TaggingSystem.isAllTagged(tag: publicVar.currentTag, urls: urls) {
            TaggingSystem.remove(tag: publicVar.currentTag, urls: urls)
        }else{
            TaggingSystem.add(tag: publicVar.currentTag, urls: urls)
        }
        
        let isInTagView = false
        if isInTagView{
            refreshCollectionView(needLoadThumbPriority: true)
        }else{
            if let collectionView = collectionView {
                for item in collectionView.visibleItems() {
                    if let item = item as? CustomCollectionViewItem {
                        item.refreshTagLabel()
                    }
                }
            }
        }
    }
    
    func toggleAutoPlayVisibleVideo() {
        publicVar.autoPlayVisibleVideo.toggle()
        // UserDefaults.standard.set(publicVar.autoPlayVisibleVideo, forKey: "autoPlayVisibleVideo")
        debounceSetLoadThumbPriority(interval: 0.1, ifNeedVisable: true)
        var showText = NSLocalizedString("Cancel Auto Play Visible Video", comment: "取消自动播放可见视频")
        if publicVar.autoPlayVisibleVideo {
            showText = NSLocalizedString("Auto Play Visible Video", comment: "自动播放可见视频")
        }
        if let windowController = (view.window?.windowController) as? WindowController {
            windowController.updateToolbar()
        }
        coreAreaView.showInfo(showText, timeOut: 1.0, cannotBeCleard: true)
    }
    
    func toggleUseInternalPlayer() {
        globalVar.useInternalPlayer.toggle()
        UserDefaults.standard.set(globalVar.useInternalPlayer, forKey: "useInternalPlayer")
    }
    
    func showCustomZoomRatioDialog(){
        
    }
    
    func showCustomZoomStepDialog(){
        
    }
    
    func handleShowOperationLogs() {
        var text = ""
        for log in globalVar.operationLogs.reversed() {
            text += "\(log)\n"
        }
        if globalVar.operationLogs.isEmpty {
            text = NSLocalizedString("operation-logs-info", comment: "(对操作日志的说明)")
        }
        showInformationLong(title: NSLocalizedString("Operation Logs", comment: "操作日志"), message: text)
    }
    
    func handleUserRefresh(){
        if publicVar.isInLargeView{
            largeImageView.actRefresh()
        }else{
            LargeImageProcessor.clearCache()
            ThumbImageProcessor.clearCache()
            dirURLCache.removeAll()
            refreshAll([.all], needLoadThumbPriority: true)
        }
    }
    
    func adjustThumbSizeByDirection(direction: Int) {
//        publicVar.thumbSize += 128*direction
//        if publicVar.thumbSize <= 0 {
//            publicVar.thumbSize = 128
//        }
        
        if direction == 0 {
            publicVar.profile.thumbSize = 512
        }else{
            let lastWaterFallNumberOfColumns = publicVar.waterfallLayout.numberOfColumns
            while lastWaterFallNumberOfColumns == publicVar.waterfallLayout.numberOfColumns {
                if let currentIndex = THUMB_SIZES.firstIndex(of: publicVar.profile.thumbSize) {
                    let newIndex = max(0, min(THUMB_SIZES.count - 1, currentIndex + direction))
                    publicVar.profile.thumbSize = THUMB_SIZES[newIndex]
                    if currentIndex == newIndex {
                        if currentIndex == THUMB_SIZES.count-1 {
                            break
                        }else{
                            return
                        }
                    }
                    changeWaterfallLayoutNumberOfColumns()
                }else{
                    return
                }
            }
        }
        changeThumbSize(thumbSize: publicVar.profile.thumbSize)
    }
    
    func showCmdShiftGWindow(){
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Go To", comment: "跳转至")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        alert.icon = NSImage(systemSymbolName: "arrowshape.turn.up.forward.circle", accessibilityDescription: nil)
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        inputTextField.placeholderString = ""
        inputTextField.stringValue = fileDB.curFolder.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!
        if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
            textFieldCell.usesSingleLineMode = true
            textFieldCell.wraps = false
            textFieldCell.isScrollable = true
        }
        alert.accessoryView = inputTextField
        
        // 确保输入框成为第一响应者
        // Ensure input field becomes first responder
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            alert.window.makeFirstResponder(inputTextField)
        }
        
        // 使用 beginSheetModal 替代 runModal
        // Use beginSheetModal instead of runModal
        if let window = view.window {
            let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled=false
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self = self else { return }
                publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
                if response == .alertFirstButtonReturn {
                    var path = inputTextField.stringValue
                    // 如果被''或者""包裹则去掉
                    // Remove if wrapped by '' or ""
                    if path.hasPrefix("'") && path.hasSuffix("'") {
                        path = String(path.dropFirst().dropLast())
                    }
                    if path.hasPrefix("\"") && path.hasSuffix("\"") {
                        path = String(path.dropFirst().dropLast())
                    }
                    // 解码URL编码
                    // Decode URL encoding
                    guard var path = path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding else {
                        coreAreaView.showInfo(NSLocalizedString("Invalid current path", comment: "当前路径无效"), timeOut: 2, cannotBeCleard: false)
                        return
                    }
                    
                    // 替换连续双斜杠
                    // Replace consecutive double slashes
                    while path.contains("//") {
                        path = path.replacingOccurrences(of: "//", with: "/")
                    }

                    // 检查路径是否为空
                    // Check if path is empty
                    if path.isEmpty {
                        return
                    }
                    
                    // 获取当前目录作为基准路径
                    // Get current directory as base path
                    fileDB.lock()
                    // 如果以/结尾，则去掉
                    // If ends with /, remove it
                    var curFolder = fileDB.curFolder
                    if curFolder.hasSuffix("/") {
                        curFolder = String(curFolder.dropLast())
                    }
                    fileDB.unlock()
                    
                    // 处理路径
                    // Process path
                    var fullPath = path
                    
                    guard let curUrl = URL(string: curFolder) else {
                        coreAreaView.showInfo(NSLocalizedString("Invalid current path", comment: "当前路径无效"), timeOut: 2, cannotBeCleard: false)
                        return
                    }
                    
                    // 处理相对路径
                    // Process relative path
                    if !path.hasPrefix("/") {
                        if let resolvedPath = resolveRelativePath(basePath: curUrl.path, relativePath: path) {
                            fullPath = resolvedPath
                        } else {
                            coreAreaView.showInfo(NSLocalizedString("Invalid relative path", comment: "相对路径无效"), timeOut: 2, cannotBeCleard: false)
                            return
                        }
                    }
                    
                    // 检查路径是否存在
                    // Check if path exists
                    let fileManager = FileManager.default
                    var isDirectory: ObjCBool = false
                    if !fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
                        coreAreaView.showInfo(NSLocalizedString("Path does not exist", comment: "路径不存在"), timeOut: 2, cannotBeCleard: false)
                        return
                    }
                    
                    // 转换为 file:// URL 格式
                    // Convert to file:// URL format
                    var destPath = getFileStylePath(fullPath)
                    
                    // 检查是否是目录
                    // Check if is directory
                    if !isDirectory.boolValue {
                        if let appDelegate=NSApplication.shared.delegate as? AppDelegate {
                            appDelegate.openImageInMainWindow(getFileStylePath(destPath))
                        }
                        return
                    }
                    
                    if !destPath.hasSuffix("/") {
                        destPath += "/"
                    }

                    if publicVar.isInLargeView {
                        closeLargeImage(0)
                    }
                    
                    switchDirByDirection(direction: .zero, dest: destPath, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
                }
            }
        }
    }
}
