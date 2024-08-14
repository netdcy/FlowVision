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

class PublicVar{
    weak var refView: NSView!

    var layoutType: LayoutType = .justified {
        didSet {updateToolbar()}
    }
    var sortType: SortType = .pathA
    var isSortFolderFirst: Bool = true
    var isLargeImageFitWindow = true
    
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
    var isDirTreeHidden = false
    var lastLargeImageIdInImage: Int = 0
    var isCollectionViewFirstResponder: Bool = false
    var isOutlineViewFirstResponder: Bool = false
    var isShowExif: Bool = false {
        didSet {
            getViewController(refView)?.largeImageView.exifTextView.isHidden = !isShowExif
            updateToolbar()
        }
    }
    var thumbSize = 512
    var isNeedChangeLayoutType = false
    var justifiedLayout = CustomFlowLayout() //JQCollectionViewAlignLayout()
    var waterfallLayout = WaterfallLayout()
    //weak var viewController:ViewController?
    var timer = MyTimer()
    
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
    
    var LRUqueue = [(String,DispatchTime)]()
    var LRUcount = 0
    
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

    override func viewDidLoad() {
        super.viewDidLoad()
        
        log("开始viewDidLoad")
        
        publicVar.refView=collectionView
        //publicVar.viewController=self
        
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
        
        //读取用户配置
        let defaults = UserDefaults.standard
        
        //TODO: 没有工具栏时，载入时折叠且divider宽度设为0会造成菜单栏变白
        if let savedIsDirTreeHidden = UserDefaults.standard.value(forKey: "isDirTreeHidden") as? Bool {
            publicVar.isDirTreeHidden=savedIsDirTreeHidden
        }
        if publicVar.isDirTreeHidden{
            splitView.setPosition(0, ofDividerAt: 0)
        }

        if let savedIsLargeImageFitWindow = UserDefaults.standard.value(forKey: "isLargeImageFitWindow") as? Bool {
            publicVar.isLargeImageFitWindow=savedIsLargeImageFitWindow
        }
        
        if let layoutType: LayoutType = defaults.enumValue(forKey: "layoutType"){
            publicVar.layoutType=layoutType
        }
        //collectionView.collectionViewLayout=LeftAlignedCollectionViewFlowLayout()
        if publicVar.layoutType == .waterfall {
            collectionView.collectionViewLayout = publicVar.waterfallLayout
        }else if publicVar.layoutType == .justified {
            collectionView.collectionViewLayout = publicVar.justifiedLayout
        }else if publicVar.layoutType == .grid {
            collectionView.collectionViewLayout = publicVar.justifiedLayout
        }else {
            collectionView.collectionViewLayout = publicVar.justifiedLayout
        }
        
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
            NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll(_:)), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
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
                
                // 检查按键是否是 "A" 键
                if event.keyCode == 0x00 && noModifierKey {
                    closeLargeImage(0)
                    switchDirByDirection(direction: .left, stackDeep: 0)
                }
                // 检查按键是否是 "D" 键
                if event.keyCode == 0x02 && noModifierKey {
                    closeLargeImage(0)
                    switchDirByDirection(direction: .right, stackDeep: 0)
                }
                // 检查按键是否是 "W" 键
                if event.keyCode == 0x0D && noModifierKey {
                    closeLargeImage(0)
                    switchDirByDirection(direction: .up, stackDeep: 0)
                }
                // 检查按键是否是 "S" 键
                if event.keyCode == 0x01 && noModifierKey {
                    closeLargeImage(0)
                    switchDirByDirection(direction: .down, stackDeep: 0)
                }
                // 检查按键是否是 "R" 键
                if event.keyCode == 15 && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actRefresh()
                    }else{
                        refreshAll()
                    }
                }
                
                // 检查按键是否是 Esc 键
                if event.keyCode == 53 {
                    self.view.window?.close()
                }
                
                // 检查按键是否是 Delete(117) Backspace(51) 键
                if event.keyCode == 117 || event.keyCode == 51 {
                    //如果焦点在OutlineView
                    if publicVar.isOutlineViewFirstResponder{
                        outlineView.actDelete(isByKeyboard: true)
                        
                    }
                    //如果焦点在CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        handleDelete()
                    }
                }
                
                // 检查按键是否是 空格 键
                if event.keyCode == 49 && noModifierKey {
                    if publicVar.isInLargeView{
                        closeLargeImage(0)
                    }else{
                        if let indexPath = collectionView.selectionIndexPaths.first {
                            if publicVar.isCollectionViewFirstResponder{
                                openLargeImage(indexPath)
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
                
                // 检查按键是否是 12345 12345(小键盘) 键
                if ([18,19,20,21,23,83,84,85,86,87].contains(event.keyCode)) && noModifierKey {
                    if [18,83].contains(event.keyCode) { // 1
                        adjustWindowMaximize()
                    }else if [19,84].contains(event.keyCode){ // 2
                        adjustWindowSuitable()
                    }else if ([23,87].contains(event.keyCode)){ // 5
                        //adjustWindowToCenter()
                    }else{
                        if publicVar.isInLargeView {
                            if ([20,85].contains(event.keyCode)){ // 3
                                adjustWindowImageActual()
                            }else if ([21,86].contains(event.keyCode)){ // 4
                                adjustWindowImageCurrent()
                            }
                        }
                    }
                }
                
                // 检查按键是否是 "~"
                if event.keyCode == 50 && noModifierKey {
                    togglePortableMode()
                }
                
                // 检查按键是否是 "I"
                if event.keyCode == 34 && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actShowExif()
                    }
                }
                
                // 检查按键是否是 "E"
                if event.keyCode == 14 && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actRotateR()
                    }
                }
                
                // 检查按键是否是 "Q"
                if event.keyCode == 12 && noModifierKey {
                    if publicVar.isInLargeView{
                        largeImageView.actRotateL()
                    }
                }
                
                // 检查按键是否是 ➡️⬇️PageDown 键
                if event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 121 {
                    if publicVar.isInLargeView{
                        nextLargeImage()
                    }
                }
                // 检查按键是否是 ⬅️⬆️PageUp 键
                if event.keyCode == 123 || event.keyCode == 126 || event.keyCode == 116 {
                    if publicVar.isInLargeView{
                        previousLargeImage()
                    }
                }
                
                // 检查按键是否是 Tab 键
                if event.keyCode == 48 && noModifierKey {
                    if !publicVar.isInLargeView{
                        if publicVar.isOutlineViewFirstResponder{
                            view.window?.makeFirstResponder(collectionView)
                        }else if publicVar.isCollectionViewFirstResponder{
                            view.window?.makeFirstResponder(outlineView)
                        }
                    }
                }

                // 检查按键是否是 "⬅️➡️⬆️⬇️" 键
                if event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 126 {
                    if !publicVar.isInLargeView{
                        //如果焦点在OutlineView
                        if publicVar.isOutlineViewFirstResponder{
                            if let outlineView = outlineView {
                                let selectedRow=outlineView.selectedRow
                                if event.keyCode == 126 {//⬆️
                                    if selectedRow > 0 {
                                        let previousRow = selectedRow - 1
                                        outlineView.selectRowIndexes(IndexSet(integer: previousRow), byExtendingSelection: false)
                                        outlineView.scrollRowToVisible(previousRow) // 可选：滚动视图以确保选中的项可见
                                    }
                                }
                                if event.keyCode == 125 {//⬇️
                                    if selectedRow != -1 && selectedRow < outlineView.numberOfRows - 1 {
                                        let nextRow = selectedRow + 1
                                        outlineView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
                                        outlineView.scrollRowToVisible(nextRow) // 可选：滚动视图以确保选中的项可见
                                    }
                                }
                                if event.keyCode == 124 || event.keyCode == 123 {//⬅️➡️
                                    // 获取行对应的条目
                                    if let item = outlineView.item(atRow: selectedRow) {
                                        if outlineView.isItemExpanded(item) {
                                            outlineView.collapseItem(item)
                                        } else {
                                            outlineView.expandItem(item)
                                        }
                                    }
                                }
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
                                newIndexPath = findClosestItem(currentItem: currentItem, direction: event.keyCode)
                                
                                // 还原滚动位置
                                scrollView.contentView.setBoundsOrigin(savedContentOffset)
                                scrollView.reflectScrolledClipView(scrollView.contentView)
                                
                                if let newIndexPath = newIndexPath {
                                    collectionView.deselectAll(nil)
                                    collectionView.selectItems(at: [newIndexPath], scrollPosition: [])
                                    collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [newIndexPath])
                                    collectionView.scrollToItems(at: [newIndexPath], scrollPosition: .nearestHorizontalEdge)
                                }

                            }else if let collectionView = collectionView {
                                var newIndexPath = IndexPath(item: 0, section: 0)
                                collectionView.selectItems(at: [newIndexPath], scrollPosition: [])
                                collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [newIndexPath])
                                collectionView.scrollToItems(at: [newIndexPath], scrollPosition: .nearestHorizontalEdge)
                            }
                        }
                    }
                }
                
                // 检查按键是否是 F2、回车、小键盘回车 键
                if event.keyCode == 120 || event.keyCode == 36 || event.keyCode == 76 {
                    //如果焦点在OutlineView
                    if publicVar.isOutlineViewFirstResponder{
                        outlineView.actRename(isByKeyboard: true)
                    }
                    
                    //如果焦点在CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        if publicVar.selectedUrls().count == 1 {
                            renameAlert(url: publicVar.selectedUrls()[0])
                        }
                    }
                }
                
                // 检查按键是否是 "F" 键
                if event.keyCode == 3 && noModifierKey {
                    if !publicVar.isInLargeView{
                        toggleSidebar()
                    }
                }
                
                // 检查按键是否是 "T" 键
                if event.keyCode == 17 && noModifierKey {
                    toggleOnTop()
                }
                
                // 检查按键是否是 -、-(小键盘) 键
                if event.keyCode == 27 || event.keyCode == 78 {
                    if publicVar.isInLargeView{
                        largeImageView.zoom(direction: -1)
                    }else{
                        adjustThumbSizeByDirection(direction: -1)
                    }
                }
                
                // 检查按键是否是 +(=)、+(小键盘) 键
                if event.keyCode == 24 || event.keyCode == 69 {
                    if publicVar.isInLargeView {
                        largeImageView.zoom(direction: +1)
                    }else{
                        adjustThumbSizeByDirection(direction: +1)
                    }
                }
                
                // 检查按键是否是 0、0(小键盘) 键
                if event.keyCode == 29 || event.keyCode == 82 {
                    if publicVar.isInLargeView {
                        changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: true)
                    }else{
                        adjustThumbSizeByDirection(direction: 0)
                    }
                }
                
                // 检查按键是否是 "N" 键
                if event.keyCode == 45 && noModifierKey {
                    //如果焦点在CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        handleCopyToDownload()
                    }
                }
                
                // 检查按键是否是 "M" 键
                if event.keyCode == 46 && noModifierKey {
                    //如果焦点在CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        handleMoveToDownload()
                    }
                }

            }
            
            // 处理弹出重命名对话框时的复制粘贴操作
            if !publicVar.isKeyEventEnabled && event.modifierFlags.contains(.command) {
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
    
    func changeSortType(_ sortType: SortType){
        fileDB.lock()
        publicVar.sortType = sortType
        globalVar.randomSeed = Int.random(in: 0...Int.max)
        for dirModel in fileDB.db {
            dirModel.1.changeSortType(publicVar.sortType, isSortFolderFirst: publicVar.isSortFolderFirst)
        }
        fileDB.unlock()
        refreshCollectionView([])
    }

    func toggleSidebar(){
        hasManualToggleSidebar=true
        publicVar.isDirTreeHidden.toggle()
        if !publicVar.isDirTreeHidden{
            splitView.setPosition(270, ofDividerAt: 0)
        }else{
            splitView.setPosition(0, ofDividerAt: 0)
        }

        let defaults = UserDefaults.standard
        defaults.set(publicVar.isDirTreeHidden, forKey: "isDirTreeHidden")
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
    
    func toggleIsShowHiddenFile(){
        globalVar.isShowHiddenFile.toggle()
        UserDefaults.standard.set(globalVar.isShowHiddenFile, forKey: "isShowHiddenFile")
        refreshAll([])
    }
    
    func toggleIsShowAllTypeFile(){
        globalVar.isShowAllTypeFile.toggle()
        UserDefaults.standard.set(globalVar.isShowAllTypeFile, forKey: "isShowAllTypeFile")
        refreshAll([])
    }
    
    func toggleIsHideRawFile(){
        globalVar.isHideRawFile.toggle()
        UserDefaults.standard.set(globalVar.isHideRawFile, forKey: "isHideRawFile")
        setFileExtensions()
        refreshCollectionView([])
    }
    
    func toggleIsHideVideoFile(){
        globalVar.isHideVideoFile.toggle()
        UserDefaults.standard.set(globalVar.isHideVideoFile, forKey: "isHideVideoFile")
        setFileExtensions()
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
                
                // 确定最大比例
                var ratioWidth = globalVar.portableListWidthRatio
                var ratioHeight = globalVar.portableListHeightRatio
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
    
    func switchToJustifiedView(){
        let defaults = UserDefaults.standard
        defaults.setEnum(LayoutType.justified, forKey: "layoutType")
        publicVar.layoutType = .justified
        publicVar.isNeedChangeLayoutType = true
        refreshCollectionView([])
    }
    
    func switchToGridView(){
        let defaults = UserDefaults.standard
        defaults.setEnum(LayoutType.grid, forKey: "layoutType")
        publicVar.layoutType = .grid
        publicVar.isNeedChangeLayoutType = true
        refreshCollectionView([])
    }
    
    func switchToWaterfallView(){
        let defaults = UserDefaults.standard
        defaults.setEnum(LayoutType.waterfall, forKey: "layoutType")
        publicVar.layoutType = .waterfall
        publicVar.isNeedChangeLayoutType = true
        refreshCollectionView([])
    }
    
    func switchToDetailView(){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.detail, forKey: "layoutType")
//        publicVar.layoutType = .detail
//        publicVar.isNeedChangeLayoutType = true
//        refreshCollectionView([])
    }
    
    func changeThumbSize(thumbSize: Int){
        publicVar.thumbSize = thumbSize
        changeWaterfallLayoutNumberOfColumns()
        refreshCollectionView([])
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
    
    func nearbyIndexPaths(around indexPaths: Set<IndexPath>, range: (Int,Int)) -> Set<IndexPath> {
        guard let dataSource = collectionView.dataSource else { return [] }
        
        var expandedIndexPaths = Set<IndexPath>()
        
        for indexPath in indexPaths {
            let section = indexPath.section
            let item = indexPath.item
            
            for i in max(0, item + range.0)...(item + range.1) {
                if i < dataSource.collectionView(collectionView, numberOfItemsInSection: section) {
                    expandedIndexPaths.insert(IndexPath(item: i, section: section))
                }
            }
        }
        
        return expandedIndexPaths
    }
    
    func findClosestItem(currentItem: NSCollectionViewItem, direction: UInt16) -> IndexPath? {
        //let indexPaths = collectionView.indexPathsForVisibleItems()
        let indexPaths = nearbyIndexPaths(around: collectionView.indexPathsForVisibleItems(), range: (-20,20))
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
            case 123: // Left arrow key
                if itemCenter.x < currentCenter.x && (itemCenter.y == currentCenter.y || publicVar.layoutType == .waterfall) {
                    distance = hypot(currentCenter.x - itemCenter.x, itemCenter.y - currentCenter.y)
                    valid = true
                }
            case 124: // Right arrow key
                if itemCenter.x > currentCenter.x && (itemCenter.y == currentCenter.y || publicVar.layoutType == .waterfall) {
                    distance = hypot(currentCenter.x - itemCenter.x, itemCenter.y - currentCenter.y)
                    valid = true
                }
            case 125: // Up arrow key (Adjusted to move up)
                if itemCenter.y > currentCenter.y && (itemCenter.x == currentCenter.x || publicVar.layoutType != .waterfall) {
                    distance = hypot(currentCenter.x - itemCenter.x, itemCenter.y - currentCenter.y)
                    valid = true
                }
            case 126: // Down arrow key (Adjusted to move down)
                if itemCenter.y < currentCenter.y && (itemCenter.x == currentCenter.x || publicVar.layoutType != .waterfall) {
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
    
    func handleDelete() {
        if publicVar.selectedUrls().count == 0 {return}
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("delete", comment: "删除")
        alert.informativeText = NSLocalizedString("ask-to-delete", comment: "你确定要将这些文件移动到废纸篓吗？")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("delete", comment: "删除"))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: "取消"))
        alert.icon = NSImage(named: NSImage.cautionName) // 设置系统警告图标

        publicVar.isKeyEventEnabled=false
        let response = alert.runModal()
        publicVar.isKeyEventEnabled=true

        if response == .alertFirstButtonReturn {
            // 用户确认删除
            let fileManager = FileManager.default
            var urlsToDelete = [URL]()
            
            for url in publicVar.selectedUrls() {
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
                log("没有需要删除的文件")
            }
            
        } else {
            // 用户取消操作
            log("删除操作已取消")
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
        if targetURL != nil {
            destinationURL = targetURL
        }else{
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
        
        var shouldReplaceAll = false
        
        publicVar.isKeyEventEnabled=false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            var destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)
            
            // 如果是在同一目录复制粘贴，则修改名称
            if fileURL.deletingLastPathComponent() == destinationURL {
                destURL = getUniqueDestinationURL(for: destURL)
            }
            
            if FileManager.default.fileExists(atPath: destURL.path) {
                // 文件已存在，弹出对话框询问用户是否覆盖
                if shouldReplaceAll || showReplaceDialog(for: destURL, shouldReplaceAll: &shouldReplaceAll) {
                    do {
                        try FileManager.default.removeItem(at: destURL)
                        try FileManager.default.copyItem(at: fileURL, to: destURL)
                    } catch {
                        log("粘贴失败 \(fileURL): \(error)")
                    }
                }
            } else {
                do {
                    try FileManager.default.copyItem(at: fileURL, to: destURL)
                } catch {
                    log("粘贴失败 \(fileURL): \(error)")
                }
            }
        }
        publicVar.isKeyEventEnabled=true
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
        //let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems else { return }
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        var destinationURL: URL? = nil
        if targetURL != nil {
            destinationURL = targetURL
        }else{
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
        
        var shouldReplaceAll = false
        
        publicVar.isKeyEventEnabled=false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            let destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)
            
            // 如果是在同一目录移动，则不作动作
            if fileURL.deletingLastPathComponent() == destinationURL {
                log("不能将文件/文件夹移动到相同目录中。")
                continue
            }

            if FileManager.default.fileExists(atPath: destURL.path) {
                // 文件已存在，弹出对话框询问用户是否覆盖
                if shouldReplaceAll || showReplaceDialog(for: destURL, shouldReplaceAll: &shouldReplaceAll) {
                    do {
                        try FileManager.default.removeItem(at: destURL)
                        try FileManager.default.moveItem(at: fileURL, to: destURL)
                    } catch {
                        log("移动失败 \(fileURL): \(error)")
                    }
                }
            } else {
                do {
                    try FileManager.default.moveItem(at: fileURL, to: destURL)
                } catch {
                    log("移动失败 \(fileURL): \(error)")
                }
            }
        }
        publicVar.isKeyEventEnabled=true
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

    func showReplaceDialog(for destinationURL: URL, shouldReplaceAll: inout Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("has-exist-in-dest1", comment: "目标文件夹中已存在名为") + destinationURL.lastPathComponent
                            + NSLocalizedString("has-exist-in-dest2", comment: "的文件。")
        alert.informativeText = NSLocalizedString("do-you-want-replace", comment: "你要用正在粘贴或移动的文件替换它吗？")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("replace", comment: "替换"))
        alert.addButton(withTitle: NSLocalizedString("replace-all", comment: "全部替换"))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: "取消"))
        alert.icon = NSImage(named: NSImage.infoName)// 设置系统通知图标
        
        publicVar.isKeyEventEnabled=false
        let response = alert.runModal()
        publicVar.isKeyEventEnabled=true
        
        switch response {
        case .alertFirstButtonReturn:
            // 用户选择“替换”
            return true
        case .alertSecondButtonReturn:
            // 用户选择“全部替换”
            shouldReplaceAll = true
            return true
        default:
            // 用户选择“取消”
            return false
        }
    }
    
    func handleNewFolder(targetURL: URL? = nil) -> Bool {
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
        
        alert.addButton(withTitle: NSLocalizedString("ok", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: "取消"))
        
        publicVar.isKeyEventEnabled=false
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
                guard let destinationURL=destinationURL else {return false}
                
                let newFolderURL = destinationURL.appendingPathComponent(folderName)
                
                // 检查是否存在同名文件
                if FileManager.default.fileExists(atPath: newFolderURL.path) {
                    showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                }else{
                    // 执行新建操作
                    do {
                        try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: true, attributes: nil)
                        log("新建文件夹成功: \(newFolderURL.path)")
                        return true
                    } catch {
                        log("新建文件夹失败: \(error)")
                    }
                }
            }
        }
        return false
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
                refreshAll([])
            }
            lastTheme=theme
        }
    }
    
    func refreshAll(_ reloadThumbType: [FileType] = [.folder]){
        refreshTreeView()
        refreshCollectionView(reloadThumbType)
    }
    
    func refreshCollectionView(_ reloadThumbType: [FileType] = [.folder]){
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
        switchDirByDirection(direction: .zero, doCollapse: false, stackDeep: 0)
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
        if publicVar.layoutType == .grid {
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
            publicVar.thumbSize = 512
        }else{
            let lastWaterFallNumberOfColumns = publicVar.waterfallLayout.numberOfColumns
            while lastWaterFallNumberOfColumns == publicVar.waterfallLayout.numberOfColumns {
                if let currentIndex = THUMB_SIZES.firstIndex(of: publicVar.thumbSize) {
                    let newIndex = max(0, min(THUMB_SIZES.count - 1, currentIndex + direction))
                    publicVar.thumbSize = THUMB_SIZES[newIndex]
                    if currentIndex == newIndex {
                        return
                    }
                    changeWaterfallLayoutNumberOfColumns()
                }else{
                    return
                }
            }
        }
        changeThumbSize(thumbSize: publicVar.thumbSize)
    }
    
    func changeWaterfallLayoutNumberOfColumns(){
        var singleWidth = Double(publicVar.thumbSize) / 512 * 300
        
        var totalWidth=self.mainScrollView.bounds.width-16-10
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
        var WIDTH_THRESHOLD=6.0/1920*512/Double(publicVar.thumbSize)
        
        if publicVar.layoutType == .grid {
            WIDTH_THRESHOLD=10.0/1920*512/Double(publicVar.thumbSize)
        }
        //TODO: 这里滚动条宽度？
        var totalWidth=self.mainScrollView.bounds.width-16-10
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
                lastSingleHeight = thumbSize.height - (12+0)
            }
        }
        if layoutCalcPos < count {
            for i in layoutCalcPos...(count-1) {
                guard let key = fileDB.db[SortKeyDir(targetFolder)]!.files.elementSafe(atOffset: i)?.0 else{break}
                guard var originalSize=fileDB.db[SortKeyDir(targetFolder)]!.files[key]!.originalSize else{break}
                if fileDB.db[SortKeyDir(targetFolder)]!.files[key]!.canBeCalcued != true {break}

                if publicVar.layoutType == .grid { originalSize=DEFAULT_SIZE }
                sum+=(originalSize.width/originalSize.height)
                singleIds.append(key)
                if sum>=actualThreshold || i==fileDB.db[SortKeyDir(targetFolder)]!.files.count-1 {
                    sum=max(sum,actualThreshold)
                    var singleHeight = (totalWidth - (12.0+10.0) * Double(singleIds.count))/sum
                    if publicVar.layoutType == .grid && lastSingleHeight != nil { singleHeight=lastSingleHeight! } //防止最后一行不一样大小
                    lastSingleHeight=singleHeight
                    for singleId in singleIds{
                        var originalSizeSingle=fileDB.db[SortKeyDir(targetFolder)]!.files[singleId]!.originalSize!
                        
                        if publicVar.layoutType == .grid { originalSizeSingle=DEFAULT_SIZE }
                        
                        var singleWidth = originalSizeSingle.width/originalSizeSingle.height*singleHeight
                        
                        if publicVar.layoutType == .waterfall {
                            let numberOfColumns=Double(publicVar.waterfallLayout.numberOfColumns)
                            let cellPadding=publicVar.waterfallLayout.cellPadding
                            singleWidth = totalWidth/numberOfColumns-2*cellPadding-12
                            singleHeight = originalSizeSingle.height/originalSizeSingle.width*singleWidth
                        }
                        
                        let size=NSSize(width: singleWidth+12, height: singleHeight+12+0)
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
                fullTitle += String(format: "%d %@ ", folderCount, NSLocalizedString("folder", comment: "目录"))
            }
            if imageCount != 0 {
                fullTitle += String(format: "%d %@ ", imageCount, NSLocalizedString("image", comment: "图像"))
            }
            if videoCount != 0 {
                fullTitle += String(format: "%d %@ ", videoCount, NSLocalizedString("video", comment: "视频"))
            }
            if otherCount != 0 {
                fullTitle += String(format: "%d %@ ", otherCount, NSLocalizedString("other", comment: "其它"))
            }
            fullTitle=fullTitle.trimmingCharacters(in: .whitespaces)
            //                if folderCount == 0 && imageCount == 0 && videoCount == 0 && otherCount == 0 {
            //                    windowTitle += NSLocalizedString("empty", comment: "空")
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
    
    func switchDirByDirection(direction rawdirection: GestureDirection, dest: String = "", doCollapse: Bool = true, expandLast: Bool = true, skip: Bool = false, stackDeep: Int){

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
                      sameLevel: secondDirection == .down, skip: skip)
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
        LRUMemRecord(path: nextFolder)
        
        let defaults = UserDefaults.standard
        defaults.set(nextFolder, forKey: "lastFolder")

    }

    
    func treeTraversal(folderURL: URL, round: Int, initURL: URL, direction: GestureDirection, sameLevel: Bool = false, skip: Bool = false) {
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
        var properties: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        if VolumeManager.shared.isExternalVolume(folderURL) {
            properties = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey]
        }
        if !skip {
            do {
                //读取内容
                //let folderURL = URL(string: path)!
                contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: properties, options: [])
                //contents.sort { $0.absoluteString < $1.absoluteString }
                //contents.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }catch{
                
            }
        }
        
        //过滤隐藏文件
        contents = contents.filter { url in
            if VolumeManager.shared.isExternalVolume(url) {return true} //外置卷则不获取属性避免频繁请求
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
            return !isHidden || globalVar.isShowHiddenFile
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
        for file in contents {
            if HandledFileExtensions.contains(file.pathExtension.lowercased()) || (globalVar.isShowAllTypeFile && file.pathExtension.lowercased() != "") {
                filesUrlInFolder.append(file)
            }
            if HandledImageExtensions.contains(file.pathExtension.lowercased()) {
                imageCount+=1
            }
            if HandledVideoExtensions.contains(file.pathExtension.lowercased()) {
                videoCount+=1
            }
            if HandledSearchExtensions.contains(file.pathExtension.lowercased()) {
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
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.folderCount=subFolders.count
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.fileCount=fileCount
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.imageCount=imageCount
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.videoCount=videoCount
        fileDB.db[SortKeyDir(folderURL.absoluteString)]!.isMemClearedToAvoidRemainingTask=false
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
        if !skip && (initURL != folderURL || direction == .zero) {
            let folderpath = folderURL.absoluteString
            fileDB.lock()
            //log(filesInFolder.count)
            for (i,filePath) in filesInFolder.enumerated(){
                var fileSortKey:SortKeyFile
                let isDir:Bool
                if filePath.hasSuffix("_FolderMark") {
                    fileSortKey=SortKeyFile(String(filePath.dropLast("_FolderMark".count)), isDir: true, isInSameDir: true, sortType: publicVar.sortType, isSortFolderFirst: publicVar.isSortFolderFirst)
                    isDir=true
                }else{
                    fileSortKey=SortKeyFile(filePath, isInSameDir: true, sortType: publicVar.sortType, isSortFolderFirst: publicVar.isSortFolderFirst)
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
                var newFileModel=FileModel(path: fileSortKey.path, ver: fileDB.db[SortKeyDir(folderpath)]!.ver, isDir: isDir, fileSize: fileSize, createDate: createDate, modDate: modDate, addDate: addDate, doNotActualRead: doNotActualRead)
                //newFileModel.folderImageCount=fileCount
                //log(fileSortKey.path)
                if fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] != nil {
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.ver = fileDB.db[SortKeyDir(folderpath)]!.ver
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.canBeCalcued=false
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.isDir=isDir
                    //fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.folderImageCount=fileCount
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.doNotActualRead=doNotActualRead
                    //检查文件是否有变化
                    if !isDir{
                        if fileSize != fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.fileSize || modDate != fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey]?.modDate {
                            fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] = newFileModel
                        }
                    }
                }else{
                    fileDB.db[SortKeyDir(folderpath)]!.files[fileSortKey] = newFileModel
                }
            }
            for ele in fileDB.db[SortKeyDir(folderpath)]!.files{
                //log(ele.0.path.removingPercentEncoding)
                if ele.1.ver != fileDB.db[SortKeyDir(folderpath)]!.ver {
                    fileDB.db[SortKeyDir(folderpath)]!.files.removeValue(forKey: ele.0)
                }
            }
            var id=0
            var idInImage=0
            for ele in fileDB.db[SortKeyDir(folderpath)]!.files{
                if !ele.1.isDir{
                    ele.1.ext=URL(string: ele.1.path)!.pathExtension.lowercased()
                    if HandledImageExtensions.contains(ele.1.ext) {
                        ele.1.type = .image
                        ele.1.idInImage = idInImage
                        idInImage += 1
                    }else if HandledVideoExtensions.contains(ele.1.ext) {
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
            fileDB.unlock()
        }
        
        
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
            if let index=fileDB.db[SortKeyDir(path)]?.files.index(forKey: SortKeyFile(filename, needGetProperties: true, sortType: publicVar.sortType, isSortFolderFirst: publicVar.isSortFolderFirst)),
               let offset=fileDB.db[SortKeyDir(path)]?.files.offset(of: index),
               let file=fileDB.db[SortKeyDir(path)]?.files[SortKeyFile(filename, needGetProperties: true, sortType: publicVar.sortType, isSortFolderFirst: publicVar.isSortFolderFirst)],
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
            }else{
                fileDB.unlock()
            }
            
        }
        
        if publicVar.isNeedChangeLayoutType {
            if publicVar.layoutType == .waterfall {
                collectionView.collectionViewLayout=publicVar.waterfallLayout
            }else{
                collectionView.collectionViewLayout=publicVar.justifiedLayout
            }
            publicVar.isNeedChangeLayoutType = false
        }
        
        //清空collectionView
        fileDB.lock()
        fileDB.db[SortKeyDir(path)]?.layoutCalcPos=0
        fileDB.db[SortKeyDir(path)]?.lastLayoutCalcPosUsed=0
        let lastCurFolder=fileDB.curFolder
        fileDB.curFolder = path
        let fileNum=fileDB.db[SortKeyDir(path)]?.files.count ?? 0
        fileDB.unlock()
        
        //如果是切换目录或者文件数量过多，则清空后再insertItems，否则仅reloadData(保持位置)
        if lastCurFolder != path || fileNum > 5000 {
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
                readInfoTaskPool.append((path,dirModel,key.0,key.1,dirModel.ver))
                readInfoTaskPoolSemaphore.signal()
            }
            readInfoTaskPoolLock.unlock()
            
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
                                coreAreaView.showInfo(NSLocalizedString("Loading...", comment: "加载中..."), timeOut: .infinity)
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
                    if VolumeManager.shared.isExternalVolume(key.path) {
                        operationQueue.waitUntilAllOperationsAreFinished()
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
                        fileDB.unlock() //内存屏障
                        
                        if ver != dirModel.ver {return}
                        
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
                                if(nowLayoutCalcPos > lastLayoutCalcPosUsed && (publicVar.timer.intervalSafe(name: "insertItems", second: 0.02+Double(i)*0.0001) || nowLayoutCalcPos == count)){
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
                                        fileDB.lock()
                                        let curKey = dirModel.files.elementSafe(atOffset: x)?.0
                                        let file = dirModel.files.elementSafe(atOffset: x)?.1
                                        fileDB.unlock()
                                        guard let curKey=curKey,let file=file else{continue}
                                        loadImageTaskPool.lock.lock()
                                        loadImageTaskPool.push(dir,(dir,dirModel,curKey,file,dirModel.ver))
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
                        fileDB.unlock() //内存屏障
                        
                        if i == -1 {return}
                        if ver != dirModel.ver {return}
                        
                        if VolumeManager.shared.isExternalVolume(key.path) {
                            let dirPath=getDirectoryPath(key.path)
                            externalVolumeThreadSemaphoresLock.lock()
                            let semaphore = externalVolumeThreadSemaphores[dirPath, default: DispatchSemaphore(value: globalVar.thumbThreadNum_External)]
                            externalVolumeThreadSemaphores[dirPath] = semaphore
                            externalVolumeThreadSemaphoresLock.unlock()
                            semaphore.wait()
                        }
                        defer {
                            if VolumeManager.shared.isExternalVolume(key.path) {
                                let dirPath=getDirectoryPath(key.path)
                                externalVolumeThreadSemaphoresLock.lock()
                                let semaphore = externalVolumeThreadSemaphores[dirPath, default: DispatchSemaphore(value: globalVar.thumbThreadNum_External)]
                                externalVolumeThreadSemaphores[dirPath] = semaphore
                                externalVolumeThreadSemaphoresLock.unlock()
                                semaphore.signal()
                            }
                        }
                        
                        fileDB.lock()
                        let originalSize:NSSize? = file.originalSize
                        let thumbSize:NSSize? = file.thumbSize
                        let count = dirModel.files.count
                        let isMemClearedToAvoidRemainingTask=dirModel.isMemClearedToAvoidRemainingTask
                        let curFolder=fileDB.curFolder
                        fileDB.unlock()
                        //loadImageTaskPool.lock.unlock()//此处解锁是因为防止8个线程与主线程排队争fileDB.lock
                        if isMemClearedToAvoidRemainingTask {return}
                        
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
                        
                        if thumbSize != nil {
                            if i == 0 {
                                let curTime = DispatchTime.now()
                                let nanoTime = curTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                                let timeInterval = Double(nanoTime) / 1_000_000_000
                                log("第一张图片开始载入耗时: \(timeInterval) seconds")
                            }
                            
                            var revisedSize = NSSize(width: thumbSize!.width-12, height: thumbSize!.height-12-0)
                            if publicVar.layoutType == .grid {
                                revisedSize = AVMakeRect(aspectRatio: originalSize ?? DEFAULT_SIZE, insideRect: CGRect(origin: CGPoint(x: 0, y: 0), size: revisedSize)).size
                            }
                            //log(max(revisedSize.width,revisedSize.height),level: .debug)
                            
                            var imageExist=false
                            loadImageTaskPool.lock.lock()
                            fileDB.lock()
                            if let thumbImage = file.image {
                                imageExist=true
                                if globalVar.isGenHdThumb && file.type == .image { //&& publicVar.layoutType != .grid
                                    let maxLength = max(revisedSize.width,revisedSize.height)
                                    if thumbImage.size.width != revisedSize.width && maxLength > 256 {
                                        imageExist=false
                                    }
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
                                    let maxLength = max(revisedSize.width,revisedSize.height)
                                    if !globalVar.isGenHdThumb || maxLength <= 256 { // || publicVar.layoutType == .grid
                                        image = getImageThumb(url: url, refSize: originalSize)
                                    }else{
                                        image = getImageThumb(url: url, size: revisedSize)
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
                Thread.sleep(forTimeInterval: 1)
                
//                log("Memory usage:")
//                log(reportPhyMemoryUsage())
//                log(reportTotalMemoryUsage())
                
                let memUse = reportTotalMemoryUsage()
                
                if LRUqueue.count >= 2 {
                    let overTime = (DispatchTime.now().uptimeNanoseconds-LRUqueue.last!.1.uptimeNanoseconds)/1000000000
                    let memUseLimit = globalVar.memUseLimit // ?? (memSizeInGB > 20 ? 4000 : 2000)
                    
                    if overTime > 3600 || Int(memUse) > memUseLimit {
                        fileDB.lock()
                        log("Memory free:")
                        log(LRUqueue.last!.0.removingPercentEncoding)
                        //由于先置目录再请求缩略图，所以此处可保证安全
                        if(LRUqueue.last!.0 != fileDB.curFolder){
                            fileDB.db[SortKeyDir(LRUqueue.last!.0)]!.isMemClearedToAvoidRemainingTask=true
                            for fileModel in fileDB.db[SortKeyDir(LRUqueue.last!.0)]!.files {
                                fileModel.1.image=nil
                                fileModel.1.folderImages=[NSImage]()
                            }
                            LRUcount-=fileDB.db[SortKeyDir(LRUqueue.last!.0)]!.fileCount
                            LRUqueue.removeLast()
                        }
                        fileDB.unlock()
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
    func LRUMemRecord(path: String){
        fileDB.lock()
        var index: Int?
        if LRUqueue.count > 0 {
            //之前队首的最后访问时间记录为当前时间
            LRUqueue[0].1=DispatchTime.now()
            //查找队列中是否有path
            for (i,(lruPath,_)) in LRUqueue.enumerated() {
                if lruPath == path {
                    index=i
                    break
                }
            }
        }
        
        if index != nil {
            LRUqueue.remove(at: index!)
        }else{
            LRUcount+=fileDB.db[SortKeyDir(path)]!.fileCount
        }
        LRUqueue.insert((path,DispatchTime.now()), at: 0)
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

    @objc func scrollViewDidScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else { return }
        // 确保是针对我们感兴趣的ScrollView（如果有多个ScrollView）
        if scrollView == collectionView.enclosingScrollView {
            setLoadThumbPriority(ifNeedVisable: true)
        }
        
    }
    
    func setLoadThumbPriority(indexPath: IndexPath? = nil, range: (Int,Int) = (-20,20), ifNeedVisable: Bool){

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

            //序号最大最小值
            let itemIndexMin=itemSorted[0]
            let itemIndexMax=itemSorted.last! + 20
            
            if itemIndexMin >= itemIndexMax {return}
            
            loadImageTaskPool.lock.lock()
            fileDB.lock()
            let curFolder=fileDB.curFolder
            for itemIndex in (itemIndexMin...itemIndexMax).reversed() {
                if let dirModel = fileDB.db[SortKeyDir(curFolder)],
                   let key = dirModel.files.elementSafe(atOffset: itemIndex)?.0,
                   let file = dirModel.files.elementSafe(atOffset: itemIndex)?.1,
                   file.image == nil {
                    loadImageTaskPool.pool[curFolder]?.insert((curFolder,dirModel,key,file,dirModel.ver), at: 0)
                    loadImageTaskPoolSemaphore.signal()
                }
            }
            fileDB.unlock()
            loadImageTaskPool.lock.unlock()
        }

    }
 
    @objc func closeLargeImage(_ sender: Any) {
        
        if currLargeImagePos == -1 {
            return
        }
        
        if !publicVar.isInLargeView || !publicVar.isInLargeViewAfterAnimate {
            return
        }
        
        view.window?.makeFirstResponder(collectionView)
        
        //复原旋转
        largeImageView.file.rotate=0
        
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
            
        
        if currLargeImagePos < collectionView.numberOfItems(inSection: 0) {
            
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
            
            if(url.hasDirectoryPath){
                switchDirByDirection(direction: .zero, dest: item.file.path, stackDeep: 0)
            }
            else if !HandledImageExtensions.contains(url.pathExtension.lowercased()) {
                NSWorkspace.shared.open(url)
            }else{
                if largeImageView.isHidden {
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
    
    var cumulativeScroll: CGFloat = 0 //累积滚动量
    
    func handleScrollWheel(_ event: NSEvent) {
        //log("触控板:",event.scrollingDeltaY)
        //log("滚轮的:",event.deltaY)
        if largeImageView.isHidden {return}
        
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
        if abs(event.scrollingDeltaY) > abs(event.deltaY) {
            //通常是触控板事件
            let sign = event.scrollingDeltaY >= 0 ? 1.0 : -1.0
            let abs=abs(event.scrollingDeltaY)
            deltaY=sign*pow(abs,1.0/1.4)/5
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
                setLoadThumbPriority(indexPath: IndexPath(item: currLargeImagePos, section: 0), ifNeedVisable: false)
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
                setLoadThumbPriority(indexPath: IndexPath(item: currLargeImagePos, section: 0), ifNeedVisable: false)
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
        let folderPath=url.deletingLastPathComponent().absoluteString
        let imageCount=fileDB.db[SortKeyDir(folderPath)]?.imageCount ?? 0
        if imageCount != 0{
            if let idInImage=fileDB.db[SortKeyDir(folderPath)]?.files[SortKeyFile(file.path, needGetProperties: true, sortType: publicVar.sortType, isSortFolderFirst: publicVar.isSortFolderFirst)]?.idInImage {
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
            
            //gif图直接使用缩略图（原图），能直接播放
            if ["gif"].contains(url.pathExtension.lowercased()){
                doNotGenResized=true
            }
            
            //svg图直接使用缩略图（原图），没必要缩放
            if ["svg"].contains(url.pathExtension.lowercased()){
                doNotGenResized=true
            }

            DispatchQueue.global(qos: .userInitiated).async {
                _ = ImageProcessor.getImageCache(url: url, size: largeSize, rotate: 0, useOriginalImage: doNotGenResized)
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
            
            //gif图直接使用缩略图（原图），能直接播放
            if ["gif"].contains(url.pathExtension.lowercased()){
                doNotGenResized=true
            }
            
            //svg图直接使用缩略图（原图），没必要缩放
            if ["svg"].contains(url.pathExtension.lowercased()){
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
            let isImageCached = ImageProcessor.isImageCached(url: url, size: largeSize, rotate: rotate)
            
            //先显示小图
            if firstShowThumb && !isImageCached {
                largeImageView.imageView.image=file.image?.rotated(by: CGFloat(-90*rotate))
            }
            
            //有大图缓存则直接载入
            if isImageCached {
                log("命中缓存:",url.absoluteString.removingPercentEncoding!)
                largeImageView.imageView.image=ImageProcessor.getImageCache(url: url, size: largeSize, rotate: rotate, useOriginalImage: doNotGenResized)
            }else{
                log("即时载入:",url.absoluteString.removingPercentEncoding!)
            }
            
            //读取exif信息
            if let exifData = getExifData(from: url) {
                let translatedExifData = formatExifData(exifData)
                largeImageView.updateTextItems(translatedExifData)
            } else {
                log("Failed to get EXIF data")
                largeImageView.updateTextItems([])
            }
            
            //显示窗口
            if let windowController = self.view.window?.windowController,
               let window = windowController.window,
               !window.isVisible {
                windowController.showWindow(nil)
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
                    largeImage=ImageProcessor.getImageCache(url: url, size: largeSize, rotate: rotate, useOriginalImage: doNotGenResized)
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
        watchDispatchSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: watchFileDescriptor, eventMask: .all, queue: queue)
        watchDispatchSource?.setEventHandler {
            //log("Directory at path \(path) changed.")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                folderMonitorTimer?.invalidate()
                folderMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { timer in
                    //self.switchDirByDirection(direction: .zero, doCollapse: false, expandLast: true)
                    self.refreshAll([])
                }
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
            if doAction {switchDirByDirection(direction: .up_right, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-sibling-of-parent", comment: "上级的平级下一个目录")}
        case (.up, .left):
            //log("Gesture: ⬆️ ⬅️")
            if doAction {switchDirByDirection(direction: .up_left, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-sibling-of-parent", comment: "上级的平级上一个目录")}
        case (.down, .right):
            //log("Gesture: ⬇️ ➡️")
            if doAction {switchDirByDirection(direction: .down_right, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("next-sibling", comment: "平级的下一个目录")}
        case (.down, .left):
            //log("Gesture: ⬇️ ⬅️")
            if doAction {switchDirByDirection(direction: .down_left, stackDeep: 0)}
            else{drawingView?.statusLabel.stringValue=NSLocalizedString("previous-sibling", comment: "平级的上一个目录")}
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
        let selectedIndexes = collectionView.selectionIndexPaths.map { indexPath in
            return indexPath.item
        }
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
                if !HandledImageExtensions.contains(urls[0].pathExtension) {return} //限制文件类型
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

