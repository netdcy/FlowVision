//
//  ViewController.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/13.
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

class CustomProfile: Codable {
    
    //布局类型
    var layoutType: LayoutType = .justified
    
    //侧边栏
    var isDirTreeHidden = false
    
    //排序
    var sortType: SortType = .pathA
    var isSortFolderFirst: Bool = true
    
    //缩略图大小
    var thumbSize = 512
    
    //布局
    var isShowThumbnailFilename = true
    var ThumbnailBorderThickness: Double = 6
    var ThumbnailBorderRadius: Double = 5
    var ThumbnailCellPadding: Double = 5
    //以下暂时为内部使用
    var ThumbnailFilenameSize: Double = 12
    //var ThumbnailFilenamePaddingInternal: Double = 18
    var ThumbnailFilenamePadding: Double = 18
    var ThumbnailScrollbarWidth: Double = 16
    var isGridViewNotAffectedByCustomStyle = true
    
    func saveToUserDefaults(withKey key: String) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    static func loadFromUserDefaults(withKey key: String) -> CustomProfile {
        if let savedData = UserDefaults.standard.data(forKey: key) {
            let decoder = JSONDecoder()
            if let loadedStyle = try? decoder.decode(CustomProfile.self, from: savedData) {
                return loadedStyle
            }
        }
        return CustomProfile() //读取异常时返回默认值
    }
}

class PublicVar{
    weak var refView: NSView!
    weak var viewController: ViewController!

    var isLargeImageFitWindow = true
    var isRecursiveMode = false
    var isShowHiddenFile = false
    var isShowAllTypeFile = false
    var isShowImageFile = true
    var isShowRawFile = true
    var isShowVideoFile = true
    var isGenHdThumb = false
    
    //可一键切换的配置
    var profile = CustomProfile()
    
    var fullTitle = "FlowVision"
    var isKeyEventEnabled = true
    var folderStepStack = [String]() {
        didSet {updateToolbar()}
    }
    var folderStepForwardStack = [String]()
    var isLeftMouseDown: Bool = false
    var isRightMouseDown: Bool = false
    var isInInitStage: Bool = true
    var isInLargeView: Bool = false {
        didSet {
            if !isInInitStage {
                getViewController(refView)?.setCollectionViewTooltip()
                updateToolbar()
                if globalVar.portableMode {
                    getViewController(refView)?.adjustWindowPortable(firstShowThumb: true, animate: false)
                }
                if !isInLargeView {
                    getViewController(refView)?.recalcIfHasChangedSize()
                }
            }
        }
    }
    var isInLargeViewAfterAnimate: Bool = false
    var openFromFinderPath = ""
    var isColllectionViewItemRightClicked = false
    var lastLargeImageIdInImage: Int = 0
    var isCollectionViewFirstResponder: Bool = false
    var isOutlineViewFirstResponder: Bool = false
    var isShowExif: Bool = false {
        didSet {
            if let largeImageView = getViewController(refView)?.largeImageView,
               let url = URL(string: largeImageView.file.path),
               isShowExif && largeImageView.exifTextView.textItems.isEmpty{
                largeImageView.updateTextItems(formatExifData(getExifData(from: url) ?? [:]))
            }
            getViewController(refView)?.largeImageView.exifTextView.isHidden = !isShowExif
            updateToolbar()
        }
    }
    var isNeedChangeLayoutType = false
    var justifiedLayout = CustomFlowLayout() //JQCollectionViewAlignLayout()
    var waterfallLayout = WaterfallLayout()
    //weak var viewController:ViewController?
    var timer = MyTimer()
    var fileChangedCount = 0
    var isInStageOneProgress = false
    var isInStageTwoProgress = false
    var isInStageThreeProgress = false
    
    var HandledImageExtensions: [String] = []
    var HandledVideoExtensions: [String] = []
    var HandledOtherExtensions: [String] = []
    var HandledNonExternalExtensions: [String] = []
    var HandledNotNativeSupportedVideoExtensions: [String] = []
    //var HandledExternalExtensions: [String] = []
    var HandledFileExtensions: [String] = []
    var HandledSearchExtensions: [String] = []
    var HandledFolderThumbExtensions: [String] = []
    //使用个别特殊svg作为文件夹缩略图绘图元素会导致程序异常 'NSGenericException', reason: 'NaN point value'

    func setFileExtensions(){
        HandledImageExtensions = []
        if self.isShowImageFile{
            HandledImageExtensions += ["jpg", "jpeg", "jxl", "png", "gif", "bmp", "heif", "heic", "hif", "avif", "tif", "tiff", "webp", "jfif", "jp2", "ai", "psd", "ico", "icns", "svg"]
        }
        if self.isShowRawFile {
            HandledImageExtensions += ["crw", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "rw2", "orf", "raf", "pef", "dng", "raw", "rwl", "x3f", "3fr", "fff", "iiq", "mos", "dcr", "erf", "mrw", "gpr", "srw"]
        }
        HandledVideoExtensions = []
        if self.isShowVideoFile {
            HandledVideoExtensions += ["mp4", "mov", "m2ts", "vob", "mpeg", "mpg", "m4v"] + ["mkv", "mts", "ts", "avi", "flv", "f4v", "asf", "wmv", "rmvb", "rm", "webm", "divx", "xvid", "3gp", "3g2"]
        }
        HandledOtherExtensions = [] //["pdf"] //不能为""，否则会把目录异常包含进来
        HandledNonExternalExtensions = HandledImageExtensions
        HandledNotNativeSupportedVideoExtensions = ["mkv", "mts", "ts", "avi", "flv", "f4v", "asf", "wmv", "rmvb", "rm", "webm", "divx", "xvid", "3gp", "3g2"]
        //HandledExternalExtensions = HandledVideoExtensions // + ["pdf"] //外部程序打开的
        HandledFileExtensions = HandledImageExtensions + HandledVideoExtensions + HandledOtherExtensions //文件列表显示的
        HandledSearchExtensions = HandledImageExtensions + HandledVideoExtensions //作为鼠标手势查找的目标
        HandledFolderThumbExtensions = HandledImageExtensions.filter{$0 != "svg"} + HandledVideoExtensions // + ["pdf"] //目录缩略图
        //使用个别特殊svg作为文件夹缩略图绘图元素会导致程序异常 'NSGenericException', reason: 'NaN point value'
    }
    
    var selectedUrls2 = [URL]()
    func selectedUrls() -> [URL] {
        var urls = getViewController(refView)?.getSelectedURLs() ?? []
        if urls.count == 0,
           getViewController(refView)?.publicVar.isInLargeView == true,
           let path=getViewController(refView)?.largeImageView.file.path,
           let url=URL(string: path){
            urls.append(url)
        }
        return urls
    }
    
    func updateToolbar(){
        if let windowController = (getViewController(refView)?.view.window?.windowController) as? WindowController {
            windowController.updateToolbar()
        }
    }
}

class ViewController: NSViewController, NSSplitViewDelegate {
    
    @IBOutlet weak var collectionView: CustomCollectionView!
    @IBOutlet weak var mainScrollView: NSScrollView!
    @IBOutlet weak var outlineScrollView: NSScrollView!
    @IBOutlet weak var largeImageView: LargeImageView!
    @IBOutlet weak var largeImageBgEffectView: NSVisualEffectView!
    @IBOutlet weak var coreAreaView: CoreAreaView!
    @IBOutlet weak var outlineView: CustomOutlineView!
    @IBOutlet weak var splitView: CustomSplitView!
    
    var treeViewData = TreeViewModel()
    
    var publicVar = PublicVar()
    
    var recalcLayoutTimes = 0
    var startTime = DispatchTime(uptimeNanoseconds: 0)
    var endTime = DispatchTime(uptimeNanoseconds: 0)
    
    
    var initLargeImagePos = -1
    var currLargeImagePos = -1
    var fileDB = DatabaseModel()
    
    var readInfoTaskPool = [TaskType]()
    var readInfoTaskPoolLock = NSLock()
    
    //var loadImageTaskPool = [(String,String,Int)]()
    var loadImageTaskPool = TaskPool()
    //var loadImageTaskPool.lock = NSLock()
    
    //var infoThreadPoolNum = 0
    //var infoThreadPoolLock = NSLock()
    //var thumbThreadPoolNum = 0
    //var thumbThreadPoolLock = NSLock()
    
    let readInfoTaskPoolSemaphore = DispatchSemaphore(value: 0)
    let loadImageTaskPoolSemaphore = DispatchSemaphore(value: 0)
    var externalVolumeThreadSemaphores = [String: DispatchSemaphore]()
    let externalVolumeThreadSemaphoresLock = NSLock()
    
    var searchFolderRound=0
    
#if DEBUG
    var rootFolder="file://\(homeDirectory)/RepoData/ImageViewerPlus/"
    var treeRootFolder="file://\(homeDirectory)/RepoData/ImageViewerPlus/"
    
//    var rootFolder="file:///"
//    var treeRootFolder="root"
    
    let isDeveloper=false
#else
    var rootFolder="file:///"
    var treeRootFolder="root"
    
    let isDeveloper=false
#endif
    
    var collectionViewManager: CustomCollectionViewManager!
    var outlineViewManager: CustomOutlineViewManager!
    
    var snapshotQueue = [NSView?]()
    
    var initialPoint: NSPoint?
    var drawingView: DrawingView?
    
    var resizeTimer: Timer?
    var folderMonitorTimer: Timer?
    
    var watchFileDescriptor: Int32 = -1
    var watchDispatchSource: DispatchSourceFileSystemObject?
    
    var LRUqueue = [(String,DispatchTime,Int)]()
    
    var largeImageLoadTask: DispatchWorkItem?
    var largeImageLoadQueueLock = NSLock()
    
    var lastDoNotGenResized = false
    var lastLargeImageRotate = 0
    
    var lastTheme: NSAppearance.Name = .aqua
    
    var hasManualToggleSidebar=false
    
    var eventMonitorKeyDown: Any?
    var eventMonitorRightMouseDown: Any?
    var eventMonitorRightMouseUp: Any?
    var eventMonitorRightMouseDragged: Any?
    var eventMonitorScrollWheel: Any?
    
    var willTerminate = false
    
    var windowSizeChangedTimesWhenInLarge=0
    
    var arrowScrollDebounceWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        log("开始viewDidLoad")
        
        publicVar.refView=collectionView
        publicVar.viewController=self
        treeViewData.viewController=self
        
        //初始化大图
        if globalVar.isLaunchFromFile {
            largeImageView.isHidden=false
            largeImageBgEffectView.isHidden=false
            largeImageView.alphaValue = 1
            largeImageBgEffectView.alphaValue = 1
            publicVar.isInLargeView=true
        }else{
            largeImageView.isHidden=true
            largeImageBgEffectView.isHidden=true
            largeImageView.alphaValue = 0
            largeImageBgEffectView.alphaValue = 0
            publicVar.isInLargeView=false
        }
        
        //防止设置上面值时触发动作
        publicVar.isInInitStage = false
        
        
        //初始化collectionView
        collectionViewManager=CustomCollectionViewManager(fileDB: fileDB)
        collectionView.wantsLayer = true
        collectionView.allowsMultipleSelection = true
        collectionView.isSelectable = true
        collectionView.delegate = collectionViewManager
        collectionView.dataSource = collectionViewManager
        collectionView.register(CustomCollectionViewItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "CustomCollectionViewItem"))
        collectionView.setDraggingSourceOperationMask([.every], forLocal: true)  // 本地拖动操作
        collectionView.setDraggingSourceOperationMask([.every], forLocal: false) // 全局拖动操作
        
//        publicVar.justifiedLayout.minimumInteritemSpacing=10
//        publicVar.justifiedLayout.minimumLineSpacing=10
//        publicVar.justifiedLayout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
//        publicVar.justifiedLayout.itemsHorizontalAlignment = JQCollectionViewItemsHorizontalAlignment.left;
//        publicVar.justifiedLayout.itemsVerticalAlignment = JQCollectionViewItemsVerticalAlignment.center;
        
        //初始化目录树
        outlineViewManager=CustomOutlineViewManager(fileDB: fileDB, treeViewData: treeViewData, outlineView: outlineView)
        outlineView.delegate = outlineViewManager
        outlineView.dataSource = outlineViewManager
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask([.every], forLocal: true)  // 本地拖动操作
        outlineView.setDraggingSourceOperationMask([.every], forLocal: false) // 全局拖动操作
        outlineView.columnAutoresizingStyle = .noColumnAutoresizing
        treeViewData.initData(path: treeRootFolder)
        outlineView.reloadData()
        DispatchQueue.main.async {
            self.outlineViewManager.adjustColumnWidth()
        }
        
        //初始化splitView
        splitView.delegate = self
        
        // 初始化DrawingView
        drawingView = DrawingView(frame: self.view.bounds)
        drawingView?.autoresizingMask = [.width, .height]  // 使视图随父视图改变大小而改变大小
        self.view.addSubview(drawingView!)
        
        //-----开始读取配置-----
        
        //TODO: 没有工具栏时，载入时折叠且divider宽度设为0会造成菜单栏变白

        if let isLargeImageFitWindow = UserDefaults.standard.value(forKey: "isLargeImageFitWindow") as? Bool {
            publicVar.isLargeImageFitWindow=isLargeImageFitWindow
        }
        if let isShowHiddenFile = UserDefaults.standard.value(forKey: "isShowHiddenFile") as? Bool {
            publicVar.isShowHiddenFile = isShowHiddenFile
        }
        if let isShowImageFile = UserDefaults.standard.value(forKey: "isShowImageFile") as? Bool {
            publicVar.isShowImageFile = isShowImageFile
        }
        if let isShowRawFile = UserDefaults.standard.value(forKey: "isShowRawFile") as? Bool {
            publicVar.isShowRawFile = isShowRawFile
        }
        if let isShowAllTypeFile = UserDefaults.standard.value(forKey: "isShowAllTypeFile") as? Bool {
            publicVar.isShowAllTypeFile = isShowAllTypeFile
        }
        if let isShowVideoFile = UserDefaults.standard.value(forKey: "isShowVideoFile") as? Bool {
            publicVar.isShowVideoFile = isShowVideoFile
        }
        if let isGenHdThumb = UserDefaults.standard.value(forKey: "isGenHdThumb") as? Bool {
            publicVar.isGenHdThumb = isGenHdThumb
        }
//        if let layoutType: LayoutType = UserDefaults.standard.enumValue(forKey: "layoutType"){
//            publicVar.layoutType=layoutType
//        }
//        if let thumbSize = UserDefaults.standard.value(forKey: "thumbSize") as? Int {
//            publicVar.profile.thumbSize = thumbSize
//        }
//        if let isDirTreeHidden = UserDefaults.standard.value(forKey: "isDirTreeHidden") as? Bool {
//            publicVar.profile.isDirTreeHidden=isDirTreeHidden
//        }
//        if let sortType: SortType = UserDefaults.standard.enumValue(forKey: "sortType"){
//            publicVar.profile.sortType=sortType
//        }
//        if let isSortFolderFirst = UserDefaults.standard.value(forKey: "isSortFolderFirst") as? Bool {
//            publicVar.profile.isSortFolderFirst = isSortFolderFirst
//        }
        publicVar.profile = CustomProfile.loadFromUserDefaults(withKey: "CustomStyle_v1_current")
        
        //-----结束读取配置------
        
        publicVar.setFileExtensions()
        
        if publicVar.profile.isDirTreeHidden{
            splitView.setPosition(0, ofDividerAt: 0)
        }

        if publicVar.profile.layoutType == .waterfall {
            collectionView.collectionViewLayout = publicVar.waterfallLayout
        }else if publicVar.profile.layoutType == .justified {
            collectionView.collectionViewLayout = publicVar.justifiedLayout
        }else if publicVar.profile.layoutType == .grid {
            collectionView.collectionViewLayout = publicVar.justifiedLayout
        }else {
            collectionView.collectionViewLayout = publicVar.justifiedLayout
        }
        changeWaterfallLayoutNumberOfColumns()
        
        let theme=NSApp.effectiveAppearance.name
        if theme == .darkAqua {
            // 暗模式下的颜色
            collectionView.layer?.backgroundColor = hexToNSColor(hex: "#212223").cgColor
            lastTheme = .darkAqua
        } else {
            // 光模式下的颜色
            collectionView.layer?.backgroundColor = hexToNSColor(hex: "#FFFFFF").cgColor
            lastTheme = .aqua
        }
        
        if globalVar.autoHideToolbar {
            mainScrollView.automaticallyAdjustsContentInsets = false
            outlineScrollView.automaticallyAdjustsContentInsets = false
        }
        
        mainScrollView.scrollerStyle = .legacy
        outlineScrollView.scrollerStyle = .legacy
        
        //=========以下是事件监听配置==========
        
        NSApp.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new, .old], context: nil)
        
        //双击目录树
        outlineView.doubleAction = #selector(outlineViewDoubleClicked(_:))
        
        //双击大图
//        let clickLargeImageGestureRecognizer = NSClickGestureRecognizer(target: self, action: #selector(closeLargeImage))
//        clickLargeImageGestureRecognizer.numberOfClicksRequired = 2 // 设置为双击
//        clickLargeImageGestureRecognizer.delaysPrimaryMouseButtonEvents = false // 阻止延迟主按钮事件
//        largeImageView.addGestureRecognizer(clickLargeImageGestureRecognizer)
        
        //双击collectionView
//        let clickCollectionItemGesture = NSClickGestureRecognizer(target: self, action: #selector(openLargeImageFromPos(_:)))
//        clickCollectionItemGesture.numberOfClicksRequired = 2 // 设置为双击
//        clickCollectionItemGesture.delaysPrimaryMouseButtonEvents = false // 阻止延迟主按钮事件
//        collectionView.addGestureRecognizer(clickCollectionItemGesture)
        
        //全局滚动事件
        eventMonitorScrollWheel = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self=self else{return event}
            //if getMainViewController() != self {return event}
            // 检查事件的窗口是否是当前窗口
            if event.window != self.view.window {
                return event
            }
            self.handleScrollWheel(event)
            return event
        }
        
        //滚动collectionView
        if let scrollView = collectionView.enclosingScrollView {
            // 监听滚动开始和结束的通知
            NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll(_:)), name: NSScrollView.didLiveScrollNotification, object: scrollView)
            NotificationCenter.default.addObserver(self, selector: #selector(scrollViewScrollEnd(_:)), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }
        
        //监听键盘按键
        eventMonitorKeyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self=self else{return event}
            // 检查事件的窗口是否是当前窗口，如果不是、也非弹窗状态，就不处理，事件继续传递
            if event.window != self.view.window && publicVar.isKeyEventEnabled {
                return event
            }
            if publicVar.isKeyEventEnabled && publicVar.timer.intervalSafe(name: "keyEvent", second: 0.1) {
                // 获取修饰键
                let modifierFlags = event.modifierFlags
                // 检测是否按下了 Control 键
                let isCtrlPressed = modifierFlags.contains(.control)
                // 检测是否按下了 Command 键
                let isCommandPressed = modifierFlags.contains(.command)
                // 检测是否按下了 Option 键
                let isAltPressed = modifierFlags.contains(.option)
                // 检测是否按下了 Shift 键
                let isShiftPressed = modifierFlags.contains(.shift)
                
                let noModifierKey = !isCommandPressed && !isAltPressed && !isCtrlPressed && !isShiftPressed
                let isOnlyCommandPressed = isCommandPressed && !isAltPressed && !isCtrlPressed && !isShiftPressed
                let isOnlyAltPressed = !isCommandPressed && isAltPressed && !isCtrlPressed && !isShiftPressed
                let isOnlyCtrlPressed = !isCommandPressed && !isAltPressed && isCtrlPressed && !isShiftPressed
                let isOnlyShiftPressed = !isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed
                
                let characters = event.charactersIgnoringModifiers ?? ""
                let specialKey = event.specialKey ?? .f30
                
                // 检查按键是否是 "A" 键
                if characters == "a" && noModifierKey {
                    closeLargeImage(0)
                    switchDirByDirection(direction: .left, stackDeep: 0)
                    return nil
                }
                // 检查按键是否是 "D" 键
                if characters == "d" && noModifierKey {
                    closeLargeImage(0)
                    switchDirByDirection(direction: .right, stackDeep: 0)
                    return nil
                }
                // 检查按键是否是 "W" 键
                if characters == "w" && noModifierKey {
                    closeLargeImage(0)
                    switchDirByDirection(direction: .up, stackDeep: 0)
                    return nil
                }
                // 检查按键是否是 "S" 键
                if characters == "s" && noModifierKey {
                    closeLargeImage(0)
                    switchDirByDirection(direction: .down, stackDeep: 0)
                    return nil
                }
                // 检查按键是否是 "R" 键
                if (characters == "r" || specialKey == .f5) && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actRefresh()
                        return nil
                    }else{
                        refreshAll()
                        return nil
                    }
                }
                
                // 检查按键是否是 Command+[ 键
                if characters == "[" && isCommandPressed {
                    switchDirByDirection(direction: .back, stackDeep: 0)
                    return nil
                }
                
                // 检查按键是否是 Command+] 键
                if characters == "]" && isCommandPressed {
                    switchDirByDirection(direction: .forward, stackDeep: 0)
                    return nil
                }
                
                // 检查按键是否是 Command+⬆️ 键
                if (specialKey == .upArrow && isOnlyCommandPressed) || (specialKey == .home && noModifierKey) {
                    if !publicVar.isInLargeView{
                        if let scrollView = collectionView.enclosingScrollView {
                            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
                            scrollView.reflectScrolledClipView(scrollView.contentView)
                            DispatchQueue.main.async { [weak self] in
                                self?.setLoadThumbPriority(ifNeedVisable: true)
                            }
                        }
                        return nil
                    }
                }
                
                // 检查按键是否是 Command+⬇️ 键
                if (specialKey == .downArrow && isOnlyCommandPressed) || (specialKey == .end && noModifierKey) {
                    if !publicVar.isInLargeView{
                        if let scrollView = collectionView.enclosingScrollView {
                            let newOrigin = NSPoint(x: 0, y: collectionView.bounds.height - scrollView.contentSize.height)
                            scrollView.contentView.scroll(to: newOrigin)
                            scrollView.reflectScrolledClipView(scrollView.contentView)
                            DispatchQueue.main.async { [weak self] in
                                self?.setLoadThumbPriority(ifNeedVisable: true)
                            }
                        }
                        return nil
                    }
                }
                
                // 检查按键是否是 Alt+⬆️ 键
                if (specialKey == .upArrow && isOnlyAltPressed) || (specialKey == .pageUp && noModifierKey) {
                    if !publicVar.isInLargeView{
                        if let scrollView = collectionView.enclosingScrollView {
                            let currentOrigin = scrollView.contentView.bounds.origin
                            let pageHeight = scrollView.contentSize.height
                            
                            // Calculate the new y position by subtracting the page height from the current y position.
                            let newY = max(currentOrigin.y - pageHeight, 0)
                            let newOrigin = NSPoint(x: currentOrigin.x, y: newY)
                            
                            // Scroll to the new origin
                            scrollView.contentView.scroll(to: newOrigin)
                            scrollView.reflectScrolledClipView(scrollView.contentView)
                            
                            DispatchQueue.main.async { [weak self] in
                                self?.setLoadThumbPriority(ifNeedVisable: true)
                            }
                        }
                        return nil
                    }
                }

                
                // 检查按键是否是 Alt+⬇️ 键
                if (specialKey == .downArrow && isOnlyAltPressed) || (specialKey == .pageDown && noModifierKey) {
                    if !publicVar.isInLargeView{
                        if let scrollView = collectionView.enclosingScrollView {
                            let currentOrigin = scrollView.contentView.bounds.origin
                            let pageHeight = scrollView.contentSize.height
                            
                            // Calculate the new y position by adding the page height to the current y position.
                            let newY = min(currentOrigin.y + pageHeight, collectionView.bounds.height - pageHeight)
                            let newOrigin = NSPoint(x: currentOrigin.x, y: newY)
                            
                            // Scroll to the new origin
                            scrollView.contentView.scroll(to: newOrigin)
                            scrollView.reflectScrolledClipView(scrollView.contentView)
                            
                            DispatchQueue.main.async { [weak self] in
                                self?.setLoadThumbPriority(ifNeedVisable: true)
                            }
                        }
                        return nil
                    }
                }
                
                // 检查按键是否是 Esc 键
                if event.keyCode == 53 {
//                    self.view.window?.close()
                    if publicVar.isInLargeView{
                        closeLargeImage(0)
                        return nil
                    }else{
                        deselectAll()
                        return nil
                    }
                }
                
                // 检查按键是否是 Delete(117) Backspace(51) 键
                if specialKey == .delete || specialKey == .backspace || specialKey == .deleteForward {
                    //如果焦点在OutlineView
                    if publicVar.isOutlineViewFirstResponder{
                        outlineView.actDelete(isByKeyboard: true, isShowPrompt: !isCommandPressed)
                        return nil
                    }
                    //如果焦点在CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        handleDelete(isShowPrompt: !isCommandPressed)
                        return nil
                    }
                }
                
                // 检查按键是否是 空格 键
                if characters == " " && noModifierKey {
                    if publicVar.isInLargeView{
                        closeLargeImage(0)
                        return nil
                    }else{
                        if let indexPath = collectionView.selectionIndexPaths.first {
                            if publicVar.isCollectionViewFirstResponder{
                                openLargeImage(indexPath)
                                return nil
                            }
                        }
                    }
                }
                
//                // 检查按键是否是 1、1(小键盘) 键
//                if event.keyCode == 18 || event.keyCode == 83 {
//                    switchToJustifiedView()
//                }
//                // 检查按键是否是 2、2(小键盘) 键
//                if event.keyCode == 19 || event.keyCode == 84 {
//                    switchToWaterfallView()
//                }
//                // 检查按键是否是 3、3(小键盘) 键
//                if event.keyCode == 20 || event.keyCode == 85 {
//                    switchToGridView()
//                }
//                // 检查按键是否是 4、4(小键盘) 键
//                if event.keyCode == 21 || event.keyCode == 86 {
//                    switchToDetailView()
//                }
                
                // 检查按键是否是 12345 键
                if (["1","2","3","4","5"].contains(characters)) && noModifierKey {
                    if characters == "1" { // 1
                        adjustWindowMaximize()
                        return nil
                    }else if characters == "2"{ // 2
                        adjustWindowSuitable()
                        return nil
                    }else if characters == "5"{ // 5
                        adjustWindowToCenter()
                        return nil
                    }else{
                        if publicVar.isInLargeView {
                            if characters == "3"{ // 3
                                adjustWindowImageActual()
                                return nil
                            }else if characters == "4"{ // 4
                                adjustWindowImageCurrent()
                                return nil
                            }
                        }
                    }
                }
                
                // 检查按键是否是 Alt+12345 键
                if (["1","2","3","4","5"].contains(characters)) && isOnlyAltPressed {
                    if !publicVar.isInLargeView {
                        useCustomProfile(characters)
                        return nil
                    }
                }
                
                // 检查按键是否是 Cmd+Alt+12345 键
                if (["1","2","3","4","5"].contains(characters)) && isCommandPressed && isAltPressed && !isCtrlPressed && !isShiftPressed {
                    if !publicVar.isInLargeView {
                        setCustomProfileTo(characters)
                        return nil
                    }
                }
                
                // 检查按键是否是 "~"
                if event.keyCode == 50 && noModifierKey {
                    togglePortableMode()
                    return nil
                }
                
                // 检查按键是否是 "I"
                if characters == "i" && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actShowExif()
                        return nil
                    }else{
                        if publicVar.isOutlineViewFirstResponder{
                            outlineView.actGetInfo(isByKeyboard: true)
                            return nil
                        }
                        if publicVar.isCollectionViewFirstResponder{
                            handleGetInfo()
                            return nil
                        }
                    }
                }
                
                // 检查按键是否是 "O"
                if characters == "o" && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actOCR()
                        return nil
                    }
                }
                
                // 检查按键是否是 "P"
                if characters == "p" && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actQRCode()
                        return nil
                    }
                }
                
                // 检查按键是否是 "E"
                if characters == "e" && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actRotateR()
                        return nil
                    }
                }
                
                // 检查按键是否是 "Q"
                if characters == "q" && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actRotateL()
                        return nil
                    }
                }
                
                // 检查按键是否是 ➡️⬇️PageDown 键
                if (specialKey == .rightArrow || specialKey == .downArrow || specialKey == .pageDown || specialKey == .next) && noModifierKey {
                    if publicVar.isInLargeView{
                        nextLargeImage()
                        return nil
                    }
                }
                // 检查按键是否是 ⬅️⬆️PageUp 键
                if (specialKey == .leftArrow || specialKey == .upArrow || specialKey == .pageUp || specialKey == .prev) && noModifierKey {
                    if publicVar.isInLargeView{
                        previousLargeImage()
                        return nil
                    }
                }
                
                // 检查按键是否是 Tab 键
                if specialKey == .tab && noModifierKey {
                    if !publicVar.isInLargeView{
                        if publicVar.isOutlineViewFirstResponder{
                            view.window?.makeFirstResponder(collectionView)
                            return nil
                        }else if publicVar.isCollectionViewFirstResponder{
                            view.window?.makeFirstResponder(outlineView)
                            return nil
                        }
                    }
                }

                // 检查按键是否是 "⬅️➡️⬆️⬇️" 键
                if (specialKey == .leftArrow || specialKey == .rightArrow || specialKey == .upArrow || specialKey == .downArrow) && noModifierKey {
                    if !publicVar.isInLargeView{
                        //如果焦点在OutlineView
                        if publicVar.isOutlineViewFirstResponder{
                            if let outlineView = outlineView {
                                let selectedRow=outlineView.selectedRow
                                if specialKey == .upArrow {//⬆️
                                    if selectedRow > 0 {
                                        let previousRow = selectedRow - 1
                                        outlineView.selectRowIndexes(IndexSet(integer: previousRow), byExtendingSelection: false)
                                        outlineView.scrollRowToVisible(previousRow) // 可选：滚动视图以确保选中的项可见
                                    }
                                }
                                if specialKey == .downArrow {//⬇️
                                    if selectedRow != -1 && selectedRow < outlineView.numberOfRows - 1 {
                                        let nextRow = selectedRow + 1
                                        outlineView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
                                        outlineView.scrollRowToVisible(nextRow) // 可选：滚动视图以确保选中的项可见
                                    }
                                }
                                if specialKey == .leftArrow || specialKey == .rightArrow {//⬅️➡️
                                    // 获取行对应的条目
                                    if let item = outlineView.item(atRow: selectedRow) {
                                        if outlineView.isItemExpanded(item) {
                                            outlineView.collapseItem(item)
                                        } else {
                                            outlineView.expandItem(item)
                                        }
                                    }
                                }
                                return nil
                            }
                        }
                        
                        //如果焦点在CollectionView
                        if publicVar.isCollectionViewFirstResponder{
                            if let currentIndexPath = collectionView.selectionIndexPaths.first,
                               let collectionView = collectionView,
                               let currentItem = collectionView.item(at: currentIndexPath),
                               let scrollView = collectionView.enclosingScrollView
                            {
                                // 存储当前滚动位置，因为findClosestItem期间会多次滚动
                                let savedContentOffset = scrollView.contentView.bounds.origin
                                
                                var newIndexPath: IndexPath?
                                newIndexPath = findClosestItem(currentItem: currentItem, direction: specialKey)
                                
                                // 还原滚动位置
                                scrollView.contentView.setBoundsOrigin(savedContentOffset)
                                scrollView.reflectScrolledClipView(scrollView.contentView)
                                
                                if let newIndexPath = newIndexPath {
                                    collectionView.deselectAll(nil)
                                    collectionView.selectItems(at: [newIndexPath], scrollPosition: [])
                                    collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [newIndexPath])
                                    collectionView.scrollToItems(at: [newIndexPath], scrollPosition: .nearestHorizontalEdge)
                                    
                                    setLoadThumbPriority(ifNeedVisable: true)
                                    //log(DispatchTime.now().uptimeNanoseconds)
//                                    if publicVar.timer.intervalSafe(name: "arrowScrollViewDidScrollSetLoadThumbPriority", second: 0.1) {
//                                        setLoadThumbPriority(ifNeedVisable: true)
//                                    }
//                                    arrowScrollDebounceWorkItem?.cancel()
//                                    arrowScrollDebounceWorkItem = DispatchWorkItem {
//                                        DispatchQueue.main.async { [weak self] in
//                                            self?.setLoadThumbPriority(ifNeedVisable: true)
//                                        }
//                                    }
//                                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: arrowScrollDebounceWorkItem!)
                                }

                            }else if let collectionView = collectionView {
                                
                                var indexPaths = collectionView.indexPathsForVisibleItems()

                                let visibleRectRaw = mainScrollView.contentView.visibleRect
                                let scrollPos = visibleRectRaw.origin
                                let scrollWidth = visibleRectRaw.width
                                let scrollHeight = visibleRectRaw.height
                                let visibleRect = NSRect(origin: scrollPos, size: CGSize(width: scrollWidth, height: scrollHeight*1)) //注意这里乘了1
                                indexPaths = indexPaths.filter { indexPath in
                                    let itemFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
                                    return itemFrame.intersects(visibleRect)
                                }
                                let sortedIndexPaths = indexPaths.sorted { $0.item < $1.item }
                                
                                if let newIndexPath = sortedIndexPaths.first{
                                    collectionView.selectItems(at: [newIndexPath], scrollPosition: [])
                                    collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [newIndexPath])
                                    collectionView.scrollToItems(at: [newIndexPath], scrollPosition: .nearestHorizontalEdge)
                                }
                            }
                            return nil
                        }
                    }
                }
                
                // 检查按键是否是 F2、回车、小键盘回车 键
                if specialKey == .f2 || specialKey == .enter || specialKey == .carriageReturn || specialKey == .newline {
                    //如果焦点在OutlineView
                    if publicVar.isOutlineViewFirstResponder{
                        outlineView.actRename(isByKeyboard: true)
                        return nil
                    }
                    
                    //如果焦点在CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        if publicVar.selectedUrls().count == 1 {
                            renameAlert(url: publicVar.selectedUrls()[0])
                            return nil
                        }
                    }
                }
                
                // 检查按键是否是 "F" 键
                if characters == "f" && noModifierKey {
                    if !publicVar.isInLargeView{
                        toggleSidebar()
                        return nil
                    }
                }
                
                // 检查按键是否是 "T" 键
                if characters == "t" && noModifierKey {
                    toggleOnTop()
                    return nil
                }
                
                // 检查按键是否是 -、-(小键盘) 键
                if characters == "-" && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.zoom(direction: -1)
                        return nil
                    }else{
                        adjustThumbSizeByDirection(direction: -1)
                        return nil
                    }
                }
                
                // 检查按键是否是 +(=)、+(小键盘) 键
                if (characters == "=" || characters == "+") && noModifierKey {
                    if publicVar.isInLargeView {
                        largeImageView.zoom(direction: +1)
                        return nil
                    }else{
                        adjustThumbSizeByDirection(direction: +1)
                        return nil
                    }
                }
                
                // 检查按键是否是 0、0(小键盘) 键
                if characters == "0" && noModifierKey {
                    if publicVar.isInLargeView {
                        changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: true)
                        return nil
                    }else{
                        adjustThumbSizeByDirection(direction: 0)
                        return nil
                    }
                }
                
                // 检查按键是否是 "N" 键
                if characters == "n" && noModifierKey {
                    //如果焦点在CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        handleCopyToDownload()
                        return nil
                    }
                }
                
                // 检查按键是否是 "M" 键
                if characters == "m" && noModifierKey {
                    //如果焦点在CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        handleMoveToDownload()
                        return nil
                    }
                }

            }
            
            // 处理弹出重命名对话框、OCR状态的复制粘贴操作
            if (!publicVar.isKeyEventEnabled || largeImageView.isInOcrState) && event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "c":
                    if let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: #selector(NSText.copy(_:))) {
                        responder.perform(#selector(NSText.copy(_:)), with: nil)
                        return nil // 事件已处理，返回 nil 以防止传递给下一个响应者
                    } else {
                        // 处理自定义 Command+C 操作
                        log("Custom Command+C action")
                        return nil // 事件已处理，返回 nil 以防止传递给下一个响应者
                    }
                case "v":
                    if let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: #selector(NSText.paste(_:))) {
                        responder.perform(#selector(NSText.paste(_:)), with: nil)
                        return nil // 事件已处理，返回 nil 以防止传递给下一个响应者
                    } else {
                        // 处理自定义 Command+V 操作
                        log("Custom Command+V action")
                        return nil // 事件已处理，返回 nil 以防止传递给下一个响应者
                    }
                case "x":
                    if let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: #selector(NSText.cut(_:))) {
                        responder.perform(#selector(NSText.cut(_:)), with: nil)
                        return nil // 事件已处理，返回 nil 以防止传递给下一个响应者
                    } else {
                        // 处理自定义 Command+X 操作
                        log("Custom Command+X action")
                        return nil // 事件已处理，返回 nil 以防止传递给下一个响应者
                    }
                default:
                    break
                }
            }
            
            return event
            //return nil
        }
        
        //鼠标右键事件
        eventMonitorRightMouseUp = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            guard let self=self else{return event}
            //if getMainViewController() != self {return event}
            // 检查事件的窗口是否是当前窗口
            if event.window != self.view.window {
                return event
            }
            if publicVar.isInLargeView {
                self.largeImageView.rightMouseUp(with: event)
            }else{
                self.drawingView?._rightMouseUp(with: event)
            }
            //return event  // 返回 nil 则不传递事件
            return nil
        }
        eventMonitorRightMouseDown = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self=self else{return event}
            //if getMainViewController() != self {return event}
            // 检查事件的窗口是否是当前窗口
            if event.window != self.view.window {
                return event
            }
            if publicVar.isInLargeView {
                self.largeImageView.rightMouseDown(with: event)
            }else{
                self.drawingView?._rightMouseDown(with: event)
            }
            //return event  // 返回 nil 则不传递事件
            return nil
        }
        eventMonitorRightMouseDragged = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDragged) { [weak self] event in
            guard let self=self else{return event}
            //if getMainViewController() != self {return event}
            // 检查事件的窗口是否是当前窗口
            if event.window != self.view.window {
                return event
            }
            if publicVar.isInLargeView {
                self.largeImageView.rightMouseDragged(with: event)
            }else{
                self.drawingView?._rightMouseDragged(with: event)
            }
            //return event  // 返回 nil 则不传递事件
            return nil
        }
        
        //=========结束事件监听配置==========
        
        //startListeningForFileSystemEvents(in: "/Users")
        //startWatchingDirectory(atPath: "/Users")
        
        log("结束viewDidLoad")

    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    deinit {
        // 在这里执行清理工作
        log("ViewController is being deinitialized")
        willTerminate=true
        
        if let eventMonitorKeyDown = eventMonitorKeyDown {
            NSEvent.removeMonitor(eventMonitorKeyDown)
        }
        if let eventMonitorRightMouseDown = eventMonitorRightMouseDown {
            NSEvent.removeMonitor(eventMonitorRightMouseDown)
        }
        if let eventMonitorRightMouseUp = eventMonitorRightMouseUp {
            NSEvent.removeMonitor(eventMonitorRightMouseUp)
        }
        if let eventMonitorRightMouseDragged = eventMonitorRightMouseDragged {
            NSEvent.removeMonitor(eventMonitorRightMouseDragged)
        }
        if let eventMonitorScrollWheel = eventMonitorScrollWheel {
            NSEvent.removeMonitor(eventMonitorScrollWheel)
        }
        
        // 移除 KVO 观察者
        NSApp.removeObserver(self, forKeyPath: "effectiveAppearance")
        
        // 移除通知中心的观察者
        if let scrollView = collectionView.enclosingScrollView {
            NotificationCenter.default.removeObserver(self, name: NSScrollView.didLiveScrollNotification, object: scrollView)
            NotificationCenter.default.removeObserver(self, name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }

    }
    
    func afterFinishLoad(_ openFolder: String? = nil){
        log("开始afterFinishLoad")
        if globalVar.isLaunchFromFile == false { //从文件夹启动
            let defaults = UserDefaults.standard
            var lastFolder = defaults.string(forKey: "lastFolder")
            if lastFolder == nil {
                lastFolder = rootFolder
            }
            if openFolder != nil {
                lastFolder = openFolder
            }
            fileDB.lock()
            fileDB.curFolder=lastFolder!
            fileDB.unlock()
            refreshAll()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                setWindowTitle()
            }
        }else{//从文件启动
            globalVar.isLaunchFromFile = false //重置
        }
        
        //启动后台任务线程
        startBackgroundTaskThread()
    }
    
    func handlePrint(){
        if publicVar.isInLargeView {
            printContent(largeImageView.imageView)
        } else {
            // 临时隐藏滚动条
            let originalVerticalScroller = mainScrollView.verticalScroller
            let originalHorizontalScroller = mainScrollView.horizontalScroller
            mainScrollView.verticalScroller=nil
            mainScrollView.horizontalScroller=nil
            
            printContent(mainScrollView)
            
            // 恢复原始滚动条状态
            mainScrollView.verticalScroller = originalVerticalScroller
            mainScrollView.horizontalScroller = originalHorizontalScroller
        }
    }
    
    func changeSortType(sortType: SortType, isSortFolderFirst: Bool, doNotRefresh: Bool = false){
        fileDB.lock()
        publicVar.profile.sortType = sortType
        publicVar.profile.isSortFolderFirst = isSortFolderFirst
//        UserDefaults.standard.setEnum(publicVar.profile.sortType, forKey: "sortType")
//        UserDefaults.standard.set(publicVar.profile.isSortFolderFirst, forKey: "isSortFolderFirst")
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_current")
        globalVar.randomSeed = Int.random(in: 0...Int.max)
        for dirModel in fileDB.db {
            dirModel.1.changeSortType(publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst)
        }
        fileDB.unlock()
        if !doNotRefresh {
            refreshCollectionView([], dryRun: true)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            setLoadThumbPriority(ifNeedVisable: true)
        }
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
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_current")
    }
    
    func toggleOnTop(){
        if let windowController = view.window?.windowController as? WindowController {
            windowController.toggleWindowOnTop()
        }
    }
    
    func adjustWindowMaximize(){
        if let window = view.window {
            if !window.isZoomed {
                window.zoom(nil)
                if publicVar.isInLargeView {
                    changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
                }
            }
        }
    }
    
    func adjustWindowSuitable(){
        if globalVar.portableMode {
            adjustWindowPortable(firstShowThumb: false, animate: true, isToCenter: true)
        }else{
            adjustWindowToRatio(animate: true, isToCenter: true)
        }
    }
    
    func adjustWindowImageActual(refSize:NSSize? = nil, firstShowThumb: Bool = false, animate: Bool = true){
        //let zoomSize=largeImageView.customZoomSize()
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        var tmpSize=largeImageView.file.originalSize ?? NSSize(width: 800, height: 600)
        if refSize != nil {tmpSize=refSize!}
        tmpSize = NSSize(width: tmpSize.width/scale, height: tmpSize.height/scale)
        adjustWindowTo(tmpSize, firstShowThumb: firstShowThumb, animate: animate, justAdjustWindowFrame: false, isToCenter: false)
    }
    
    func adjustWindowImageCurrent(){
        let zoomSize=largeImageView.imageView.frame.size
        adjustWindowTo(zoomSize, firstShowThumb: false, animate: true, isToCenter: false)
    }
    
//    func adjustWindowImageMax() {
//        adjustWindowToImageRatio(refSize: largeImageView.imageView.image?.size, firstShowThumb: false, animate: true, refRatio: (1,1))
//    }

    func adjustWindowPortable(refSize:NSSize? = nil, firstShowThumb: Bool, animate: Bool, justAdjustWindowFrame: Bool = false, isToCenter: Bool = false) {
        if publicVar.isInLargeView {
            let scale = NSScreen.main?.backingScaleFactor ?? 1
            var tmpSize = largeImageView.file.originalSize
            if refSize != nil {tmpSize=refSize}
            if tmpSize == nil {tmpSize=NSSize(width: 400, height: 400)}
            tmpSize = NSSize(width: tmpSize!.width/scale, height: tmpSize!.height/scale)
            
            if publicVar.isLargeImageFitWindow{
                adjustWindowToImageRatio(refSize: tmpSize, firstShowThumb: firstShowThumb, animate: animate, justAdjustWindowFrame: justAdjustWindowFrame, isToCenter: isToCenter)
            }else{
                adjustWindowTo(tmpSize!, firstShowThumb: firstShowThumb, animate: false, justAdjustWindowFrame: justAdjustWindowFrame, isToCenter: isToCenter)
            }
        }else{
            adjustWindowToRatio(animate: animate, isToCenter: isToCenter)
        }
    }
    
    func togglePortableMode(){
        globalVar.portableMode.toggle()
        UserDefaults.standard.set(globalVar.portableMode, forKey: "portableMode")
        adjustWindowPortable(firstShowThumb: false, animate: true)
        if globalVar.portableMode {
            coreAreaView.showInfo(NSLocalizedString("Portable Mode: On", comment: "便携模式：开启"))
        }else{
            coreAreaView.showInfo(NSLocalizedString("Portable Mode: Off", comment: "便携模式：关闭"))
        }
    }
    
    func toggleRecursiveMode(){
        publicVar.isRecursiveMode.toggle()
        refreshCollectionView([])
    }
    
    func toggleIsShowHiddenFile(){
        publicVar.isShowHiddenFile.toggle()
        UserDefaults.standard.set(publicVar.isShowHiddenFile, forKey: "isShowHiddenFile")
        refreshAll([])
    }
    
    func toggleIsShowAllTypeFile(){
        publicVar.isShowAllTypeFile.toggle()
        UserDefaults.standard.set(publicVar.isShowAllTypeFile, forKey: "isShowAllTypeFile")
        refreshAll([])
    }
    
    func toggleIsShowImageFile(){
        publicVar.isShowImageFile.toggle()
        UserDefaults.standard.set(publicVar.isShowImageFile, forKey: "isShowImageFile")
        publicVar.setFileExtensions()
        refreshCollectionView([])
    }
    
    func toggleIsShowRawFile(){
        publicVar.isShowRawFile.toggle()
        UserDefaults.standard.set(publicVar.isShowRawFile, forKey: "isShowRawFile")
        publicVar.setFileExtensions()
        refreshCollectionView([])
    }
    
    func toggleIsShowVideoFile(){
        publicVar.isShowVideoFile.toggle()
        UserDefaults.standard.set(publicVar.isShowVideoFile, forKey: "isShowVideoFile")
        publicVar.setFileExtensions()
        refreshCollectionView([])
    }
    
    func adjustWindowToCenter(animate: Bool = true) {
        if let window = view.window,
           let screen = window.screen {
            
            let visibleFrame = screen.visibleFrame
            
            // 获取当前窗口的尺寸
            let windowFrame = window.frame
            let newWindowSize = windowFrame.size
            
            // 计算新的窗口位置，使其居中
            let newX = visibleFrame.origin.x + round((visibleFrame.width - newWindowSize.width) / 2)
            let newY = visibleFrame.origin.y + round((visibleFrame.height - newWindowSize.height) / 2)
            let newOrigin = NSPoint(x: newX, y: newY)
            
            // 设置窗口的新框架并居中显示
            let newFrame = NSRect(origin: newOrigin, size: newWindowSize)
            window.setFrame(newFrame, display: true, animate: animate)
        }
    }
    
    // ------------以下为调整窗口 间接接口-----------
    
    func adjustWindowToRatio(animate: Bool, refRatio: (Double,Double)? = nil, isToCenter: Bool) {
        if let window = view.window {
            // 获取屏幕的可见区域
            if let screen = window.screen {
                let visibleFrame = screen.visibleFrame
                let aspectRatio = screen.frame.width / screen.frame.height
                
                // 确定最大比例
                var ratioWidth: Double
                var ratioHeight: Double
                
                if aspectRatio < 16.0/9.0 { //mbp屏幕或者竖屏
                    ratioWidth = globalVar.portableListWidthRatioHH
                    ratioHeight = globalVar.portableListHeightRatioHH
                }else{
                    ratioWidth = globalVar.portableListWidthRatio
                    ratioHeight = globalVar.portableListHeightRatio
                }
                
                if refRatio != nil {
                    ratioWidth = refRatio!.0
                    ratioHeight = refRatio!.1
                }
                
                // 计算目标窗口尺寸（可见区域的%）
                let targetWidth = visibleFrame.width * ratioWidth
                let targetHeight = visibleFrame.height * ratioHeight
                
                // 计算窗口的边框尺寸（标题栏高度）
                let windowFrame = window.frame
                let contentRect = window.contentRect(forFrameRect: windowFrame)
                let titleBarHeight = windowFrame.height - contentRect.height
                
                // 计算新的内容区域尺寸
                let newContentWidth = targetWidth
                let newContentHeight = targetHeight - titleBarHeight
                
                // 确保新的内容区域尺寸不小于最小窗口尺寸
                let minWindowSize = window.minSize
                let newContentSize = NSSize(width: max(newContentWidth, minWindowSize.width),
                                            height: max(newContentHeight, minWindowSize.height))
                
                // 计算新的窗口尺寸，包括标题栏
                let newWindowSize = NSSize(width: newContentSize.width, height: newContentSize.height + titleBarHeight)
                
                let newOrigin: NSPoint
                
                if isToCenter {
                    // 计算新的窗口位置，使其居中
                    let newX = visibleFrame.origin.x + round((visibleFrame.width - newWindowSize.width) / 2)
                    let newY = visibleFrame.origin.y + round((visibleFrame.height - newWindowSize.height) / 2)
                    newOrigin = NSPoint(x: newX, y: newY)
                } else {
                    // 保持窗口的中心位置不变
                    let oldCenter = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
                    let newX = oldCenter.x - round(newWindowSize.width / 2)
                    let newY = oldCenter.y - round(newWindowSize.height / 2)
                    newOrigin = NSPoint(x: newX, y: newY)
                }
                
                // 设置窗口的新框架
                let newFrame = NSRect(origin: newOrigin, size: newWindowSize)
                window.setFrame(newFrame, display: true, animate: animate)
                
                // 重置图片大小位置
                if publicVar.isInLargeView {
                    changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
                }
            }
        }
    }
    
    func adjustWindowToImageRatio(refSize: NSSize?, firstShowThumb: Bool, animate: Bool, refRatio: (Double, Double)? = nil, justAdjustWindowFrame: Bool = false, isToCenter: Bool) {
        if let window = view.window,
           let screen = window.screen {
            
            let visibleFrame = screen.visibleFrame
            
            // 计算窗口的边框尺寸
            let windowFrame = window.frame
            let contentRect = window.contentRect(forFrameRect: windowFrame)
            let titleBarHeight = windowFrame.height - contentRect.height
            
            // 确定最大比例
            var ratioWidth = globalVar.portableImageWidthRatio
            var ratioHeight = globalVar.portableImageHeightRatio
            if let refRatio = refRatio {
                ratioWidth = refRatio.0
                ratioHeight = refRatio.1
            }
            
            // 计算可见区域的宽高，减去标题栏的高度
            let maxWidth = (visibleFrame.width) * ratioWidth
            let maxHeight = (visibleFrame.height) * ratioHeight - titleBarHeight
            
            // 获取图像的宽高比
            let imageWidth = refSize?.width ?? 1
            let imageHeight = refSize?.height ?? 1
            let imageAspectRatio = imageWidth / imageHeight
            
            // 计算屏幕的宽高比
            let screenAspectRatio = maxWidth / maxHeight
            
            // 计算缩放比例
            var scaleFactor: CGFloat
            if imageAspectRatio > screenAspectRatio {
                // 图像宽高比更大，以宽度为基准缩放
                scaleFactor = maxWidth / imageWidth
            } else {
                // 图像宽高比更小，以高度为基准缩放
                scaleFactor = maxHeight / imageHeight
            }
            
            // 计算新的图像尺寸
            var newWidth = imageWidth * scaleFactor
            var newHeight = imageHeight * scaleFactor
            
            // 如果新的宽度或高度超过了屏幕的可见区域，进行调整
            if newWidth > maxWidth {
                scaleFactor = maxWidth / imageWidth
                newWidth = maxWidth
                newHeight = imageHeight * scaleFactor
            }
            
            if newHeight > maxHeight {
                scaleFactor = maxHeight / imageHeight
                newHeight = maxHeight
                newWidth = imageWidth * scaleFactor
            }
            
            let newContentSize = NSSize(width: newWidth, height: newHeight)
            
            largeImageView.imageView.frame.size = newContentSize
            
            // 调整窗口的内容尺寸
            window.setContentSize(newContentSize)
            if !justAdjustWindowFrame{
                changeLargeImage(firstShowThumb: firstShowThumb, resetSize: true, triggeredByLongPress: true)
            }
            
            // 计算新的窗口尺寸，包括标题栏
            let newWindowSize = NSSize(width: newContentSize.width, height: newContentSize.height + titleBarHeight)
            
            let newOrigin: NSPoint
            
            if isToCenter {
                // 计算新的窗口位置，使其居中
                let newX = visibleFrame.origin.x + round((visibleFrame.width - newWindowSize.width) / 2)
                let newY = visibleFrame.origin.y + round((visibleFrame.height - newWindowSize.height) / 2)
                newOrigin = NSPoint(x: newX, y: newY)
            } else {
                // 保持窗口的中心位置不变
                let oldCenter = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
                let newX = oldCenter.x - round(newWindowSize.width / 2)
                let newY = oldCenter.y - round(newWindowSize.height / 2)
                newOrigin = NSPoint(x: newX, y: newY)
            }
            
            // 设置窗口的新框架
            let newFrame = NSRect(origin: newOrigin, size: newWindowSize)
            window.setFrame(newFrame, display: true, animate: animate)
        }
    }
    
    func adjustWindowTo(_ zoomSize: CGSize, firstShowThumb: Bool, animate: Bool, justAdjustWindowFrame: Bool = false, isToCenter: Bool) {
        if let window = view.window,
           let screen = window.screen {
            
            let visibleFrame = screen.visibleFrame
            
            // 计算窗口的边框尺寸
            let windowFrame = window.frame
            let contentRect = window.contentRect(forFrameRect: windowFrame)
            let titleBarHeight = windowFrame.height - contentRect.height
            
            // 计算可见区域的宽高，减去标题栏的高度
            let maxWidth = visibleFrame.width
            let maxHeight = visibleFrame.height - titleBarHeight
            
            // 计算图像的宽高比
            let imageAspectRatio = zoomSize.width / zoomSize.height
            
            // 计算屏幕的宽高比
            let screenAspectRatio = maxWidth / maxHeight
            
            // 计算缩放比例
            var scaleFactor: CGFloat
            if imageAspectRatio > screenAspectRatio {
                // 图像宽高比更大，以宽度为基准缩放
                scaleFactor = maxWidth / zoomSize.width
            } else {
                // 图像宽高比更小，以高度为基准缩放
                scaleFactor = maxHeight / zoomSize.height
            }
            
            // 计算新的图像尺寸
            let newWidth = zoomSize.width * scaleFactor
            let newHeight = zoomSize.height * scaleFactor
            var newContentSize = NSSize(width: newWidth, height: newHeight)
            if newWidth > zoomSize.width {
                newContentSize = zoomSize
            }
            largeImageView.imageView.frame.size = newContentSize
            
            // 调整窗口的内容尺寸
            window.setContentSize(newContentSize)
            if !justAdjustWindowFrame{
                changeLargeImage(firstShowThumb: firstShowThumb, resetSize: true, triggeredByLongPress: false)
            }
            
            // 计算新的窗口尺寸，包括标题栏
            let newWindowSize = NSSize(width: newContentSize.width, height: newContentSize.height + titleBarHeight)
            
            let newOrigin: NSPoint
            
            if isToCenter {
                // 计算新的窗口位置，使其居中
                let newX = visibleFrame.origin.x + round((visibleFrame.width - newWindowSize.width) / 2)
                let newY = visibleFrame.origin.y + round((visibleFrame.height - newWindowSize.height) / 2)
                newOrigin = NSPoint(x: newX, y: newY)
            } else {
                // 保持窗口的中心位置不变
                let oldCenter = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
                let newX = oldCenter.x - round(newWindowSize.width / 2)
                let newY = oldCenter.y - round(newWindowSize.height / 2)
                newOrigin = NSPoint(x: newX, y: newY)
            }
            
            // 设置窗口的新框架
            let newFrame = NSRect(origin: newOrigin, size: newWindowSize)
            window.setFrame(newFrame, display: true, animate: animate)
        }
    }
    
    func switchToJustifiedView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.justified, forKey: "layoutType")
        publicVar.profile.layoutType = .justified
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView([], dryRun: true)
        }
    }
    
    func switchToGridView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.grid, forKey: "layoutType")
        publicVar.profile.layoutType = .grid
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView([], dryRun: true)
        }
    }
    
    func switchToWaterfallView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.waterfall, forKey: "layoutType")
        publicVar.profile.layoutType = .waterfall
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView([], dryRun: true)
        }
    }
    
    func switchToDetailView(doNotRefresh: Bool = false){
        return
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.detail, forKey: "layoutType")
        publicVar.profile.layoutType = .detail
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView([], dryRun: true)
        }
    }
    
    func changeThumbSize(thumbSize: Int, doNotRefresh: Bool = false){
        publicVar.profile.thumbSize = thumbSize
        //UserDefaults.standard.set(thumbSize, forKey: "thumbSize")
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_current")
        changeWaterfallLayoutNumberOfColumns()
        if !doNotRefresh {
            refreshCollectionView([], dryRun: true)
        }
    }
    
    func switchToActualSize(){
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "isLargeImageFitWindow")
        publicVar.isLargeImageFitWindow=false
        if publicVar.isInLargeView{
            changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
        }
    }
    
    func switchToFitToWindow(){
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "isLargeImageFitWindow")
        publicVar.isLargeImageFitWindow=true
        if publicVar.isInLargeView{
            changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: false)
        }
    }
    
    func centerPoint(of item: NSCollectionViewItem) -> CGPoint {
        let frame = item.view.frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    
    func centerPoint(of layoutAttributes: NSCollectionViewLayoutAttributes) -> CGPoint {
        let frame = layoutAttributes.frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    
    func nearbyIndexPaths(around indexPaths: Set<IndexPath>, range: (Int,Int), needValid: Bool) -> Set<IndexPath> {
        guard let dataSource = collectionView.dataSource else { return [] }
        
        var expandedIndexPaths = Set<IndexPath>()
        
        for indexPath in indexPaths {
            let section = indexPath.section
            let item = indexPath.item
            
            for i in max(0, item + range.0)...(item + range.1) {
                if !needValid || i < dataSource.collectionView(collectionView, numberOfItemsInSection: section) {
                    expandedIndexPaths.insert(IndexPath(item: i, section: section))
                }
            }
        }
        
        return expandedIndexPaths
    }
    
    func findClosestItem(currentItem: NSCollectionViewItem, direction: NSEvent.SpecialKey) -> IndexPath? {
        //let indexPaths = collectionView.indexPathsForVisibleItems()
        let indexPaths = nearbyIndexPaths(around: collectionView.indexPathsForVisibleItems(), range: (-20,20), needValid: true)
        //log(indexPaths.map{$0.item})
        guard let currentIndexPath = collectionView.selectionIndexPaths.first else { return nil }
        guard let currentItem = collectionView.item(at: currentIndexPath) else { return nil }
        
        let currentCenter = centerPoint(of: currentItem)
        var closestIndexPath: IndexPath?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        
        for indexPath in indexPaths {
//            if indexPath != currentIndexPath {continue}
//            guard let item = collectionView.item(at: indexPath) else { continue }
//            let itemCenter = centerPoint(of: item)
            
//            if indexPath != currentIndexPath {continue}
//            guard let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
//            let itemCenter = centerPoint(of: layoutAttributes)
            
            if indexPath == currentIndexPath {continue}
            var item = collectionView.item(at: indexPath)
            if item == nil {
                collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                item = collectionView.item(at: indexPath)
                guard item != nil else {continue}
            }
            
            let itemCenter = centerPoint(of: item!)
            
            var valid = false
            var distance = CGFloat.greatestFiniteMagnitude
            
            switch direction {
            case .leftArrow: // Left arrow key
                if itemCenter.x < currentCenter.x && (itemCenter.y == currentCenter.y || publicVar.profile.layoutType == .waterfall) {
                    distance = hypot(currentCenter.x - itemCenter.x, itemCenter.y - currentCenter.y)
                    valid = true
                }
            case .rightArrow: // Right arrow key
                if itemCenter.x > currentCenter.x && (itemCenter.y == currentCenter.y || publicVar.profile.layoutType == .waterfall) {
                    distance = hypot(currentCenter.x - itemCenter.x, itemCenter.y - currentCenter.y)
                    valid = true
                }
            case .downArrow: // Up arrow key (Adjusted to move up)
                if itemCenter.y > currentCenter.y && (itemCenter.x == currentCenter.x || publicVar.profile.layoutType != .waterfall) {
                    distance = hypot(currentCenter.x - itemCenter.x, itemCenter.y - currentCenter.y)
                    valid = true
                }
            case .upArrow: // Down arrow key (Adjusted to move down)
                if itemCenter.y < currentCenter.y && (itemCenter.x == currentCenter.x || publicVar.profile.layoutType != .waterfall) {
                    distance = hypot(currentCenter.x - itemCenter.x, currentCenter.y - itemCenter.y)
                    valid = true
                }
            default:
                break
            }
            
            if valid && distance < closestDistance {
                closestDistance = distance
                closestIndexPath = indexPath
            }
        }
        
        return closestIndexPath
    }
    
    func handleDelete(fileUrls: [URL] = [], isShowPrompt: Bool = true) -> Bool {
        var urls = fileUrls
        if urls.count == 0 {
            urls = publicVar.selectedUrls()
        }
        guard urls.count != 0 else {return false}
        
        let ifHasPermission = requestAppleEventsPermission()
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete", comment: "删除")
        if VolumeManager.shared.isExternalVolume(urls.first!) {
            alert.informativeText = NSLocalizedString("ask-to-delete-external", comment: "此目录不支持移动到废纸篓。将立即删除这些项目，此操作无法撤销。")
        }else{
            if ifHasPermission{
                alert.informativeText = NSLocalizedString("ask-to-delete", comment: "你确定要将这些文件移动到废纸篓吗？")
            }else{
                alert.informativeText = NSLocalizedString("ask-to-delete-nopermission", comment: "你确定要将这些文件移动到废纸篓吗？(无权限)")
            }
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "删除"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        alert.icon = NSImage(named: NSImage.cautionName) // 设置系统警告图标

        var response: NSApplication.ModalResponse = .alertFirstButtonReturn
        if isShowPrompt || !ifHasPermission || VolumeManager.shared.isExternalVolume(urls.first!) {
            publicVar.isKeyEventEnabled=false
            response = alert.runModal()
            publicVar.isKeyEventEnabled=true
        }

        if response == .alertFirstButtonReturn {
            // 用户确认删除
            let fileManager = FileManager.default
            var urlsToDelete = [URL]()
            
            for url in urls {
                if fileManager.fileExists(atPath: url.path) {
                    urlsToDelete.append(url)
                } else {
                    log("文件不存在: \(url.path)")
                }
            }
            
            if !urlsToDelete.isEmpty {
                var appleScriptURLs = ""
                for url in urlsToDelete {
                    appleScriptURLs += "\"\(url.path)\" as POSIX file, "
                }
                
                // Remove the trailing comma and space
                if appleScriptURLs.hasSuffix(", ") {
                    appleScriptURLs = String(appleScriptURLs.dropLast(2))
                }
                
                let script = """
                        tell application "Finder"
                            move { \(appleScriptURLs) } to trash
                        end tell
                        """
                
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: script) {
                    // 文件更改计数
                    publicVar.fileChangedCount += 1
                    
                    scriptObject.executeAndReturnError(&error)
                    if let error = error, let errorCode = error[NSAppleScript.errorNumber] as? Int, errorCode == -1743 {
                        // AppleScript 无权限，回退到 NSWorkspace.shared.recycle
                        for url in urlsToDelete {
                            NSWorkspace.shared.recycle([url], completionHandler: { (newURLs, error) in
                                if let error = error {
                                    log("删除失败: \(url.path), 错误: \(error)")
                                } else {
                                    log("文件已移动到废纸篓: \(url.path)")
                                }
                            })
                        }
                    } else if let error = error {
                        log("删除失败: \(error)")
                    } else {
                        log("文件已移动到废纸篓")
                    }
                }
            } else {
                log("要删除的文件不存在")
            }
            return true
        } else {
            // 用户取消操作
            log("删除操作已取消")
            return false
        }
    }
    
    struct StatisticInfo {
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
    
    func handleNewFolderWithSelection() {
        var urls = publicVar.selectedUrls()
        if urls.isEmpty {return}
        
        let (ifSuccess,newFolderURL) = handleNewFolder()
        
        if ifSuccess {
            // 备份剪贴板内容
            let backupItems = backupPasteboard()
            
            handleCopy()
            handleMove(targetURL: newFolderURL)
            
            // 还原剪贴板内容
            restorePasteboard(items: backupItems)
        }
        
    }
    
    func handleGetInfo(_ providedUrls: [URL] = []) {
        var urls = providedUrls
        if providedUrls.isEmpty {
            urls = publicVar.selectedUrls()
        }
        if urls.isEmpty {return}
        
        var result = StatisticInfo()
        
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    result.folderCount += 1
                    getFolderStatistic(url, result: &result)
                }else{
                    result.fileCount += 1
                    if globalVar.HandledImageExtensions.contains(url.pathExtension.lowercased()) {
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
    
    func getFolderStatistic(_ folderURL: URL, result: inout StatisticInfo) {
        let properties: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .fileSizeKey]
        let options:FileManager.DirectoryEnumerationOptions = [] // [.skipsHiddenFiles]
        
        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: properties, options: options, errorHandler: { (url, error) -> Bool in
            print("Error enumerating \(url): \(error.localizedDescription)")
            return true
        })

        //var result = StatisticInfo()
        let scanInterval: TimeInterval = 4.0
        var startDate = Date()
        
        while let url = enumerator?.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            
            if !isDirectory {
                result.fileCount += 1
                if globalVar.HandledImageExtensions.contains(url.pathExtension.lowercased()) {
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
    
//    // 备份剪贴板内容的函数
//    func backupPasteboard() -> [NSPasteboard.PasteboardType: Any] {
//        let pasteboard = NSPasteboard.general
//        var backupItems = [NSPasteboard.PasteboardType: Any]()
//        
//        for type in pasteboard.types ?? [] {
//            if let item = pasteboard.data(forType: type) {
//                backupItems[type] = item
//            }
//        }
//        
//        return backupItems
//    }
//
//    // 还原剪贴板内容的函数
//    func restorePasteboard(items: [NSPasteboard.PasteboardType: Any]) {
//        let pasteboard = NSPasteboard.general
//        pasteboard.clearContents()
//        
//        for (type, item) in items {
//            if let data = item as? Data {
//                pasteboard.setData(data, forType: type)
//            }
//        }
//    }
    
    // 备份剪贴板内容的函数
    func backupPasteboard() -> [[String: Data]] {
        let pasteboard = NSPasteboard.general
        var backupItems = [[String: Data]]()
        
        for item in pasteboard.pasteboardItems ?? [] {
            var backupItem = [String: Data]()
            for type in item.types {
                if let data = item.data(forType: type) {
                    backupItem[type.rawValue] = data
                }
            }
            backupItems.append(backupItem)
        }
        
        return backupItems
    }

    // 还原剪贴板内容的函数
    func restorePasteboard(items: [[String: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        for itemData in items {
            let newItem = NSPasteboardItem()
            for (type, data) in itemData {
                newItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: type))
            }
            pasteboard.writeObjects([newItem])
        }
    }
    
    func handleCopy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // 清除剪贴板现有内容
        pasteboard.writeObjects(publicVar.selectedUrls() as [NSPasteboardWriting]) // 将文件URL添加到剪贴板
    }
    
    func handleCopyToDownload() {
        // 备份剪贴板内容
        let backupItems = backupPasteboard()
        
        handleCopy()
        handlePaste(targetURL: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        
        // 还原剪贴板内容
        restorePasteboard(items: backupItems)
    }
    
    func handlePaste(targetURL: URL? = nil) {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems else { return }
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        var destinationURL: URL? = nil
        if let targetURL = targetURL {
            destinationURL = targetURL
        } else {
            destinationURL = URL(string: curFolder)
        }
        guard let destinationURL = destinationURL else { return }
        
        // 检查待复制的文件/文件夹列表
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            
            // 检查是否包含目标目录自身或者它的父目录
            if fileURL == destinationURL || destinationURL.path.hasPrefix(fileURL.path) {
                showAlert(message: NSLocalizedString("cannot-copy-to-self", comment: "不能将文件/文件夹复制到自身或其子目录中。"))
                return
            }
        }
        
        //播放提示音
        triggerFinderSound()
        
        var shouldReplaceAll = false
        var shouldSkipAll = false
        
        publicVar.isKeyEventEnabled = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            var destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)
            
            // 如果是在同一目录复制粘贴，则修改名称
            if fileURL.deletingLastPathComponent() == destinationURL {
                destURL = getUniqueDestinationURL(for: destURL)
            }
            
            if FileManager.default.fileExists(atPath: destURL.path) {
                if shouldReplaceAll {
                    do {
                        publicVar.fileChangedCount += 1
                        try FileManager.default.removeItem(at: destURL)
                        try FileManager.default.copyItem(at: fileURL, to: destURL)
                    } catch {
                        log("粘贴失败 \(fileURL): \(error)")
                    }
                } else if shouldSkipAll {
                    continue
                } else {
                    let userChoice = showReplaceDialog(for: destURL, isSingle: items.count == 1, isMove: false)
                    switch userChoice {
                    case .replace:
                        do {
                            publicVar.fileChangedCount += 1
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                        } catch {
                            log("粘贴失败 \(fileURL): \(error)")
                        }
                    case .replaceAll:
                        shouldReplaceAll = true
                        do {
                            publicVar.fileChangedCount += 1
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                        } catch {
                            log("粘贴失败 \(fileURL): \(error)")
                        }
                    case .skip:
                        continue
                    case .skipAll:
                        shouldSkipAll = true
                        continue
                    case .cancel:
                        publicVar.isKeyEventEnabled = true
                        return
                    }
                }
            } else {
                do {
                    publicVar.fileChangedCount += 1
                    try FileManager.default.copyItem(at: fileURL, to: destURL)
                } catch {
                    log("粘贴失败 \(fileURL): \(error)")
                }
            }
        }
        publicVar.isKeyEventEnabled = true
    }
    
    func handleMoveToDownload() {
        // 备份剪贴板内容
        let backupItems = backupPasteboard()
        
        handleCopy()
        handleMove(targetURL: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        
        // 还原剪贴板内容
        restorePasteboard(items: backupItems)
    }

    func handleMove(targetURL: URL? = nil, pasteboard: NSPasteboard = NSPasteboard.general) {
        guard let items = pasteboard.pasteboardItems else { return }
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        var destinationURL: URL? = nil
        if let targetURL = targetURL {
            destinationURL = targetURL
        } else {
            destinationURL = URL(string: curFolder)
        }
        guard let destinationURL = destinationURL else { return }
        
        // 检查待移动的文件/文件夹列表
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            
            // 检查是否包含目标目录自身或者它的父目录
            if fileURL == destinationURL || destinationURL.path.hasPrefix(fileURL.path) {
                showAlert(message: NSLocalizedString("cannot-move-to-self", comment: "不能将文件/文件夹移动到自身或其子目录中。"))
                return
            }
        }
        
        //播放提示音
        triggerFinderSound()
        
        var shouldReplaceAll = false
        var shouldSkipAll = false
        
        publicVar.isKeyEventEnabled = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            let destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)
            
            // 如果是在同一目录移动，则不作动作
            if fileURL.deletingLastPathComponent() == destinationURL {
                log("不能将文件/文件夹移动到相同目录中。")
                continue
            }

            if FileManager.default.fileExists(atPath: destURL.path) {
                if shouldReplaceAll {
                    do {
                        publicVar.fileChangedCount += 1
                        try FileManager.default.removeItem(at: destURL)
                        try FileManager.default.moveItem(at: fileURL, to: destURL)
                    } catch {
                        log("移动失败 \(fileURL): \(error)")
                    }
                } else if shouldSkipAll {
                    continue
                } else {
                    let userChoice = showReplaceDialog(for: destURL, isSingle: items.count == 1, isMove: true)
                    switch userChoice {
                    case .replace:
                        do {
                            publicVar.fileChangedCount += 1
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                        } catch {
                            log("移动失败 \(fileURL): \(error)")
                        }
                    case .replaceAll:
                        shouldReplaceAll = true
                        do {
                            publicVar.fileChangedCount += 1
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                        } catch {
                            log("移动失败 \(fileURL): \(error)")
                        }
                    case .skip:
                        continue
                    case .skipAll:
                        shouldSkipAll = true
                        continue
                    case .cancel:
                        publicVar.isKeyEventEnabled = true
                        return
                    }
                }
            } else {
                do {
                    publicVar.fileChangedCount += 1
                    try FileManager.default.moveItem(at: fileURL, to: destURL)
                } catch {
                    log("移动失败 \(fileURL): \(error)")
                }
            }
        }
        publicVar.isKeyEventEnabled = true
    }

    func getUniqueDestinationURL(for url: URL) -> URL {
        var newURL = url
        var counter = 1
        
        while FileManager.default.fileExists(atPath: newURL.path) {
            let baseName = url.deletingPathExtension().lastPathComponent
            let extensionName = url.pathExtension
            let newName = "\(baseName)_副本\(counter > 1 ? "\(counter)" : "")"
            
            newURL = url.deletingLastPathComponent().appendingPathComponent(newName).appendingPathExtension(extensionName)
            counter += 1
        }
        
        return newURL
    }

    enum UserChoice {
        case replace
        case replaceAll
        case skip
        case skipAll
        case cancel
    }

    func showReplaceDialog(for url: URL, isSingle: Bool, isMove: Bool) -> UserChoice {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("has-exist-in-dest1", comment: "目标文件夹中已存在名为") + url.lastPathComponent
                            + NSLocalizedString("has-exist-in-dest2", comment: "的文件。")
        if isMove {
            alert.informativeText = NSLocalizedString("do-you-want-replace(move)", comment: "你要用正在移动的文件替换它吗？")
        }else{
            alert.informativeText = NSLocalizedString("do-you-want-replace(paste)", comment: "你要用正在粘贴的文件替换它吗？")
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Replace", comment: "替换"))
        if !isSingle {
            alert.addButton(withTitle: NSLocalizedString("Replace All", comment: "全部替换"))
            alert.addButton(withTitle: NSLocalizedString("Skip", comment: "跳过"))
            alert.addButton(withTitle: NSLocalizedString("Skip All", comment: "全部跳过"))
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            if isSingle {
                return .cancel
            }else{
                return .replaceAll
            }
        case .alertThirdButtonReturn:
            return .skip
        case NSApplication.ModalResponse(rawValue: 1003):
            return .skipAll
        case NSApplication.ModalResponse(rawValue: 1004):
            return .cancel
        default:
            return .cancel
        }
    }
    
    func handleNewFolder(targetURL: URL? = nil) -> (Bool,URL?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("new-folder", comment: "新建文件夹")
        alert.informativeText = NSLocalizedString("input-new-folder-name", comment: "请输入文件夹名称：")
        alert.alertStyle = .informational
        alert.icon = NSImage(named: NSImage.infoName)// 设置系统通知图标
        
        // 添加一个文本输入框
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
            textFieldCell.usesSingleLineMode = true
            textFieldCell.wraps = false
            textFieldCell.isScrollable = true
        }
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        publicVar.isKeyEventEnabled=false
        DispatchQueue.main.async {
            _ = inputTextField.becomeFirstResponder()
        }
        let response = alert.runModal()
        publicVar.isKeyEventEnabled=true
        
        if response == .alertFirstButtonReturn {
            let folderName = inputTextField.stringValue
            
            if !folderName.isEmpty {
                fileDB.lock()
                let curFolder = fileDB.curFolder
                fileDB.unlock()
                
                var destinationURL = URL(string: curFolder)
                if targetURL != nil {destinationURL=targetURL}
                guard let destinationURL=destinationURL else {return (false,nil)}
                
                let newFolderURL = destinationURL.appendingPathComponent(folderName)
                
                // 检查是否存在同名文件
                if FileManager.default.fileExists(atPath: newFolderURL.path) {
                    showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                }else{
                    // 执行新建操作
                    do {
                        // 文件更改计数
                        publicVar.fileChangedCount += 1
                        
                        try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: true, attributes: nil)
                        log("新建文件夹成功: \(newFolderURL.path)")
                        return (true,newFolderURL)
                    } catch {
                        log("新建文件夹失败: \(error)")
                    }
                }
            }
        }
        return (false,nil)
    }
    
    // 系统主题变化时会触发此方法
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            let theme=NSApp.effectiveAppearance.name
            if theme == .darkAqua {
                // 暗模式下的颜色
                collectionView.layer?.backgroundColor = hexToNSColor(hex: "#212223").cgColor
            } else {
                // 光模式下的颜色
                collectionView.layer?.backgroundColor = hexToNSColor(hex: "#FFFFFF").cgColor
            }
            if(lastTheme != theme){
                refreshAll([], dryRun: true)
            }
            lastTheme=theme
        }
    }
    
    func refreshAll(_ reloadThumbType: [FileType] = [.folder], dryRun: Bool = false, needStopAutoScroll: Bool = true){
        refreshTreeView()
        refreshCollectionView(reloadThumbType, dryRun: dryRun, needStopAutoScroll: needStopAutoScroll)
    }
    
    func refreshCollectionView(_ reloadThumbType: [FileType] = [.folder], dryRun: Bool = false, needStopAutoScroll: Bool = true){
        fileDB.lock()
        let curFolder = fileDB.curFolder
        if let files = fileDB.db[SortKeyDir(curFolder)]?.files {
            for file in files {
                if reloadThumbType.contains(file.1.type) || reloadThumbType.first == .all {
                    file.1.originalSize=nil
                    file.1.thumbSize=nil
                    file.1.image=nil
                    file.1.folderImages=[]
                }
            }
        }
        fileDB.unlock()
        switchDirByDirection(direction: .zero, doCollapse: false, skip: dryRun, stackDeep: 0, dryRun: dryRun, needStopAutoScroll: needStopAutoScroll)
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
        for item in expandedItems {
            treeViewData.expand(node: item, isLookSub: true)
        }
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        outlineView.reloadData()
        treeReLocate(path: curFolder, doCollapse: false, expandLast: false)
    }
    
    @objc func outlineViewDoubleClicked(_ sender: AnyObject) {
        // 获取当前选中的行
        let row = outlineView.clickedRow

        // 确保点击的是有效行
        if row == -1 {
            return
        }

        // 获取行对应的条目
        if let item = outlineView.item(atRow: row) {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        }
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        //collectionViewSizeChanged()
    }
    
    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        let leftView = splitView.arrangedSubviews[0]
        let rightView = splitView.arrangedSubviews[1]

        let dividerThickness = splitView.dividerThickness
        let newWidth = splitView.bounds.width - leftView.frame.width - dividerThickness
        rightView.frame.size.width = newWidth

        // 更新右侧视图的大小，左侧视图保持不变
        rightView.frame = CGRect(x: leftView.frame.width + dividerThickness, y: 0, width: newWidth, height: splitView.bounds.height)
        leftView.frame = CGRect(x: 0, y: 0, width: leftView.frame.width, height: splitView.bounds.height)
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        // 取消之前的定时器
        resizeTimer?.invalidate()
        
        if publicVar.isInLargeView {
            windowSizeChangedTimesWhenInLarge += 1
            return
        }
        
        fileDB.lock()
        let fileCount=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count
        fileDB.unlock()
        //注：此处最好使用定时器，因为程序首次启动时会调用6次！
        if fileCount ?? 0 > -1 && !hasManualToggleSidebar && notification.name != .AVAssetDurationDidChange {
            resizeTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(splitViewSizeChanged), userInfo: nil, repeats: false)
        }else{
            splitViewSizeChanged()
        }
        hasManualToggleSidebar=false
    }
    
    func recalcIfHasChangedSize(){
        if windowSizeChangedTimesWhenInLarge > 0 {
            splitViewDidResizeSubviews(Notification(name: .AVAssetDurationDidChange)) // 表示立即执行
            windowSizeChangedTimesWhenInLarge = 0
        }
    }
    
    var _temp_count_sizeChanged: Int = 0
    @objc func splitViewSizeChanged() {
        
        _temp_count_sizeChanged+=1
        //print("计算布局"+String(_temp_count_sizeChanged))
        
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//        }
        fileDB.lock()
        let curFolder=fileDB.curFolder
        fileDB.db[SortKeyDir(curFolder)]?.layoutCalcPos=0
        fileDB.unlock()
        
        changeWaterfallLayoutNumberOfColumns()
        
        //startTime = DispatchTime.now()
        recalcLayout(curFolder)
//        if(true){
//            let curTime = DispatchTime.now()
//            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
//            let timeInterval = Double(nanoTime) / 1_000_000_000
//            log("完整计算一次布局耗时: \(timeInterval) seconds")
//        }
        //collectionView.collectionViewLayout=LeftAlignedCollectionViewFlowLayout()
        collectionView.collectionViewLayout?.invalidateLayout()
        view.window?.layoutIfNeeded()
        //collectionView.collectionViewLayout=LeftAlignedCollectionViewFlowLayout()
        
        //以下是处理左侧目录树，防止在宽度为0时切换目录，再拉宽时，某些条目显示...
        //注：似乎改变了实现方式（直接从数据源获取而不是可见view），就不用此处调用了，这里调用计算量大会导致卡顿
        //outlineViewManager.adjustColumnWidth()
        
        //解决gird时改变窗口大小，由于不彻底重载，导致的缩放不正常
        if publicVar.profile.layoutType == .grid {
            let visibleIndexPaths=collectionView.indexPathsForVisibleItems()
            for indexPath in visibleIndexPaths{
                if let item = collectionView.item(at: indexPath) as? CustomCollectionViewItem {
                    item.configureWithImage(item.file,playAnimation:false)
                }
            }
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
        //log("recalcLayout:"+String(recalcLayoutTimes))
        
        //var WIDTH_THRESHOLD=6.0/2000
        var WIDTH_THRESHOLD=6.4/1920*512/Double(publicVar.profile.thumbSize)
        
        if publicVar.profile.layoutType == .grid {
            WIDTH_THRESHOLD=10.0/1920*512/Double(publicVar.profile.thumbSize)
        }
        
        let scrollbarWidth = publicVar.profile.ThumbnailScrollbarWidth
        var totalWidth = self.mainScrollView.bounds.width - scrollbarWidth - 2 * publicVar.profile.ThumbnailCellPadding
        if totalWidth < 25 {totalWidth = 25}
        if publicVar.isInLargeView && globalVar.portableMode {totalWidth = 1000}
        
        //let totalWidth=collectionView.bounds.width-10
        //log("totalWidth:",totalWidth)
        let actualThreshold=WIDTH_THRESHOLD*totalWidth
        var sum=0.0
        var lineCount=0
        var singleIds=[SortKeyFile]()
        var lastSingleHeight:Double?
        
        fileDB.lock()
        if fileDB.db[SortKeyDir(targetFolder)] == nil {
            fileDB.unlock()
            return
        }
        let count = fileDB.db[SortKeyDir(targetFolder)]!.files.count
        let fileCount = fileDB.db[SortKeyDir(targetFolder)]!.fileCount
        let layoutCalcPos = fileDB.db[SortKeyDir(targetFolder)]!.layoutCalcPos
        //let startKey = fileDB.db[targetFolder]!.files.elementSafe(atOffset: layoutCalcPos).0
        if layoutCalcPos>0 {
            if let thumbSize=fileDB.db[SortKeyDir(targetFolder)]!.files.elementSafe(atOffset: layoutCalcPos-1)?.1.thumbSize {
                lastSingleHeight = thumbSize.height - (2*publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailFilenamePadding)
            }
        }
        if layoutCalcPos < count {
            for i in layoutCalcPos...(count-1) {
                guard let key = fileDB.db[SortKeyDir(targetFolder)]!.files.elementSafe(atOffset: i)?.0 else{break}
                guard var originalSize=fileDB.db[SortKeyDir(targetFolder)]!.files[key]!.originalSize else{break}
                if fileDB.db[SortKeyDir(targetFolder)]!.files[key]!.canBeCalcued != true {break}

                if publicVar.profile.layoutType == .grid { originalSize=DEFAULT_SIZE }
                sum+=(originalSize.width/originalSize.height)
                singleIds.append(key)
                if sum>=actualThreshold || i==fileDB.db[SortKeyDir(targetFolder)]!.files.count-1 {
                    sum=max(sum,actualThreshold)
                    var singleHeight = floor((totalWidth - 2 * (publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailCellPadding) * Double(singleIds.count))/sum)
                    if publicVar.profile.layoutType == .grid && lastSingleHeight != nil { singleHeight=lastSingleHeight! } //防止最后一行不一样大小
                    lastSingleHeight=singleHeight
                    for singleId in singleIds{
                        var originalSizeSingle=fileDB.db[SortKeyDir(targetFolder)]!.files[singleId]!.originalSize!
                        
                        if publicVar.profile.layoutType == .grid { originalSizeSingle=DEFAULT_SIZE }
                        
                        var singleWidth = floor(originalSizeSingle.width/originalSizeSingle.height*singleHeight)
                        
                        if publicVar.profile.layoutType == .waterfall {
                            let numberOfColumns=Double(publicVar.waterfallLayout.numberOfColumns)
                            singleWidth = floor(totalWidth/numberOfColumns-2*(publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailCellPadding))
                            singleHeight = round(originalSizeSingle.height/originalSizeSingle.width*singleWidth)
                        }
                        
                        let size=NSSize(width: singleWidth+2*publicVar.profile.ThumbnailBorderThickness, height: singleHeight+2*publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailFilenamePadding)
                        fileDB.db[SortKeyDir(targetFolder)]!.files[singleId]!.thumbSize=size
                        fileDB.db[SortKeyDir(targetFolder)]!.files[singleId]!.lineNo=lineCount
                    }
                    for singleId in singleIds.reversed(){
                        fileDB.db[SortKeyDir(targetFolder)]!.files[singleId]!.isLayoutCalcued=true
                    }
                    singleIds=[]
                    sum=0.0
                    lineCount+=1
                    fileDB.db[SortKeyDir(targetFolder)]!.layoutCalcPos=i+1
                }
            }
        }
        fileDB.unlock()
    }
    
    private func findItemsToExpand(outlineView: NSOutlineView, targetPaths: [String], currentPath: [String], currentItem: Any?, itemsToExpand: inout Set<AnyHashable>) {
        guard !targetPaths.isEmpty else { return }
        
        outlineView.expandItem(currentItem)
        
        let childrenCount = outlineView.numberOfChildren(ofItem: currentItem)
        for index in 0..<childrenCount {
            if let item = outlineView.child(index, ofItem: currentItem),
               let itemObject = (item as? TreeNode)
            {
                let itemName = itemObject.name
                let newPath = currentPath + [itemName]
                
                if targetPaths.starts(with: newPath) {
                    _=itemsToExpand.insert(itemObject)
                    findItemsToExpand(outlineView: outlineView, targetPaths: targetPaths, currentPath: newPath, currentItem: item, itemsToExpand: &itemsToExpand)
                }
            }
        }
    }
    
    private func adjustExpansion(outlineView: NSOutlineView, parentItem: Any?, itemsToExpand: Set<AnyHashable>, doCollapse: Bool) {
        let childrenCount = outlineView.numberOfChildren(ofItem: parentItem)
        for index in 0..<childrenCount {
            if let item = outlineView.child(index, ofItem: parentItem),
               let itemObject = (item as? TreeNode) {
                if itemsToExpand.contains(itemObject) {
                    outlineView.expandItem(item)
                } else {
                    if doCollapse{
                        outlineView.collapseItem(item, collapseChildren: true)
                    }
                }
                adjustExpansion(outlineView: outlineView, parentItem: item, itemsToExpand: itemsToExpand, doCollapse: doCollapse)
            }
        }
    }
    
    private func selectFinalItem(outlineView: NSOutlineView, targetPaths: [String]) {
        var currentItem: Any? = nil
        for path in targetPaths {
            let count = outlineView.numberOfChildren(ofItem: currentItem)
            var found = false
            for index in 0..<count {
                if let item = outlineView.child(index, ofItem: currentItem),
                   let itemObject = (item as? TreeNode),
                   itemObject.name == path {
                    currentItem = item
                    found = true
                    break
                }
            }
            if !found {
                outlineViewManager.ifActWhenSelected=false
                outlineView.selectRowIndexes([], byExtendingSelection: false)
                outlineViewManager.ifActWhenSelected=true
                return
            }
        }
        if let finalItem = currentItem, let rowIndex = outlineView.row(forItem: finalItem) as Int? {
            outlineViewManager.ifActWhenSelected=false
            outlineView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
            outlineView.scrollRowToVisible(rowIndex)
            outlineViewManager.ifActWhenSelected=true
        }
    }
    
    func treeReLocate(path: String, doCollapse: Bool, expandLast: Bool) {
        var path=path
        let externalVolumes=VolumeManager.shared.getExternalVolumes()
        var isInExternal=false
        for exUrl in externalVolumes {
            if path.hasPrefix(exUrl.absoluteString) {
                path=exUrl.lastPathComponent+"/"+path.replacingOccurrences(of: exUrl.absoluteString, with: "")
                isInExternal=true
                break
            }
        }

        var targetPaths = path.replacingOccurrences(of: rootFolder, with: "").removingPercentEncoding!.components(separatedBy: "/")
        targetPaths.removeLast()
        log("Locate:",targetPaths)
        
        //额外插入一层用来定位
        if treeRootFolder == "root" && !isInExternal {
            targetPaths.insert(ROOT_NAME, at: 0)
        }
        
        if targetPaths.isEmpty {
            outlineView.deselectAll(nil)
        }else{
            let last=targetPaths.last!
            if !expandLast {targetPaths.removeLast()}
            
            // 用于记录应当展开的项
            var itemsToExpand = Set<AnyHashable>()
            
            // 找到应该展开的项
            findItemsToExpand(outlineView: outlineView, targetPaths: targetPaths, currentPath: [], currentItem: nil, itemsToExpand: &itemsToExpand)
            
            // 展开找到的项，并折叠不在路径上的项
            adjustExpansion(outlineView: outlineView, parentItem: nil, itemsToExpand: itemsToExpand, doCollapse: doCollapse)
            
            if !expandLast {targetPaths.append(last)}
            // 选择最后一项
            selectFinalItem(outlineView: outlineView, targetPaths: targetPaths)
        }
    }
    
    func setWindowTitle(){
        var fullTitle = "FlowVision"

        fileDB.lock()
        let curFolder=fileDB.curFolder
        let imageCount=(fileDB.db[SortKeyDir(curFolder)]?.imageCount ?? 0)
        let videoCount=fileDB.db[SortKeyDir(curFolder)]?.videoCount ?? 0
        let otherCount=(fileDB.db[SortKeyDir(curFolder)]?.fileCount ?? 0) - imageCount - videoCount
        let folderCount=(fileDB.db[SortKeyDir(curFolder)]?.folderCount ?? 0)
        fileDB.unlock()
        fullTitle = curFolder.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!
        if folderCount+imageCount+videoCount+otherCount > 0 {
            fullTitle += String(format: " (")
            if folderCount != 0 {
                fullTitle += String(format: "%d %@ ", folderCount, NSLocalizedString("Folder", comment: "目录"))
            }
            if imageCount != 0 {
                fullTitle += String(format: "%d %@ ", imageCount, NSLocalizedString("Image", comment: "图像"))
            }
            if videoCount != 0 {
                fullTitle += String(format: "%d %@ ", videoCount, NSLocalizedString("Video", comment: "视频"))
            }
            if otherCount != 0 {
                fullTitle += String(format: "%d %@ ", otherCount, NSLocalizedString("Other", comment: "其它"))
            }
            fullTitle=fullTitle.trimmingCharacters(in: .whitespaces)
            //                if folderCount == 0 && imageCount == 0 && videoCount == 0 && otherCount == 0 {
            //                    windowTitle += NSLocalizedString("Empty", comment: "空")
            //                }
            fullTitle += String(format: ")")
        }

        var shortTitle = (curFolder as NSString).lastPathComponent.removingPercentEncoding!
        if curFolder == "file:///" {shortTitle = ROOT_NAME}
        view.window?.title = shortTitle
        publicVar.fullTitle = fullTitle
        if let windowController = view.window?.windowController as? WindowController {
            windowController.updateToolbar()
        }
    }
    
    func captureSnapshot(of view: NSView) -> NSView? {
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmapRep)
        
        let snapshotView = NSImageView(frame: view.bounds)
        snapshotView.image = NSImage(size: view.bounds.size)
        snapshotView.image?.addRepresentation(bitmapRep)
        return snapshotView
    }
    
    func switchDirByDirection(direction rawdirection: GestureDirection, dest: String = "", doCollapse: Bool = true, expandLast: Bool = true, skip: Bool = false, stackDeep: Int, dryRun: Bool = false, needStopAutoScroll: Bool = true){
        
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
        
        //停止自动滚动
        if needStopAutoScroll {
            stopAutoScroll()
        }
        
        //停止自动播放
        stopAutoPlay()

        stopWatchingDirectory()
        collectionView.deselectAll(nil)
        //publicVar.selectedUrls=[URL]()
        
        var direction=rawdirection
        var secondDirection: GestureDirection = .zero
        if rawdirection == .down_left {direction = .left; secondDirection = .down}
        if rawdirection == .down_right {direction = .right; secondDirection = .down}
        if rawdirection == .up_left {direction = .up; secondDirection = .down_left}
        if rawdirection == .up_right {direction = .up; secondDirection = .down_right}
        
        //初始为空则返回
        fileDB.lock()
        if fileDB.curFolder=="" && direction != .zero {
            fileDB.unlock()
            return
        }
        fileDB.unlock()
        
        startTime = DispatchTime.now()
        
        //返回上一次目录
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
        //前进
        if direction == .forward {
            if publicVar.folderStepForwardStack.count == 0 {return}
            if publicVar.folderStepForwardStack[0] == "" {return}
            switchDirByDirection(direction: .zero, dest: publicVar.folderStepForwardStack.removeFirst(), stackDeep: stackDeep+1)
            return
        }
        //跳转父级目录
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
        
        treeTraversal(folderURL: URL(string: startFolder)!, round: searchFolderRound, initURL: URL(string: startFolder)!, direction: direction,
                          sameLevel: secondDirection == .down, skip: skip, dryRun: dryRun)

        //let a=1
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
        //log(fileDB.db[curIndex].1.files.count)
        fileDB.unlock()
        //testTmpFolder=fileDB.db[curIndex].0
        
        if(true){
            let curTime = DispatchTime.now()
            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let timeInterval = Double(nanoTime) / 1_000_000_000
            log("完成文件列表耗时: \(timeInterval) seconds")
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
    
    func showScanAlert(fileCount: Int, imageCount: Int, videoCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Scan Prompt", comment: "扫描提示")
        alert.informativeText = String(format: NSLocalizedString("scanned-files", comment: "当前已扫描 %d 个文件，其中图像 %d 个，视频 %d 个。是否继续？"), fileCount, imageCount, videoCount)
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: "继续"))
        alert.addButton(withTitle: NSLocalizedString("Stop", comment: "停止"))
        return alert.runModal() == .alertFirstButtonReturn
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
            if !isDirectory {
                contents.append(url)
                fileCount += 1
                if globalVar.HandledImageExtensions.contains(url.pathExtension.lowercased()) {
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

    
    func treeTraversal(folderURL: URL, round: Int, initURL: URL, direction: GestureDirection, sameLevel: Bool = false, skip: Bool = false, dryRun: Bool = false) {
        //guard let root = root else { return }
        //let aaa=folderURL.absoluteString
        
        //找到了则停止
        if round != searchFolderRound {return}
        //重复的则停止
        fileDB.lock()
        if fileDB.db[SortKeyDir(folderURL.absoluteString)]?.ver == fileDB.ver {
            fileDB.unlock()
            return
        }
        fileDB.unlock()
        //找后继时如果不是父目录还小于它则停止
        if direction == .right && SortKeyDir(folderURL.absoluteString) < SortKeyDir(initURL.absoluteString) && !initURL.absoluteString.contains(folderURL.absoluteString) {return}
        //找前驱时如果大于它则停止
        if direction == .left && SortKeyDir(folderURL.absoluteString) > SortKeyDir(initURL.absoluteString) {return}
        
        
        var contents=[URL]()
        var properties: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        if VolumeManager.shared.isExternalVolume(folderURL) {
            properties = [.isHiddenKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey]
        }
        if !skip {
            do {
                if publicVar.isRecursiveMode {
                    scanFiles(at: folderURL, contents: &contents, properties: properties)
                }else{
                    contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: properties, options: [])
                }
            }catch{}
        }
        
        //过滤隐藏文件
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
        
        //过滤出目录列表
        var subFolders = contents.filter { url in
            guard let isDirectoryResourceValue = try? url.resourceValues(forKeys: [.isDirectoryKey]), let isDirectory = isDirectoryResourceValue.isDirectory else {
                return false
            }
            return isDirectory
        }
        if folderURL == initURL && sameLevel { subFolders.removeAll() } //如果找平级则无视子目录
        subFolders.sort { $0.lastPathComponent.lowercased().localizedStandardCompare($1.lastPathComponent.lowercased()) == .orderedAscending }
        
        //过滤出需处理文件列表
        var filesUrlInFolder = [URL]()
        var videoCount=0
        var imageCount=0
        var searchCount=0
        let fileContents = contents.filter { url in
            guard let isDirectoryResourceValue = try? url.resourceValues(forKeys: [.isDirectoryKey]), let isDirectory = isDirectoryResourceValue.isDirectory else {
                return false
            }
            return !isDirectory
        }
        for file in fileContents {
            if publicVar.HandledFileExtensions.contains(file.pathExtension.lowercased()) || publicVar.isShowAllTypeFile {
                filesUrlInFolder.append(file)
            }
            if publicVar.HandledImageExtensions.contains(file.pathExtension.lowercased()) {
                imageCount+=1
            }
            if publicVar.HandledVideoExtensions.contains(file.pathExtension.lowercased()) {
                videoCount+=1
            }
            if publicVar.HandledSearchExtensions.contains(file.pathExtension.lowercased()) {
                searchCount+=1
            }
        }
        //好像没必要排序
        var filesInFolder = filesUrlInFolder.map{$0.absoluteString}
        let fileCount=filesInFolder.count
        for folder in subFolders {
            filesInFolder.append(folder.absoluteString+"_FolderMark")
            
        }
        
        //标记当前节点
        fileDB.lock()
        if fileDB.db[SortKeyDir(folderURL.absoluteString)] == nil {
            fileDB.db[SortKeyDir(folderURL.absoluteString)] = DirModel(path: folderURL.absoluteString, ver: fileDB.ver)
        }
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.ver = fileDB.ver
        if !skip {
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
        
        //往前则后序遍历
        if direction == .left {
            for subFolder in subFolders.reversed(){
                treeTraversal(folderURL: subFolder, round: round, initURL: initURL, direction: direction)
            }
            if folderURL.deletingLastPathComponent().absoluteString != "file:///../" {
                treeTraversal(folderURL: folderURL.deletingLastPathComponent(), round: round, initURL: initURL, direction: direction)
            }
        }
        
        //有图片且满足条件则停止之后搜索
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
        
        
        //排序传递性断言
        //            var testList=[SortKey]()
        //            for filePath in filesInFolder{
        //                let fileSortKey:SortKey
        //                //fileSortKey=SortKeyDir(filePath)
        //                if filePath.hasSuffix("_FolderMark") {
        //                    fileSortKey=SortKeyDir(String(filePath.dropLast("_FolderMark".count)),isDir: true)
        //                }else{
        //                    fileSortKey=SortKeyDir(filePath)
        //                }
        //                testList.append(fileSortKey)
        //                //log(filePath)
        //            }
        //            testList.sort()
        //            for (i, _) in testList.enumerated() {
        //                for (j,_) in testList.enumerated() where j > i {
        //                    assert(testList[i] <= testList[j], "Sort order \(i) and \(j) is incorrect \(testList[i].path.removingPercentEncoding!) and \(testList[j].path.removingPercentEncoding!)")
        //                }
        //            }
        
        
        //处理当前节点，注意检查skip，否则向上时会清空
        fileDB.lock()
        if !skip && (initURL != folderURL || direction == .zero) {
            let folderpath = folderURL.absoluteString
            //log(filesInFolder.count)
            for (i,filePath) in filesInFolder.enumerated(){
                var fileSortKey:SortKeyFile
                let isDir:Bool
                if filePath.hasSuffix("_FolderMark") {
                    fileSortKey=SortKeyFile(String(filePath.dropLast("_FolderMark".count)), isDir: true, isInSameDir: !publicVar.isRecursiveMode, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst)
                    isDir=true
                }else{
                    fileSortKey=SortKeyFile(filePath, isInSameDir: !publicVar.isRecursiveMode, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst)
                    isDir=false
                }
                //读取文件大小日期
                var fileSize: Int?
                var modDate: Date?
                var createDate: Date?
                var addDate: Date?
                var doNotActualRead=false
                do{
                    //文件在前i个，目录在后面
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
                    }else{//目录
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
                        //由于文件夹下内容没下载全，downloadingStatus好像也会为current，因此只要是icloud文件夹，就不生成缩略图
                        if let isUbiquitousItem = resourceValues.isUbiquitousItem,
                           isUbiquitousItem
                           {
                            doNotActualRead=true
                        }
                    }
                }catch{
                    log("Error reading properties.")
                }
                //log("i:",i,"path:",fileSortKey.path.removingPercentEncoding)
                let newFileModel=FileModel(path: fileSortKey.path, ver: fileDB.db[SortKeyDir(folderpath)]!.ver, isDir: isDir, fileSize: fileSize, createDate: createDate, modDate: modDate, addDate: addDate, doNotActualRead: doNotActualRead)
                //log(fileSortKey.path)
                if fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] != nil {
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.ver = fileDB.db[SortKeyDir(folderpath)]!.ver
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.isDir=isDir
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.doNotActualRead=doNotActualRead
                    //检查文件或文件夹是否有变化(文件夹fileSize为nil)
                    if fileSize != fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.fileSize || modDate != fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.modDate {
                        fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] = newFileModel
                    }
                }else{
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] = newFileModel
                }
            }
            for ele in fileDB.db[SortKeyDir(folderpath)]!.files{
                //log(ele.0.path.removingPercentEncoding)
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
            for ele in fileDB.db[SortKeyDir(folderpath)]!.files{
                ele.1.ver = fileDB.db[SortKeyDir(folderpath)]!.ver
                ele.1.canBeCalcued = false
                if !ele.1.isDir{
                    ele.1.ext=URL(string: ele.1.path)!.pathExtension.lowercased()
                    if globalVar.HandledImageExtensions.contains(ele.1.ext) {
                        ele.1.type = .image
                        ele.1.idInImage = idInImage
                        idInImage += 1
                    }else if globalVar.HandledVideoExtensions.contains(ele.1.ext) {
                        ele.1.type = .video
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
        
        //往后则先序遍历
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
        //startTime = DispatchTime.now()
        
        //getFileListOfFolder(folderpath: path)
        
        //清空任务池
        readInfoTaskPoolLock.lock()
        readInfoTaskPool.removeAll()
        readInfoTaskPoolLock.unlock()
        loadImageTaskPool.lock.lock()
        loadImageTaskPool.removeAllQueue()
        loadImageTaskPool.setMostPriority(queueName: path)
        loadImageTaskPool.lock.unlock()
        
        //是捕获界面，还是将从finder打开替换为目录中打开
        if publicVar.openFromFinderPath == "" {
            let snapshot = captureSnapshot(of: mainScrollView)
            mainScrollView.addSubview(snapshot!)
            snapshotQueue.append(snapshot)
//            currLargeImagePos = -1
            initLargeImagePos = -1
            if publicVar.lastLargeImageIdInImage == 0 {
                nextLargeImage(isShowReachEndPrompt: false)
                previousLargeImage(isShowReachEndPrompt: false)
            }else{
                previousLargeImage(isShowReachEndPrompt: false)
                nextLargeImage(isShowReachEndPrompt: false)
            }

        }else{
            
            let filename=publicVar.openFromFinderPath
            //log(filename)
            fileDB.lock()
            if let index=fileDB.db[SortKeyDir(path)]?.files.index(forKey: SortKeyFile(filename, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst)),
               let offset=fileDB.db[SortKeyDir(path)]?.files.offset(of: index),
               let file=fileDB.db[SortKeyDir(path)]?.files[SortKeyFile(filename, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst)],
               let url=URL(string: file.path),
               let totalCount=fileDB.db[SortKeyDir(path)]?.files.count,
               let fileCount=fileDB.db[SortKeyDir(path)]?.fileCount
            {
                fileDB.unlock()
                //log(offset-(totalCount-fileCount))
                currLargeImagePos = offset//-(totalCount-fileCount)
                initLargeImagePos = -1
                publicVar.openFromFinderPath = ""
                file.originalSize=getImageSize(url: url)
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
            }else{
                collectionView.collectionViewLayout=publicVar.justifiedLayout
            }
            publicVar.isNeedChangeLayoutType = false
        }
        
        //清空collectionView
        fileDB.lock()
        let lastCurFolder=fileDB.curFolder
        fileDB.curFolder = path
        let fileNum=fileDB.db[SortKeyDir(path)]?.files.count ?? 0
        let lastLayoutCalcPos=fileDB.db[SortKeyDir(path)]?.layoutCalcPos ?? fileNum
        fileDB.db[SortKeyDir(path)]?.layoutCalcPos=0
        fileDB.db[SortKeyDir(path)]?.lastLayoutCalcPosUsed=0
        fileDB.unlock()
        
        //如果是切换目录或者文件数量过多，则清空后再insertItems，否则仅reloadData(保持位置)
        if lastCurFolder != path || fileNum > 5000 || fileDB.db[SortKeyDir(path)]?.keepScrollPos == false {
            //必须按顺序执行以下两句，否则频繁切换目录时会出现异常
            collectionView.reloadData() //重载清空
            collectionView.numberOfItems(inSection:0)
            
            fileDB.lock()
            fileDB.db[SortKeyDir(path)]?.keepScrollPos=false
            fileDB.unlock()
        }
        
        //界面快照渐隐动画
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
            
            //对于空文件夹，播放渐变动画（因为没有分派任务，所以在任务里的渐变调用不到）
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
            
            //对于非空文件夹，延迟播放渐变动画（主要是针对网络驱动器时，可能连第一个对象获取信息都非常耗时，需要在此处也计时）
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                Thread.sleep(forTimeInterval: 0.5)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    fileDB.lock()
                    let curFolder=fileDB.curFolder
                    let layoutCalcPos=fileDB.db[SortKeyDir(curFolder)]?.layoutCalcPos ?? -1
                    fileDB.unlock() //内存屏障
                    
                    if ver != dirModel.ver {return}
                    
                    if curFolder == path {
                        while snapshotQueue.count > 0{
                            
                            if layoutCalcPos == 0{
                                coreAreaView.showInfo(NSLocalizedString("Loading...", comment: "加载中..."), timeOut: .infinity, cannotBeCleard: false)
                            }
                            
                            let snapshot=snapshotQueue.first!
                            snapshotQueue.removeFirst()
                            //publicVar.isInLargeView=false
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
            log("分派完info任务耗时: \(timeInterval) seconds")
        }
        
    }
    func startBackgroundTaskThread(){
        log("开始startBackgroundTaskThread")

        //读取信息线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = globalVar.thumbThreadNum > 2 ? 2 : 1
            operationQueue.qualityOfService = .userInitiated
            while true{
                if willTerminate {break}
                readInfoTaskPoolSemaphore.wait()

                readInfoTaskPoolLock.lock()
                if readInfoTaskPool.count != 0 {
                    let firstTask = readInfoTaskPool.removeFirst()
                    readInfoTaskPoolLock.unlock()
                    //(dir,key,i,doNotActualRead)
                    fileDB.lock()
                    let dir=firstTask.0
                    let dirModel=firstTask.1
                    let key=firstTask.2
                    let file=firstTask.3
                    let i=file.id
                    let doNotActualRead=file.doNotActualRead
                    let ver=firstTask.4
                    let count=dirModel.files.count
                    fileDB.unlock() //内存屏障
                    
                    if i == -1 {continue}
                    if ver != dirModel.ver {continue}
                    
                    //外置卷等待到队列全部执行完毕再分配(单线程)
//                    if VolumeManager.shared.isExternalVolume(key.path) {
//                        operationQueue.waitUntilAllOperationsAreFinished()
//                    }
                    if VolumeManager.shared.isExternalVolume(key.path) {
                        operationQueue.maxConcurrentOperationCount = 1
                    }else{
                        operationQueue.maxConcurrentOperationCount = globalVar.thumbThreadNum > 2 ? 2 : 1
                    }
                    
                    //最后一个等待到队列全部执行完毕再分配
                    if(i == count-1){
                        operationQueue.waitUntilAllOperationsAreFinished()
                    }
                    
                    operationQueue.addOperation { [weak self] in
                        guard let self = self else { return }
                        if willTerminate {return}
                        
                        fileDB.lock()
                        var originalSize = file.originalSize
                        let curFolder=fileDB.curFolder
                        fileDB.unlock() //内存屏障
                        
                        if ver != dirModel.ver {return}
                        if dir != curFolder {return} // 需要跳过，否则会等上一个目录完全执行完毕后才开始；不过这样就没法预载入其它目录了，待重构任务队列实现
                        
                        publicVar.isInStageTwoProgress = true
                        defer {
                            publicVar.isInStageTwoProgress = false
                        }
                        
                        var isGetImageSizeFail = false
                        
                        if originalSize == nil {
                            //获取图像大小
                            if doNotActualRead { //|| VolumeManager.shared.isExternalVolume(key.path){
                                originalSize = DEFAULT_SIZE
                                isGetImageSizeFail = true
                            }else{
                                originalSize = getImageSize(url: URL(string: key.path)!)
                                if originalSize == nil {
                                    originalSize = DEFAULT_SIZE
                                    isGetImageSizeFail = true
                                }
                            }
                        }
                        
                        if originalSize != nil {
                            //注意：可能上面的下一轮执行完毕后才执行后面的代码
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                
                                fileDB.lock()
                                file.originalSize = originalSize
                                file.canBeCalcued=true
                                file.isGetImageSizeFail=isGetImageSizeFail
                                let count=dirModel.files.count
                                let curFolder=fileDB.curFolder
                                let keepScrollPos=dirModel.keepScrollPos
                                fileDB.unlock()
                                
                                if ver != dirModel.ver {return}
                                
                                //80~0.07s, 50~0.05s, 20~0.04s
                                if(false || i % 20 == 8 || i == count-1 || publicVar.timer.intervalSafe(name: "recalcLayoutWhenReadInfo", second: 0.1)){
                                    recalcLayout(dir)
                                    //collectionView.reloadData()
                                }
                                
                                if(dir == curFolder && keepScrollPos && i == count-1){
                                    //publicVar.timer.intervalSafe(name: "recalcLayoutReloadData", second: 0.02+Double(i)*0.0001)
                                    collectionView.reloadData()
                                    collectionView.numberOfItems(inSection:0)
                                }
                                
                                fileDB.lock()
                                let lastLayoutCalcPosUsed = dirModel.lastLayoutCalcPosUsed
                                let nowLayoutCalcPos = dirModel.layoutCalcPos
                                fileDB.unlock()
                                
                                if(i == count-1){
                                    let curTime = DispatchTime.now()
                                    let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                    let timeInterval = Double(nanoTime) / 1_000_000_000
                                    log("大小的信息完全载入耗时: \(timeInterval) seconds")
                                }
                                
                                //                            if nowLayoutCalcPos-lastLayoutCalcPosUsed > 100 {
                                //                                nowLayoutCalcPos=lastLayoutCalcPosUsed+100 //避免一次显示太多导致载入缓存目录时不能瞬间显示，但这样似乎更慢了
                                //                                fileDB.lock()
                                //                                fileDB.db[SortKeyDir(dir)]!.layoutCalcPos=nowLayoutCalcPos
                                //                                fileDB.unlock()
                                //                            }
                                if(nowLayoutCalcPos > lastLayoutCalcPosUsed && (publicVar.timer.intervalSafe(name: "insertItems", second: min(0.02+Double(i)*0.0001,5.0)) || nowLayoutCalcPos == count)){
                                    var indexPaths = [IndexPath]()
                                    for x in lastLayoutCalcPosUsed...nowLayoutCalcPos-1{
                                        indexPaths.append(IndexPath(item: x, section: 0))
                                    }
                                    if(dir == curFolder){
                                        
                                        coreAreaView.hideInfo()
                                        
                                        if collectionView.numberOfItems(inSection:0) + indexPaths.count == nowLayoutCalcPos {
                                            if !keepScrollPos {
                                                collectionView.insertItems(at: Set(indexPaths))
                                            }
                                            if nowLayoutCalcPos == count {
                                                fileDB.lock()
                                                dirModel.keepScrollPos=true
                                                fileDB.unlock()
                                            }
                                        }
                                        //collectionView.reloadData()
                                        //collectionView.numberOfItems(inSection:0)
                                        //此时开始渐变动画？
                                        
                                    }
                                    for x in lastLayoutCalcPosUsed...nowLayoutCalcPos-1{
                                        //TODO: 大量读取文件时造成系统内存不足
                                        let memUseLimit = globalVar.memUseLimit
                                        if x > memUseLimit {
                                            break
                                        }
                                        fileDB.lock()
                                        let curKey = dirModel.files.elementSafe(atOffset: x)?.0
                                        let file = dirModel.files.elementSafe(atOffset: x)?.1
                                        fileDB.unlock()
                                        guard let curKey=curKey,let file=file else{continue}
                                        loadImageTaskPool.lock.lock()
                                        loadImageTaskPool.push(dir,(dir,dirModel,curKey,file,dirModel.ver,OtherTaskInfo()))
                                        loadImageTaskPoolSemaphore.signal()
                                        loadImageTaskPool.lock.unlock()
                                        if x == 0 {
                                            let curTime = DispatchTime.now()
                                            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                            let timeInterval = Double(nanoTime) / 1_000_000_000
                                            log("第一张添加进readImage池耗时: \(timeInterval) seconds")
                                        }
                                    }
                                    fileDB.lock()
                                    dirModel.lastLayoutCalcPosUsed=nowLayoutCalcPos
                                    fileDB.unlock()
                                }
                            }
                        }
                    }
                }else{
                    readInfoTaskPoolLock.unlock()
                }
            }
        }
        //缩略图线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = globalVar.thumbThreadNum
            operationQueue.qualityOfService = .userInitiated
            while true{
                if willTerminate {break}
                loadImageTaskPoolSemaphore.wait()
                operationQueue.addOperation { [weak self] in
                    guard let self = self else { return }
                    if willTerminate {return}
                    loadImageTaskPool.lock.lock()
                    if let firstTask = loadImageTaskPool.pop() {
                        loadImageTaskPool.lock.unlock()
                        //(dir,key,i,doNotActualRead)
                        fileDB.lock()
                        let dir=firstTask.0
                        let dirModel=firstTask.1
                        let key=firstTask.2
                        let file=firstTask.3
                        let doNotActualRead = file.doNotActualRead
                        let i=file.id
                        let ver=firstTask.4
                        let otherTaskInfo=firstTask.5
                        let curFolder=fileDB.curFolder
                        fileDB.unlock() //内存屏障
                        
                        if i == -1 {return}
                        if ver != dirModel.ver {return}
                        if dir != curFolder {return} // 暂时跳过，以降低网络驱动器单线程的载入延迟
                        
                        publicVar.isInStageThreeProgress = true
                        defer {
                            publicVar.isInStageThreeProgress = false
                        }
                        
                        if VolumeManager.shared.isExternalVolume(key.path) {
                            operationQueue.maxConcurrentOperationCount = globalVar.thumbThreadNum_External
                        }else{
                            operationQueue.maxConcurrentOperationCount = globalVar.thumbThreadNum
                        }
                        
//                        if VolumeManager.shared.isExternalVolume(key.path) {
//                            let dirPath=getDirectoryPath(key.path)
//                            externalVolumeThreadSemaphoresLock.lock()
//                            let semaphore = externalVolumeThreadSemaphores[dirPath, default: DispatchSemaphore(value: globalVar.thumbThreadNum_External)]
//                            externalVolumeThreadSemaphores[dirPath] = semaphore
//                            externalVolumeThreadSemaphoresLock.unlock()
//                            semaphore.wait()
//                        }
//                        defer {
//                            if VolumeManager.shared.isExternalVolume(key.path) {
//                                let dirPath=getDirectoryPath(key.path)
//                                externalVolumeThreadSemaphoresLock.lock()
//                                let semaphore = externalVolumeThreadSemaphores[dirPath, default: DispatchSemaphore(value: globalVar.thumbThreadNum_External)]
//                                externalVolumeThreadSemaphores[dirPath] = semaphore
//                                externalVolumeThreadSemaphoresLock.unlock()
//                                semaphore.signal()
//                            }
//                        }
                        
                        fileDB.lock()
                        var originalSize:NSSize? = file.originalSize
                        var thumbSize:NSSize? = file.thumbSize
                        let count = dirModel.files.count
                        let isMemClearedToAvoidRemainingTask=dirModel.isMemClearedToAvoidRemainingTask
                        fileDB.unlock()
                        //loadImageTaskPool.lock.unlock()//此处解锁是因为防止8个线程与主线程排队争fileDB.lock
                        if isMemClearedToAvoidRemainingTask && !otherTaskInfo.isFromScroll {return}
                        
//                        if(true){
//                            let curTime = DispatchTime.now()
//                            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
//                            let timeInterval = Double(nanoTime) / 1_000_000_000
//                            log("read接任务耗时: \(timeInterval) seconds ",dir)
//                        }
                        
                        //完全载入计时
                        if(i == count-1){
                            let curTime = DispatchTime.now()
                            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                            let timeInterval = Double(nanoTime) / 1_000_000_000
                            log("图像的缩略完全载入耗时: \(timeInterval) seconds")
                            log("-----------------------------------------------------------")
                        }
                        //此时开始渐变动画
                        if dir == curFolder {//防止其它队列末尾任务造成提前渐变
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                
                                fileDB.lock()
                                let curFolder=fileDB.curFolder
                                fileDB.unlock() //内存屏障
                                
                                if ver != dirModel.ver {return}
                                if dir != curFolder {return}
                                
                                coreAreaView.hideInfo()
                                
                                let curTime = DispatchTime.now()
                                let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                let timeInterval = Double(nanoTime) / 1_000_000_000
                                if i>40 || i==count-1 || timeInterval>0.3 {
                                    while snapshotQueue.count > 0{
                                        let snapshot=snapshotQueue.first!
                                        snapshotQueue.removeFirst()
                                        //publicVar.isInLargeView=false
                                        NSAnimationContext.runAnimationGroup({ context in
                                            context.duration = 0.2
                                            snapshot?.animator().alphaValue = 0
//                                            self.largeImageView.animator().alphaValue = 0
//                                            self.largeImageBgEffectView.animator().alphaValue = 0
                                        }, completionHandler: {
                                            snapshot?.removeFromSuperview()
//                                            self.largeImageView.isHidden=true
//                                            self.largeImageBgEffectView.isHidden=true
//                                            publicVar.isInLargeViewAfterAnimate=false
                                        })
                                    }
                                }
                            }
                        }
                        
                        //因为优先级调度未能预先计算到目标大小时，设置标识
                        var noThumbSizeDueToSchedule = false
                        if thumbSize == nil && otherTaskInfo.isPriorityScheduled {
                            //originalSize = getImageSize(url: URL(string: key.path)!)
                            thumbSize = NSSize(width: 256, height: 256)
                            noThumbSizeDueToSchedule = true
                        }
                        
                        if thumbSize != nil {
                            if i == 0 {
                                let curTime = DispatchTime.now()
                                let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                let timeInterval = Double(nanoTime) / 1_000_000_000
                                log("第一张图片开始载入耗时: \(timeInterval) seconds")
                            }
                            
                            var revisedSize = NSSize(width: thumbSize!.width-2*publicVar.profile.ThumbnailBorderThickness, height: thumbSize!.height-2*publicVar.profile.ThumbnailBorderThickness-publicVar.profile.ThumbnailFilenamePadding)
                            if publicVar.profile.layoutType == .grid {
                                var size = originalSize ?? DEFAULT_SIZE
                                if size.width == 0 || size.height == 0 {size=DEFAULT_SIZE}
                                revisedSize = AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: CGPoint(x: 0, y: 0), size: revisedSize)).size
                            }
                            //log(max(revisedSize.width,revisedSize.height),level: .debug)
                            
                            var imageExist=false
                            loadImageTaskPool.lock.lock()
                            fileDB.lock()
                            if let thumbImage = file.image {
                                imageExist=true
                                //print(revisedSize,thumbImage.size)
                                
                                if (publicVar.isGenHdThumb && !noThumbSizeDueToSchedule) && file.type == .image { //&& publicVar.layoutType != .grid
                                    if thumbImage.size.width != revisedSize.width {
                                        imageExist=false
                                    }
                                }
                                if (!publicVar.isGenHdThumb || noThumbSizeDueToSchedule) && file.type == .image {
                                    let maxLength = max(thumbImage.size.width,thumbImage.size.height)
                                    if maxLength < 256 { // 说明是由targetSize重绘生成的且不够清晰的图（双倍采样），取不取等不重要
                                        imageExist=false
                                    }
                                }
                                if ["gif", "svg", "ai"].contains(file.ext.lowercased()){
                                    imageExist=true //由于无法正常生成指定大小的缩略图
                                }
                            }
                            fileDB.unlock()
                            loadImageTaskPool.lock.unlock()
                            if imageExist == false {
                                //开始缩略图步骤
                                //let fileVer=file.ver//获取缩略图开始之前版本 （注：已经用dirModel的方法）
                                let url=URL(string: key.path)!
                                var image: NSImage? = nil
                                if doNotActualRead{
                                    image = getFileTypeIcon(url: url)
                                }else{
                                    if !publicVar.isGenHdThumb || noThumbSizeDueToSchedule { // publicVar.layoutType == .grid
                                        //image = getImageThumb(url: url, refSize: originalSize)
                                        image = ThumbImageProcessor.getImageCache(url: url, refSize: originalSize, ver: ver)
                                    }else{
                                        //image = getImageThumb(url: url, size: revisedSize)
                                        image = ThumbImageProcessor.getImageCache(url: url, size: revisedSize, ver: ver)
                                    }
                                    if image == nil {
                                        image = getFileTypeIcon(url: url)
                                    }
                                }
                                
                                //目录则请求3个缩略图
                                var folderImages = [NSImage]()
//                                if url.hasDirectoryPath {
//                                    let urls = findImageURLs(in: url, maxDepth: 3, maxImages: 3)
//                                    if urls.count>0 {
//                                        for url in urls {
//                                            if let img=getImageThumb(url: url){
//                                                folderImages.append(img)
//                                            }
//                                        }
//                                    }
//                                }
                                
                                if image != nil {
                                    //注意：可能上面的下一轮执行完毕后才执行后面的代码
                                    DispatchQueue.main.async { [weak self] in
                                        guard let self = self else { return }
                                        
                                        fileDB.lock()
                                        let curFolder=fileDB.curFolder
                                        fileDB.unlock() //内存屏障
                                        
                                        if ver != dirModel.ver {return}
                                        
                                        fileDB.lock()
                                        file.image=image
                                        file.folderImages=folderImages
                                        fileDB.unlock()
                                        //此处必须分开加锁解锁，因为下面这句调用底层会重入锁
                                        if dir == curFolder {
                                            let indexPath = IndexPath(item: i, section: 0)
                                            if let item = collectionView.item(at: indexPath) as? CustomCollectionViewItem{
                                                fileDB.lock()
                                                item.configureWithImage(file,playAnimation:true)
                                                //log(i)
                                                if i == 0 {
                                                    let curTime = DispatchTime.now()
                                                    let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                                    let timeInterval = Double(nanoTime) / 1_000_000_000
                                                    log("第一张图片载入完毕耗时: \(timeInterval) seconds")
                                                }
                                                fileDB.unlock()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                    }else{
                        loadImageTaskPool.lock.unlock()
                    }
                }
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let memSizeInGB = getSystemMemorySize()
            while true {
                if willTerminate {break}
                Thread.sleep(forTimeInterval: 2)
                
                let memUse = reportTotalMemoryUsage()
                //let memPhyUse = reportPhyMemoryUsage()
                
                //log("Memory usage: "+String(memUse))
                
                if LRUqueue.count >= 1 {
                    let overTime = (DispatchTime.now().uptimeNanoseconds-LRUqueue.last!.1.uptimeNanoseconds)/1000000000
                    let memUseLimit = globalVar.memUseLimit
                    
                    fileDB.lock()
                    let curFolder=fileDB.curFolder
                    let curFolderFileCount = fileDB.db[SortKeyDir(curFolder)]!.fileCount
                    fileDB.unlock()
                    
                    var totalCount = 0
                    for (_,_,count) in LRUqueue {
                        totalCount += count
                    }
                    
                    var ifCantDetectMemUse = false
                    if #available(macOS 15, *) {
                        //有时在macos 15上观察到，图片占用的内存变成了与WindowServer的共享内存，此时无法直接获取大小
                        ifCantDetectMemUse = totalCount > memUseLimit * 2
                    }
                    
                    if (overTime > 600 && LRUqueue.count >= 2) || (Int(memUse) > memUseLimit) {
                        log("Memory free:")
                        log(LRUqueue.last!.0.removingPercentEncoding)
                        //由于先置目录再请求缩略图，所以此处可保证安全
                        
                        if(LRUqueue.last!.0 != fileDB.curFolder){
                            //不是当前目录
                            fileDB.lock()
                            fileDB.db[SortKeyDir(LRUqueue.last!.0)]!.isMemClearedToAvoidRemainingTask=true
                            for fileModel in fileDB.db[SortKeyDir(LRUqueue.last!.0)]!.files {
                                fileModel.1.image=nil
                                fileModel.1.folderImages=[NSImage]()
                            }
                            LRUqueue.removeLast()
                            fileDB.unlock()
                        }else{
                            //是当前目录
                            let visibleIndexPaths=collectionView.indexPathsForVisibleItems()
                            var itemArray: [Int] = visibleIndexPaths.map { $0.item }
                            itemArray.sort()
                            let indexMin = (itemArray.first ?? 0) - PRELOAD_THUMB_RANGE_PRE
                            let indexMax = (itemArray.last ?? 0) + PRELOAD_THUMB_RANGE_NEXT
                            
                            fileDB.lock()
                            fileDB.db[SortKeyDir(LRUqueue.last!.0)]!.isMemClearedToAvoidRemainingTask=true
                            for fileModel in fileDB.db[SortKeyDir(LRUqueue.last!.0)]!.files {
                                if fileModel.1.id < indexMin || fileModel.1.id > indexMax {
                                    fileModel.1.image=nil
                                    fileModel.1.folderImages=[NSImage]()
                                }
                            }
                            fileDB.unlock()
                        }
                        
                    }
                }
                
            }
            
        }
        
        if isDeveloper {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                while true {
                    if willTerminate {break}
                    Thread.sleep(forTimeInterval: 0.2)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        checkConsistencyAssert()
                    }
                }
            }
        }
        
    }
    func LRUMemRecord(path: String, count: Int){
        fileDB.lock()
        var index: Int?
        if LRUqueue.count > 0 {
            //之前队首的最后访问时间记录为当前时间
            LRUqueue[0].1=DispatchTime.now()
            //查找队列中是否有path
            for (i,(lruPath,_,_)) in LRUqueue.enumerated() {
                if lruPath == path {
                    index=i
                    break
                }
            }
        }
        
        if index != nil {
            LRUqueue.remove(at: index!)
        }
        LRUqueue.insert((path,DispatchTime.now(),count), at: 0)
        fileDB.unlock()
    }
    func reportPhyMemoryUsage() -> Double {
        let task = mach_task_self_
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / 1024 / 1024
            return usedMemoryMB
        } else {
            return 0
        }
    }
    func reportTotalMemoryUsage() -> Double {
        let task = mach_task_self_
        var info = task_vm_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemoryMB = Double(info.phys_footprint) / 1024 / 1024
            return usedMemoryMB
        } else {
            return 0
        }
    }
    func getSystemMemorySize() -> Double {
        var size: UInt64 = 0
        var sizeOfSize = MemoryLayout<UInt64>.size
        
        let result = sysctlbyname("hw.memsize", &size, &sizeOfSize, nil, 0)
        
        if result == 0 {
            return Double(size) / 1024 / 1024 / 1024
        } else {
            return 0
        }
    }

    var scrollDebounceWorkItem: DispatchWorkItem?
    
    @objc func scrollViewDidScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else { return }
        // 确保是针对我们感兴趣的ScrollView（如果有多个ScrollView）
        if scrollView == collectionView.enclosingScrollView {

            if publicVar.timer.intervalSafe(name: "scrollViewDidScrollSetLoadThumbPriority", second: 0.1) {
                setLoadThumbPriority(ifNeedVisable: true)
            }
            
            scrollDebounceWorkItem?.cancel()
            scrollDebounceWorkItem = DispatchWorkItem {
                DispatchQueue.main.async { [weak self] in
                    self?.setLoadThumbPriority(ifNeedVisable: true)
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: scrollDebounceWorkItem!)
        }
    }
    
    @objc func scrollViewScrollEnd(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else { return }
        // 确保是针对我们感兴趣的ScrollView（如果有多个ScrollView）
        if scrollView == collectionView.enclosingScrollView {
            setLoadThumbPriority(ifNeedVisable: true)
        }
    }

    func setLoadThumbPriority(indexPath: IndexPath? = nil, range: (Int,Int) = (-20,20), ifNeedVisable: Bool){

        var indexPaths: Set<IndexPath> = Set()
        if indexPath != nil {
            indexPaths=nearbyIndexPaths(around: [indexPath!], range: range, needValid: false)
        }else{
            indexPaths=collectionView.indexPathsForVisibleItems()
        }
        
        if ifNeedVisable {
            let visibleRectRaw = mainScrollView.contentView.visibleRect
            let scrollPos = visibleRectRaw.origin
            let scrollWidth = visibleRectRaw.width
            let scrollHeight = visibleRectRaw.height
            let visibleRect = NSRect(origin: scrollPos, size: CGSize(width: scrollWidth, height: scrollHeight*2)) //注意这里乘了2
            indexPaths = indexPaths.filter { indexPath in
                let itemFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
                return itemFrame.intersects(visibleRect)
            }
        }
        
        
        var itemSorted = [Int]()
        for tmp in indexPaths{
            itemSorted.append(tmp.item)
        }
        itemSorted.sort()
        
        if(itemSorted.count>0){
            
            let originalMin=itemSorted.first!
            let originalMax=itemSorted.last!

            //序号最大最小值
            let itemIndexMin=max(itemSorted.first! - PRELOAD_THUMB_RANGE_PRE, 0)
            let itemIndexMax=itemSorted.last! + PRELOAD_THUMB_RANGE_NEXT
            
            if itemIndexMin >= itemIndexMax {return}
            
            var newRange = Array((itemIndexMin...itemIndexMax).reversed())
            if let centerPos=indexPath?.item{
                newRange.sort(){
                    let x = Double($0-centerPos)
                    let y = Double($1-centerPos)
                    return (x > 0 ? x/2 : -x) > (y > 0 ? y/2 : -y)
                }
            }else{
                let centerPos=(originalMin+originalMax)/2
                newRange.sort(){
                    let x = Double($0-centerPos)
                    let y = Double($1-centerPos)
                    var xIsVisible = false
                    var yIsVisible = false
                    if $0 >= originalMin && $0 <= originalMax {xIsVisible=true}
                    if $1 >= originalMin && $1 <= originalMax {yIsVisible=true}
                    if xIsVisible && yIsVisible {
                        return x > y
                    }else if xIsVisible && !yIsVisible {
                        return false
                    }else if !xIsVisible && yIsVisible {
                        return true
                    }else{
                        return (x > 0 ? x/2 : -x) > (y > 0 ? y/2 : -y)
                    }
                }
            }
            
            loadImageTaskPool.lock.lock()
            fileDB.lock()
            let curFolder=fileDB.curFolder
            loadImageTaskPool.makeQueue(curFolder)
            for itemIndex in newRange {
                if let dirModel = fileDB.db[SortKeyDir(curFolder)],
                   let key = dirModel.files.elementSafe(atOffset: itemIndex)?.0,
                   let file = dirModel.files.elementSafe(atOffset: itemIndex)?.1,
                   file.image == nil {
                    loadImageTaskPool.pool[curFolder]?.insert((curFolder,dirModel,key,file,dirModel.ver,OtherTaskInfo(isFromScroll: true, isPriorityScheduled: true)), at: 0)
                    loadImageTaskPoolSemaphore.signal()
                }
            }
            fileDB.unlock()
            loadImageTaskPool.lock.unlock()
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
        
        //继续自动滚动
        isAutoScrollPaused = false
        
        //停止自动播放
        stopAutoPlay()
        
        //隐藏首次使用提示
        coreAreaView.hideInfo()
        globalVar.isFirstTimeUse = false
        UserDefaults.standard.set(false, forKey: "isFirstTimeUse")
        
        //复原旋转
        largeImageView.file.rotate=0
        
        //取消OCR
        largeImageView.unSetOcr()
        
        //需要在reloadData前取消选择，否则不会调用相关函数
        collectionView.deselectAll(nil)
        
        if globalVar.portableMode {//便携模式下不使用动画，因为反倒有两次变化
            largeImageView.alphaValue = 0
            largeImageBgEffectView.alphaValue = 0
            self.largeImageView.isHidden=true
            self.largeImageBgEffectView.isHidden=true
            self.publicVar.isInLargeViewAfterAnimate=false
        }else{
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = OPEN_LARGEIMAGE_DURATION
                largeImageView.animator().alphaValue = 0
                largeImageBgEffectView.animator().alphaValue = 0
            }, completionHandler: {
                self.largeImageView.isHidden=true
                self.largeImageBgEffectView.isHidden=true
                self.publicVar.isInLargeViewAfterAnimate=false
            })
        }
        publicVar.isLeftMouseDown = false //防止某些情况下此状态未重置，导致再打开大图时直接会滚动缩放
        publicVar.isRightMouseDown = false
        largeImageView.longPressZoomTimer?.invalidate()
        largeImageView.longPressZoomTimer = nil
        
        //注意，由于被选中的外观取决于这个状态，因此要先置状态再选择
        //另外，修改此值会触发重布局
        publicVar.isInLargeView=false
        //view.window?.layoutIfNeeded() 修改时已经调用

            
//        let visibleRect = mainScrollView.contentView.visibleRect
//        let itemFrame = collectionView.layoutAttributesForItem(at: IndexPath(item: currLargeImagePos, section: 0))?.frame ?? .zero
//        
//        //判断缩略图是否全部可见
//        if visibleRect.contains(itemFrame) == false {
//            //奇怪问题：用finder从manys末尾打开一个关闭，再用finder打开它的前一个再关闭（后一个不行），列表会为空，需要鼠标滚轮滚动几下才能显示
//            //reloadData可避免，不管是在滚动前、后，都可以
//            collectionView.reloadData()
//            
//            //在后面再统一滚动，考虑到即使图没变，但是窗口大小改变导致被选中对象不在视野
//            //collectionView.scrollToItems(at: [IndexPath(item: currLargeImagePos, section: 0)], scrollPosition: .nearestHorizontalEdge)
//            
//            //collectionView.reloadData()
//            //setVisableItemPriority(indexPath: IndexPath(item: currLargeImagePos, section: 0))
//            
//        }


//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//
//            //滚动到选中项目
//            collectionView.scrollToItems(at: [IndexPath(item: currLargeImagePos, section: 0)], scrollPosition: .nearestHorizontalEdge)
//            setVisableItemPriority(indexPath: IndexPath(item: currLargeImagePos, section: 0))
//
//            //选中新项目
//            let indexPath=IndexPath(item: currLargeImagePos, section: 0)
//            //此处加if是因为前面说的从finder二次打开时，如果滚动到目标位置后collectionView显示是空的（目标位置附近对象未被创建），此时对象不存在不能调用选中函数
//            if let _ = collectionView.item(at: indexPath) as? CustomCollectionViewItem{
//                collectionView.selectItems(at: [indexPath], scrollPosition: [])
//                //collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
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
            collectionView.selectItems(at: [indexPath], scrollPosition: [])
            collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
            setLoadThumbPriority(indexPath: IndexPath(item: currLargeImagePos, section: 0), ifNeedVisable: false)
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
            
            //取消OCR
            largeImageView.unSetOcr()
            
            if(url.hasDirectoryPath){
                switchDirByDirection(direction: .zero, dest: item.file.path, stackDeep: 0)
            }
            else if !globalVar.HandledImageExtensions.contains(url.pathExtension.lowercased()) {
                NSWorkspace.shared.open(url)
            }else{
                if largeImageView.isHidden {
                    
                    //暂停自动滚动
                    isAutoScrollPaused = true
                    
                    //显示首次使用提示
                    if globalVar.isFirstTimeUse{
                        coreAreaView.showInfo(NSLocalizedString("first-time-use-prompt", comment: "首次使用提示..."), timeOut: .infinity, cannotBeCleard: false)
                    }
                    
                    currLargeImagePos=indexPath.item
                    initLargeImagePos=indexPath.item
                    lastDoNotGenResized=false
                    changeLargeImage(justChangeLargeImageViewFile: globalVar.portableMode)
                    largeImageView.isHidden=false
                    largeImageBgEffectView.isHidden=false
                    publicVar.isInLargeView=true
                    
                    if globalVar.portableMode {//便携模式下不使用动画，因为反倒有两次变化
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
                    
                    //setWindowTitleOfLargeImage(file: item.file)
                    
                    //选中打开的项目
                    collectionView.deselectAll(nil)
                    let indexPath=IndexPath(item: currLargeImagePos, section: 0)
                    collectionView.selectItems(at: [indexPath], scrollPosition: [])
                    collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])

                }
            }
        }
    }
    
    func deselectAll(){
        collectionView.deselectAll(nil)
    }
    
    private var cumulativeScroll: CGFloat = 0 //累积滚动量
    private var lastScrollSwitchLargeImageTime: TimeInterval = 0
    
    func handleScrollWheel(_ event: NSEvent) {
        //log("触控板:",event.scrollingDeltaY,event.scrollingDeltaX)
        //log("滚轮的:",event.deltaY)
        
        if largeImageView.isHidden {return}
        if event.momentumPhase == .changed
            && event.timestamp - lastScrollSwitchLargeImageTime > 0.2
        {
            return
        }
        
        //以下是防止按住鼠标缩放后松开，滚轮惯性滚动造成切换
        if publicVar.isRightMouseDown || publicVar.isLeftMouseDown {
            _ = publicVar.timer.intervalSafe(name: "largeImageZoomForbidSwitch", second: -1)
            return
        }
        if !publicVar.timer.intervalSafe(name: "largeImageZoomForbidSwitch", second: 0.4, execute: false){
            _ = publicVar.timer.intervalSafe(name: "largeImageZoomForbidSwitch", second: -1)
            return
        }

        var deltaY=0.0
        if abs(event.scrollingDeltaY)+abs(event.scrollingDeltaX) > abs(event.deltaY) {
            //通常是触控板事件
            var sign = 1.0
            var absv = 1.0
            if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
                sign = event.scrollingDeltaY >= 0 ? 1.0 : -1.0
                absv=abs(event.scrollingDeltaY)
            }else{
                sign = event.scrollingDeltaX >= 0 ? 1.0 : -1.0
                absv=abs(event.scrollingDeltaX)
            }
            if absv == 1.0 {absv=0.1}
            deltaY=sign*pow(absv,1.0/1.4)/3
        }else{
            //通常是滚轮事件
            deltaY=event.deltaY
            //没有使用LineMouse时
            if abs(deltaY) < 1.5 {
                deltaY = 1.5 * deltaY / abs(deltaY)
            }
        }
        cumulativeScroll += deltaY
        
        if abs(cumulativeScroll)<1.4 {return}
        if publicVar.timer.intervalSafe(name: "scrollLargeImage", second: 0.8/pow(abs(cumulativeScroll),1.0/1.0)) != true {
            cumulativeScroll=0
            return
        }

        if cumulativeScroll > 0 {
            // 向上滚动
            previousLargeImage()
        } else if cumulativeScroll < 0 {
            // 向下滚动
            nextLargeImage()
        }
        cumulativeScroll=0
        lastScrollSwitchLargeImageTime=event.timestamp
    }
    
    func previousLargeImage(isShowReachEndPrompt: Bool = true){
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
        while nextLargeImagePos >= 0 {
            nextLargeImagePos-=1
            if fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1.type == .image {
                ifFoundNextImage=true
                break
            }
        }
        fileDB.unlock()
        
        if ifFoundNextImage {
            //复原旋转
            largeImageView.file.rotate=0
            
            currLargeImagePos=nextLargeImagePos
            lastDoNotGenResized=false
            
            //取消OCR
            largeImageView.unSetOcr()
            
            if globalVar.portableMode {
                fileDB.lock()
                let refSize = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1.originalSize
                fileDB.unlock()
                adjustWindowPortable(refSize: refSize, firstShowThumb: true, animate: false)
            }else{
                changeLargeImage()
            }
            
            //选中新的项目
            collectionView.deselectAll(nil)
            if currLargeImagePos < collectionView.numberOfItems(inSection: 0) {
                let indexPath=IndexPath(item: currLargeImagePos, section: 0)
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
                collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
            }
        }else if isShowReachEndPrompt {
            largeImageView.showInfo(NSLocalizedString("already-first", comment: "已经是第一张图片"))
        }
    }
    
    func nextLargeImage(isShowReachEndPrompt: Bool = true){
        //log(currLargeImagePos)
        if largeImageView.isHidden {return}
        if publicVar.openFromFinderPath != "" {return}
        if currLargeImagePos == -1 {
            return
        }
        
        fileDB.lock()
        let curFolder=fileDB.curFolder
        let totalCount = fileDB.db[SortKeyDir(curFolder)]!.files.count
        //let fileCount = fileDB.db[SortKeyDir(curFolder)]!.fileCount
        var nextLargeImagePos=currLargeImagePos
        var ifFoundNextImage=false
        while nextLargeImagePos < totalCount-1 {
            nextLargeImagePos+=1
            if fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1.type == .image {
                ifFoundNextImage=true
                break
            }
        }
        fileDB.unlock()
        
        if ifFoundNextImage {
            //复原旋转
            largeImageView.file.rotate=0
            
            currLargeImagePos=nextLargeImagePos
            lastDoNotGenResized=false
            
            //取消OCR
            largeImageView.unSetOcr()
            
            if globalVar.portableMode {
                fileDB.lock()
                let refSize = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1.originalSize
                fileDB.unlock()
                adjustWindowPortable(refSize: refSize, firstShowThumb: true, animate: false)
            }else{
                changeLargeImage()
            }
            
            //选中新的项目
            collectionView.deselectAll(nil)
            if currLargeImagePos < collectionView.numberOfItems(inSection: 0) {
                let indexPath=IndexPath(item: currLargeImagePos, section: 0)
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
                collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
            }
        }else if isShowReachEndPrompt {
            largeImageView.showInfo(NSLocalizedString("already-last", comment: "已经是最后一张图片"))
        }
    }
    
    func getCurrentImageOriginalSizeInScreenScale() -> NSSize? {
        let pos=currLargeImagePos
        var result: NSSize?
        fileDB.lock()
        if let file=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: pos)?.1{
            fileDB.unlock()
            if let originalSize=file.originalSize{
                //判断是否Retina，NSScreen.main是当前具有键盘焦点的屏幕，通常是用户正在与之交互的屏幕
                let scale = NSScreen.main?.backingScaleFactor ?? 1
                result=NSSize(width: originalSize.width/scale, height: originalSize.height/scale)
                if file.rotate%2 == 1 {
                    result=NSSize(width: originalSize.height/scale, height: originalSize.width/scale)
                }
            }
        }else{
            fileDB.unlock()
        }
        return result
    }
    
    func setWindowTitleOfLargeImage(file: FileModel){
        let url=URL(string:file.path)!
        var fullTitle=url.lastPathComponent
        //fullTitle += " | " + readableFileSize(file.fileSize ?? 0)
        if file.originalSize != nil {
            if file.originalSize!.width != 0 {
                //fullTitle += " | " + String(format: "%.0f", file.originalSize!.width) + " × " + String(format: "%.0f", file.originalSize!.height)
            }
        }
        
        fileDB.lock()
        let folderPath=fileDB.curFolder
        let imageCount=fileDB.db[SortKeyDir(folderPath)]?.imageCount ?? 0
        if imageCount != 0{
            if let idInImage=fileDB.db[SortKeyDir(folderPath)]?.files[SortKeyFile(file.path, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst)]?.idInImage {
                //fullTitle += " | " + String(format: "(%d/%d)",idInImage+1,imageCount)
                fullTitle += " " + String(format: "(%d/%d)",idInImage+1,imageCount)
                publicVar.lastLargeImageIdInImage=idInImage
            }
        }
        fileDB.unlock()
        
        let shortTitle = (file.path as NSString).lastPathComponent.removingPercentEncoding!
        view.window?.title = shortTitle
        publicVar.fullTitle = fullTitle
        //publicVar.fullTitle = shortTitle
        if let windowController = view.window?.windowController as? WindowController {
            windowController.updateToolbar()
        }
    }
    
    func OpenLargeImageFromFinder(path: String){
        currLargeImagePos = -1
        initLargeImagePos = -1
        
        lastDoNotGenResized=false
        changeLargeImage(justChangeLargeImageViewFile: globalVar.portableMode)
        largeImageView.isHidden=false
        largeImageBgEffectView.isHidden=false
        publicVar.isInLargeView=true
        publicVar.isInLargeViewAfterAnimate=true
        largeImageView.alphaValue = 1
        largeImageBgEffectView.alphaValue = 1
        
        
        //setWindowTitleOfLargeImage(file: item.file)
    }
    
    func preloadLargeImage(){
        //if !publicVar.isInLargeView {return} //由于第一次打开的顺序问题，此处不能作判断
        if publicVar.openFromFinderPath != "" {return}
        if currLargeImagePos == -1 {
            return
        }

        fileDB.lock()
        let curFolder=fileDB.curFolder
        let totalCount = fileDB.db[SortKeyDir(curFolder)]!.files.count
        fileDB.unlock()
        guard let path = fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: currLargeImagePos)?.1.path,
              let url = URL(string: path)
        else{ return }
        
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

        do{ // 后面的图像
            fileDB.lock()
            var nextLargeImagePos=currLargeImagePos
            var loadCount=0
            while nextLargeImagePos < totalCount-1 {
                nextLargeImagePos += 1
                if let file=fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1,
                   file.type == .image{
                    loadCount += 1
                    if loadCount > preloadNumNext { break } // 预载入数量
                    fileQueue.append((file, Double(loadCount)-0.5))
                }
            }
            fileDB.unlock()
        }
        
        do{ // 前面的图像
            fileDB.lock()
            var nextLargeImagePos=currLargeImagePos
            var loadCount=0
            while nextLargeImagePos >= 0 {
                nextLargeImagePos -= 1
                if let file=fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: nextLargeImagePos)?.1,
                   file.type == .image{
                    loadCount += 1
                    if loadCount > preloadNumPrevious { break } // 预载入数量
                    fileQueue.append((file, Double(loadCount)))
                }
            }
            fileDB.unlock()
        }
        
        do{ // 当前图像
            if let file=fileDB.db[SortKeyDir(curFolder)]!.files.elementSafe(atOffset: currLargeImagePos)?.1,
               file.type == .image{
                fileQueue.append((file, 0))
            }
        }
        
        fileQueue.sort { $0.1 > $1.1 }
        
        fileDB.lock()
        for (file,priority) in fileQueue {
            preloadLargeImageForFile(file: file, priority: priority)
        }
        fileDB.unlock()

    }
    
    func preloadLargeImageForFile(file: FileModel, priority: Double){

        let url=URL(string:file.path)!
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let maxBounds=largeImageView.bounds
        //print(maxBounds)
        
        var largeSize: NSSize
        var originalSize: NSSize? = file.originalSize
        
        //当文件被修改，列表重新读取但大小还没来得及获取时可能为空，此时需要获取一下
        //或者由于外置卷，使用的默认大小 || VolumeManager.shared.isExternalVolume(url)
        if originalSize == nil {
            originalSize = getImageSize(url: url)
            if originalSize == nil {
                originalSize = DEFAULT_SIZE
                file.isGetImageSizeFail = true
            }else{
                file.isGetImageSizeFail = false
            }
        }
        
        if let originalSize=originalSize{
            
            //计算宽高
            if originalSize.height/originalSize.width*maxBounds.width > maxBounds.height {
                largeSize=NSSize(width: originalSize.width/originalSize.height*maxBounds.height, height: maxBounds.height)
            }else{
                largeSize=NSSize(width: maxBounds.width, height: originalSize.height/originalSize.width*maxBounds.width)
            }
            
            //当原图实际大小小于视图大小时，按实际大小显示
            if !publicVar.isLargeImageFitWindow && originalSize.width<largeSize.width*scale {
                largeSize=NSSize(width: originalSize.width/scale, height: originalSize.height/scale)
            }
            
            //不进行过大缩放，内存炸了
            var doNotGenResized=false
            if largeSize.width*scale>=originalSize.width && largeSize.height*scale>=originalSize.height {
                doNotGenResized=true
            }
            
            //使用原图的格式
            if ["gif", "svg", "ai"].contains(url.pathExtension.lowercased()){
                doNotGenResized=true
            }

            DispatchQueue.global(qos: .userInitiated).async {
                _ = LargeImageProcessor.getImageCache(url: url, size: largeSize, rotate: 0, useOriginalImage: doNotGenResized, needWaitWhenSame: false)
            }
            
        }
    }
    
    func changeLargeImage(firstShowThumb: Bool = true, resetSize: Bool = true, triggeredByLongPress: Bool = false, justChangeLargeImageViewFile: Bool = false){
        let pos=currLargeImagePos
        var file=FileModel(path: "", ver: 0)
        var isThisFromFinder=false
        if publicVar.openFromFinderPath != "" {
            let url = URL(string: publicVar.openFromFinderPath)!
            file=FileModel(path: publicVar.openFromFinderPath, ver: 0)
            file.originalSize=getImageSize(url: url)
            if !justChangeLargeImageViewFile {
                file.image = getImageThumb(url: url, refSize: file.originalSize) // 获取缩略图（以加快响应）
            }
            if file.originalSize == nil {
                file.originalSize = DEFAULT_SIZE
                file.isGetImageSizeFail = true
            }
            file.fileSize=Int(getFileSize(atPath: publicVar.openFromFinderPath.replacingOccurrences(of: "file://", with: "")))
            //log(file.fileSize)
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
                preloadLargeImage()
            }
        }
        
        largeImageView.file=file
        
        if justChangeLargeImageViewFile {return}
        
        setWindowTitleOfLargeImage(file: file)
            
        let url=URL(string:file.path)!
        
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        
        var maxBounds=largeImageView.imageView.bounds
        if resetSize{maxBounds=largeImageView.bounds}
        
        log("largeImageView.imageView",largeImageView.imageView.bounds)
        log("largeImageView",largeImageView.bounds)
        
        var largeSize: NSSize
        var originalSize: NSSize? = file.originalSize
        var rotate = file.rotate

        //当文件被修改，列表重新读取但大小还没来得及获取时可能为空，此时需要获取一下
        //或者由于外置卷，使用的默认大小 || VolumeManager.shared.isExternalVolume(url)
        if originalSize == nil {
            originalSize = getImageSize(url: url)
            if originalSize == nil {
                originalSize = DEFAULT_SIZE
                file.isGetImageSizeFail = true
            }else{
                file.isGetImageSizeFail = false
            }
        }
        
        if var originalSize=originalSize{
            
            //判断旋转
            if rotate%2 == 1 {
                originalSize=NSSize(width: originalSize.height, height: originalSize.width)
            }
            
            //if let originalSize=getCurrentImageOriginalSize(){
            if originalSize.height/originalSize.width*maxBounds.width > maxBounds.height {
                largeSize=NSSize(width: originalSize.width/originalSize.height*maxBounds.height, height: maxBounds.height)
            }else{
                largeSize=NSSize(width: maxBounds.width, height: originalSize.height/originalSize.width*maxBounds.width)
            }
            
            //当原图实际大小小于视图大小时，按实际大小显示
            if !publicVar.isLargeImageFitWindow && originalSize.width<largeSize.width*scale && !triggeredByLongPress {
                largeSize=NSSize(width: originalSize.width/scale, height: originalSize.height/scale)
            }
            
            if resetSize{
                let rectView=largeImageView.frame
                let rectImage=NSRect(origin: CGPoint(x: (rectView.width-largeSize.width)/2, y: (rectView.height-largeSize.height)/2), size: largeSize)
                largeImageView.imageView.frame=rectImage
            }
            
            //不进行过大缩放，内存炸了
            var doNotGenResized=false
            if largeSize.width*scale>=originalSize.width && largeSize.height*scale>=originalSize.height {
                doNotGenResized=true
            }
            
            //使用原图的格式
            if ["gif", "svg", "ai"].contains(url.pathExtension.lowercased()){
                doNotGenResized=true
            }
            
            //但如果是旋转，还是缩放占用更小
            if rotate != 0 {
                doNotGenResized=false
            }
            log("ori:",originalSize.width,originalSize.height)
            log("dest:",largeSize.width,largeSize.height)
            
            //若上次已经用了原图，这次还用原图，则不重新载入
            if lastDoNotGenResized && doNotGenResized && lastLargeImageRotate == rotate {return}
            lastDoNotGenResized=doNotGenResized
            lastLargeImageRotate=rotate
            
            //检查是否有大图缓存
            let preGetImageCache = LargeImageProcessor.isImageCachedAndGet(url: url, size: largeSize, rotate: rotate)
            let isImageCached = preGetImageCache != nil
            
            //先显示小图
            if firstShowThumb && !isImageCached {
                largeImageView.imageView.image=file.image?.rotated(by: CGFloat(-90*rotate))
            }
            
            //有大图缓存则直接载入
            if isImageCached {
                log("命中缓存:",url.absoluteString.removingPercentEncoding!)
                largeImageView.imageView.image=preGetImageCache
            }else{
                log("即时载入:",url.absoluteString.removingPercentEncoding!)
            }
            
            //显示窗口
            if let windowController = self.view.window?.windowController,
               let window = windowController.window,
               !window.isVisible {
                windowController.showWindow(nil)
            }
            globalVar.useCreateWindowShowDelay = false
            
            //加载Exif
            if publicVar.isShowExif && resetSize {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    if pos != currLargeImagePos && !isThisFromFinder {return}
                    
                    let exifData = formatExifData(getExifData(from: url) ?? [:])
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if pos != currLargeImagePos && !isThisFromFinder {return}
                        
                        largeImageView.updateTextItems(exifData)
                    }
                }
            }
            
            if isImageCached {
                return
            }
            
            //用来对比异步任务是否过期
            largeImageView.file.largeSize = largeSize
            
            //开始加载大图
            largeImageLoadTask?.cancel()
            
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
                
                //按实际目标分辨率绘制效果较差，观察到1080P屏幕双倍插值后绘制与直接使用原图效果才类似，因此即使scale==1，此处size也不除以2
                var largeImage: NSImage?
                if resetSize {
                    largeImage=LargeImageProcessor.getImageCache(url: url, size: largeSize, rotate: rotate, useOriginalImage: doNotGenResized)
                }else{
                    if doNotGenResized {
                        largeImage = NSImage(contentsOf: url)?.rotated(by: CGFloat(-90*rotate))
                    }else{
                        largeImage = getResizedImage(url: url, size: largeSize, rotate: rotate)
                        if largeImage == nil {
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
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if pos != currLargeImagePos && !isThisFromFinder {return}
                        if rotate != largeImageView.file.rotate {return}
                        if largeImageView.file.largeSize != nil && largeSize != largeImageView.file.largeSize {return}
                        largeImageView.imageView.image=largeImage
                        //log("replaced")
                    }
                }
            }
            // 保存新的任务
            largeImageLoadTask = task
            
            // 在全局队列上异步执行新的任务
            DispatchQueue.global(qos: .userInitiated).async(execute: task!)
        }
        
        
    }

    func startWatchingDirectory(atPath path: String) {
        watchFileDescriptor = open(path, O_EVTONLY)
        guard watchFileDescriptor != -1 else {
            log("Failed to open directory, errno: \(errno)")
            return
        }
        
        let queue = DispatchQueue.global()
        watchDispatchSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: watchFileDescriptor, eventMask: [.write,.link,.delete,.rename], queue: queue)
        watchDispatchSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            // 打印事件类型
            let event = watchDispatchSource!.data
            //logFileSystemEvent(event)
            
            // 计划刷新
            readInfoTaskPoolLock.lock()
            let isReadInfoFinish = (readInfoTaskPool.count == 0)
            readInfoTaskPoolLock.unlock()
            loadImageTaskPool.lock.lock()
            let isLoadThumbFinish = (loadImageTaskPool.getTaskNum() == 0)
            loadImageTaskPool.lock.unlock()
            let isInProgress = (publicVar.isInStageOneProgress || publicVar.isInStageTwoProgress || publicVar.isInStageThreeProgress
                                || !isReadInfoFinish || !isLoadThumbFinish)
            //log(publicVar.isInStageOneProgress,publicVar.isInStageTwoProgress,publicVar.isInStageThreeProgress,!isReadInfoFinish,!isLoadThumbFinish,level: .debug)
            if VolumeManager.shared.isExternalVolume(path) && isInProgress && publicVar.fileChangedCount == 0 {
                // samba的smb读取时会改变atime，产生write和attrib事件
                //log("ExternalVol FileSystemEvent DoNot Refresh.",level: .debug)
            }else{
                //log("FileSystemEvent Refreshd",level: .debug)
                scheduledRefresh()
            }
            
        }
        
        watchDispatchSource?.setCancelHandler {
            close(self.watchFileDescriptor)
        }
        
        watchDispatchSource?.resume()
    }

    func stopWatchingDirectory() {
        watchDispatchSource?.cancel()
        watchDispatchSource = nil
    }
    
    func scheduledRefresh(){
        publicVar.fileChangedCount = 0
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            folderMonitorTimer?.invalidate()
            folderMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { timer in
                self.refreshAll(needStopAutoScroll: false)
            }
        }
    }
    
    private func logFileSystemEvent(_ event: DispatchSource.FileSystemEvent) {
        if event.contains(.delete) {
            log("File system event: delete")
        }
        if event.contains(.write) {
            log("File system event: write")
        }
        if event.contains(.extend) {
            log("File system event: extend")
        }
        if event.contains(.attrib) {
            log("File system event: attrib")
        }
        if event.contains(.link) {
            log("File system event: link")
        }
        if event.contains(.rename) {
            log("File system event: rename")
        }
        if event.contains(.revoke) {
            log("File system event: revoke")
        }
    }

    enum GestureState {
        case none, oneDirection(GestureDirection), twoDirections(GestureDirection, GestureDirection)
    }
    
    var initialMouseLocation: CGPoint?
    var lastMouseLocation: CGPoint?
    var gestureState: GestureState = .none
    var directionHistory: [GestureDirection] = []
    
    override func rightMouseDown(with event: NSEvent) {
        //publicVar.isRightMouseDown = true
        if !largeImageView.isHidden {return}
        
        initialMouseLocation = event.locationInWindow
        lastMouseLocation = initialMouseLocation
        gestureState = .none
    }

    override func rightMouseDragged(with event: NSEvent) {
        if !largeImageView.isHidden {return}
        if event.locationInWindow.y > self.mainScrollView.bounds.height {
            return
        }
        
        guard let startLocation = initialMouseLocation else { return }
        
        let currentLocation = event.locationInWindow
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y

        // 使用阈值以避免轻微的移动造成的方向改变
        let threshold: CGFloat = 4.0

        let newDirection: GestureDirection?
        if abs(dx) > threshold || abs(dy) > threshold {
            if abs(dx) > abs(dy) {
                newDirection = dx > 0 ? .right : .left
            } else {
                newDirection = dy > 0 ? .up : .down
            }

            if let lastDirection = directionHistory.last {
                if newDirection != lastDirection {
                    directionHistory.append(newDirection!)
                }
            } else {
                directionHistory.append(newDirection!)
            }
        }
        
        initialMouseLocation = currentLocation
        
        analyzeGesture(doAction: false)
    }

    override func rightMouseUp(with event: NSEvent) {
        //publicVar.isRightMouseDown = false
        if !largeImageView.isHidden {return}
        
        analyzeGesture(doAction: true)
        directionHistory.removeAll()
//        drawingView?.containerView.isHidden=true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            drawingView?.containerView.animator().alphaValue = 0
        }, completionHandler: {
            self.drawingView?.containerView.isHidden = true
        })
        
        if event.locationInWindow.y > self.mainScrollView.bounds.height {
            popTitlebarMenu(with: event)
        }
    }

    func analyzeGesture(doAction: Bool) {
        if directionHistory.count > 0 {
//            drawingView?.containerView.isHidden=false
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                drawingView?.containerView.animator().alphaValue = 1
                drawingView?.containerView.animator().isHidden = false
            }, completionHandler: {
            })
        }
        
        if directionHistory.count == 1 {
            handleSingleDirectionGesture(directionHistory.first!, doAction: doAction)
        } else if directionHistory.count == 2 {
            // 可以在这里扩展更复杂的手势分析
            handleMultiDirectionGesture(directionHistory, doAction: doAction)
        } else {
            drawingView?.statusLabel.stringValue=""
        }
        
        
        if !doAction {
            var status=[String]()
            for direction in directionHistory{
                switch direction {
                case .right:
                    status.append("arrow.right.square.fill")
                case .left:
                    status.append("arrow.left.square.fill")
                case .up:
                    status.append("arrow.up.square.fill")
                case .down:
                    status.append("arrow.down.square.fill")
                default:
                    break
                }
            }
            drawingView?.directionLabel.attributedStringValue=attributedStringWithSymbols(status)
        }else{
            drawingView?.directionLabel.attributedStringValue=attributedStringWithSymbols([])
            drawingView?.statusLabel.stringValue=""
        }
    }

    func handleMultiDirectionGesture(_ directions: [GestureDirection], doAction: Bool) {
        if directions.count == 2 {
            //log("Detected two-direction gesture: \(directions[0]) then \(directions[1])")
            handleTwoDirectionsGesture(directions[0],directions[1], doAction: doAction)
        }
    }

    func handleSingleDirectionGesture(_ direction: GestureDirection, doAction: Bool) {
        switch direction {
        case .right:
            //log("Gesture: ➡️")
            if doAction {switchDirByDirection(direction: .right, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-folder", comment: "下一个目录")}
        case .left:
            //log("Gesture: ⬅️")
            if doAction {switchDirByDirection(direction: .left, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-folder", comment: "上一个目录")}
        case .up:
            //log("Gesture: ⬆️")
            if doAction {switchDirByDirection(direction: .up, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("parent-folder", comment: "上级目录")}
        case .down:
            //log("Gesture: ⬇️")
            if doAction {switchDirByDirection(direction: .down, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("back-folder", comment: "返回历史目录")}
        default:
            break
        }
    }

    func handleTwoDirectionsGesture(_ first: GestureDirection, _ second: GestureDirection, doAction: Bool) {
        switch (first, second) {
        case (.up, .right):
            //log("Gesture: ⬆️ ➡️")
            //if doAction {switchDirByDirection(direction: .up_right, stackDeep: 0)}
            //else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-sibling-of-parent", comment: "上级的平级下一个目录")}
            if doAction {switchDirByDirection(direction: .down_right, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-sibling", comment: "平级的下一个目录")}
        case (.up, .left):
            //log("Gesture: ⬆️ ⬅️")
            //if doAction {switchDirByDirection(direction: .up_left, stackDeep: 0)}
            //else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-sibling-of-parent", comment: "上级的平级上一个目录")}
            if doAction {switchDirByDirection(direction: .down_left, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-sibling", comment: "平级的上一个目录")}
        case (.down, .right):
            //log("Gesture: ⬇️ ➡️")
//            if doAction {switchDirByDirection(direction: .down_right, stackDeep: 0)}
//            else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-sibling", comment: "平级的下一个目录")}
            if doAction {self.view.window?.performClose(nil)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("Close Tab", comment: "关闭标签页")}
//        case (.down, .left):
//            //log("Gesture: ⬇️ ⬅️")
//            if doAction {switchDirByDirection(direction: .down_left, stackDeep: 0)}
//            else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-sibling", comment: "平级的上一个目录")}
        default:
            drawingView?.statusLabel.stringValue=""
            break
        }
    }
    
    func checkConsistencyAssert(){

//        let count1=collectionView.selectionIndexPaths.count
//        let count2=publicVar.selectedUrls2.count
//        if false || count1 != count2 {
//            // 转换为对象序号
//            let selectedIndexes = collectionView.selectionIndexPaths.map { indexPath in
//                return indexPath.item
//            }
//            var urls = [String]()
//            fileDB.lock()
//            for i in selectedIndexes {
//                if i < fileDB.db[SortKeyDir(fileDB.curFolder)]!.files.count {
//                    urls.append(fileDB.db[SortKeyDir(fileDB.curFolder)]!.files.elementSafe(atOffset: i).1.path.removingPercentEncoding!)
//                }
//            }
//            fileDB.unlock()
//            if isDeveloper{
//                showAlert(message: "collectionView.selectionIndexPaths:"+urls.joined(separator: ",")+"\n\n\nselectedUrls:"+publicVar.selectedUrls2.map { $0.absoluteString.removingPercentEncoding! }.joined(separator: ","))
//            }else{
//                fatalError("Inconsistent. selectedUrls=\(count1). selectionIndexPaths=\(count2)")
//            }
//        }
        
    }
    
    func getSelectedURLs() -> [URL] {
        var selectedIndexes = collectionView.selectionIndexPaths.map { indexPath in
            return indexPath.item
        }
        selectedIndexes.sort()
        var urls = [URL]()
        fileDB.lock()
        for i in selectedIndexes {
            if i < fileDB.db[SortKeyDir(fileDB.curFolder)]!.files.count {
                if let file=fileDB.db[SortKeyDir(fileDB.curFolder)]!.files.elementSafe(atOffset: i)?.1{
                    urls.append(URL(string: file.path)!)
                }
            }
        }
        fileDB.unlock()
        return urls
    }
    
    func popTitlebarMenu(with event: NSEvent) {
        
        return; // TODO
        
        if globalVar.windowNum <= 1 {return}
        
        let menu = NSMenu()
        
//        let closeTab = menu.addItem(withTitle: NSLocalizedString("Close Tab", comment: "关闭标签页"), action: #selector(closeTabAction(_:)), keyEquivalent: "")
//        closeTab.target = self
//        
//        let closeOtherTabs = menu.addItem(withTitle: NSLocalizedString("Close Other Tabs", comment: "关闭其它标签页"), action: #selector(closeOtherTabsAction(_:)), keyEquivalent: "")
//        closeOtherTabs.target = self
        
        let mergeAllWindows = menu.addItem(withTitle: NSLocalizedString("Merge All Windows", comment: "合并所有窗口"), action: #selector(mergeAllWindowsAction(_:)), keyEquivalent: "")
        mergeAllWindows.target = self
        
        NSMenu.popUpContextMenu(menu, with: event, for: self.view)
    }
    
    @objc func closeTabAction(_ sender: NSMenuItem) {
        if let window = NSApp.keyWindow {
            window.performClose(sender)
        }
    }
    
    @objc func closeOtherTabsAction(_ sender: NSMenuItem) {
        if let currentWindow = NSApp.keyWindow {
            for window in NSApp.windows {
                if window != currentWindow {
                    window.performClose(sender)
                }
            }
        }
    }
    
    @objc func mergeAllWindowsAction(_ sender: NSMenuItem) {
        if let window = NSApp.keyWindow {
            window.mergeAllWindows(sender)
        }
    }
    
    func setCollectionViewTooltip(){
        if let visibleItems = collectionView.visibleItems() as? [CustomCollectionViewItem] {
            for item in visibleItems {
                item.setTooltip()
            }
        }
    }
    
    func handleDraggedFiles(_ urls: [URL]) {
        var folderPath="file:///"
        var path="file:///"
        
        let viewController=self
        
        if urls.count == 1 {
            if urls[0].hasDirectoryPath {
                folderPath=""+urls[0].absoluteString
                if viewController.publicVar.isInLargeView {
                    //由于图像关闭有动画，导致大图时瞬间关闭再打开大图会有bug，因此暂时只对目录关闭大图
                    viewController.closeLargeImage(0)
                }
            }else{
                if !globalVar.HandledImageExtensions.contains(urls[0].pathExtension) {return} //限制文件类型
                folderPath=""+urls[0].deletingLastPathComponent().absoluteString
                path=""+urls[0].absoluteString
                viewController.publicVar.openFromFinderPath=path
                viewController.OpenLargeImageFromFinder(path: path)
                
                NSDocumentController.shared.noteNewRecentDocumentURL(urls[0])
            }
        } else if urls.count >= 2 {
            folderPath=""+urls[0].deletingLastPathComponent().absoluteString
        }
        
        viewController.switchDirByDirection(direction: .zero, dest: folderPath, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
        
        for url in urls {
            if url.hasDirectoryPath {
                // 处理文件夹
                log("Dragged folder: \(url.path)")
            } else {
                // 处理文件
                log("Dragged file: \(url.path)")
            }
        }
    }

    var autoScrollTimer: Timer?
    var scrollSpeed: CGFloat = 1.0
    var isAutoScrollPaused: Bool = false
    
    func promptForScrollSpeed(completion: @escaping (CGFloat?) -> Void) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Set Scroll Speed", comment: "设置滚动速度")
        alert.informativeText = NSLocalizedString("Enter the scroll speed in pixels per second:", comment: "输入每秒滚动的像素数：")
        alert.alertStyle = .informational
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.stringValue = "100"
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let text = inputTextField.stringValue
            if let speed = Double(text), speed != 0 {
                completion(CGFloat(speed))
            } else {
                // Handle invalid input
                completion(nil)
            }
        } else {
            completion(nil)
        }
    }
    
    func startContinuousAutoScroll() {
        stopAutoScroll() // Stop any existing timer
        
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.performContinuousScroll()
        }
    }
    
    func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
    
    func performContinuousScroll() {
        guard let scrollView = collectionView.enclosingScrollView, !isAutoScrollPaused else { return }
        
        let currentOrigin = scrollView.contentView.bounds.origin
        let newY = max(0, min(currentOrigin.y + scrollSpeed / 60.0, collectionView.bounds.height - scrollView.contentSize.height))
        let newOrigin = NSPoint(x: currentOrigin.x, y: newY)
        
        scrollView.contentView.scroll(to: newOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    
    func toggleAutoScroll() {
        if autoScrollTimer == nil {
            promptForScrollSpeed { [weak self] speed in
                guard let self = self, let speed = speed else {
                    return
                }
                self.scrollSpeed = speed
                self.isAutoScrollPaused = false
                self.startContinuousAutoScroll()
            }
        } else {
            stopAutoScroll()
        }
    }
    
    func pauseAutoScroll() {
        isAutoScrollPaused = true
    }
    
    func resumeAutoScroll() {
        isAutoScrollPaused = false
    }
    
    func toggleAutoScrollPauseResume(_ sender: Any) {
        if isAutoScrollPaused {
            resumeAutoScroll()
        } else {
            pauseAutoScroll()
        }
    }
    
    var autoPlayTimer: Timer? // 定时器，用于控制自动播放的节奏
    var autoPlayInterval: TimeInterval = 0 // 播放间隔，初始设置为0，用户输入后更新
    var isAutoPlaying: Bool = false // 自动播放是否正在进行的标志

    func startAutoPlay() {
        guard !isAutoPlaying else {return}
        
        promptForAutoPlayInterval()
    }

    func stopAutoPlay() {
        guard isAutoPlaying else {return}
        
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
        isAutoPlaying = false
    }

    func toggleAutoPlay() {
        if isAutoPlaying {
            stopAutoPlay()
        } else {
            startAutoPlay()
        }
    }

    private func promptForAutoPlayInterval() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Set Auto Play Interval", comment: "设置自动播放间隔")
        alert.informativeText = NSLocalizedString("Enter the auto play interval in seconds:", comment: "请输入自动播放的间隔时间（秒）：")
        alert.alertStyle = .informational
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.stringValue = "1"
        alert.accessoryView = inputTextField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let text = inputTextField.stringValue as String?,
               let interval = TimeInterval(text), interval > 0 {
                autoPlayInterval = interval
                isAutoPlaying = true
                scheduleAutoPlay()
            } else {
                showAlert(message: NSLocalizedString("Invalid input, please enter a positive number", comment: "输入不合法，请输入一个正数"))
            }
        }
    }

    private func scheduleAutoPlay() {
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: autoPlayInterval, repeats: true) { [weak self] _ in
            self?.nextLargeImage()
        }
    }

    func configLayoutStyle(newStyle: CustomProfile ,doNotRefresh: Bool = false){
        publicVar.profile.isShowThumbnailFilename = newStyle.isShowThumbnailFilename
        publicVar.profile.ThumbnailBorderThickness = newStyle.ThumbnailBorderThickness
        publicVar.profile.ThumbnailCellPadding = newStyle.ThumbnailCellPadding
        publicVar.profile.ThumbnailBorderRadius = newStyle.ThumbnailBorderRadius
        publicVar.profile.ThumbnailFilenameSize = newStyle.ThumbnailFilenameSize
        
        if publicVar.profile.isShowThumbnailFilename {
            publicVar.profile.ThumbnailFilenamePadding = round(publicVar.profile.ThumbnailFilenameSize*1.3) + 2
        }else{
            publicVar.profile.ThumbnailFilenamePadding = 0
        }
        
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_current")
        
        changeWaterfallLayoutNumberOfColumns()
        if !doNotRefresh {
            refreshCollectionView([], dryRun: true)
        }
    }
    
    func customLayoutStylePrompt (){
        if let mainWindow = NSApplication.shared.mainWindow {
            showThumbnailOptionsPanel(on: mainWindow) { [weak self] isShowFilename, borderThickness, cellPadding, borderRadius, filenameSize in
                guard let self = self else { return }
                
                let newStyle = CustomProfile()
                newStyle.isShowThumbnailFilename = isShowFilename
                newStyle.ThumbnailBorderThickness = borderThickness
                newStyle.ThumbnailCellPadding = cellPadding
                newStyle.ThumbnailBorderRadius = borderRadius
                newStyle.ThumbnailFilenameSize = filenameSize
                
                configLayoutStyle(newStyle: newStyle)
            }
        }
    }
    
    
    //以下是切换自定义配置
    func setCustomProfileTo(_ styleName: String){
        coreAreaView.showInfo(String(format: NSLocalizedString("save-to-custom-profile", comment: "保存到自定义配置"), styleName), timeOut: 1)
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v1_"+styleName)
    }
    
    func useCustomProfile(_ styleName: String){
        coreAreaView.showInfo(String(format: NSLocalizedString("switch-to-custom-profile", comment: "切换至自定义配置"), styleName), timeOut: 1)
        let newStyle = CustomProfile.loadFromUserDefaults(withKey: "CustomStyle_v1_"+styleName)
        
        //布局类型
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
        //边栏
        if newStyle.isDirTreeHidden != publicVar.profile.isDirTreeHidden {
            toggleSidebar()
        }
        //排序
        if newStyle.sortType != publicVar.profile.sortType || newStyle.isSortFolderFirst != publicVar.profile.isSortFolderFirst || newStyle.sortType == .random {
            changeSortType(sortType: newStyle.sortType, isSortFolderFirst: newStyle.isSortFolderFirst, doNotRefresh: true)
        }
        //缩略图大小
        if newStyle.thumbSize != publicVar.profile.thumbSize {
            changeThumbSize(thumbSize: newStyle.thumbSize, doNotRefresh: true)
        }
        //样式
        configLayoutStyle(newStyle: newStyle, doNotRefresh: true)
        
        refreshCollectionView([], dryRun: true)
    }
    
}

