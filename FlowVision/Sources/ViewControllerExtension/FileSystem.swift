//
//  FileSystem.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func showScanAlert(fileCount: Int, imageCount: Int, videoCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Scan Prompt", comment: "扫描提示")
        alert.informativeText = String(format: NSLocalizedString("scanned-files", comment: "当前已扫描 %d 个文件，其中图像 %d 个，视频 %d 个。是否继续？"), fileCount, imageCount, videoCount)
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: "继续"))
        alert.addButton(withTitle: NSLocalizedString("Stop", comment: "停止"))
        
        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        let response = alert.runModal()
        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
        
        return response == .alertFirstButtonReturn
    }
    
    func scanFiles(at folderURL: URL, contents: inout [URL],  properties: [URLResourceKey]) {
        let options:FileManager.DirectoryEnumerationOptions = publicVar.isShowHiddenFile ? [] : [.skipsHiddenFiles]
        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: properties, options: options, errorHandler: { (url, error) -> Bool in
            print("Error enumerating \(url): \(error.localizedDescription)")
            return true
        })

        var fileCount = 0
        var imageCount = 0
        var videoCount = 0
        let scanInterval: TimeInterval = 4.0
        var startDate = Date()
        
        while let url = enumerator?.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDirectory || publicVar.isRecursiveContainFolder {
                contents.append(url)
                fileCount += 1
                if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
                    imageCount += 1
                } else if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
                    videoCount += 1
                }
            }
            
            let elapsedTime = Date().timeIntervalSince(startDate)
            if elapsedTime >= scanInterval {
                let shouldContinue = showScanAlert(fileCount: fileCount, imageCount: imageCount, videoCount: videoCount)
                if !shouldContinue {
                    break
                }
                // Reset the timer
                startDate = Date()
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
        var properties: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        if VolumeManager.shared.isExternalVolume(folderURL) {
            properties = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey]
        }
        var isInSameDir = !publicVar.isRecursiveMode
        if !skip {
            do {
                let curDirURLCacheParameters = (folderURL, publicVar.isRecursiveMode, publicVar.isShowHiddenFile, publicVar.isRecursiveContainFolder, properties)
                if let dirURLCacheParameters = dirURLCacheParameters as? (URL, Bool, Bool, Bool, [URLResourceKey]) {
                    if dirURLCacheParameters != curDirURLCacheParameters {
                        dirURLCache.removeAll()
                    }
                }
                dirURLCacheParameters = curDirURLCacheParameters
                
                if dirURLCache.isEmpty {
                    if folderURL.path.contains("VirtualTagFolder") {
                        dirURLCache = TaggingSystem.getList(tag: folderURL.lastPathComponent)
                        isInSameDir = false
                    }else if publicVar.isRecursiveMode {
                        scanFiles(at: folderURL, contents: &dirURLCache, properties: properties)
                    }else{
                        dirURLCache = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: properties, options: [])
                    }
                }
                contents.append(contentsOf: dirURLCache)
            }catch{}
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
        
        // 过滤出目录列表
        // Filter out directory list
        var subFolders = contents.filter { url in
            guard let isDirectoryResourceValue = try? url.resourceValues(forKeys: [.isDirectoryKey]), let isDirectory = isDirectoryResourceValue.isDirectory else {
                return false
            }
            return isDirectory
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
            guard let isDirectoryResourceValue = try? url.resourceValues(forKeys: [.isDirectoryKey]), let isDirectory = isDirectoryResourceValue.isDirectory else {
                return false
            }
            return !isDirectory
        }
        for file in fileContents {
            if publicVar.HandledFileExtensions.contains(file.pathExtension.lowercased()) || publicVar.isShowAllTypeFile {
                filesUrlInFolder.append(file)
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
            || publicVar.profile.sortType == .exifPixelA || publicVar.profile.sortType == .exifPixelZ {
            
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
                let isDir:Bool
                if filePath.hasSuffix("_FolderMark") {
                    fileSortKey=SortKeyFile(String(filePath.dropLast("_FolderMark".count)), isDir: true, isInSameDir: isInSameDir, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)
                    isDir=true
                }else{
                    fileSortKey=SortKeyFile(filePath, isInSameDir: isInSameDir, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)
                    isDir=false
                }
                // 读取文件大小日期
                // Read file size and dates
                var fileSize: Int?
                var modDate: Date?
                var createDate: Date?
                var addDate: Date?
                var doNotActualRead=false
                do{
                    // 文件在前i个，目录在后面
                    // Files in first i items, directories after
                    if i < fileCount {
                        let resourceValues = try filesUrlInFolder[i].resourceValues(forKeys: Set(properties))
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
                    // 目录
                    // Directory
                    }else{
                        let resourceValues = try subFolders[i-fileCount].resourceValues(forKeys: Set(properties))
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
                    }
                }catch{
                    log("Error reading properties.")
                }
                // log("i:",i,"path:",fileSortKey.path.removingPercentEncoding)
                let newFileModel=FileModel(path: fileSortKey.path, ver: fileDB.db[SortKeyDir(folderpath)]!.ver, isDir: isDir, fileSize: fileSize, createDate: createDate, modDate: modDate, addDate: addDate, doNotActualRead: doNotActualRead)
                // log(fileSortKey.path)
                if let file = fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] {
                    if file.path == fileSortKey.path {
                        file.ver = fileDB.db[SortKeyDir(folderpath)]!.ver
                        file.isDir=isDir
                        file.doNotActualRead=doNotActualRead
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
            for ele in fileDB.db[SortKeyDir(folderpath)]!.files{
                // log(ele.0.path.removingPercentEncoding)
                if ele.1.ver != fileDB.db[SortKeyDir(folderpath)]!.ver {
                    ele.1.image=nil
                    ele.1.folderImages=[]
                    fileDB.db[SortKeyDir(folderpath)]!.files.removeValue(forKey: ele.0)
                }
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
                    if globalVar.HandledImageAndRawExtensions.contains(ele.1.ext) {
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
            
            // 对于空文件夹，播放渐变动画（因为没有分派任务，所以在任务里的渐变调用不到）
            // For empty folders, play fade animation (because no tasks are dispatched, fade in tasks won't be called)
            if keys.isEmpty {
                
                collectionView.reloadData()
                collectionView.numberOfItems(inSection:0)
                
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
        
        treeReLocate(path: nextFolder, doCollapse: doCollapse, expandLast: expandLast)
        
        log("Switch:",nextFolder.removingPercentEncoding!)
        switchFolder(path: nextFolder)
        startWatchingDirectory(atPath: nextFolder.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!)
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
        
        if urls.count == 1 {
            let url = urls[0]
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    let file = FileModel(path: "", ver: 0)
                    file.path = url.absoluteString
                    file.fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    file.createDate = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                    file.modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    file.addDate = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate)
                    
                    let ext = url.pathExtension.lowercased()
                    if globalVar.HandledImageAndRawExtensions.contains(ext) || globalVar.HandledVideoExtensions.contains(ext) {
                        file.imageInfo = getImageInfo(url: url, needMetadata: true)
                    }
                    let exifData = convertExifData(file: file)
                    var formatedExifData = formatExifData(exifData ?? [:], isVideo: globalVar.HandledVideoExtensions.contains(ext), needWarp: false)
                    formatedExifData.insert((NSLocalizedString("File Path", comment: "文件路径"),url.deletingLastPathComponent().path+"/"), at: 0)
                    
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
                    
                    if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()),
                       let videoRawMetadata = getVideoMetadataFFmpeg(for: url),
                       let specificMetadata = getVideoMetadataFormatedFFmpeg(for: url) {
                        let metadataAligned = formatExifDataAligned(specificMetadata)
                        text += "\n" + separator + "\n" + metadataAligned + "\n" + separator + "\n" + videoRawMetadata
                    }
                    
                    if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
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
                                text += "\n" + separator + "\n" + formatDictionary(properties).replacingOccurrences(of: "\\/", with: "/")
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
                                text += "\n" + separator + "\n" + formatDictionary(result).replacingOccurrences(of: "\\/", with: "/")
                            }
                        }
                    }
                    
                    showInformationLong(title: NSLocalizedString("File Info", comment: "文件信息"), message: text, width: 400)
                    
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
                if isDirectory.boolValue {
                    result.folderCount += 1
                    getFolderStatistic(url, result: result)
                }else{
                    result.fileCount += 1
                    if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
                        result.imageCount += 1
                    } else if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
                        result.videoCount += 1
                    }
                    let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    result.totalSize += fileSize
                }
            }
        }
        
        showInformation(title: NSLocalizedString("Statistic", comment: "统计信息"), message: result.description)
    }
    
    func getFolderStatistic(_ folderURL: URL, result: FolderStatisticInfo) {
        let properties: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .fileSizeKey]
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
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            
            if !isDirectory {
                result.fileCount += 1
                if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
                    result.imageCount += 1
                } else if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
                    result.videoCount += 1
                }
                result.totalSize += fileSize
            }else{
                result.folderCount += 1
            }
            
            let elapsedTime = Date().timeIntervalSince(startDate)
            if elapsedTime >= scanInterval {
                let shouldContinue = showScanAlert(fileCount: result.fileCount, imageCount: result.imageCount, videoCount: result.videoCount)
                if !shouldContinue {
                    break
                }
                // Reset the timer
                startDate = Date()
            }
        }
    }
}
