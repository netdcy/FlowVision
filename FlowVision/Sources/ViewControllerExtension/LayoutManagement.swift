//
//  LayoutManagement.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func changeWaterfallLayoutNumberOfColumns(){
        var singleWidth = Double(publicVar.profile.thumbSize) / 512 * 300
        
        let scrollbarWidth = publicVar.profile.ThumbnailScrollbarWidth
        var totalWidth=self.mainScrollView.bounds.width - scrollbarWidth - 2 * publicVar.profile.ThumbnailCellPadding
        if totalWidth < 25 {totalWidth = 25}
        if publicVar.isInLargeView && globalVar.portableMode {totalWidth = 1000}
        
        var columnNum = Int(ceil(totalWidth / singleWidth))
        if columnNum <= 0 {columnNum=1}
        publicVar.waterfallLayout.numberOfColumns = columnNum
    }
    
    func recalcLayout(_ targetFolder: String){
        recalcLayoutTimes+=1
        // log("recalcLayout:"+String(recalcLayoutTimes))
        
        // var WIDTH_THRESHOLD=6.0/2000
        var WIDTH_THRESHOLD=6.4/1920*512/Double(publicVar.profile.thumbSize)
        
        if publicVar.profile.layoutType == .grid {
            WIDTH_THRESHOLD=10.0/1920*512/Double(publicVar.profile.thumbSize)
        }
        
        let scrollbarWidth = publicVar.profile.ThumbnailScrollbarWidth
        var totalWidth = self.mainScrollView.bounds.width - scrollbarWidth - 2 * publicVar.profile.ThumbnailCellPadding
        if totalWidth < 25 {totalWidth = 25}
        if publicVar.isInLargeView && globalVar.portableMode {totalWidth = 1000}
        
        let actualThreshold=WIDTH_THRESHOLD*totalWidth
        var sum=0.0
        var lineCount=0
        var singleIds=[FileModel]()
        var lastSingleHeight:Double?
        
        fileDB.lock()
        guard let dirModel = fileDB.db[SortKeyDir(targetFolder)] else {
            fileDB.unlock()
            return
        }
        let count = dirModel.files.count
        let fileCount = dirModel.fileCount
        let layoutCalcPos = dirModel.layoutCalcPos
        // let startKey = fileDB.db[targetFolder]!.files.elementSafe(atOffset: layoutCalcPos).0
        if layoutCalcPos>0 {
            if let thumbSize=dirModel.files.elementSafe(atOffset: layoutCalcPos-1)?.1.thumbSize {
                lastSingleHeight = thumbSize.height - (2*publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailFilenamePadding)
            }
        }
        if layoutCalcPos < count {
            for i in layoutCalcPos...(count-1) {
                guard let file = dirModel.files.elementSafe(atOffset: i)?.1 else{break}
                guard var originalSize=file.originalSize else{break}
                if file.canBeCalcued != true {break}

                // if publicVar.profile.layoutType == .grid { originalSize=DEFAULT_SIZE }
                sum+=(originalSize.width/originalSize.height)
                singleIds.append(file)
                if sum>=actualThreshold || i==count-1 {
                    sum=max(sum,actualThreshold)
                    var singleHeight = floor((totalWidth - 2 * (publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailCellPadding) * Double(singleIds.count))/sum)
                    // 防止最后一行不一样大小
                    // Prevent last row from having different size
                    // if publicVar.profile.layoutType == .grid && lastSingleHeight != nil { singleHeight=lastSingleHeight! }
                    lastSingleHeight=singleHeight
                    for singleId in singleIds{
                        var originalSizeSingle=singleId.originalSize!
                        
                        // if publicVar.profile.layoutType == .grid { originalSizeSingle=DEFAULT_SIZE }
                        
                        var singleWidth = floor(originalSizeSingle.width/originalSizeSingle.height*singleHeight)
                        
                        if publicVar.profile.layoutType == .waterfall {
                            let numberOfColumns=Double(publicVar.waterfallLayout.numberOfColumns)
                            singleWidth = floor(totalWidth/numberOfColumns-2*(publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailCellPadding))
                            singleHeight = round(originalSizeSingle.height/originalSizeSingle.width*singleWidth)
                        }
                        
                        if publicVar.profile.layoutType == .grid {
                            let numberOfColumns=Double(publicVar.waterfallLayout.numberOfColumns)
                            let sideLength = floor(totalWidth/CGFloat(numberOfColumns+1)-2*(publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailCellPadding))
                            let squareFrame = NSRect(x: 0, y: 0, width: sideLength, height: sideLength)
                            let newFrame = AVMakeRect(aspectRatio: originalSizeSingle, insideRect: squareFrame)
                            singleWidth = round(newFrame.width)
                            singleHeight = round(newFrame.height)
                        }
                        
                        let size=NSSize(width: singleWidth+2*publicVar.profile.ThumbnailBorderThickness, height: singleHeight+2*publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailFilenamePadding)
                        singleId.thumbSize=size
                        singleId.lineNo=lineCount
                    }
                    for singleId in singleIds.reversed(){
                        singleId.isLayoutCalcued=true
                    }
                    singleIds=[]
                    sum=0.0
                    lineCount+=1
                    dirModel.layoutCalcPos=i+1
                }
            }
        }
        fileDB.unlock()
    }
    
    func switchToJustifiedView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.justified, forKey: "layoutType")
        publicVar.profile.layoutType = .justified
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func switchToGridView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.grid, forKey: "layoutType")
        publicVar.profile.layoutType = .grid
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func switchToWaterfallView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.waterfall, forKey: "layoutType")
        publicVar.profile.layoutType = .waterfall
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func switchToDetailView(doNotRefresh: Bool = false){
        assertionFailure()
        return
    }
    
    func changeThumbSize(thumbSize: Int, doNotRefresh: Bool = false){
        publicVar.profile.thumbSize = thumbSize
        // UserDefaults.standard.set(thumbSize, forKey: "thumbSize")
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        changeWaterfallLayoutNumberOfColumns()
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func refreshAll(_ reloadThumbType: [FileType] = [], dryRun: Bool = false, needStopAutoScroll: Bool = true, needLoadThumbPriority: Bool){
        refreshTreeView()
        refreshCollectionView(reloadThumbType, dryRun: dryRun, needStopAutoScroll: needStopAutoScroll, needLoadThumbPriority: needLoadThumbPriority)
    }
    
    func refreshCollectionView(_ reloadThumbType: [FileType] = [], dryRun: Bool = false, needStopAutoScroll: Bool = true, needLoadThumbPriority: Bool){
        fileDB.lock()
        let curFolder = fileDB.curFolder
        if let files = fileDB.db[SortKeyDir(curFolder)]?.files {
            for file in files {
                if reloadThumbType.contains(file.1.type) || reloadThumbType.contains(.all) {
                    file.1.originalSize=nil
                    file.1.thumbSize=nil
                    file.1.image=nil
                    file.1.folderImages=[]
                }
            }
        }
        fileDB.unlock()
        switchDirByDirection(direction: .zero, doCollapse: false, skip: dryRun, stackDeep: 0, dryRun: dryRun, needStopAutoScroll: needStopAutoScroll)
        
        if needLoadThumbPriority {
            DispatchQueue.main.async { [weak self] in
                self?.setLoadThumbPriority(ifNeedVisable: true)
            }
        }
    }
    
    func refreshTreeView(){
        var expandedItems: [TreeNode] = []
        
        func checkExpandedItems(item: TreeNode) {
            if outlineView.isItemExpanded(item) {
                expandedItems.append(item)
                if let children = item.children {
                    for child in children {
                        checkExpandedItems(item: child)
                    }
                }
            }
        }

        if let root = treeViewData.root {
            treeViewData.expand(node: root, isLookSub: true)
        }
        
        if let children = treeViewData.root?.children {
            for item in children {
                checkExpandedItems(item: item)
            }
        }

        // 对已展开的项进行操作
        // Operate on the expanded items
        for item in expandedItems {
            treeViewData.expand(node: item, isLookSub: true)
        }
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        outlineView.reloadData()
        if globalVar.dirTreeAutoExpand {
            treeReLocate(path: curFolder, doCollapse: false, expandLast: false)
        }
        outlineViewManager.adjustColumnWidth()
    }
}
