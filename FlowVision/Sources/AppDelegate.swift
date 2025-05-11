//
//  AppDelegate.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/13.
//

import Cocoa
import Settings

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {

    @IBOutlet weak var favoritesMenu: NSMenu!
    @IBOutlet weak var historyMenu: NSMenu!
    @IBOutlet weak var viewMenu: NSMenu!
    @IBOutlet weak var systemThemeMenuItem: NSMenuItem!
    @IBOutlet weak var lightModeMenuItem: NSMenuItem!
    @IBOutlet weak var darkModeMenuItem: NSMenuItem!
    @IBOutlet weak var justifiedViewMenuItem: NSMenuItem!
    @IBOutlet weak var waterfallViewModeMenuItem: NSMenuItem!
    @IBOutlet weak var gridViewMenuItem: NSMenuItem!
    @IBOutlet weak var detailViewModeMenuItem: NSMenuItem!
    @IBOutlet weak var switchToActualSizeMenuItem: NSMenuItem!
    @IBOutlet weak var switchToFitToWindowMenuItem: NSMenuItem!
    @IBOutlet weak var toggleSidebarMenuItem: NSMenuItem!
    @IBOutlet weak var onTopMenuItem: NSMenuItem!
    @IBOutlet weak var maximizeWindowMenuItem: NSMenuItem!
    @IBOutlet weak var optimizeWindowMenuItem: NSMenuItem!
    @IBOutlet weak var adjustWindowActualMenuItem: NSMenuItem!
    @IBOutlet weak var adjustWindowCurrentMenuItem: NSMenuItem!
    @IBOutlet weak var adjustWindowToCenterMenuItem: NSMenuItem!
    @IBOutlet weak var toggleIsShowHiddenFileMenuItem: NSMenuItem!
    @IBOutlet weak var toggleIsShowImageFileMenuItem: NSMenuItem!
    @IBOutlet weak var toggleIsShowRawFileMenuItem: NSMenuItem!
    @IBOutlet weak var toggleIsShowVideoFileMenuItem: NSMenuItem!
    @IBOutlet weak var toggleIsShowAllTypeFileMenuItem: NSMenuItem!
    @IBOutlet weak var deselectMenuItem: NSMenuItem!
    
    var commonParentPath=""
    
    var windowControllers: [NSWindowController] = []
    
    lazy var settingsWindowController = SettingsWindowController(
        panes: [
            GeneralSettingsViewController(),
            CustomSettingsViewController(),
            ActionsSettingsViewController(),
            AdvancedSettingsViewController()
        ],
        animated: true,
        hidesToolbarForSingleItem: true
    )
    
    func applicationWillFinishLaunching(_ aNotification: Notification) {

        log("开始applicationWillFinishLaunching")
        
        func generateRoundedArray() -> [Int] {
            var result: [Int] = []
            var uniqueNumbers: Set<Int> = Set()
            var currentNumber: Double = 192
            
            while currentNumber <= 10000 {
                let roundedNumber = Int(round(currentNumber) / 64) * 64
                if !uniqueNumbers.contains(roundedNumber) {
                    result.append(roundedNumber)
                    uniqueNumbers.insert(roundedNumber)
                }
                
                currentNumber *= 1.1
            }
            
            return result
        }
        THUMB_SIZES=generateRoundedArray()
        //print(THUMB_SIZES)
        
        //UserDefaults.standard.set(nil, forKey: "AppleLanguages")
        //UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        //UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        
        let defaults = UserDefaults.standard
        let appearance = defaults.string(forKey: "appearance")
        if appearance == "darkAqua" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }else if appearance == "aqua" {
            NSApp.appearance = NSAppearance(named: .aqua)
        }else{
            NSApp.appearance = nil
        }
        
        if let hasNormalExit = UserDefaults.standard.value(forKey: "hasNormalExit") as? Bool {
            if !hasNormalExit {
                UserDefaults.standard.set("file:///", forKey: "lastFolder")
            }
        }
        UserDefaults.standard.set(false, forKey: "hasNormalExit")
        
        if let isFirstTimeUse = UserDefaults.standard.value(forKey: "isFirstTimeUse") as? Bool {
            globalVar.isFirstTimeUse = isFirstTimeUse
        }
        if let terminateAfterLastWindowClosed = UserDefaults.standard.value(forKey: "terminateAfterLastWindowClosed") as? Bool {
            globalVar.terminateAfterLastWindowClosed = terminateAfterLastWindowClosed
        }
        if let autoHideToolbar = UserDefaults.standard.value(forKey: "autoHideToolbar") as? Bool {
            globalVar.autoHideToolbar = autoHideToolbar
        }
        if let randomFolderThumb = UserDefaults.standard.value(forKey: "randomFolderThumb") as? Bool {
            globalVar.randomFolderThumb = randomFolderThumb
        }
        if let loopBrowsing = UserDefaults.standard.value(forKey: "loopBrowsing") as? Bool {
            globalVar.loopBrowsing = loopBrowsing
        }
        if let blackBgInFullScreen = UserDefaults.standard.value(forKey: "blackBgInFullScreen") as? Bool {
            globalVar.blackBgInFullScreen = blackBgInFullScreen
        }
        if let blackBgAlways = UserDefaults.standard.value(forKey: "blackBgAlways") as? Bool {
            globalVar.blackBgAlways = blackBgAlways
        }
        if let blackBgInFullScreenForVideo = UserDefaults.standard.value(forKey: "blackBgInFullScreenForVideo") as? Bool {
            globalVar.blackBgInFullScreenForVideo = blackBgInFullScreenForVideo
        }
        if let blackBgAlwaysForVideo = UserDefaults.standard.value(forKey: "blackBgAlwaysForVideo") as? Bool {
            globalVar.blackBgAlwaysForVideo = blackBgAlwaysForVideo
        }
        if let thumbnailExcludeList = UserDefaults.standard.value(forKey: "thumbnailExcludeList") as? [String] {
            globalVar.thumbnailExcludeList = thumbnailExcludeList
        }
        if let usePinyinSearch = UserDefaults.standard.value(forKey: "usePinyinSearch") as? Bool {
            globalVar.usePinyinSearch = usePinyinSearch
        }
        if let usePinyinInitialSearch = UserDefaults.standard.value(forKey: "usePinyinInitialSearch") as? Bool {
            globalVar.usePinyinInitialSearch = usePinyinInitialSearch
        }
        if let memUseLimit = UserDefaults.standard.value(forKey: "memUseLimit") as? Int {
            globalVar.memUseLimit = memUseLimit
        }
        if let thumbThreadNum = UserDefaults.standard.value(forKey: "thumbThreadNum") as? Int {
            globalVar.thumbThreadNum = thumbThreadNum
        }
        if let folderSearchDepth = UserDefaults.standard.value(forKey: "folderSearchDepth") as? Int {
            globalVar.folderSearchDepth = folderSearchDepth
        }
        if let thumbThreadNum_External = UserDefaults.standard.value(forKey: "thumbThreadNum_External") as? Int {
            globalVar.thumbThreadNum_External = thumbThreadNum_External
        }
        if let folderSearchDepth_External = UserDefaults.standard.value(forKey: "folderSearchDepth_External") as? Int {
            globalVar.folderSearchDepth_External = folderSearchDepth_External
        }
        if let doNotUseFFmpeg = UserDefaults.standard.value(forKey: "doNotUseFFmpeg") as? Bool {
            globalVar.doNotUseFFmpeg = doNotUseFFmpeg
        }
        if let portableMode = UserDefaults.standard.value(forKey: "portableMode") as? Bool {
            globalVar.portableMode = portableMode
        }
        if let videoPlayRememberPosition = UserDefaults.standard.value(forKey: "videoPlayRememberPosition") as? Bool {
            globalVar.videoPlayRememberPosition = videoPlayRememberPosition
        }
        if let useInternalPlayer = UserDefaults.standard.value(forKey: "useInternalPlayer") as? Bool {
            globalVar.useInternalPlayer = useInternalPlayer
        }
        if let isEnterKeyToOpen = UserDefaults.standard.value(forKey: "isEnterKeyToOpen") as? Bool {
            globalVar.isEnterKeyToOpen = isEnterKeyToOpen
        }
        
        globalVar.myFavoritesArray = defaults.array(forKey: "globalVar.myFavoritesArray") as? [String] ?? [String]()
        
        //requestAppleEventsPermission()
        
        favoritesMenu.removeAllItems()
        favoritesMenu.delegate = self
        historyMenu.removeAllItems()
        historyMenu.delegate = self
        viewMenu.delegate = self

        log("结束applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        log("开始applicationDidFinishLaunching")
        
        if windowControllers.count == 0 {
            _ = createNewWindow()
        }

//        DispatchQueue.global(qos: .userInitiated).async {
//            Thread.sleep(forTimeInterval: 8)
//            FFmpegKitWrapper.shared.loadFFmpegKitIfNeeded()
//        }
        
        log("结束applicationDidFinishLaunching")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        log("App EXIT")
        log("-----------------------------------------------------------")
        //Logger.shared.clearLogFile()
        UserDefaults.standard.set(true, forKey: "hasNormalExit")
        UserDefaults.standard.synchronize()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
//    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
//        return true
//    }
    
    func createNewWindow(_ path: String? = nil) -> WindowController? {
        log("开始createNewWindow")
        if isWindowNumMax() {
            showAlert(message: NSLocalizedString("window-num-max", comment: "窗口数量超过限制"))
            return nil
        }
        
        var openFolder: String? = nil

        if let path = path,
           let url = URL(string: path){
            
            var isDirectoryObj: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectoryObj)
            let isDirectory=isDirectoryObj.boolValue

            if isDirectory || path.hasSuffix("/") { //如果打开目录
                var tmp = url.absoluteString
                if !tmp.hasSuffix("/"){
                    tmp += "/"
                }
                openFolder=getFileStyleFolderPath(tmp+"xxx")
            }else{ //如果打开文件
                openFolder=getFileStyleFolderPath(path)
                if globalVar.portableMode,
                   let originalSize=getImageInfo(url: URL(string: getFileStylePath(path))!)?.size{
                    globalVar.startSpeedUpImageSizeCache=originalSize
                }
            }
        }
        
        // 加载 Main.storyboard
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        
        // 实例化 WindowController
        guard let windowController = storyboard.instantiateController(withIdentifier: "WindowController") as? WindowController else {
            fatalError("Cannot find WindowController in Main.storyboard")
        }
        
        // 添加到 windowControllers 数组
        windowControllers.append(windowController)
        globalVar.windowNum += 1
        
        // 显示窗口
        if !globalVar.isLaunchFromFile || !globalVar.useCreateWindowShowDelay {
            windowController.showWindow(self)
        }
        
        // 获取 contentViewController 并调用其函数
        if let viewController = windowController.contentViewController as? ViewController {
            if let openFolder=openFolder{
                viewController.fileDB.lock()
                viewController.fileDB.curFolder=openFolder
                viewController.fileDB.unlock()
            }
            DispatchQueue.main.async {
                viewController.afterFinishLoad(openFolder)
            }
        } else {
            log("Content view controller is not of type ViewController")
        }
        
        return windowController
    }
    
    func removeWindowController(_ windowController: NSWindowController) {
        if let index = windowControllers.firstIndex(of: windowController) {
            windowControllers.remove(at: index)
        }
    }

    func application(_ application: NSApplication, openFiles files: [String]) {
        NSApplication.shared.reply(toOpenOrPrint: .success)
        for filePath in files {
            log(filePath)
        }

        var path = files[0]
        
        if path == "." {
            path = FileManager.default.currentDirectoryPath
        }
        
        var file = path.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!
        file = file.hasPrefix("file://") ? file : "file://" + file
        if let url=URL(string: file){
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
        
        var isDirectoryObj: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectoryObj)
        let isDirectory=isDirectoryObj.boolValue
        
        if isDirectory && file.last != "/" {file=file+"/"}
        
        //新窗口打开（暂时统一新窗口打开）
        if true || windowControllers.count == 0 {
            if isDirectory{
                _ = createNewWindow(file)
                return
            }else{
                globalVar.isLaunchFromFile=true
                if windowControllers.count == 0 || globalVar.autoHideToolbar {
                    //直到大图加载完毕后才显示窗口，用来减少首次启动的画面闪动
                    //对于多标签页情况的第二个标签页，使用此会导致大图的缩放是按上次记忆而不是当前窗口实际大小，因此除这两种情况外不适合使用
                    globalVar.useCreateWindowShowDelay=true
                }
                if let targetWindowController = createNewWindow(file) {
                    openImageInTargetWindow(file, windowController: targetWindowController)
                }
                return
            }
        }
        
        //本窗口打开
        if isDirectory{
            DispatchQueue.main.async {
                if let mainViewController = NSApplication.shared.mainWindow?.windowController?.contentViewController as? ViewController {
                    mainViewController.handleDraggedFiles([URL(string: file)!])
                }else if let viewController = self.windowControllers.first?.contentViewController as? ViewController {
                    viewController.handleDraggedFiles([URL(string: file)!])
                }
            }
        }else{
            DispatchQueue.main.async {
                if let mainWindowController = NSApplication.shared.mainWindow?.windowController {
                    self.openImageInTargetWindow(file, windowController: mainWindowController)
                }else if let windowController = self.windowControllers.first {
                    self.openImageInTargetWindow(file, windowController: windowController)
                }
            }
        }
    }
    
    func openImageInMainWindow(_ openPath: String){
//        guard let mainViewController=getMainViewController() else {return}
//        let folderPath=getFileStyleFolderPath(openPath)
//        let path=getFileStylePath(openPath)
//        
//        mainViewController.publicVar.openFromFinderPath=path
//        mainViewController.OpenLargeImageFromFinder(path: path)
//        mainViewController.switchDirByDirection(direction: .zero, dest: folderPath, doCollapse: true, expandLast: true, skip: false)
//        
        
        guard let mainWindowController = NSApplication.shared.mainWindow?.windowController else {return}
        openImageInTargetWindow(openPath, windowController: mainWindowController)
    }
    
    func openImageInTargetWindow(_ openPath: String, windowController: NSWindowController){
        guard let viewController = windowController.contentViewController as? ViewController else {return}
        let folderPath=getFileStyleFolderPath(openPath)
        let path=getFileStylePath(openPath)
        
        viewController.publicVar.openFromFinderPath=path
        viewController.OpenLargeImageFromFinder(path: path)
        DispatchQueue.main.async {
            viewController.switchDirByDirection(direction: .zero, dest: folderPath, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
        }
    }
        
    @IBAction func openDocument(_ sender: Any?) {
        let dialog = NSOpenPanel()
        
        dialog.title                   = NSLocalizedString("Choose a file or folder", comment: "选择一个文件或文件夹")
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = false
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories    = true
        dialog.allowedFileTypes        = globalVar.HandledImageAndRawExtensions
        
        if (dialog.runModal() == NSApplication.ModalResponse.OK) {
            if let result = dialog.url {
                // Add the selected document to recent documents
                NSDocumentController.shared.noteNewRecentDocumentURL(result)
                
                log("Selected file: \(result.path)")
                
                //本窗口打开
                //getMainViewController()?.handleDraggedFiles([result])
                
                //新窗口打开
                var isDirectoryObj: ObjCBool = false
                FileManager.default.fileExists(atPath: result.path, isDirectory: &isDirectoryObj)
                let isDirectory=isDirectoryObj.boolValue
                if isDirectory {
                    _ = createNewWindow(result.absoluteString)
                }else{
                    globalVar.isLaunchFromFile=true
                    if let windowController = createNewWindow(result.absoluteString) {
                        openImageInTargetWindow(result.absoluteString, windowController: windowController)
                    }
                }
            }
        } else {
            // User clicked on "Cancel"
            return
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let mainViewController=getMainViewController() else{return}
        if menu == favoritesMenu {
            favoritesMenu.removeAllItems()
            
            let addFolderMenuItem = NSMenuItem(
                title: NSLocalizedString("Add Current Folder", comment: "添加当前文件夹"),
                action: #selector(favoritesAdd(_:)),
                keyEquivalent: ""
            )
            addFolderMenuItem.target = self
            favoritesMenu.addItem(addFolderMenuItem)
            
            favoritesMenu.addItem(NSMenuItem.separator())
            
            if globalVar.myFavoritesArray.count > 0 {
                for (index, folderPath) in globalVar.myFavoritesArray.enumerated() {
                    let folderMenuItem = NSMenuItem(
                        title: folderPath.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!,
                        action: #selector(pathClick(_:)),
                        keyEquivalent: ""
                    )
                    folderMenuItem.target = self
                    
                    // 创建子菜单
                    let subMenu = NSMenu(title: folderPath)
                    
                    // 创建删除项
                    let deleteMenuItem = NSMenuItem(
                        title: NSLocalizedString("Delete", comment: "删除"),
                        action: #selector(deleteFavorite(_:)),
                        keyEquivalent: ""
                    )
                    deleteMenuItem.target = self
                    deleteMenuItem.representedObject = folderPath
                    
                    // 创建上移项
                    let moveUpMenuItem = NSMenuItem(
                        title: NSLocalizedString("Move Up", comment: "上移"),
                        action: #selector(moveUpFavorite(_:)),
                        keyEquivalent: ""
                    )
                    moveUpMenuItem.target = self
                    moveUpMenuItem.representedObject = index
                    
                    // 创建下移项
                    let moveDownMenuItem = NSMenuItem(
                        title: NSLocalizedString("Move Down", comment: "下移"),
                        action: #selector(moveDownFavorite(_:)),
                        keyEquivalent: ""
                    )
                    moveDownMenuItem.target = self
                    moveDownMenuItem.representedObject = index
                    
                    // 将项添加到子菜单
                    subMenu.addItem(deleteMenuItem)
                    subMenu.addItem(moveUpMenuItem)
                    subMenu.addItem(moveDownMenuItem)
                    
                    // 将子菜单添加到主菜单项
                    folderMenuItem.submenu = subMenu
                    
                    // 将主菜单项添加到 favoritesMenu
                    favoritesMenu.addItem(folderMenuItem)
                }
            } else {
                let emptyMenuItem = NSMenuItem(
                    title: NSLocalizedString("empty-enclose", comment: "菜单当内容为空时显示的东西"),
                    action: nil,
                    keyEquivalent: ""
                )
                favoritesMenu.addItem(emptyMenuItem)
            }
        }
        
        if menu == historyMenu {
            historyMenu.removeAllItems()
            if mainViewController.publicVar.folderStepStack.count > 0 {
                for item in mainViewController.publicVar.folderStepStack {
                    let menuItem = NSMenuItem(title: item.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!, action: #selector(pathClick(_:)), keyEquivalent: "")
                    menuItem.target = self
                    historyMenu.addItem(menuItem)
                }
            }else{
                let menuItem = NSMenuItem(title: NSLocalizedString("empty-enclose", comment: "菜单当内容为空时显示的东西"), action: nil, keyEquivalent: "")
                menuItem.target = self
                historyMenu.addItem(menuItem)
            }
        }
        
        if menu == viewMenu {
            let theme=NSApp.effectiveAppearance.name
            if NSApp.appearance == nil {
                systemThemeMenuItem.state = .on
                lightModeMenuItem.state = .off
                darkModeMenuItem.state = .off
            }else{
                systemThemeMenuItem.state = .off
                lightModeMenuItem.state = (theme == .darkAqua) ? .off : .on
                darkModeMenuItem.state = (theme == .darkAqua) ? .on : .off
            }
            
            if let window = NSApplication.shared.mainWindow {
                onTopMenuItem.state = (window.level == .floating) ? .on : .off
            }
            onTopMenuItem.keyEquivalent="t"
            onTopMenuItem.keyEquivalentModifierMask=[]
            
            toggleIsShowHiddenFileMenuItem.state = mainViewController.publicVar.isShowHiddenFile ? .on : .off
            toggleIsShowAllTypeFileMenuItem.state = mainViewController.publicVar.isShowAllTypeFile ? .on : .off
            toggleIsShowImageFileMenuItem.state = mainViewController.publicVar.isShowImageFile ? .on : .off
            toggleIsShowRawFileMenuItem.state = mainViewController.publicVar.isShowRawFile ? .on : .off
            toggleIsShowVideoFileMenuItem.state = mainViewController.publicVar.isShowVideoFile ? .on : .off
            
            justifiedViewMenuItem.state = (mainViewController.publicVar.profile.layoutType == .justified) ? .on : .off
            waterfallViewModeMenuItem.state = (mainViewController.publicVar.profile.layoutType == .waterfall) ? .on : .off
            gridViewMenuItem.state = (mainViewController.publicVar.profile.layoutType == .grid) ? .on : .off
            detailViewModeMenuItem.state = (mainViewController.publicVar.profile.layoutType == .detail) ? .on : .off
            
            maximizeWindowMenuItem.keyEquivalent="1"
            maximizeWindowMenuItem.keyEquivalentModifierMask=[]
            optimizeWindowMenuItem.keyEquivalent="2"
            optimizeWindowMenuItem.keyEquivalentModifierMask=[]
            adjustWindowActualMenuItem.keyEquivalent="3"
            adjustWindowActualMenuItem.keyEquivalentModifierMask=[]
            adjustWindowCurrentMenuItem.keyEquivalent="4"
            adjustWindowCurrentMenuItem.keyEquivalentModifierMask=[]
            adjustWindowToCenterMenuItem.keyEquivalent="5"
            adjustWindowToCenterMenuItem.keyEquivalentModifierMask=[]
            
//            justifiedViewMenuItem.keyEquivalent="1"
//            justifiedViewMenuItem.keyEquivalentModifierMask=[]
//            waterfallViewModeMenuItem.keyEquivalent="2"
//            waterfallViewModeMenuItem.keyEquivalentModifierMask=[]
//            gridViewMenuItem.keyEquivalent="3"
//            gridViewMenuItem.keyEquivalentModifierMask=[]
//            detailViewModeMenuItem.keyEquivalent="4"
//            detailViewModeMenuItem.keyEquivalentModifierMask=[]
            
            switchToActualSizeMenuItem.state = (mainViewController.publicVar.isLargeImageFitWindow == false) ? .on : .off
            switchToFitToWindowMenuItem.state = (mainViewController.publicVar.isLargeImageFitWindow == true) ? .on : .off
            
            toggleSidebarMenuItem.state = (mainViewController.publicVar.profile.isDirTreeHidden == false) ? .on : .off
            toggleSidebarMenuItem.keyEquivalent="f"
            toggleSidebarMenuItem.keyEquivalentModifierMask=[]
        }
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let mainViewController=getMainViewController() else{
            //如果没有窗口，则只有新建标签页为有效，其它皆为无效
            if menuItem.action == #selector(fileNewTab(_:)) {
                return true
            }else{
                return false
            }
        }
        //新建标签页限制最大窗口数量
        if menuItem.action == #selector(fileNewTab(_:)) && isWindowNumMax() {
            return false
        }
        //根据图片大小调整窗口
        if menuItem.action == #selector(adjustWindowActual(_:)) || menuItem.action == #selector(adjustWindowCurrent(_:)) {
            if !mainViewController.publicVar.isInLargeView {
                return false
            }
        }
        //复制、删除
        if menuItem.action == #selector(editCopy(_:)) || menuItem.action == #selector(editDelete(_:)) {
            if mainViewController.publicVar.isKeyEventEnabled == false {
                return false
            }
//            if !mainViewController.publicVar.isOutlineViewFirstResponder && !mainViewController.publicVar.isCollectionViewFirstResponder {
//                return false
//            }
            //如果焦点在OutlineView
            if mainViewController.publicVar.isOutlineViewFirstResponder{
                if mainViewController.outlineView.getFirstSelectedUrl() == nil {
                    return false
                }
            }
            //如果焦点在CollectionView
            if mainViewController.publicVar.isCollectionViewFirstResponder{
                if mainViewController.publicVar.selectedUrls().count == 0 {
                    return false
                }
            }
        }
        //粘贴、移动
        if menuItem.action == #selector(editPaste(_:)) || menuItem.action == #selector(editMove(_:)) {
            if mainViewController.publicVar.isKeyEventEnabled == false {
                return false
            }
            if !mainViewController.publicVar.isOutlineViewFirstResponder && !mainViewController.publicVar.isCollectionViewFirstResponder {
                return false
            }
            if mainViewController.publicVar.isInLargeView {
                return false
            }
            let pasteboard = NSPasteboard.general
            let types = pasteboard.types ?? []
            if !types.contains(.fileURL) {
                return false
            }
        }
        //选择全部、搜索
        if menuItem.action == #selector(selectAll(_:)) || menuItem.action == #selector(showSearch(_:)) {
            if mainViewController.publicVar.isInLargeView {
                return false
            }
        }
        //取消选择
        if menuItem.action == #selector(deselectAll(_:)) {
            if mainViewController.publicVar.isInLargeView {
                return false
            }
            //如果焦点在CollectionView
            if mainViewController.publicVar.isCollectionViewFirstResponder{
                if mainViewController.publicVar.selectedUrls().count == 0 {
                    return false
                }
            }else{
                return false
            }
        }
        //是否是显示全部文件类型
        if menuItem.action == #selector(toggleIsShowImageFile(_:)) || menuItem.action == #selector(toggleIsShowRawFile(_:)) || menuItem.action == #selector(toggleIsShowVideoFile(_:)) {
            if mainViewController.publicVar.isShowAllTypeFile {
                return false
            }
        }
        return true
    }
    
    @IBAction
    func settingsMenuItemActionHandler(_ sender: NSMenuItem) {
        settingsWindowController.show()
    }

    @objc func pathClick(_ sender: NSMenuItem) {
        guard let mainViewController=getMainViewController() else {return}
        log("Clicked on \(sender.title)")

        guard let url=URL(string: getFileStylePath(sender.title)) else {return}
        if mainViewController.publicVar.isInLargeView {
            mainViewController.closeLargeImage(0)
        }
        mainViewController.switchDirByDirection(direction: .zero, dest: url.absoluteString, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
    }
    
    @objc func favoritesAdd(_ sender: NSMenuItem) {
        guard let mainViewController=getMainViewController() else {return}
        mainViewController.fileDB.lock()
        let curFolder=mainViewController.fileDB.curFolder
        mainViewController.fileDB.unlock()
        if !globalVar.myFavoritesArray.contains(curFolder) {
            globalVar.myFavoritesArray.append(curFolder)
            let defaults = UserDefaults.standard
            defaults.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
        }
    }
    @objc func deleteFavorite(_ sender: NSMenuItem) {
        guard let folderPath = sender.representedObject as? String else { return }
        
        // 在这里处理删除逻辑
        if let index = globalVar.myFavoritesArray.firstIndex(of: folderPath) {
            globalVar.myFavoritesArray.remove(at: index)
            let defaults = UserDefaults.standard
            defaults.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
        }
        
        // 更新菜单以反映更改
        //menuNeedsUpdate(favoritesMenu)
    }
    @objc func moveUpFavorite(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, index > 0 else { return }
        
        // 在这里处理上移逻辑
        globalVar.myFavoritesArray.swapAt(index, index - 1)
        let defaults = UserDefaults.standard
        defaults.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
        
        // 更新菜单以反映更改
        //menuNeedsUpdate(favoritesMenu)
    }

    @objc func moveDownFavorite(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, index < globalVar.myFavoritesArray.count - 1 else { return }
        
        // 在这里处理下移逻辑
        globalVar.myFavoritesArray.swapAt(index, index + 1)
        let defaults = UserDefaults.standard
        defaults.set(globalVar.myFavoritesArray, forKey: "globalVar.myFavoritesArray")
        
        // 更新菜单以反映更改
        //menuNeedsUpdate(favoritesMenu)
    }
    
    @IBAction func editMove(_ sender: NSMenuItem){
        getMainViewController()?.handleMove()
    }
    
    @IBAction func editCopy(_ sender: NSMenuItem){
        guard let mainViewController=getMainViewController() else{return}
        if mainViewController.publicVar.isInLargeView {
            mainViewController.largeImageView.actCopy()
        }else{
            //如果焦点在OutlineView
            if mainViewController.publicVar.isOutlineViewFirstResponder{
                mainViewController.outlineView.actCopy(isByKeyboard: true)
            }
            //如果焦点在CollectionView
            if mainViewController.publicVar.isCollectionViewFirstResponder{
                mainViewController.handleCopy()
            }
        }
        
    }
    
    @IBAction func editPaste(_ sender: NSMenuItem){
        getMainViewController()?.handlePaste()
    }
    
    @IBAction func editDelete(_ sender: NSMenuItem){
        //注意：由于未知原因有时无法触发，因此主要在按键监听里处理
        guard let mainViewController=getMainViewController() else{return}
        if mainViewController.publicVar.isInLargeView {
            mainViewController.handleDelete()
        }else{
            //如果焦点在OutlineView
            if mainViewController.publicVar.isOutlineViewFirstResponder{
                mainViewController.outlineView.actDelete(isByKeyboard: true)
            }
            //如果焦点在CollectionView
            if mainViewController.publicVar.isCollectionViewFirstResponder{
                mainViewController.handleDelete()
            }
        }
    }
    
    @IBAction func fileNewTab(_ sender: NSMenuItem){
        getMainViewController()?.fileDB.lock()
        let curFolder = getMainViewController()?.fileDB.curFolder
        getMainViewController()?.fileDB.unlock()
        createNewWindow(curFolder)
    }
    
    @IBAction func fileNewFolder(_ sender: NSMenuItem){
        getMainViewController()?.handleNewFolder()
    }
    
    @IBAction func gotoFolder(_ sender: NSMenuItem){
        getMainViewController()?.showCmdShiftGWindow()
    }
    
    @IBAction func filePrint(_ sender: NSMenuItem){
        getMainViewController()?.handlePrint()
    }
    
    @IBAction func filePageSetup(_ sender: NSMenuItem){
        let pageLayout = NSPageLayout()
        let printInfo = NSPrintInfo.shared
        
        pageLayout.runModal(with: printInfo)
    }
    
    @IBAction func toggleIsShowHiddenFile(_ sender: NSMenuItem){
        getMainViewController()?.toggleIsShowHiddenFile()
    }
    
    @IBAction func toggleIsShowImageFile(_ sender: NSMenuItem){
        getMainViewController()?.toggleIsShowImageFile()
    }
    
    @IBAction func toggleIsShowRawFile(_ sender: NSMenuItem){
        getMainViewController()?.toggleIsShowRawFile()
    }
    
    @IBAction func toggleIsShowVideoFile(_ sender: NSMenuItem){
        getMainViewController()?.toggleIsShowVideoFile()
    }
    
    @IBAction func toggleIsShowAllTypeFile(_ sender: NSMenuItem){
        getMainViewController()?.toggleIsShowAllTypeFile()
    }
    
    @IBAction func switchToSystemTheme(_ sender: NSMenuItem){
        let defaults = UserDefaults.standard
        defaults.set("", forKey: "appearance")
        NSApp.appearance=nil
    }
    
    @IBAction func switchToLightMode(_ sender: NSMenuItem){
        let defaults = UserDefaults.standard
        defaults.set("aqua", forKey: "appearance")
        NSApp.appearance=NSAppearance(named: .aqua)
    }
    
    @IBAction func switchToDarkMode(_ sender: NSMenuItem){
        let defaults = UserDefaults.standard
        defaults.set("darkAqua", forKey: "appearance")
        NSApp.appearance=NSAppearance(named: .darkAqua)
    }
    
    @IBAction func maximizeWindow(_ sender: NSMenuItem){
        getMainViewController()?.adjustWindowMaximize()
    }
    
    @IBAction func optimizeWindow(_ sender: NSMenuItem){
        getMainViewController()?.adjustWindowSuitable()
    }
    
    @IBAction func adjustWindowActual(_ sender: NSMenuItem){
        getMainViewController()?.adjustWindowImageActual()
    }
    
    @IBAction func adjustWindowCurrent(_ sender: NSMenuItem){
        getMainViewController()?.adjustWindowImageCurrent()
    }
    
    @IBAction func adjustWindowToCenter(_ sender: NSMenuItem){
        getMainViewController()?.adjustWindowToCenter()
    }
    
    @IBAction func switchToJustifiedView(_ sender: NSMenuItem){
        getMainViewController()?.switchToJustifiedView()
    }
    
    @IBAction func switchToGridView(_ sender: NSMenuItem){
        getMainViewController()?.switchToGridView()
    }
    
    @IBAction func switchToWaterfallView(_ sender: NSMenuItem){
        getMainViewController()?.switchToWaterfallView()
    }
    
    @IBAction func switchToDetailView(_ sender: NSMenuItem){
        getMainViewController()?.switchToDetailView()
    }
    
    @IBAction func switchToActualSize(_ sender: NSMenuItem){
        getMainViewController()?.switchToActualSize()
        
    }
    @IBAction func switchToFitToWindow(_ sender: NSMenuItem){
        getMainViewController()?.switchToFitToWindow()
    }
    
    @IBAction func toggleSidebar(_ sender: NSMenuItem){
        getMainViewController()?.toggleSidebar()
    }
    
    @IBAction func toggleOnTop(_ sender: NSMenuItem){
        getMainViewController()?.toggleOnTop()
    }
    
    @IBAction func showLogWindow(_ sender: NSMenuItem){
        Logger.shared.showLogWindow()
    }
    
    @IBAction func officialWebsite(_ sender: NSMenuItem){
        if let url = URL(string: OFFICIAL_WEBSITE) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @IBAction func customLayoutStyle(_ sender: NSMenuItem){
        getMainViewController()?.customLayoutStylePrompt()
    }
    
    @IBAction func selectAll(_ sender: NSMenuItem){
        //getMainViewController()?.collectionView.selectAll(nil)
        NSApp.keyWindow?.firstResponder?.selectAll(nil)
    }
    
    @IBAction func deselectAll(_ sender: NSMenuItem){
        //主要由按键监听处理
        getMainViewController()?.collectionView.deselectAll(nil)
    }
    
    @IBAction func showSearch(_ sender: NSMenuItem){
        getMainViewController()?.toggleSearchOverlay()
    }
}

