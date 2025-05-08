//
//  Global.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation
import Cocoa

//let DEFAULT_SIZE = 512
let DEFAULT_SIZE = NSSize(width: 512, height: 512)
let OPEN_LARGEIMAGE_DURATION = 0.1
//let THUMB_SIZES = [192,256,384,512,640,768,896,1024,1536,2048,4096]
var THUMB_SIZES = [Int]()
let PRELOAD_THUMB_RANGE_PRE = 20
let PRELOAD_THUMB_RANGE_NEXT = 40

let OFFICIAL_WEBSITE = "https://flowvision.app"

let ROOT_NAME = getSystemVolumeName() ?? "Macintosh HD"

class GlobalVar{
    var myFavoritesArray = ["/"]
    var WINDOW_LIMIT=16
    var windowNum=0
    var randomSeed = Int.random(in: 0...Int.max)
    var toolbarIndex = 0
    
    //TODO: 临时公用状态变量
    var isLaunchFromFile = false
    var startSpeedUpImageSizeCache: NSSize? = nil
    var useCreateWindowShowDelay = false
    
    //实时状态变量
    var isInMiddleMouseDrag = false
    
    //“设置”中按钮，用于同步状态
    weak var useInternalPlayerCheckbox: NSButton?
    
    //“设置”中的变量
    var terminateAfterLastWindowClosed = true
    var autoHideToolbar = false
    var doNotUseFFmpeg = false
    var memUseLimit: Int = 4000
    var thumbThreadNum: Int = 8
    var folderSearchDepth: Int = 4
    var thumbThreadNum_External: Int = 1
    var folderSearchDepth_External: Int = 0
    var randomFolderThumb = false
    var loopBrowsing = false
    var blackBgInFullScreen = false
    var blackBgInFullScreenForVideo = false
    var blackBgAlways = false
    var blackBgAlwaysForVideo = true
    var thumbnailExcludeList: [String] = []
    var usePinyinSearch = false
    var usePinyinInitialSearch = false
    var videoPlayRememberPosition = false
    var useInternalPlayer = false {
        didSet {
            useInternalPlayerCheckbox?.state = useInternalPlayer ? .on : .off
        }
    }
    var useQuickSearch = false
    var isEnterKeyToOpen = false
    
    //可记忆设置变量
    var isFirstTimeUse = true
    var portableMode = false
    var portableImageUseActualSize = false
    var portableImageWidthRatio = 0.8
    var portableImageHeightRatio = 0.95
    var portableListWidthRatio = 0.7
    var portableListHeightRatio = 0.84
    var portableListWidthRatioHH = 0.82
    var portableListHeightRatioHH = 0.84
    
    var HandledImageExtensions: [String] = []
    var HandledRawExtensions: [String] = []
    var HandledImageAndRawExtensions: [String] = []
    var HandledVideoExtensions: [String] = []
    var HandledOtherExtensions: [String] = []
    var HandledNonExternalExtensions: [String] = []
    var HandledNativeSupportedVideoExtensions: [String] = []
    var HandledNotNativeSupportedVideoExtensions: [String] = []
    var HandledFileExtensions: [String] = []
    var HandledSearchExtensions: [String] = []
    var HandledFolderThumbExtensions: [String] = []

    var rawFileUseThumbnail = true

    init(){
        HandledImageExtensions = ["jpg", "jpeg", "jxl", "png", "gif", "bmp", "heif", "heic", "hif", "avif", "tif", "tiff", "webp", "jfif", "jp2", "ai", "psd", "ico", "icns", "svg", "tga"]
        HandledRawExtensions = ["crw", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "rw2", "orf", "raf", "pef", "dng", "raw", "rwl", "x3f", "3fr", "fff", "iiq", "mos", "dcr", "erf", "mrw", "gpr", "srw"]
        HandledImageAndRawExtensions = HandledImageExtensions + HandledRawExtensions
        HandledNativeSupportedVideoExtensions = ["mp4", "mov", "m2ts", "ts", "mpeg", "mpg", "m4v", "vob"]
        HandledNotNativeSupportedVideoExtensions = ["mkv", "mts", "avi", "flv", "f4v", "asf", "wmv", "rmvb", "rm", "webm", "divx", "xvid", "3gp", "3g2"]
        HandledVideoExtensions = HandledNativeSupportedVideoExtensions + HandledNotNativeSupportedVideoExtensions
        HandledOtherExtensions = [] //["pdf"] //不能为""，否则会把目录异常包含进来
        HandledNonExternalExtensions = HandledImageAndRawExtensions
        HandledFileExtensions = HandledImageAndRawExtensions + HandledVideoExtensions + HandledOtherExtensions //文件列表显示的
        HandledSearchExtensions = HandledImageAndRawExtensions + HandledVideoExtensions //作为鼠标手势查找的目标
        HandledFolderThumbExtensions = HandledImageAndRawExtensions.filter{$0 != "svg"} + HandledVideoExtensions // + ["pdf"] //目录缩略图
        //使用个别特殊svg作为文件夹缩略图绘图元素会导致程序异常 'NSGenericException', reason: 'NaN point value'
    }
}
var globalVar = GlobalVar()

let homeDirectory = NSHomeDirectory()

func isWindowNumMax() -> Bool{
    return globalVar.windowNum >= globalVar.WINDOW_LIMIT
}

func getMainViewController() -> ViewController? {
    if let viewController = NSApplication.shared.mainWindow?.contentViewController as? ViewController {
        return viewController
    }
    return nil
}

func getViewController(_ selfView: NSView) -> ViewController? {
    var responder: NSResponder? = selfView
    while responder != nil {
        if let viewController = responder as? ViewController {
            return viewController
        }
        responder = responder?.nextResponder
    }
    return nil
}

func getSystemVolumeName() -> String? {
    let fileManager = FileManager.default
    
    // 获取根目录的URL
    let rootURL = URL(fileURLWithPath: "/")
    
    do {
        // 获取根目录的资源值，特别是卷名
        let resourceValues = try rootURL.resourceValues(forKeys: [.volumeNameKey])
        return resourceValues.volumeName
    } catch {
        print("Error retrieving volume name: \(error)")
        return nil
    }
}

