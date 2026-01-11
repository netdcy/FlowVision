//
//  LayoutProfileConfig.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func configLayoutStyle(newStyle: CustomProfile ,doNotRefresh: Bool = false){
        // 窗口标题相关
        // Window title related
        publicVar.profile.setValue(forKey: "isWindowTitleUseFullPath", value: newStyle.getValue(forKey: "isWindowTitleUseFullPath"))
        publicVar.profile.setValue(forKey: "isWindowTitleShowStatistics", value: newStyle.getValue(forKey: "isWindowTitleShowStatistics"))
        
        // 通用布局
        // General layout
        publicVar.profile.setValue(forKey: "isShowThumbnailBadge", value: newStyle.getValue(forKey: "isShowThumbnailBadge"))
        publicVar.profile.setValue(forKey: "isShowThumbnailTag", value: newStyle.getValue(forKey: "isShowThumbnailTag"))
        publicVar.profile.isShowThumbnailFilename = newStyle.isShowThumbnailFilename
        publicVar.profile.ThumbnailFilenameSize = newStyle.ThumbnailFilenameSize
        publicVar.profile._thumbnailCellPadding = newStyle._thumbnailCellPadding
        
        // 网格视图
        // Grid view
        publicVar.profile.ThumbnailBorderRadiusInGrid = newStyle.ThumbnailBorderRadiusInGrid
        
        // 非网格视图
        // Non-grid view
        publicVar.profile.ThumbnailBorderRadius = newStyle.ThumbnailBorderRadius
        publicVar.profile._thumbnailBorderThickness = newStyle._thumbnailBorderThickness
        publicVar.profile.ThumbnailLineSpaceAdjust = newStyle.ThumbnailLineSpaceAdjust
        publicVar.profile.ThumbnailShowShadow = newStyle.ThumbnailShowShadow
        
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        
        changeWaterfallLayoutNumberOfColumns()
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func customLayoutStylePrompt (){
        if let mainWindow = NSApplication.shared.mainWindow {
            showThumbnailOptionsPanel(on: mainWindow) { [weak self] isUseFullPath, isShowStatistics, isShowBadge, isShowTag, isShowFilename, filenameSize, cellPadding, borderRadiusInGrid, borderRadius, borderThickness, lineSpaceAdjust, showShadow in
                guard let self = self else { return }
                
                let newStyle = CustomProfile()
                // 窗口标题相关
                // Window title related
                newStyle.setValue(forKey: "isWindowTitleUseFullPath", value: String(isUseFullPath))
                newStyle.setValue(forKey: "isWindowTitleShowStatistics", value: String(isShowStatistics))
                
                // 通用布局
                // General layout
                newStyle.setValue(forKey: "isShowThumbnailBadge", value: String(isShowBadge))
                newStyle.setValue(forKey: "isShowThumbnailTag", value: String(isShowTag))
                newStyle.isShowThumbnailFilename = isShowFilename
                newStyle.ThumbnailFilenameSize = filenameSize
                newStyle._thumbnailCellPadding = cellPadding
                
                // 网格视图
                // Grid view
                newStyle.ThumbnailBorderRadiusInGrid = borderRadiusInGrid
                
                // 非网格视图
                // Non-grid view
                newStyle.ThumbnailBorderRadius = borderRadius
                newStyle._thumbnailBorderThickness = borderThickness
                newStyle.ThumbnailLineSpaceAdjust = lineSpaceAdjust
                newStyle.ThumbnailShowShadow = showShadow
                
                configLayoutStyle(newStyle: newStyle)
            }
        }
    }
    
    
    // 以下是切换自定义配置
    // Below is switching custom configuration
    func setCustomProfileTo(_ styleName: String){
        coreAreaView.showInfo(String(format: NSLocalizedString("save-to-custom-profile", comment: "保存到自定义配置"), styleName), timeOut: 1)
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_"+styleName)
    }
    
    func useCustomProfile(_ styleName: String){
        coreAreaView.showInfo(String(format: NSLocalizedString("switch-to-custom-profile", comment: "切换至自定义配置"), styleName), timeOut: 1)
        let newStyle = CustomProfile.loadFromUserDefaults(withKey: "CustomStyle_v2_"+styleName)
        
        // 布局类型
        // Layout type
        if newStyle.layoutType != publicVar.profile.layoutType {
            if newStyle.layoutType == .justified {
                switchToJustifiedView(doNotRefresh: true)
            }else if newStyle.layoutType == .waterfall {
                switchToWaterfallView(doNotRefresh: true)
            }else if newStyle.layoutType == .grid {
                switchToGridView(doNotRefresh: true)
            }else {
                //
            }
        }
        // 边栏
        // Sidebar
        if newStyle.isDirTreeHidden != publicVar.profile.isDirTreeHidden {
            toggleSidebar()
        }
        // 排序
        // Sort
        if newStyle.sortType != publicVar.profile.sortType || newStyle.isSortFolderFirst != publicVar.profile.isSortFolderFirst || newStyle.isSortUseFullPath != publicVar.profile.isSortUseFullPath || newStyle.sortType == .random {
            changeSortType(sortType: newStyle.sortType, isSortFolderFirst: newStyle.isSortFolderFirst, isSortUseFullPath: newStyle.isSortUseFullPath, doNotRefresh: true)
        }
        // 缩略图大小
        // Thumbnail size
        if newStyle.thumbSize != publicVar.profile.thumbSize {
            changeThumbSize(thumbSize: newStyle.thumbSize, doNotRefresh: true)
        }
        // 样式
        // Style
        configLayoutStyle(newStyle: newStyle, doNotRefresh: true)
        
        refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
    }
}
