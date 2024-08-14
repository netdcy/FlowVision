//
//  ImageCollectionViewItem.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/17.
//

import Cocoa
import AVFoundation

class CustomCollectionViewItem: NSCollectionViewItem {
    
    @IBOutlet weak var imageViewObj: BorderedImageView!
    @IBOutlet weak var imageViewRef: BorderedImageView!
    @IBOutlet weak var imageNameField: NSTextField!
    
    var folderViews=[NSView]()
    var folderImageViews=[CustomImageView]()
    
    var file = FileModel(path: "", ver: 0)
    private var mouseDownLocation: NSPoint? = nil
    
    private var lastClickTime: TimeInterval = 0
    private var lastClickLocation: NSPoint = NSPoint.zero
    private let positionThreshold: CGFloat = 4.0 // 双击位置阈值，可以根据需要调整
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        view.wantsLayer = true
        view.layer?.cornerRadius = 5.0
        view.layer?.masksToBounds = true
        
        imageViewObj.wantsLayer = true
        imageViewObj.layer?.borderWidth = 0.0
        imageViewObj.layer?.borderColor = NSColor.gray.cgColor
        imageViewObj.layer?.cornerRadius = 5.0 // 这里可以根据需要调整圆角的半径
        imageViewObj.layer?.masksToBounds = true
        imageViewObj.animates=true
        
        imageNameField.cell?.lineBreakMode = .byTruncatingTail
        
        
//        for _ in 0...0 {
//            // 父视图 - 用于阴影和边框
//            let shadowView = NSView(frame: CGRect(x: 100, y: 100, width: 200, height: 200))
//            shadowView.wantsLayer = true
//            //阴影
//            shadowView.layer?.shadowColor = NSColor.black.cgColor
//            shadowView.layer?.shadowOpacity = 0.8
//            shadowView.layer?.shadowOffset = CGSize(width: 3, height: -3)
//            shadowView.layer?.shadowRadius = 5
//            //边框
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
//            //contentView.layer?.backgroundColor = NSColor.white.cgColor // 背景颜色，对于透明png？
//            contentView.imageScaling = .scaleProportionallyUpOrDown
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
            selectedColor()
        } else {
            // 未选中状态的处理代码
            deselectedColor()
        }
        lastClickTime=0
    }
    
    override var isSelected: Bool {
        didSet {
            super.isSelected = isSelected
            // 在这里处理选中状态变化
            if isSelected && !getViewController(collectionView!)!.publicVar.isInLargeView {
                // 选中状态的处理代码
                selectedColor()
            } else {
                // 未选中状态的处理代码
                deselectedColor()
            }
        }
    }
    
    func configureWithImage(_ fileModel: FileModel, playAnimation: Bool = false) {
        
        self.file=fileModel
        
        setTooltip()
        
        if isSelected {
            // 选中状态的处理代码
            selectedColor()
        } else {
            // 未选中状态的处理代码
            deselectedColor()
        }
        
        if getViewController(collectionView!)!.publicVar.layoutType == .grid {
            imageViewObj.imageScaling = .scaleProportionallyUpOrDown
        }else{
            imageViewObj.imageScaling = .scaleAxesIndependently
        }
        
        imageViewObj.url = URL(string: file.path)
        if file.isDir {
            imageViewObj.isFolder = true
        }else{
            imageViewObj.isFolder = false
        }
        
        imageNameField.stringValue=""//URL(string:file.path)!.lastPathComponent
        
        if(playAnimation){
            NSAnimationContext.runAnimationGroup({ context in
                // 设置动画持续时间秒
                context.duration = 0.1
                
                // 使用Core Animation的crossfade效果
                imageViewObj.wantsLayer = true // 确保imageView使用了CALayer
                let transition = CATransition()
                transition.type = CATransitionType.fade
                transition.duration = context.duration
                imageViewObj.layer?.add(transition, forKey: kCATransition)
                
                // 设置新图像
                imageViewObj.image = file.image
                //imageViewObj.sd_setImage(with: URL(string: path), placeholderImage: nil)
                
//                if file.folderImages.count>0{
//                    folderViews[0].isHidden=false
//                    folderImageViews[0].image=file.folderImages[0]
//                }else{
//                    folderViews[0].isHidden=true
//                    folderImageViews[0].image=nil
//                }

            }, completionHandler: {
                // 动画完成后的操作（如果有）
            })
        }else{
            imageViewObj.image=file.image
            //imageViewObj.sd_setImage(with: URL(string: path), placeholderImage: nil)
            
//            if file.folderImages.count>0{
//                folderViews[0].isHidden=false
//                folderImageViews[0].image=file.folderImages[0]
//            }else{
//                folderViews[0].isHidden=true
//                folderImageViews[0].image=nil
//            }
        }
        
        
    }
    
    func setTooltip(){
        if !getViewController(collectionView!)!.publicVar.isInLargeView {
            if file.isDir {
                self.view.toolTip = generateTooltip(filePath: file.path.removingPercentEncoding!, fileSize: nil, imageSize: nil, creationDate: file.createDate, modificationDate: file.modDate, addDate: file.addDate)
            }else{
                var imageSize = file.isGetImageSizeFail ? nil : file.originalSize
                if file.type == .other { imageSize = nil }
                self.view.toolTip = generateTooltip(filePath: file.path.removingPercentEncoding!, fileSize: file.fileSize, imageSize: imageSize, creationDate: file.createDate, modificationDate: file.modDate, addDate: file.addDate)
            }
        }else{
            self.view.toolTip = nil
        }
        
    }
    
    func generateTooltip(filePath: String, fileSize: Int?, imageSize: NSSize?, creationDate: Date?, modificationDate: Date?, addDate: Date?) -> String {
        // 获取文件名
        let fileName = (filePath as NSString).lastPathComponent
        
        // 准备局部化字符串
        let nameLabel = NSLocalizedString("name", comment: "名称")
        let sizeLabel = NSLocalizedString("file-size", comment: "文件大小")
        let dimensionsLabel = NSLocalizedString("file-dimensions", comment: "图像尺寸")
        let creationDateLabel = NSLocalizedString("Date Created", comment: "创建日期")
        let modificationDateLabel = NSLocalizedString("Date Modified", comment: "修改日期")
        let addDateLabel = NSLocalizedString("Date Added", comment: "添加日期")
        
        // 生成Tooltip字符串的数组
        var tooltipParts: [String] = []
        
        // 添加文件名
        tooltipParts.append("\(nameLabel): \(fileName)")
        
        // 如果文件大小存在，添加文件大小
        if let fileSize = fileSize {
            let byteCountFormatter = ByteCountFormatter()
            byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
            byteCountFormatter.countStyle = .file
            let formattedFileSize = byteCountFormatter.string(fromByteCount: Int64(fileSize))
            tooltipParts.append("\(sizeLabel): \(formattedFileSize)")
        }
        
        // 如果图像尺寸存在，添加图像尺寸
        if let imageSize = imageSize {
            let formattedImageSize = "\(Int(imageSize.width)) x \(Int(imageSize.height))"
            tooltipParts.append("\(dimensionsLabel): \(formattedImageSize)")
        }
        
        // 日期格式化器
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        // 如果创建日期存在，添加创建日期
        if let creationDate = creationDate {
            let formattedCreationDate = dateFormatter.string(from: creationDate)
            tooltipParts.append("\(creationDateLabel): \(formattedCreationDate)")
        }
        
        // 如果修改日期存在，添加修改日期
        if let modificationDate = modificationDate {
            let formattedModificationDate = dateFormatter.string(from: modificationDate)
            tooltipParts.append("\(modificationDateLabel): \(formattedModificationDate)")
        }
        
        // 如果添加日期存在，添加添加日期
        if let addDate = addDate {
            let formattedAddDate = dateFormatter.string(from: addDate)
            tooltipParts.append("\(addDateLabel): \(formattedAddDate)")
        }
        
        // 将所有部分连接成最终的Tooltip字符串
        let tooltip = tooltipParts.joined(separator: "\n")
        
        return tooltip
    }
    
    func selectedColor(){
        //log("selectedColor")
        let theme=NSApp.effectiveAppearance.name
        
        if file.isDir {
            imageNameField.textColor = hexToNSColor(hex: "#FFFFFF") //文字
            imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor //填充
            //imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#ECECEC").cgColor
        }else{
            imageNameField.textColor = hexToNSColor(hex: "#FFFFFF") //文字
            if theme == .darkAqua {
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#505050").cgColor //填充
            }else{
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#CECECE").cgColor //填充
            }
        }
        
        // 失去焦点时的样式
        if getViewController(collectionView!)!.publicVar.isCollectionViewFirstResponder{
            view.layer?.backgroundColor = NSColor.systemBlue.cgColor //边框
        }else{
            view.layer?.backgroundColor = NSColor.systemGray.cgColor //边框
        }
        
        // GridView时特殊样式
        if getViewController(collectionView!)!.publicVar.layoutType == .grid && !file.isDir {
            if let image = file.image {
                imageViewObj.isDrawBorder=true
                imageViewObj.layer?.borderWidth = 2.0
                imageViewObj.frame = AVMakeRect(aspectRatio: image.size, insideRect: imageViewRef.bounds)
                imageViewObj.center = imageViewRef.center
            }else{
                imageViewObj.isDrawBorder=false
                imageViewObj.layer?.borderWidth = 0.0
                imageViewObj.frame = imageViewRef.frame
            }
            
            imageViewObj.layer?.cornerRadius = 0.0
            imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor //填充
            //view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor //图片边框
            //imageNameField.textColor = hexToNSColor(hex: "#7E7E7E") //图片文字
        }else{
            imageViewObj.isDrawBorder=false
            imageViewObj.layer?.borderWidth = 0.0
            imageViewObj.frame = imageViewRef.frame
            
            imageViewObj.layer?.cornerRadius = 5.0
        }
        
    }
    func deselectedColor(){
        //log("deselectedColor")
        let theme=NSApp.effectiveAppearance.name
        
        //目录
        if file.isDir {
            //黑暗模式
            if theme == .darkAqua {
                imageNameField.textColor = hexToNSColor(hex: "#7E7E7E")
                imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
                //imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#272A2C").cgColor
                view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            }else{//浅色模式
                imageNameField.textColor = hexToNSColor(hex: "#7E7E7E")
                imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
                //imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#ECECEC").cgColor
                view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor
            }
        }else{//文件
            //黑暗模式
            if theme == .darkAqua {
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#404040").cgColor //填充
                if let url=URL(string:file.path),
                   HandledVideoExtensions.contains(url.pathExtension.lowercased())
                {
                    imageNameField.textColor = hexToNSColor(hex: "#7E7E7E") //视频文字
                    view.layer?.backgroundColor = hexToNSColor(hex: "#DDDDDD").cgColor //视频边框
                }else{
                    imageNameField.textColor = hexToNSColor(hex: "#7E7E7E") //图片文字
                    view.layer?.backgroundColor = hexToNSColor(hex: "#333333").cgColor //图片边框
                }
            }else{//浅色模式
                imageViewObj.layer?.backgroundColor = hexToNSColor(hex: "#DDDDDD").cgColor //填充
                if let url=URL(string:file.path),
                   HandledVideoExtensions.contains(url.pathExtension.lowercased())
                {
                    imageNameField.textColor = hexToNSColor(hex: "#7E7E7E") //视频文字
                    view.layer?.backgroundColor = hexToNSColor(hex: "#404040").cgColor //视频边框
                }else{
                    imageNameField.textColor = hexToNSColor(hex: "#7E7E7E") //图片文字
                    view.layer?.backgroundColor = hexToNSColor(hex: "#F4F5F5").cgColor //图片边框
                }
            }
        }
        
        // GridView时特殊样式
        if getViewController(collectionView!)!.publicVar.layoutType == .grid && !file.isDir {
            if let image = file.image {
                imageViewObj.isDrawBorder=true
                imageViewObj.layer?.borderWidth = 2.0
                imageViewObj.frame = AVMakeRect(aspectRatio: image.size, insideRect: imageViewRef.bounds)
                imageViewObj.center = imageViewRef.center
            }else{
                imageViewObj.isDrawBorder=false
                imageViewObj.layer?.borderWidth = 0.0
                imageViewObj.frame = imageViewRef.frame
            }
            
            imageViewObj.layer?.cornerRadius = 0.0
            imageViewObj.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor //填充
            view.layer?.backgroundColor = hexToNSColor(alpha: 0).cgColor //图片边框
            imageNameField.textColor = hexToNSColor(hex: "#7E7E7E") //图片文字
        }else{
            imageViewObj.isDrawBorder=false
            imageViewObj.layer?.borderWidth = 0.0
            imageViewObj.frame = imageViewRef.frame
            
            imageViewObj.layer?.cornerRadius = 5.0
        }
    }
    func select(){
        
    }
    func deselect(){
        
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        //print("mouseDownItem: ",file.id)
        let currentTime = event.timestamp
        let currentLocation = event.locationInWindow
        if currentTime - lastClickTime < NSEvent.doubleClickInterval &&
            distanceBetweenPoints(lastClickLocation, currentLocation) < positionThreshold {
            if let collectionView = collectionView,
               let selfIndexPath=collectionView.indexPath(for: self),
               let selectedIndexPath=collectionView.selectionIndexPaths.first,
               let viewController=getViewController(collectionView){
                
                if !viewController.publicVar.isInLargeView && !viewController.publicVar.isInLargeViewAfterAnimate {
                    viewController.openLargeImageFromIndexPath(selectedIndexPath)
                }else if viewController.publicVar.isInLargeView && viewController.publicVar.isInLargeViewAfterAnimate {
                    viewController.closeLargeImage([])
                }
                
                lastClickTime=0
                return
            }
        }
        lastClickTime = currentTime
        lastClickLocation = currentLocation
    }
    
    override func rightMouseDown(with event: NSEvent) {
        self.mouseDownLocation = event.locationInWindow
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        getViewController(collectionView!)!.publicVar.isColllectionViewItemRightClicked=true
        super.rightMouseUp(with: event)
        
        let mouseUpLocation = event.locationInWindow
        if let mouseDownLocation = self.mouseDownLocation {
            let maxDistance: CGFloat = 5.0 // 允许的最大移动距离
            let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)
            
            // 鼠标移动距离在允许范围内，弹出菜单
            if distance <= maxDistance {
                
                if !isSelected{
                    if let collectionView = self.collectionView {
                        collectionView.deselectAll(nil)
                        if let indexPath=collectionView.indexPath(for: self){
                            collectionView.selectItems(at: [indexPath], scrollPosition: [])
                            collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
                        }
                        
                    }
                }
                
                var canPasteOrMove=true
                let pasteboard = NSPasteboard.general
                let types = pasteboard.types ?? []
                if !types.contains(.fileURL) {
                    canPasteOrMove=false
                }
                
                //弹出菜单
                let menu = NSMenu(title: "Custom Menu")
                menu.autoenablesItems = false
                
                let actionItemOpen = menu.addItem(withTitle: NSLocalizedString("open", comment: "打开"), action: #selector(actOpen), keyEquivalent: " ")
                actionItemOpen.keyEquivalentModifierMask = []
                
                if (file.type == .folder || file.type == .image) {
                    let actionItemOpenInNewTab = menu.addItem(withTitle: NSLocalizedString("open-in-new-tab", comment: "在新标签页中打开"), action: #selector(actOpenInNewTab), keyEquivalent: "")
                    if isWindowNumMax() {
                        actionItemOpenInNewTab.isEnabled=false
                    }else{
                        actionItemOpenInNewTab.isEnabled=true
                    }
                }
                
                menu.addItem(NSMenuItem.separator())
                
                if URL(string: file.path)!.hasDirectoryPath == false {
                    addOpenWithSubMenu(to: menu, for: URL(string: file.path)!)
                }
                
                menu.addItem(withTitle: NSLocalizedString("show-in-finder", comment: "在Finder中显示"), action: #selector(actShowInFinder), keyEquivalent: "")
                
                let actionItemRename = menu.addItem(withTitle: NSLocalizedString("rename", comment: "重命名"), action: #selector(actRename), keyEquivalent: "\r")
                actionItemRename.keyEquivalentModifierMask = []
                
                menu.addItem(NSMenuItem.separator())
                
                // 定义排序项
                do{
                    let sortTypes: [(SortType, String)] = [
                        (.pathA, NSLocalizedString("sort-pathA", comment: "文件名")),
                        (.pathZ, NSLocalizedString("sort-pathZ", comment: "文件名(倒序)")),
                        (.sizeA, NSLocalizedString("sort-sizeA", comment: "大小")),
                        (.sizeZ, NSLocalizedString("sort-sizeZ", comment: "大小(倒序)")),
                        (.extA, NSLocalizedString("sort-extA", comment: "文件类型")),
                        (.extZ, NSLocalizedString("sort-extZ", comment: "文件类型(倒序)")),
                        (.createDateA, NSLocalizedString("sort-createDateA", comment: "创建日期")),
                        (.createDateZ, NSLocalizedString("sort-createDateZ", comment: "创建日期(倒序)")),
                        (.modDateA, NSLocalizedString("sort-modDateA", comment: "修改日期")),
                        (.modDateZ, NSLocalizedString("sort-modDateZ", comment: "修改日期(倒序)")),
                        (.addDateA, NSLocalizedString("sort-addDateA", comment: "添加日期")),
                        (.addDateZ, NSLocalizedString("sort-addDateZ", comment: "添加日期(倒序)")),
                        (.random, NSLocalizedString("sort-random", comment: "随机"))
                    ]

                    let sortMenuItem = NSMenuItem(title: NSLocalizedString("sort-by", comment: "排序方式"), action: nil, keyEquivalent: "")
                    let sortSubMenu = NSMenu()
                    
                    let folderFirstItem = NSMenuItem(title: NSLocalizedString("Sort Folders First", comment: "文件夹优先排序"), action: #selector(sortFolderFirst(_:)), keyEquivalent: "")
                    folderFirstItem.state = (getViewController(collectionView!)?.publicVar.isSortFolderFirst == false) ? .off : .on
                    sortSubMenu.addItem(folderFirstItem)
                    
                    sortSubMenu.addItem(NSMenuItem.separator())
                    
                    for (sortType, title) in sortTypes {
                        let menuItem = NSMenuItem(title: title, action: #selector(sortItems(_:)), keyEquivalent: "")
                        menuItem.target = self
                        menuItem.representedObject = sortType
                        let curSortType=getViewController(collectionView!)?.publicVar.sortType
                        menuItem.state = curSortType == sortType ? .on : .off
                        sortSubMenu.addItem(menuItem)
                    }
                    sortMenuItem.submenu = sortSubMenu
                    menu.addItem(sortMenuItem)
                }
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemDelete = menu.addItem(withTitle: NSLocalizedString("move-to-trash", comment: "移动到废纸篓"), action: #selector(actDelete), keyEquivalent: "\u{8}")
                actionItemDelete.keyEquivalentModifierMask = []
                //actionItemDelete.isEnabled = (items.count>0)
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemCopy = menu.addItem(withTitle: NSLocalizedString("copy", comment: "复制"), action: #selector(actCopy), keyEquivalent: "c")
                //actionItemCopy.isEnabled = (items.count>0)
                
                let actionItemPaste = menu.addItem(withTitle: NSLocalizedString("paste", comment: "粘贴"), action: #selector(actPaste), keyEquivalent: "v")
                actionItemPaste.isEnabled = canPasteOrMove
                
                let actionItemMove = menu.addItem(withTitle: NSLocalizedString("move-here", comment: "移动到此"), action: #selector(actMove), keyEquivalent: "v")
                actionItemMove.keyEquivalentModifierMask = [.command,.option]
                actionItemMove.isEnabled = canPasteOrMove
                
                let actionItemShare = menu.addItem(withTitle: NSLocalizedString("Share...", comment: "共享..."), action: #selector(actShare(_:)), keyEquivalent: "")
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemCopyToDownload = menu.addItem(withTitle: NSLocalizedString("copy-to-download", comment: "复制到\"下载\"文件夹"), action: #selector(actCopyToDownload), keyEquivalent: "n")
                actionItemCopyToDownload.keyEquivalentModifierMask = []

                let actionItemMoveToDownload = menu.addItem(withTitle: NSLocalizedString("move-to-download", comment: "移动到\"下载\"文件夹"), action: #selector(actMoveToDownload), keyEquivalent: "m")
                actionItemMoveToDownload.keyEquivalentModifierMask = []
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemNewFolder = menu.addItem(withTitle: NSLocalizedString("new-folder", comment: "新建文件夹"), action: #selector(actNewFolder), keyEquivalent: "n")
                actionItemNewFolder.keyEquivalentModifierMask = [.command,.shift]
                
                menu.addItem(NSMenuItem.separator())
                
                let actionItemRefresh = menu.addItem(withTitle: NSLocalizedString("refresh", comment: "刷新"), action: #selector(actRefresh), keyEquivalent: "r")
                actionItemRefresh.keyEquivalentModifierMask = []
                
                menu.items.forEach { $0.target = self }
                NSMenu.popUpContextMenu(menu, with: event, for: self.view)
            }
        }
        self.mouseDownLocation = nil // 重置按下位置
    }
    
    @objc func sortItems(_ sender: NSMenuItem) {
        guard let sortType = sender.representedObject as? SortType else { return }
        getViewController(collectionView!)?.changeSortType(sortType)
    }
    
    @objc func sortFolderFirst(_ sender: NSMenuItem) {
        guard let viewController = getViewController(collectionView!) else {return}
        viewController.publicVar.isSortFolderFirst.toggle()
        viewController.changeSortType(viewController.publicVar.sortType)
    }
    
    @objc func actRefresh() {
        getViewController(collectionView!)?.refreshAll()
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
            }else if file.type == .image{
                globalVar.isLaunchFromFile=true
                if let windowController = appDelegate.createNewWindow(file.path) {
                    appDelegate.openImageInTargetWindow(file.path, windowController: windowController)
                }
            }
        }
    }

    @objc func actShowInFinder() {
        let folderPath = (file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding! as NSString).deletingLastPathComponent
        // 使用NSWorkspace的实例来显示文件
        NSWorkspace.shared.selectFile(file.path.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!, inFileViewerRootedAtPath: folderPath)
    }
    
    @objc func actRename() {
        renameAlert(url: URL(string: file.path)!);
    }
    
    @objc func actNewFolder() {
        getViewController(collectionView!)?.handleNewFolder()
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
        getViewController(collectionView!)?.handleDelete()
    }
    
    @objc func actPaste() {
        getViewController(collectionView!)?.handlePaste()
    }
    
    @objc func actMove() {
        getViewController(collectionView!)?.handleMove()
    }
    
    func addOpenWithSubMenu(to menu: NSMenu, for fileUrl: URL) {
        let openWithMenu = NSMenu(title: "openWith")
        let openWithMenuItem = NSMenuItem(title: NSLocalizedString("open-with", comment: "打开方式"), action: nil, keyEquivalent: "")
        openWithMenuItem.submenu = openWithMenu
        
        // 获取可以打开文件的应用程序列表
        let cfFileUrl = fileUrl as CFURL
        let appURLs = LSCopyApplicationURLsForURL(cfFileUrl, .all)?.takeRetainedValue() as? [URL] ?? []
        
        for appURL in appURLs {
            let appName = FileManager.default.displayName(atPath: appURL.path)
            let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            let appMenuItem = NSMenuItem(title: appName.replacingOccurrences(of: ".app", with: " "), action: #selector(openFileWithApp(_:)), keyEquivalent: "")
            appMenuItem.representedObject = appURL
            appMenuItem.target = self
            appMenuItem.image = appIcon
            appMenuItem.image?.size = NSSize(width: 16, height: 16)  // Optionally resize the icon if needed
            openWithMenu.addItem(appMenuItem)
        }
        
        // 添加到主菜单
        menu.addItem(openWithMenuItem)
    }

    @objc func openFileWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL, let fileUrl = URL(string: file.path)
            else { return }
        
        NSWorkspace.shared.open([fileUrl], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: { (app, error) in
            if let error = error {
                log("Error opening file: \(error.localizedDescription)")
            } else if let app = app {
                log("Application \(app.localizedName ?? "Unknown") opened")
            }
        })
    }
    
    @objc func actShare(_ sender: NSMenuItem) {
        guard let fileUrl = URL(string: file.path) else { return }
        let sharingServicePicker = NSSharingServicePicker(items: [fileUrl])
        sharingServicePicker.show(relativeTo: view.bounds, of: self.view, preferredEdge: .maxX)
    }

}
