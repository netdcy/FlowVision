//
//  ViewController.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

class CustomProfile: Codable {
    
    // 布局类型
    // Layout type
    var layoutType: LayoutType = .justified
    
    // 侧边栏
    // Sidebar
    var isDirTreeHidden = false
    
    // 排序
    // Sort
    var sortType: SortType = .pathA
    var isSortFolderFirst: Bool = true
    var isSortUseFullPath = true
    
    // 缩略图大小
    // Thumbnail size
    var thumbSize = 512
    
    // 布局（通用）
    // Layout (general)
    var isShowThumbnailFilename = true
    var ThumbnailFilenameSize: Double = 12
    var _thumbnailCellPadding: Double = 5
    var ThumbnailCellPadding: Double {
        get {
            return layoutType == .grid ? _thumbnailCellPadding + 4 : _thumbnailCellPadding
        }
        set {
            abort()
        }
    }
    // 布局（网格视图）
    // Layout (grid view)
    var ThumbnailBorderRadiusInGrid: Double = 0
    // 布局（非网格视图）
    // Layout (non-grid view)
    var ThumbnailBorderRadius: Double = 5
    var _thumbnailBorderThickness: Double = 6
    var ThumbnailBorderThickness: Double {
        get {
            return layoutType == .grid ? 0 : _thumbnailBorderThickness
        }
        set {
            abort()
        }
    }
    var ThumbnailLineSpaceAdjust: Double = 0
    var ThumbnailShowShadow: Bool = false

    // 计算获得
    // Calculated
    var ThumbnailFilenamePadding: Double {
        if isShowThumbnailFilename {
            var tmp = round(ThumbnailFilenameSize*1.3) + 2
            if ThumbnailBorderThickness == 0 {
                tmp += 3
            }
            return tmp
        }else{
            return 0
        }
    }
    var ThumbnailScrollbarWidth: Double {
        return 15
    }

    // 可扩展值
    // Extensible values
    private var dict: [String: String] = [:]

    func getValue(forKey key: String) -> String {
        if dict[key] == nil && key == "isShowThumbnailBadge" {
            return "true"
        }
        if dict[key] == nil && key == "isShowThumbnailTag" {
            return "true"
        }
        if dict[key] == nil && key == "isWindowTitleUseFullPath" {
            return "true"
        }
        if dict[key] == nil && key == "isWindowTitleShowStatistics" {
            return "true"
        }
        if dict[key] == nil && key == "dirTreeSortType" {
            return String(SortType.pathA.rawValue)
        }
        return dict[key]!
    }

    func setValue(forKey key: String, value: String) {
        dict[key] = value
    }
    
    func saveToUserDefaults(withKey key: String) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    static func loadFromUserDefaults(withKey key: String) -> CustomProfile {
        if let savedData = UserDefaults.standard.data(forKey: key) {
            let decoder = JSONDecoder()
            do {
                let loadedStyle = try decoder.decode(CustomProfile.self, from: savedData)
                return loadedStyle
            } catch {
                log("Failed to decode CustomProfile: \(error)")
            }
        }
        // 读取异常时返回默认值
        // Return default value when read exception occurs
        return CustomProfile()
    }
}

class PublicVar{
    weak var refView: NSView!
    weak var viewController: ViewController!

    var isLaunchFromFile = false
    var isLaunchFromFile_changeLargeImage = false
    var randomSeed = Int.random(in: 0...Int.max)
    var isLargeImageFitWindow = true
    var isRecursiveMode = false
    var isRecursiveContainFolder = false
    var isShowHiddenFile = false
    var isShowAllTypeFile = false
    var isShowImageFile = true
    var isShowRawFile = true
    var isShowVideoFile = true
    var isGenHdThumb = false
    var isPreferInternalThumb = false
    var isEnableHDR = true
    var isRawUseEmbeddedThumb = false
    var autoPlayVisibleVideo = false
    var autoPlaySelectedVideo = true
    var isRotationLocked = false
    var rotationLock = 0
    var isZoomLocked = false
    var zoomLock: Double? = nil
    var isPanWhenZoomed = false
    var customZoomRatio: Double = 1.0
    var customZoomStep: Double = 0.1
    var currentTag:String? = nil

    // 可一键切换的配置
    // Configuration that can be switched with one key
    var profile = CustomProfile()
    
    var toolbarTitle = ""
    var titleStatisticInfo = ""
    var isKeyEventEnabled = true
    var folderStepStack = [String]() {
        didSet {updateToolbar()}
    }
    var folderStepForwardStack = [String]()
    var folderStepForLocate = [(String,RightMouseGestureDirection)]()
    var isLeftMouseDown: Bool = false
    var isRightMouseDown: Bool = false
    var isInInitStage: Bool = true
    var isInLargeView: Bool = false {
        didSet {
            if !isInInitStage {
                if let visibleItems = viewController.collectionView.visibleItems() as? [CustomCollectionViewItem] {
                    for item in visibleItems {
                        item.setTooltip()
                    }
                }
                updateToolbar()
                if globalVar.portableMode {
                    viewController.adjustWindowPortable(firstShowThumb: true, animate: false)
                }
                if !isInLargeView {
                    viewController.recalcIfHasChangedSize()
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
            if let largeImageView = viewController.largeImageView,
               isShowExif && largeImageView.exifTextView.textItems.isEmpty{
                let exifData = convertExifData(file: largeImageView.file)
                largeImageView.updateTextItems(formatExifData(exifData ?? [:], isVideo: globalVar.HandledVideoExtensions.contains(largeImageView.file.ext), needWarp: true))
            }
            viewController.largeImageView.exifTextView.isHidden = !isShowExif
            updateToolbar()
        }
    }
    var isNeedChangeLayoutType = false
    var justifiedLayout = CustomFlowLayout()
    var gridLayout = CustomGridLayout()
    var waterfallLayout = WaterfallLayout()
    // weak var viewController:ViewController?
    var timer = MyTimer()
    var fileChangedCount = 0
    var isInStageOneProgress = false
    var isInStageTwoProgress = false
    var isInStageThreeProgress = false
    var isInSearchState = false
    var isFilenameFilterOn = false
    var isCurrentFolderFiltered: Bool {
        viewController.fileDB.lock()
        let curFolder = viewController.fileDB.curFolder
        let isFiltered = viewController.fileDB.db[SortKeyDir(curFolder)]?.isFiltered ?? false
        viewController.fileDB.unlock()
        return isFiltered
    }
    var isInFindingClosestState = false
    
    var HandledImageAndRawExtensions: [String] = []
    var HandledVideoExtensions: [String] = []
    var HandledOtherExtensions: [String] = []
    var HandledFileExtensions: [String] = []
    var HandledSearchExtensions: [String] = []

    func setFileExtensions(){
        HandledImageAndRawExtensions = []
        if self.isShowImageFile{
            HandledImageAndRawExtensions += globalVar.HandledImageExtensions
        }
        if self.isShowRawFile {
            HandledImageAndRawExtensions += globalVar.HandledRawExtensions
        }
        HandledVideoExtensions = []
        if self.isShowVideoFile {
            HandledVideoExtensions += globalVar.HandledVideoExtensions
        }
        HandledOtherExtensions = globalVar.HandledOtherExtensions
        // 文件列表显示的
        // Displayed in file list
        HandledFileExtensions = HandledImageAndRawExtensions + HandledVideoExtensions + HandledOtherExtensions
        // 作为鼠标手势查找的目标
        // As target for mouse gesture search
        HandledSearchExtensions = HandledImageAndRawExtensions + HandledVideoExtensions
    }
    
    var selectedUrls2 = [URL]()
    func selectedUrls() -> [URL] {
        var urls = viewController.getSelectedURLs()
        if urls.count == 0,
           viewController.publicVar.isInLargeView == true,
           let url=URL(string: viewController.largeImageView.file.path){
            urls.append(url)
        }
        return urls
    }
    
    func updateToolbar(){
        if let windowController = (viewController.view.window?.windowController) as? WindowController {
            windowController.updateToolbar()
        }
    }
}

class ViewController: NSViewController, NSSplitViewDelegate, NSSearchFieldDelegate {
    
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
    
    // var loadImageTaskPool = [(String,String,Int)]()
    var loadImageTaskPool = TaskPool()
    // var loadImageTaskPool.lock = NSLock()
    
    // var infoThreadPoolNum = 0
    // var infoThreadPoolLock = NSLock()
    // var thumbThreadPoolNum = 0
    // var thumbThreadPoolLock = NSLock()
    
    let readInfoTaskPoolSemaphore = DispatchSemaphore(value: 0)
    let loadImageTaskPoolSemaphore = DispatchSemaphore(value: 0)
    var externalVolumeThreadSemaphores = [String: DispatchSemaphore]()
    let externalVolumeThreadSemaphoresLock = NSLock()
    
    var searchFolderRound=0
    
#if DEBUG && LOCAL_DEV
    var rootFolder="file://\(homeDirectory)/Repository/XcodeProj/%5BTestData%5D/ImageViewerPlus/"
    var treeRootFolder="file://\(homeDirectory)/Repository/XcodeProj/%5BTestData%5D/ImageViewerPlus/"
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
    var lastResizeFailed = false
    var lastLargeImageRotate = 0
    var lastUseHDR = false
    
    var lastTheme: NSAppearance.Name = .aqua
    
    var previousSplitViewWidth: CGFloat = 0.0
    
    var hasManualToggleSidebar=false
    
    var eventMonitorKeyDown: Any?
    var eventMonitorLeftMouseDown: Any?
    var eventMonitorLeftMouseUp: Any?
    var eventMonitorLeftMouseDragged: Any?
    var eventMonitorRightMouseDown: Any?
    var eventMonitorRightMouseUp: Any?
    var eventMonitorRightMouseDragged: Any?
    var eventMonitorScrollWheel: Any?
    var willTerminate = false
    
    var windowSizeChangedTimesWhenInLarge=0
    
    var scrollDebounceWorkItem: DispatchWorkItem?
    
    var arrowScrollDebounceWorkItem: DispatchWorkItem?
    
    // 累积滚动量
    // Cumulative scroll amount
    private var cumulativeScroll: CGFloat = 0
    private var lastScrollSwitchLargeImageTime: TimeInterval = 0
    
    var gestureTriggeredSwitch = false
    
    var initialMouseLocation: CGPoint?
    var lastMouseLocation: CGPoint?
    var gestureState: RightMouseGestureState = .none
    var directionHistory: [RightMouseGestureDirection] = []
    
    var autoScrollTimer: Timer?
    var scrollSpeed: CGFloat = 1.0
    var isAutoScrollPaused: Bool = false
    
    // 定时器，用于控制自动播放的节奏
    // Timer for controlling auto-play rhythm
    var autoPlayTimer: Timer?
    // 播放间隔，初始设置为0，用户输入后更新
    // Play interval, initially set to 0, updated after user input
    var autoPlayInterval: TimeInterval = 0
    // 自动播放是否正在进行的标志
    // Flag indicating whether auto-play is in progress
    var isAutoPlaying: Bool = false
    
    var searchField: NSSearchField?
    var searchOverlay: SearchOverlayView?
    
    var dirURLCache: [URL] = []
    var dirURLCacheParameters: Any = []
    
    // 搜索框
    // Search box
    var search_searchText: String = ""
    var search_useRegex: Bool = false
    var search_isCaseSensitive: Bool = false
    var search_isUseFullPath: Bool = false
    
    // 快速搜索
    // Quick search
    var quickSearchTimer: Timer?
    var quickSearchText: String = ""
    var quickSearchState: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        log("Start viewDidLoad")
        // Start viewDidLoad
        
        publicVar.refView=collectionView
        publicVar.viewController=self
        treeViewData.viewController=self
        
        // 初始化大图
        // Initialize large image
        publicVar.isLaunchFromFile = globalVar.isLaunchFromFile
        globalVar.isLaunchFromFile = false
        publicVar.isLaunchFromFile_changeLargeImage = publicVar.isLaunchFromFile
        if publicVar.isLaunchFromFile {
            largeImageBgEffectView.blendingMode = .behindWindow
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
            largeImageBgEffectView.blendingMode = .withinWindow
            publicVar.isInLargeView=false
        }
        
        // 防止设置上面值时触发动作
        // Prevent triggering actions when setting above values
        publicVar.isInInitStage = false
        
        
        // 初始化collectionView
        // Initialize collectionView
        collectionViewManager=CustomCollectionViewManager(fileDB: fileDB)
        collectionView.wantsLayer = true
        collectionView.allowsMultipleSelection = true
        collectionView.isSelectable = true
        collectionView.delegate = collectionViewManager
        collectionView.dataSource = collectionViewManager
        collectionView.register(CustomCollectionViewItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "CustomCollectionViewItem"))
        // 本地拖动操作
        // Local drag operation
        collectionView.setDraggingSourceOperationMask([.every], forLocal: true)
        // 全局拖动操作
        // Global drag operation
        collectionView.setDraggingSourceOperationMask([.every], forLocal: false)
        
//        publicVar.justifiedLayout.minimumInteritemSpacing=10
//        publicVar.justifiedLayout.minimumLineSpacing=10
//        publicVar.justifiedLayout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
//        publicVar.justifiedLayout.itemsHorizontalAlignment = JQCollectionViewItemsHorizontalAlignment.left;
//        publicVar.justifiedLayout.itemsVerticalAlignment = JQCollectionViewItemsVerticalAlignment.center;
        
        // 初始化目录树
        // Initialize directory tree
        outlineViewManager=CustomOutlineViewManager(fileDB: fileDB, treeViewData: treeViewData, outlineView: outlineView)
        outlineView.delegate = outlineViewManager
        outlineView.dataSource = outlineViewManager
        outlineView.registerForDraggedTypes([.fileURL])
        // 本地拖动操作
        // Local drag operation
        outlineView.setDraggingSourceOperationMask([.every], forLocal: true)
        // 全局拖动操作
        // Global drag operation
        outlineView.setDraggingSourceOperationMask([.every], forLocal: false)
        outlineView.columnAutoresizingStyle = .noColumnAutoresizing
        
        // 初始化splitView
        // Initialize splitView
        splitView.delegate = self
        
        // 初始化DrawingView
        // Initialize DrawingView
        drawingView = DrawingView(frame: self.view.bounds)
        // 使视图随父视图改变大小而改变大小
        // Make view resize with parent view
        drawingView?.autoresizingMask = [.width, .height]
        self.view.addSubview(drawingView!)
        
        // -----开始读取配置-----
        // -----Start reading configuration-----
        
        // TODO: 没有工具栏时，载入时折叠且divider宽度设为0会造成菜单栏变白
        // TODO: When there's no toolbar, collapsing on load and setting divider width to 0 will cause menu bar to turn white

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
        if let isPreferInternalThumb = UserDefaults.standard.value(forKey: "isPreferInternalThumb") as? Bool {
            publicVar.isPreferInternalThumb = isPreferInternalThumb
        }
        if let isEnableHDR = UserDefaults.standard.value(forKey: "isEnableHDR") as? Bool {
            publicVar.isEnableHDR = isEnableHDR
        }
        if let isRawUseEmbeddedThumb = UserDefaults.standard.value(forKey: "isRawUseEmbeddedThumb") as? Bool {
            publicVar.isRawUseEmbeddedThumb = isRawUseEmbeddedThumb
        }
        if let isRecursiveContainFolder = UserDefaults.standard.value(forKey: "isRecursiveContainFolder") as? Bool {
            publicVar.isRecursiveContainFolder = isRecursiveContainFolder
        }
        if let autoPlayVisibleVideo = UserDefaults.standard.value(forKey: "autoPlayVisibleVideo") as? Bool {
            publicVar.autoPlayVisibleVideo = autoPlayVisibleVideo
        }
        if let autoPlaySelectedVideo = UserDefaults.standard.value(forKey: "autoPlaySelectedVideo") as? Bool {
            publicVar.autoPlaySelectedVideo = autoPlaySelectedVideo
        }
        if let isRotationLocked = UserDefaults.standard.value(forKey: "isRotationLocked") as? Bool {
            publicVar.isRotationLocked = isRotationLocked
        }
        if let isZoomLocked = UserDefaults.standard.value(forKey: "isZoomLocked") as? Bool {
            publicVar.isZoomLocked = isZoomLocked
        }
        if let isPanWhenZoomed = UserDefaults.standard.value(forKey: "isPanWhenZoomed") as? Bool {
            publicVar.isPanWhenZoomed = isPanWhenZoomed
        }
        if let currentTag = UserDefaults.standard.value(forKey: "currentTag") as? String {
            publicVar.currentTag = currentTag
        }
        if #available(macOS 14.0, *) {
            //
        }else{
            publicVar.isEnableHDR = false
        }
        publicVar.profile = CustomProfile.loadFromUserDefaults(withKey: "CustomStyle_v2_current")
        
        // -----结束读取配置------
        // -----End reading configuration------
        
        publicVar.setFileExtensions()
        
        if publicVar.profile.isDirTreeHidden{
            splitView.setPosition(0, ofDividerAt: 0)
        }

        if publicVar.profile.layoutType == .waterfall {
            collectionView.collectionViewLayout = publicVar.waterfallLayout
        }else if publicVar.profile.layoutType == .justified {
            collectionView.collectionViewLayout = publicVar.justifiedLayout
        }else if publicVar.profile.layoutType == .grid {
            collectionView.collectionViewLayout = publicVar.gridLayout
        }else {
            collectionView.collectionViewLayout = publicVar.justifiedLayout
        }
        changeWaterfallLayoutNumberOfColumns()
        
        let theme=NSApp.effectiveAppearance.name
        if theme == .darkAqua {
            // 暗模式下的颜色
            // Color in dark mode
            collectionView.layer?.backgroundColor = hexToNSColor(hex: COLOR_COLLECTIONVIEW_BG_DARK).cgColor
            lastTheme = .darkAqua
        } else {
            // 光模式下的颜色
            // Color in light mode
            collectionView.layer?.backgroundColor = hexToNSColor(hex: COLOR_COLLECTIONVIEW_BG_LIGHT).cgColor
            lastTheme = .aqua
        }
        
        if globalVar.autoHideToolbar {
            mainScrollView.automaticallyAdjustsContentInsets = false
            outlineScrollView.automaticallyAdjustsContentInsets = false
        }

        if #available(macOS 14.0, *) {
            largeImageView.imageView.preferredImageDynamicRange = (publicVar.isEnableHDR) ? .high : .standard
        }
        
        mainScrollView.scrollerStyle = .legacy
        outlineScrollView.scrollerStyle = .legacy
        
        treeViewData.initData(path: treeRootFolder)
        outlineView.reloadData()
        DispatchQueue.main.async {
            self.outlineViewManager.adjustColumnWidth()
        }
        
        // =========以下是事件监听配置==========
        // =========Event monitoring configuration below==========
        
        NSApp.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new, .old], context: nil)
        
        // 双击目录树
        // Double-click directory tree
        outlineView.doubleAction = #selector(outlineViewDoubleClicked(_:))
        
        // 鼠标左键事件
        // Left mouse button event
        eventMonitorLeftMouseDown = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return event }
            if event.window != self.view.window { return event }

            if publicVar.isInLargeView && largeImageView.file.type == .video {
                let clickLocation = event.locationInWindow
                let videoControlYmin = largeImageView.videoView.frame.minY
                let videoControlYmax = largeImageView.videoView.frame.maxY
                let videoControlXmin = largeImageView.videoView.frame.minX
                let videoControlXmax = largeImageView.videoView.frame.maxX
                let coreAreaYmax = coreAreaView.frame.maxY - (globalVar.autoHideToolbar ? 40 : 0)
                
                if clickLocation.y > videoControlYmin + 40 && clickLocation.y < videoControlYmax,
                   clickLocation.x > videoControlXmin && clickLocation.x < videoControlXmax,
                   clickLocation.y < coreAreaYmax {
                    // 仅在视频范围内响应，范围外的由largeImageView中的鼠标事件正常处理
                    // Only respond within video range, outside range handled normally by mouse events in largeImageView
                    largeImageView.mouseDown(with: event)
                    // return nil
                }
            }
            
            return event
        }

        eventMonitorLeftMouseUp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self = self else { return event }
            if event.window != self.view.window { return event }

            if publicVar.isInLargeView && largeImageView.file.type == .video {
                let clickLocation = event.locationInWindow
                let videoControlYmin = largeImageView.videoView.frame.minY
                let videoControlYmax = largeImageView.videoView.frame.maxY
                let videoControlXmin = largeImageView.videoView.frame.minX
                let videoControlXmax = largeImageView.videoView.frame.maxX
                let coreAreaYmax = coreAreaView.frame.maxY - (globalVar.autoHideToolbar ? 40 : 0)
                
                if clickLocation.y > videoControlYmin + 40 && clickLocation.y < videoControlYmax,
                   clickLocation.x > videoControlXmin && clickLocation.x < videoControlXmax,
                   clickLocation.y < coreAreaYmax {
                    // 仅在视频范围内响应，范围外的由largeImageView中的鼠标事件正常处理
                    // Only respond within video range, outside range handled normally by mouse events in largeImageView
                    largeImageView.mouseUp(with: event)
                    // return nil
                }
            }
            
            return event
        }

        // 拖动音量滚动条时无法触发这个事件
        // This event cannot be triggered when dragging volume scrollbar
//        eventMonitorLeftMouseDragged = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
//            guard let self = self else { return event }
//            if event.window != self.view.window { return event }
//
//            if publicVar.isInLargeView && largeImageView.file.type == .video {
//                let clickLocation = event.locationInWindow
//                let videoControlYmin = largeImageView.videoView.frame.minY
//                let videoControlYmax = largeImageView.videoView.frame.maxY
//                let videoControlXmin = largeImageView.videoView.frame.minX
//                let videoControlXmax = largeImageView.videoView.frame.maxX
//                
//                if clickLocation.y > videoControlYmin + 40 && clickLocation.y < videoControlYmax,
//                   clickLocation.x > videoControlXmin && clickLocation.x < videoControlXmax {
//                    // 仅在视频范围内响应，范围外的由largeImageView中的鼠标事件正常处理
//                    // Only respond within video range, outside range handled normally by mouse events in largeImageView
//                    largeImageView.mouseDragged(with: event)
//                    // return nil
//                }
//            }
//            
//            return event
//        }
        
        // 双击collectionView
        // Double-click collectionView
//        let clickCollectionItemGesture = NSClickGestureRecognizer(target: self, action: #selector(openLargeImageFromPos(_:)))
//        clickCollectionItemGesture.numberOfClicksRequired = 2 // 设置为双击
//        clickCollectionItemGesture.delaysPrimaryMouseButtonEvents = false // 阻止延迟主按钮事件
//        collectionView.addGestureRecognizer(clickCollectionItemGesture)
        
        // 全局滚动事件
        // Global scroll event
        eventMonitorScrollWheel = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self=self else{return event}
            // if getMainViewController() != self {return event}
            // 检查事件的窗口是否是激活窗口
            if event.window != self.view.window {
                return event
            }
            self.handleScrollWheel(event)
            if publicVar.isInLargeView && largeImageView.file.type == .video {
                return nil
            }else{
                return event
            }
        }
        
        // 滚动collectionView
        // Scroll collectionView
        if let scrollView = collectionView.enclosingScrollView {
            // 监听滚动开始和结束的通知
            // Listen for scroll start and end notifications
            NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll(_:)), name: NSScrollView.didLiveScrollNotification, object: scrollView)
            NotificationCenter.default.addObserver(self, selector: #selector(scrollViewScrollEnd(_:)), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }
        
        // 监听键盘按键
        // Monitor keyboard key presses
        eventMonitorKeyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self=self else{return event}
            return self.KeyShortcutManager(event: event)
        }
        
        // 鼠标右键事件
        // Right mouse button event
        eventMonitorRightMouseUp = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            guard let self=self else{return event}
            // if getMainViewController() != self {return event}
            // 检查事件的窗口是否是激活窗口
            if event.window != self.view.window {
                return event
            }
            if self.coreAreaView.frame.contains(event.locationInWindow) {
                if publicVar.isInLargeView {
                    self.largeImageView.rightMouseUp(with: event)
                }else{
                    self.drawingView?._rightMouseUp(with: event)
                }
                // 不传递事件
                // Don't pass event
                return nil
            } else {
                // 继续传递事件
                // Continue passing event
                return event
            }
        }

        eventMonitorRightMouseDown = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self=self else{return event}
            // if getMainViewController() != self {return event}
            // 检查事件的窗口是否是激活窗口
            if event.window != self.view.window {
                return event
            }
            if self.coreAreaView.frame.contains(event.locationInWindow) {
                if publicVar.isInLargeView {
                    self.largeImageView.rightMouseDown(with: event)
                }else{
                    self.drawingView?._rightMouseDown(with: event)
                }
                // 不传递事件
                // Don't pass event
                return nil
            } else {
                // 继续传递事件
                // Continue passing event
                return event
            }
        }

        eventMonitorRightMouseDragged = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDragged) { [weak self] event in
            guard let self=self else{return event}
            // if getMainViewController() != self {return event}
            // 检查事件的窗口是否是激活窗口
            if event.window != self.view.window {
                return event
            }
            if self.coreAreaView.frame.contains(event.locationInWindow) {
                if publicVar.isInLargeView {
                    self.largeImageView.rightMouseDragged(with: event)
                }else{
                    self.drawingView?._rightMouseDragged(with: event)
                }
                // 不传递事件
                // Don't pass event
                return nil
            } else {
                // 继续传递事件
                // Continue passing event
                return event
            }
        }
        
        // =========结束事件监听配置==========
        // =========End event monitoring configuration==========
        
        // startListeningForFileSystemEvents(in: "/Users")
        // startWatchingDirectory(atPath: "/Users")
        
        log("End viewDidLoad")
        // End viewDidLoad

    }
    
    func prepareForDeinit() {
        // 在这里执行清理工作
        // Perform cleanup work here
        log("ViewController is being deinitialized")
        
        // 存储关闭的目录/文件
        // Store closed directory/file
        if publicVar.isInLargeView {
            globalVar.closedPaths.append(largeImageView.file.path)
        } else {
            globalVar.closedPaths.append(fileDB.curFolder)
        }
        
        // 移除事件观察者
        // Remove event observers
        if let eventMonitorKeyDown = eventMonitorKeyDown {
            NSEvent.removeMonitor(eventMonitorKeyDown)
        }
        if let eventMonitorLeftMouseDown = eventMonitorLeftMouseDown {
            NSEvent.removeMonitor(eventMonitorLeftMouseDown)
        }
        if let eventMonitorLeftMouseUp = eventMonitorLeftMouseUp {
            NSEvent.removeMonitor(eventMonitorLeftMouseUp)
        }
        if let eventMonitorLeftMouseDragged = eventMonitorLeftMouseDragged {
            NSEvent.removeMonitor(eventMonitorLeftMouseDragged)
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
        // Remove KVO observers
        NSApp.removeObserver(self, forKeyPath: "effectiveAppearance")
        
        // 移除通知中心的观察者
        // Remove notification center observers
        if let scrollView = collectionView.enclosingScrollView {
            NotificationCenter.default.removeObserver(self, name: NSScrollView.didLiveScrollNotification, object: scrollView)
            NotificationCenter.default.removeObserver(self, name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }
        
        // 停止监控
        // Stop monitoring
        stopWatchingDirectory()
        
        // 取消所有未完成的异步任务
        // Cancel all unfinished async tasks
        largeImageLoadTask?.cancel()
        largeImageLoadTask = nil
        scrollDebounceWorkItem?.cancel()
        scrollDebounceWorkItem = nil
        arrowScrollDebounceWorkItem?.cancel()
        arrowScrollDebounceWorkItem = nil
        
        // 停止所有计时器
        // Stop all timers
        resizeTimer?.invalidate()
        resizeTimer = nil
        folderMonitorTimer?.invalidate()
        folderMonitorTimer = nil
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        
        // 工作线程结束标志
        // Worker thread termination flag
        willTerminate=true

        // 产生空任务，防止等待信号量导致窗口无法销毁
        // Generate empty task to prevent window from being unable to destroy due to waiting for semaphore
        readInfoTaskPoolSemaphore.signal()
        loadImageTaskPoolSemaphore.signal()
        
        // 清空数据库
        // Clear database
        fileDB.lock()
        for (_,dirModel) in fileDB.db {
            for (_,fileModel) in dirModel.files {
                fileModel.image=nil
                fileModel.folderImages=[NSImage]()
            }
            // dirModel.files.removeAll()
        }
        // fileDB.db.removeAll()
        fileDB.unlock()
    }
    
    func afterFinishLoad(_ openFolder: String? = nil){
        log("Start afterFinishLoad")
        // 从文件夹启动
        // Launch from folder
        if publicVar.isLaunchFromFile == false {
            let defaults = UserDefaults.standard
            var lastFolder = defaults.string(forKey: "lastFolder")
            if !globalVar.openLastFolder  {
                if let appDelegate=NSApplication.shared.delegate as? AppDelegate,
                   appDelegate.windowControllers.count == 1 {
                    lastFolder = globalVar.homeFolder
                }
            }
            if lastFolder == nil {
                lastFolder = rootFolder
            }
            if openFolder != nil {
                lastFolder = openFolder
            }
            fileDB.lock()
            fileDB.curFolder=lastFolder!
            fileDB.unlock()
            refreshAll(needLoadThumbPriority: false)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                setWindowTitle()
            }
        // 从文件启动
        // Launch from file
        }else{
            
        }
        
        // 启动后台任务线程
        // Start background task thread
        startBackgroundTaskThread()
    }
    
    // 系统主题变化时会触发此方法
    // This method is triggered when system theme changes
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            let theme=NSApp.effectiveAppearance.name
            if theme == .darkAqua {
                // 暗模式下的颜色
                // Color in dark mode
                collectionView.layer?.backgroundColor = hexToNSColor(hex: COLOR_COLLECTIONVIEW_BG_DARK).cgColor
            } else {
                // 光模式下的颜色
                // Color in light mode
                collectionView.layer?.backgroundColor = hexToNSColor(hex: COLOR_COLLECTIONVIEW_BG_LIGHT).cgColor
            }
            if(lastTheme != theme){
                refreshAll(dryRun: true, needLoadThumbPriority: false)
            }
            lastTheme=theme
        }
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
        
        // 调整搜索框位置
        // Adjust search box position
        if let searchOverlay = searchOverlay,
           let containerView = searchOverlay.containerView {
            searchOverlay.frame = view.bounds
            containerView.frame.origin.x = searchOverlay.bounds.width - containerView.frame.width - 30
            containerView.frame.origin.y = searchOverlay.bounds.height - containerView.frame.height - 20
        }
    }
    
    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        let leftView = splitView.arrangedSubviews[0]
        let rightView = splitView.arrangedSubviews[1]

        let dividerThickness = splitView.dividerThickness
        let newWidth = splitView.bounds.width - leftView.frame.width - dividerThickness
        rightView.frame.size.width = newWidth

        // 更新右侧视图的大小，左侧视图保持不变
        // Update right view size, keep left view unchanged
        rightView.frame = CGRect(x: leftView.frame.width + dividerThickness, y: 0, width: newWidth, height: splitView.bounds.height)
        leftView.frame = CGRect(x: 0, y: 0, width: leftView.frame.width, height: splitView.bounds.height)
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        // 取消之前的定时器
        // Cancel previous timer
        resizeTimer?.invalidate()
        
        if publicVar.isInLargeView {
            windowSizeChangedTimesWhenInLarge += 1
            return
        }
        
        fileDB.lock()
        let fileCount=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count
        fileDB.unlock()
        // 注：此处最好使用定时器，因为程序首次启动时会调用6次！
        // Note: Better to use timer here, as it will be called 6 times on first launch!
        if fileCount ?? 0 > -1 && !hasManualToggleSidebar && notification.name != .AVAssetDurationDidChange {
            resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.splitViewSizeChanged()
            }
        }else{
            splitViewSizeChanged()
        }
        hasManualToggleSidebar=false
    }
    
    func recalcIfHasChangedSize(){
        if windowSizeChangedTimesWhenInLarge > 0 {
            // 表示立即执行
            // Indicates immediate execution
            splitViewDidResizeSubviews(Notification(name: .AVAssetDurationDidChange))
            windowSizeChangedTimesWhenInLarge = 0
        }
    }
    
    // var _temp_count_sizeChanged: Int = 0
    @objc func splitViewSizeChanged() {

        // 获取当前宽度
        // Get current width
        let currentWidth = collectionView.bounds.width
        
        // 检查宽度是否发生变化
        // Check if width has changed
        if currentWidth == previousSplitViewWidth {
            return
        }
        previousSplitViewWidth = currentWidth
        
        // _temp_count_sizeChanged+=1
        // print("计算布局"+String(_temp_count_sizeChanged))
        
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//        }
        fileDB.lock()
        let curFolder=fileDB.curFolder
        fileDB.db[SortKeyDir(curFolder)]?.layoutCalcPos=0
        fileDB.unlock()
        
        changeWaterfallLayoutNumberOfColumns()
        
        // startTime = DispatchTime.now()
        recalcLayout(curFolder)
//        if(true){
//            let curTime = DispatchTime.now()
//            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
//            let timeInterval = Double(nanoTime) / 1_000_000_000
//            log("Time taken to fully calculate layout: \(timeInterval) seconds")
//        }
        // collectionView.collectionViewLayout=LeftAlignedCollectionViewFlowLayout()
        collectionView.collectionViewLayout?.invalidateLayout()
        view.window?.layoutIfNeeded()
        // collectionView.collectionViewLayout=LeftAlignedCollectionViewFlowLayout()
        
        // 以下是处理左侧目录树，防止在宽度为0时切换目录，再拉宽时，某些条目显示...
        // 注：似乎改变了实现方式（直接从数据源获取而不是可见view），就不用此处调用了，这里调用计算量大会导致卡顿
        // Below is handling for left directory tree, prevent items from displaying incorrectly when switching directories at width 0 then widening
        // Note: Implementation seems changed (getting directly from data source instead of visible view), no need to call here, calling here causes lag due to heavy computation
        // outlineViewManager.adjustColumnWidth()
        
        // 解决改变窗口大小，由于不彻底重载，导致的缩放不正常（有时，原因未知）
        // Fix abnormal scaling when window size changes due to incomplete reload (sometimes, reason unknown)
        if true {
            let visibleIndexPaths=collectionView.indexPathsForVisibleItems()
            for indexPath in visibleIndexPaths{
                if let item = collectionView.item(at: indexPath) as? CustomCollectionViewItem {
                    item.configureWithImage(item.file,playAnimation:false)
                }
            }
        }
        
        // 刷新工具栏
        // Refresh toolbar
        if let windowController = view.window?.windowController as? WindowController {
            windowController.updateToolbar()
        }
    }
    
    func setWindowTitle(){
        
        fileDB.lock()
        let curFolder=fileDB.curFolder
        let imageCount=(fileDB.db[SortKeyDir(curFolder)]?.imageCount ?? 0)
        let videoCount=fileDB.db[SortKeyDir(curFolder)]?.videoCount ?? 0
        let otherCount=(fileDB.db[SortKeyDir(curFolder)]?.fileCount ?? 0) - imageCount - videoCount
        let folderCount=(fileDB.db[SortKeyDir(curFolder)]?.folderCount ?? 0)
        fileDB.unlock()

        var statisticInfo = ""
        if folderCount+imageCount+videoCount+otherCount > 0 {
            statisticInfo += String(format: "(")
            if folderCount != 0 {
                if folderCount == 1 {
                    statisticInfo += String(format: "%d %@ ", folderCount, NSLocalizedString("Folder", comment: "目录"))
                }else{
                    statisticInfo += String(format: "%d %@ ", folderCount, NSLocalizedString("Folders", comment: "目录"))
                }
            }
            if imageCount != 0 {
                if imageCount == 1 {
                    statisticInfo += String(format: "%d %@ ", imageCount, NSLocalizedString("Image", comment: "图像"))
                }else{
                    statisticInfo += String(format: "%d %@ ", imageCount, NSLocalizedString("Images", comment: "图像"))
                }
            }
            if videoCount != 0 {
                if videoCount == 1 {
                    statisticInfo += String(format: "%d %@ ", videoCount, NSLocalizedString("Video", comment: "视频"))
                }else{
                    statisticInfo += String(format: "%d %@ ", videoCount, NSLocalizedString("Videos", comment: "视频"))
                }
            }
            if otherCount != 0 {
                if otherCount == 1 {
                    statisticInfo += String(format: "%d %@ ", otherCount, NSLocalizedString("Other", comment: "其它"))
                }else{
                    statisticInfo += String(format: "%d %@ ", otherCount, NSLocalizedString("Others", comment: "其它"))
                }
            }
            statisticInfo=statisticInfo.trimmingCharacters(in: .whitespaces)
            //                if folderCount == 0 && imageCount == 0 && videoCount == 0 && otherCount == 0 {
            //                    windowTitle += NSLocalizedString("Empty", comment: "空")
            //                }
            statisticInfo += String(format: ")")
        }
        
        var shortTitle = (curFolder as NSString).lastPathComponent.removingPercentEncoding!
        var fullTitle = String(curFolder.replacingOccurrences(of: "file:///", with: "").removingPercentEncoding!.dropLast())
        
        if curFolder == "file:///" {
            shortTitle = ROOT_NAME
            fullTitle = ROOT_NAME
        }
        
//        if publicVar.profile.getValue(forKey: "isWindowTitleUseFullPath") == "true" {
//            publicVar.toolbarTitle = fullTitle
//        }else{
//            publicVar.toolbarTitle = shortTitle
//        }
        
        publicVar.toolbarTitle = shortTitle
        
        if publicVar.profile.getValue(forKey: "isWindowTitleShowStatistics") == "true" {
            publicVar.toolbarTitle += " " + statisticInfo
        }

        publicVar.titleStatisticInfo = statisticInfo
        view.window?.title = shortTitle
        
        if let windowController = view.window?.windowController as? WindowController {
            windowController.updateToolbar()
        }
    }
    
    func startBackgroundTaskThread(){
        log("Start startBackgroundTaskThread")

        // 读取信息线程
        // Read info thread
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
                    // (dir,key,i,doNotActualRead)
                    fileDB.lock()
                    let dir=firstTask.0
                    let dirModel=firstTask.1
                    let key=firstTask.2
                    let file=firstTask.3
                    let i=file.id
                    let doNotActualRead=file.doNotActualRead
                    let ver=firstTask.4
                    let count=dirModel.files.count
                    fileDB.unlock() 
                    
                    if i == -1 {continue}
                    if ver != dirModel.ver {continue}
                    
                    // 外置卷等待到队列全部执行完毕再分配(单线程)
                    // External volume waits for queue to fully execute before allocating (single-threaded)
//                    if VolumeManager.shared.isExternalVolume(key.path) {
//                        operationQueue.waitUntilAllOperationsAreFinished()
//                    }
                    if VolumeManager.shared.isExternalVolume(key.path) {
                        operationQueue.maxConcurrentOperationCount = 1
                    }else{
                        operationQueue.maxConcurrentOperationCount = globalVar.thumbThreadNum > 2 ? 2 : 1
                    }
                    
                    // 最后一个等待到队列全部执行完毕再分配
                    // Last one waits for queue to fully execute before allocating
                    if(i == count-1){
                        operationQueue.waitUntilAllOperationsAreFinished()
                    }
                    
                    operationQueue.addOperation { [weak self] in
                        guard let self = self else { return }
                        if willTerminate {return}
                        
                        fileDB.lock()
                        var imageInfo = file.imageInfo
                        var originalSize = file.originalSize
                        let curFolder=fileDB.curFolder
                        fileDB.unlock() 
                        
                        if ver != dirModel.ver {return}
                        // 需要跳过，否则会等上一个目录完全执行完毕后才开始；不过这样就没法预载入其它目录了，待重构任务队列实现
                        // Need to skip, otherwise will wait for previous directory to fully complete before starting; but this prevents preloading other directories, pending task queue refactoring
                        if dir != curFolder {return}
                        
                        publicVar.isInStageTwoProgress = true
                        defer {
                            publicVar.isInStageTwoProgress = false
                        }
                        
                        var isGetImageSizeFail = false
                        
                        if originalSize == nil {
                            // 获取图像大小
                            // Get image size
                            if doNotActualRead { // || VolumeManager.shared.isExternalVolume(key.path){
                                originalSize = DEFAULT_SIZE
                                isGetImageSizeFail = true
                            }else{
                                imageInfo = getImageInfo(url: URL(string: key.path)!, needMetadata: true)
                                originalSize = imageInfo?.size
                                if originalSize == nil {
                                    originalSize = DEFAULT_SIZE
                                    isGetImageSizeFail = true
                                }
                            }
                        }
                        
                        if originalSize != nil {
                            // 注意：可能上面的下一轮执行完毕后才执行后面的代码
                            // Note: Code below may execute after next round above completes
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                
                                fileDB.lock()
                                file.imageInfo = imageInfo
                                file.originalSize = originalSize
                                file.canBeCalcued=true
                                file.isGetImageSizeFail=isGetImageSizeFail
                                let count=dirModel.files.count
                                let curFolder=fileDB.curFolder
                                let keepScrollPos=dirModel.keepScrollPos
                                fileDB.unlock()
                                
                                if ver != dirModel.ver {return}
                                
                                // 80~0.07s, 50~0.05s, 20~0.04s
                                if(false || i % 20 == 8 || i == count-1 || publicVar.timer.intervalSafe(name: "recalcLayoutWhenReadInfo", second: 0.1)){
                                    recalcLayout(dir)
                                    // collectionView.reloadData()
                                }
                                
                                if(dir == curFolder && keepScrollPos && i == count-1){
                                    // publicVar.timer.intervalSafe(name: "recalcLayoutReloadData", second: 0.02+Double(i)*0.0001)
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
                                    log("Time taken to fully load size information: \(timeInterval) seconds")
                                }
                                
                                //                            if nowLayoutCalcPos-lastLayoutCalcPosUsed > 100 {
                                // 避免一次显示太多导致载入缓存目录时不能瞬间显示，但这样似乎更慢了
                                // Avoid displaying too many at once causing cached directory to not display instantly, but this seems slower
                                //                                nowLayoutCalcPos=lastLayoutCalcPosUsed+100
                                //                                fileDB.lock()
                                //                                fileDB.db[SortKeyDir(dir)]!.layoutCalcPos=nowLayoutCalcPos
                                //                                fileDB.unlock()
                                //                            }
                                if(nowLayoutCalcPos > lastLayoutCalcPosUsed && (publicVar.timer.intervalSafe(name: "insertItems", second: min(0.02+Double(i)*0.0001,4.0)) || nowLayoutCalcPos == count)){
                                    var indexPaths = [IndexPath]()
                                    for x in lastLayoutCalcPosUsed...nowLayoutCalcPos-1{
                                        indexPaths.append(IndexPath(item: x, section: 0))
                                    }
                                    if(dir == curFolder){
                                        
                                        coreAreaView.hideInfo()

                                        let curItemCount = collectionView.numberOfItems(inSection: 0)
                                        
                                        if curItemCount + indexPaths.count >= nowLayoutCalcPos {
                                            if !keepScrollPos {
                                                let newIndexPaths = indexPaths.dropFirst(curItemCount + indexPaths.count - nowLayoutCalcPos)
                                                collectionView.insertItems(at: Set(newIndexPaths))
                                            }
                                            if nowLayoutCalcPos == count {
                                                fileDB.lock()
                                                dirModel.keepScrollPos=true
                                                fileDB.unlock()
                                            }
                                        }
                                        // collectionView.reloadData()
                                        // collectionView.numberOfItems(inSection:0)
                                        // 此时开始渐变动画？
                                        // Start fade animation now?
                                        
                                    }
                                    for x in lastLayoutCalcPosUsed...nowLayoutCalcPos-1{
                                        // TODO: 大量读取文件时造成系统内存不足
                                        // TODO: Reading a large number of files may cause system out-of-memory issues
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
                                            log("Time taken to add first image to readImage pool: \(timeInterval) seconds")
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
        // 缩略图线程
        // Thumbnail thread
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
                        // (dir,key,i,doNotActualRead)
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
                        fileDB.unlock() 
                        
                        if i == -1 {return}
                        if ver != dirModel.ver {return}
                        // 暂时跳过，以降低网络驱动器单线程的载入延迟
                        // Temporarily skip to reduce loading delay for network drive single-threaded loading
                        if dir != curFolder {return}
                        
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
                        // 此处解锁是因为防止8个线程与主线程排队争fileDB.lock
                        // Unlock here to prevent 8 threads from contending with main thread for fileDB.lock
                        // loadImageTaskPool.lock.unlock()
                        if isMemClearedToAvoidRemainingTask && !otherTaskInfo.isFromScroll {return}
                        
//                        if(true){
//                            let curTime = DispatchTime.now()
//                            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
//                            let timeInterval = Double(nanoTime) / 1_000_000_000
//                            log("Time taken to read task: \(timeInterval) seconds ",dir)
//                        }
                        
                        // 完全载入计时
                        // Full load timing
                        if(i == count-1){
                            let curTime = DispatchTime.now()
                            let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                            let timeInterval = Double(nanoTime) / 1_000_000_000
                            log("Time taken to fully load image thumbnails: \(timeInterval) seconds")
                            log("-----------------------------------------------------------")
                        }
                        // 此时开始渐变动画
                        // Start fade animation now
                        // 防止其它队列末尾任务造成提前渐变
                        // Prevent premature fade from other queue tail tasks
                        if dir == curFolder {
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                
                                fileDB.lock()
                                let curFolder=fileDB.curFolder
                                fileDB.unlock() 
                                
                                if ver != dirModel.ver {return}
                                if dir != curFolder {return}
                                
                                coreAreaView.hideInfo()
                                
                                let curTime = DispatchTime.now()
                                let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                let timeInterval = Double(nanoTime) / 1_000_000_000
                                if i>40 || i==count-1 || timeInterval>0.3 {
                                    
                                    if snapshotQueue.count > 0 {
                                        let curTime = DispatchTime.now()
                                        let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                        let timeInterval = Double(nanoTime) / 1_000_000_000
                                        log("Time taken to reach hidden snapshot reason 1: \(timeInterval) seconds")
                                        log("-----------------------------------------------------------")
                                        
                                        // 向上或者后退时定位文件夹
                                        // Locate folder when going up or back
                                        if let (lastFolder,direction) = publicVar.folderStepForLocate.first {
                                            
                                            if let lastURL = URL(string: lastFolder),
                                               let curURL = URL(string: curFolder),
                                               lastURL.deletingLastPathComponent().absoluteString == curURL.absoluteString {
                                                
                                                publicVar.folderStepForLocate.removeAll()
                                                
                                                let targetFolderPath = lastURL.absoluteString
                                                let targetKey = SortKeyFile(targetFolderPath, isDir: true, needGetProperties: true, sortType: publicVar.profile.sortType, isSortFolderFirst: publicVar.profile.isSortFolderFirst, isSortUseFullPath: publicVar.profile.isSortUseFullPath, randomSeed: publicVar.randomSeed)
                                                
                                                fileDB.lock()
                                                if let index=fileDB.db[SortKeyDir(curFolder)]?.files.index(forKey: targetKey),
                                                   let offset=fileDB.db[SortKeyDir(curFolder)]?.files.offset(of: index) {
                                                    fileDB.unlock()
                                                    let indexPath=IndexPath(item: offset, section: 0)
                                                    collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                                                    collectionView.reloadData()
                                                    collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [indexPath])
                                                    collectionView.selectItems(at: [indexPath], scrollPosition: [])
                                                    collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
                                                    setLoadThumbPriority(ifNeedVisable: true)
                                                }else{
                                                    fileDB.unlock()
                                                }
                                            }
                                        }
                                    }
                                    
                                    while snapshotQueue.count > 0{
                                        let snapshot=snapshotQueue.first!
                                        snapshotQueue.removeFirst()
                                        // publicVar.isInLargeView=false
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
                        
                        // 因为优先级调度未能预先计算到目标大小时，设置标识
                        // Set flag when priority scheduling fails to pre-calculate target size
                        var noThumbSizeDueToSchedule = false
                        if thumbSize == nil && otherTaskInfo.isPriorityScheduled {
                            // originalSize = getImageSize(url: URL(string: key.path)!)
                            thumbSize = NSSize(width: 256, height: 256)
                            noThumbSizeDueToSchedule = true
                        }
                        
                        if thumbSize != nil {
                            if i == 0 {
                                let curTime = DispatchTime.now()
                                let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                let timeInterval = Double(nanoTime) / 1_000_000_000
                                log("Time taken to start loading first image: \(timeInterval) seconds")
                            }
                            
                            var revisedSize = NSSize(width: thumbSize!.width-2*publicVar.profile.ThumbnailBorderThickness, height: thumbSize!.height-2*publicVar.profile.ThumbnailBorderThickness-publicVar.profile.ThumbnailFilenamePadding)
                            if publicVar.profile.layoutType == .grid {
                                var size = originalSize ?? DEFAULT_SIZE
                                if size.width == 0 || size.height == 0 {size=DEFAULT_SIZE}
                                let rect = AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: CGPoint(x: 0, y: 0), size: revisedSize))
                                revisedSize = NSSize(width: round(rect.size.width), height: round(rect.size.height))
                            }
                            // log(max(revisedSize.width,revisedSize.height),level: .debug)
                            
                            var imageExist=false
                            loadImageTaskPool.lock.lock()
                            fileDB.lock()
                            if let thumbImage = file.image {
                                imageExist=true
                                // print(revisedSize,thumbImage.size)
                                
                                if (publicVar.isGenHdThumb && !noThumbSizeDueToSchedule) && file.type == .image { // && publicVar.layoutType != .grid
                                    if thumbImage.size.width != revisedSize.width {
                                        imageExist=false
                                    }
                                }
//                                if (!publicVar.isGenHdThumb || noThumbSizeDueToSchedule) && file.type == .image {
//                                    let maxLength = max(thumbImage.size.width,thumbImage.size.height)
//                                    if maxLength < 256 { // 说明是由targetSize重绘生成的且不够清晰的图（双倍采样），取不取等不重要
//                                        imageExist=false
//                                    }
//                                }
                                if ["gif", "svg", "ai"].contains(file.ext.lowercased()){
                                    // 由于无法正常生成指定大小的缩略图
                                    // Cannot generate thumbnail of specified size normally
                                    imageExist=true
                                }
                                if globalVar.HandledRawExtensions.contains(file.ext.lowercased()){
                                    // imageExist=true // RAW优先使用内嵌缩略图
                                    // RAW prioritizes embedded thumbnails
                                    // 由于现在实现了缩放内嵌缩略图，因此不再使用此逻辑
                                    // Since scaling embedded thumbnails is now implemented, this logic is no longer used
                                }
                            }
                            fileDB.unlock()
                            loadImageTaskPool.lock.unlock()
                            if imageExist == false {
                                // 开始缩略图步骤
                                // 获取缩略图开始之前版本 （注：已经用dirModel的方法）
                                // Get version before thumbnail starts (Note: dirModel method already used)
                                // let fileVer=file.ver
                                let url=URL(string: key.path)!
                                var image: NSImage? = nil
                                var getThumbFailed = false
                                if doNotActualRead{
                                    image = getFileTypeIcon(url: url)
                                    getThumbFailed = true
                                }else{
                                    if !publicVar.isGenHdThumb || noThumbSizeDueToSchedule { // publicVar.layoutType == .grid
                                        // image = getImageThumb(url: url, refSize: originalSize)
                                        image = ThumbImageProcessor.getImageCache(url: url, refSize: originalSize, isPreferInternalThumb: publicVar.isPreferInternalThumb, ver: ver)
                                    }else{
                                        // image = getImageThumb(url: url, size: revisedSize)
                                        image = ThumbImageProcessor.getImageCache(url: url, size: revisedSize, ver: ver)
                                    }
                                    if image == nil {
                                        image = getFileTypeIcon(url: url)
                                        getThumbFailed = true
                                    }
                                }
                                
                                // 目录则请求3个缩略图
                                // For directories, request 3 thumbnails
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
                                    // 注意：可能上面的下一轮执行完毕后才执行后面的代码
                                    // Note: Code below may execute after next round above completes
                                    DispatchQueue.main.async { [weak self] in
                                        guard let self = self else { return }
                                        
                                        fileDB.lock()
                                        let curFolder=fileDB.curFolder
                                        fileDB.unlock() 
                                        
                                        if ver != dirModel.ver {return}
                                        
                                        fileDB.lock()
                                        file.image=image
                                        file.getThumbFailed=getThumbFailed
                                        file.folderImages=folderImages
                                        fileDB.unlock()
                                        // 此处必须分开加锁解锁，因为下面这句调用底层会重入锁
                                        // Must lock/unlock separately here, as call below will re-enter lock
                                        if dir == curFolder {
                                            let indexPath = IndexPath(item: i, section: 0)
                                            if let item = collectionView.item(at: indexPath) as? CustomCollectionViewItem{
                                                fileDB.lock()
                                                item.configureWithImage(file,playAnimation:true)
                                                // log(i)
                                                if i == 0 {
                                                    let curTime = DispatchTime.now()
                                                    let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                                    let timeInterval = Double(nanoTime) / 1_000_000_000
                                                    log("Time taken to complete loading first image: \(timeInterval) seconds")
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
                // let memPhyUse = reportPhyMemoryUsage()
                
                // log("Memory usage: "+String(memUse), level: .warn)
                
                if LRUqueue.count >= 1 {
                    guard let lastLRUItem = LRUqueue.last else {continue}
                    
                    let overTime = (DispatchTime.now().uptimeNanoseconds-lastLRUItem.1.uptimeNanoseconds)/1000000000
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
                        // TODO: 有时在macos 15上观察到，图片占用的内存变成了与WindowServer的共享内存，此时无法直接获取大小
                        // TODO: Sometimes observed on macOS 15 that image memory becomes shared memory with WindowServer, making it impossible to directly get size
                        ifCantDetectMemUse = totalCount > memUseLimit * 2
                    }
                    
                    var debug = false
#if DEBUG
                    // 用来在debug环境复现问题
                    // Used to reproduce issues in debug environment
                    debug = true
#endif
                    
                    if (overTime > 600 && LRUqueue.count >= 2) || (Int(memUse) > memUseLimit) || (debug && LRUqueue.count >= 2) {
                        log("Memory free:", level: .warn)
                        log(lastLRUItem.0.removingPercentEncoding, level: .warn)
                        // 由于先置目录再请求缩略图，所以此处可保证安全
                        // Safe here because directory is set before requesting thumbnails
                        
                        if(lastLRUItem.0 != fileDB.curFolder){
                            // 不是当前目录
                            // Not current directory
                            fileDB.lock()
                            // TODO: 为什么这里可能为null？
                            // TODO: Why this could be null?
                            if let dirModel = fileDB.db[SortKeyDir(lastLRUItem.0)] {
                                dirModel.isMemClearedToAvoidRemainingTask=true
                                for fileModel in dirModel.files {
                                    fileModel.1.image=nil
                                    fileModel.1.folderImages=[NSImage]()
                                }
                            }else{
                                if debug {
                                    print("Null when release memory:\n",lastLRUItem.0)
                                    abort()
                                }
                            }
                            LRUqueue.removeLast()
                            fileDB.unlock()
                        }else{
                            // 是当前目录
                            // Is current directory
                            var indexPaths: Set<IndexPath> = []
                            var isInLargeView = false
                            var curImagePos = -1
                            // 注意此处是同步请求
                            // Note this is sync
                            DispatchQueue.main.sync { [weak self] in
                                guard let self = self else { return }
                                if publicVar.isInLargeView {
                                    isInLargeView = true
                                    curImagePos = currLargeImagePos
                                }
                                indexPaths = collectionView.indexPathsForVisibleItems()
                                // 进一步过滤
                                // Further filtering
                                let visibleRectRaw = mainScrollView.contentView.visibleRect
                                let scrollPos = visibleRectRaw.origin
                                let scrollWidth = visibleRectRaw.width
                                let scrollHeight = visibleRectRaw.height
                                // 注意这里乘了2
                                // Note: multiplied by 2 here
                                let visibleRect = NSRect(origin: scrollPos, size: CGSize(width: scrollWidth, height: scrollHeight*2))
                                indexPaths = indexPaths.filter { [weak self] indexPath in
                                    guard let self = self else { return true }
                                    let itemFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
                                    return itemFrame.intersects(visibleRect)
                                }
                            }
                            var itemArray: [Int] = indexPaths.map { $0.item }
                            itemArray.sort()
                            let indexMin = (itemArray.first ?? 0) - max(PRELOAD_THUMB_RANGE_PRE, itemArray.count)
                            let indexMax = (itemArray.last ?? 0) + max(PRELOAD_THUMB_RANGE_NEXT, itemArray.count*2)
                            
                            var indexMinOfLarge = -1
                            var indexMaxOfLarge = -1
                            if isInLargeView && curImagePos != -1 {
                                indexMinOfLarge = curImagePos - PRELOAD_THUMB_RANGE_PRE
                                indexMaxOfLarge = curImagePos + PRELOAD_THUMB_RANGE_NEXT
                            }
                            
                            if indexMax > indexMin {
                                fileDB.lock()
                                if let dirModel = fileDB.db[SortKeyDir(lastLRUItem.0)] {
                                    dirModel.isMemClearedToAvoidRemainingTask=true
                                    for fileModel in dirModel.files {
                                        // 如果不在任一范围内,才清除缩略图
                                        // Only clear thumbnail if not in any range
                                        if (fileModel.1.id < indexMin || fileModel.1.id > indexMax) &&
                                            (fileModel.1.id < indexMinOfLarge || fileModel.1.id > indexMaxOfLarge) {
                                            fileModel.1.image=nil
                                            fileModel.1.folderImages=[NSImage]()
                                        }
                                    }
                                }
                                fileDB.unlock()
                            }
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
                        //checkConsistencyAssert()
                    }
                }
            }
        }
        
    }
    
    @objc func scrollViewDidScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else { return }
        // 确保是针对我们感兴趣的ScrollView（如果有多个ScrollView）
        // Ensure it's the ScrollView we're interested in (if there are multiple ScrollViews)
        if scrollView == collectionView.enclosingScrollView {
            debounceSetLoadThumbPriority(interval: 0.1, ifNeedVisable: true)
        }
    }

    @objc func scrollViewScrollEnd(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else { return }
        // 确保是针对我们感兴趣的ScrollView（如果有多个ScrollView）
        // Ensure it's the ScrollView we're interested in (if there are multiple ScrollViews)
        if scrollView == collectionView.enclosingScrollView {
            debounceSetLoadThumbPriority(interval: 0.1, ifNeedVisable: true)
        }
    }

    func debounceSetLoadThumbPriority(interval: Double, ifNeedVisable: Bool){
        if publicVar.timer.intervalSafe(name: "scrollViewDidScrollSetLoadThumbPriority", second: interval) {
            setLoadThumbPriority(ifNeedVisable: ifNeedVisable)
        }
        
        scrollDebounceWorkItem?.cancel()
        scrollDebounceWorkItem = DispatchWorkItem {
            DispatchQueue.main.async { [weak self] in
                self?.setLoadThumbPriority(ifNeedVisable: ifNeedVisable)
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + interval, execute: scrollDebounceWorkItem!)
    }

    func setLoadThumbPriority(indexPath: IndexPath? = nil, range: (Int,Int) = (-1,1), ifNeedVisable: Bool, stopPlayVideo: Bool = false){

        var indexPaths: Set<IndexPath> = Set()
        if indexPath != nil {
            indexPaths=nearbyIndexPaths(around: [indexPath!], range: range)
        }else{
            indexPaths=collectionView.indexPathsForVisibleItems()
        }
        
        if ifNeedVisable {
            let visibleRectRaw = mainScrollView.contentView.visibleRect
            let scrollPos = visibleRectRaw.origin
            let scrollWidth = visibleRectRaw.width
            let scrollHeight = visibleRectRaw.height
            // 注意这里乘了2
            // Note: multiplied by 2 here
            let visibleRectExtended = NSRect(origin: scrollPos, size: CGSize(width: scrollWidth, height: scrollHeight*2))
            indexPaths = indexPaths.filter { indexPath in
                let itemFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
                return itemFrame.intersects(visibleRectExtended)
            }
            
            // 播放视频
            // Play video
            let visibleItems = collectionView.indexPathsForVisibleItems()
            let visibleRect = NSRect(origin: scrollPos, size: CGSize(width: scrollWidth, height: scrollHeight))
            let selectedIndexPaths = collectionView.selectionIndexPaths
            for indexPath in visibleItems {
                let itemFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
                let isSelected = selectedIndexPaths.contains(indexPath)
                if (publicVar.autoPlayVisibleVideo || (publicVar.autoPlaySelectedVideo && isSelected)) && itemFrame.intersects(visibleRect) && !stopPlayVideo {
                    if let item = collectionView.item(at: indexPath) as? CustomCollectionViewItem {
                        item.playVideo()
                    }
                }else{
                    if let item = collectionView.item(at: indexPath) as? CustomCollectionViewItem {
                        item.stopVideo()
                    }
                }
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
            
            // 预加载范围
            // Preload range
            var preloadRangePre = PRELOAD_THUMB_RANGE_PRE
            var preloadRangeNext = PRELOAD_THUMB_RANGE_NEXT
            if ifNeedVisable {
                preloadRangePre = max(PRELOAD_THUMB_RANGE_PRE, itemSorted.count)
                preloadRangeNext = max(PRELOAD_THUMB_RANGE_NEXT, itemSorted.count*2)
            }
            
            // 序号最大最小值
            // Index min and max values
            let itemIndexMin=max(itemSorted.first! - preloadRangePre, 0)
            let itemIndexMax=itemSorted.last! + preloadRangeNext
            
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
    
    func handleScrollWheel(_ event: NSEvent) {
        // log("Trackpad:",event.scrollingDeltaY,event.scrollingDeltaX)
        // log("Wheel:",event.deltaY)
        
        // 仅在大图模式下响应
        // Only respond in large view mode
        if largeImageView.isHidden {return}
        
        // 编辑模式下不响应
        // Do not respond in edit mode
        if largeImageView.isInEditMode {return}
        
        // 滚轮用作缩放时
        // When scroll wheel is used for zooming
        if globalVar.scrollMouseWheelToZoom || isCommandKeyPressed() {return}
        
        // 滚动滚轮或者双指操作触控板来移动图像
        // Scroll wheel or double finger operation on trackpad to move image
        if publicVar.isPanWhenZoomed && !publicVar.isLeftMouseDown && !publicVar.isRightMouseDown {
            let isTrackPad = abs(event.scrollingDeltaY)+abs(event.scrollingDeltaX) > abs(event.deltaY)
            if largeImageView.imageView.frame.height > largeImageView.frame.height || (isTrackPad && largeImageView.imageView.frame.width > largeImageView.frame.width) {
                if isTrackPad {
                    largeImageView.imageView.frame.origin.x += event.scrollingDeltaX
                    largeImageView.imageView.frame.origin.y -= event.scrollingDeltaY
                } else {
                    largeImageView.imageView.frame.origin.x += event.deltaX * 10
                    largeImageView.imageView.frame.origin.y -= event.deltaY * 10
                }
                // 限制图片不能完全移出视野范围
                // Limit image from being completely moved out of view
                let imageFrame = largeImageView.imageView.frame
                let viewFrame = largeImageView.frame
                
                // 检查是否完全超出视野
                // Check if completely out of view
                if imageFrame.maxX < 0 {
                    largeImageView.imageView.frame.origin.x = -imageFrame.width
                }
                if imageFrame.minX > viewFrame.width {
                    largeImageView.imageView.frame.origin.x = viewFrame.width
                }
                if imageFrame.maxY < 0 {
                    largeImageView.imageView.frame.origin.y = -imageFrame.height
                }
                if imageFrame.minY > viewFrame.height {
                    largeImageView.imageView.frame.origin.y = viewFrame.height
                }
                return
            }
        }
        
        // 屏蔽惯性阶段的滚动
        // Prevent scrolling in the inertia phase
        if event.momentumPhase == .changed
            && event.timestamp - lastScrollSwitchLargeImageTime > 0.2
        {
            return
        }
        
        // 以下是防止按住鼠标缩放后松开，滚轮惯性滚动造成切换
        // Prevent scrolling after releasing the mouse button and the inertia of the scroll wheel from causing switching
        if publicVar.isRightMouseDown || publicVar.isLeftMouseDown {
            _ = publicVar.timer.intervalSafe(name: "largeImageZoomForbidSwitch", second: -1)
            return
        }
        if !publicVar.timer.intervalSafe(name: "largeImageZoomForbidSwitch", second: 0.4, execute: false){
            _ = publicVar.timer.intervalSafe(name: "largeImageZoomForbidSwitch", second: -1)
            return
        }
        
        // 屏蔽横向滚动
        // Prevent horizontal scrolling
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || abs(event.deltaX) > abs(event.deltaY) {
            return
        }

        var deltaY=0.0
        if abs(event.scrollingDeltaY)+abs(event.scrollingDeltaX) > abs(event.deltaY) {
            // 通常是触控板事件
            // Usually trackpad event
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
            // 通常是滚轮事件
            // Usually wheel event
            deltaY=event.deltaY
            // 没有使用LineMouse时
            // When not using LineMouse
            if abs(deltaY) < 1.5 {
                deltaY = 1.5 * deltaY / abs(deltaY)
            }
        }
        deltaY *= globalVar.scrollSensitivityRatio
        cumulativeScroll += deltaY
        
        if abs(cumulativeScroll)<1.4 {return}
        if publicVar.timer.intervalSafe(name: "scrollLargeImage", second: 0.8/pow(abs(cumulativeScroll),1.0/1.0)) != true {
            cumulativeScroll=0
            return
        }

        if cumulativeScroll > 0 {
            // 向上滚动
            // Scroll up
            previousLargeImage()
        } else if cumulativeScroll < 0 {
            // 向下滚动
            // Scroll down
            nextLargeImage()
        }
        cumulativeScroll=0
        lastScrollSwitchLargeImageTime=event.timestamp
    }

    func startWatchingDirectory(atPath path: String) {
        // TODO: 有大量write事件且造成go-nfsv4进程繁忙
        // TODO: Has many write events and causes go-nfsv4 process to be busy
        if path.contains("Cryptomator") {
            return
        }
        
        // 递归模式不监听
        // Recursive mode doesn't listen
        if publicVar.isRecursiveMode {
            return
        }
        
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
            // Print event type
            let event = watchDispatchSource!.data
            // logFileSystemEvent(event)
            
            // 计划刷新
            // Schedule refresh
            readInfoTaskPoolLock.lock()
            let isReadInfoFinish = (readInfoTaskPool.count == 0)
            readInfoTaskPoolLock.unlock()
            loadImageTaskPool.lock.lock()
            let isLoadThumbFinish = (loadImageTaskPool.getTaskNum() == 0)
            loadImageTaskPool.lock.unlock()
            let isInProgress = (publicVar.isInStageOneProgress || publicVar.isInStageTwoProgress || publicVar.isInStageThreeProgress
                                || !isReadInfoFinish || !isLoadThumbFinish)
            // log(publicVar.isInStageOneProgress,publicVar.isInStageTwoProgress,publicVar.isInStageThreeProgress,!isReadInfoFinish,!isLoadThumbFinish,level: .debug)
            if VolumeManager.shared.isExternalVolume(path) && isInProgress && publicVar.fileChangedCount == 0 {
                // samba的smb读取时会改变atime，产生write和attrib事件
                // Samba SMB reading will change atime, generating write and attrib events
                // log("ExternalVol FileSystemEvent DoNot Refresh.",level: .debug)
            }else{
                // log("FileSystemEvent Refreshd",level: .debug)
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
            folderMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                self?.dirURLCache.removeAll()
                self?.refreshAll(needStopAutoScroll: false, needLoadThumbPriority: true)
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
    
    override func rightMouseDown(with event: NSEvent) {
        // publicVar.isRightMouseDown = true
        if !largeImageView.isHidden {return}
        
        initialMouseLocation = event.locationInWindow
        lastMouseLocation = initialMouseLocation
        gestureState = .none

        super.rightMouseDown(with: event)
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
        // Use threshold to avoid direction changes from slight movements
        let threshold: CGFloat = 4.0

        let newDirection: RightMouseGestureDirection?
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

        super.rightMouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        // publicVar.isRightMouseDown = false
        if !largeImageView.isHidden {return}
        
        gestureTriggeredSwitch = false
        analyzeGesture(doAction: true)
        directionHistory.removeAll()
//        drawingView?.containerView.isHidden=true
        
        // 由于捕获屏幕渐变切换的方式，此时后半段不要播放动画
        // Due to screen capture fade transition method, don't play animation in latter half
        if gestureTriggeredSwitch {
            drawingView?.containerView.alphaValue = 0
            drawingView?.containerView.isHidden = true
        }else{
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                drawingView?.containerView.animator().alphaValue = 0
            }, completionHandler: {
                self.drawingView?.containerView.isHidden = true
            })
        }
        
        if event.locationInWindow.y > self.mainScrollView.bounds.height {
            popTitlebarMenu(with: event)
        }

        super.rightMouseUp(with: event)
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
    
    func handleDraggedFiles(_ urls: [URL]) {
        var folderPath="file:///"
        var path="file:///"
        
        let viewController=self
        
        if urls.count == 1 {
            if urls[0].hasDirectoryPath {
                folderPath=""+urls[0].absoluteString
                if viewController.publicVar.isInLargeView {
                    // 由于图像关闭有动画，导致大图时瞬间关闭再打开大图会有bug，因此暂时只对目录关闭大图
                    // Due to image close animation, instantly closing and reopening large image when in large view causes bug, so temporarily only close large image for directories
                    viewController.closeLargeImage(0)
                }
            }else{
                // 限制文件类型
                // Limit file types
                if !globalVar.HandledImageAndRawExtensions.contains(urls[0].pathExtension.lowercased()) {return}
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
    
}
