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

let OFFICIAL_WEBSITE = "http://flowvision.netdcy.com"

let ROOT_NAME = "Macintosh HD"

class GlobalVar{
    var myFavoritesArray = ["/"]
    var WINDOW_LIMIT=16
    var windowNum=0
    var isLaunchFromFile = false
    var randomSeed = Int.random(in: 0...Int.max)
    var toolbarIndex = 0
    
    var terminateAfterLastWindowClosed = true
    var autoHideToolbar = false
    var doNotUseFFmpeg = false
    var memUseLimit: Int = 4000
    var thumbThreadNum: Int = 8
    var folderSearchDepth: Int = 4
    var thumbThreadNum_External: Int = 1
    var folderSearchDepth_External: Int = 0
    
    var isFirstTimeUse = true
    
    var portableMode = false
    var portableImageUseActualSize = false
    var portableImageWidthRatio = 0.8
    var portableImageHeightRatio = 0.95
    var portableListWidthRatio = 0.7
    var portableListHeightRatio = 0.84
    var portableListWidthRatioHH = 0.82
    var portableListHeightRatioHH = 0.84
    
    var startSpeedUpImageSizeCache: NSSize? = nil
    
    var HandledImageExtensions: [String] = []
    var HandledVideoExtensions: [String] = []
    var HandledOtherExtensions: [String] = []
    var HandledNotNativeSupportedExtensions: [String] = []
    //var HandledExternalExtensions: [String] = []
    var HandledFileExtensions: [String] = []
    var HandledSearchExtensions: [String] = []
    var HandledFolderThumbExtensions: [String] = []
    //使用个别特殊svg作为文件夹缩略图绘图元素会导致程序异常 'NSGenericException', reason: 'NaN point value'

    init(){
        HandledImageExtensions = []
        if true{
            HandledImageExtensions += ["jpg", "jpeg", "png", "gif", "bmp", "heif", "heic", "hif", "avif", "tif", "tiff", "webp", "jfif", "jp2", "ai", "psd", "ico", "icns", "svg"]
        }
        if true {
            HandledImageExtensions += ["crw", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "rw2", "orf", "raf", "pef", "dng", "raw", "rwl", "x3f", "3fr", "fff", "iiq", "mos", "dcr", "erf", "mrw", "gpr", "srw"]
        }
        HandledVideoExtensions = []
        if true {
            HandledVideoExtensions += ["mp4", "mov", "m2ts", "vob", "mpeg", "mpg", "m4v"] + ["mkv", "mts", "ts", "avi", "flv", "f4v", "asf", "wmv", "rmvb", "rm", "webm", "divx", "xvid", "3gp", "3g2"]
        }
        HandledOtherExtensions = [] //["pdf"] //不能为""，否则会把目录异常包含进来
        HandledNotNativeSupportedExtensions = ["mkv", "mts", "ts", "avi", "flv", "f4v", "asf", "wmv", "rmvb", "rm", "webm", "divx", "xvid", "3gp", "3g2"]
        //HandledExternalExtensions = HandledVideoExtensions // + ["pdf"] //外部程序打开的
        HandledFileExtensions = HandledImageExtensions + HandledVideoExtensions + HandledOtherExtensions //文件列表显示的
        HandledSearchExtensions = HandledImageExtensions + HandledVideoExtensions //作为鼠标手势查找的目标
        HandledFolderThumbExtensions = HandledImageExtensions.filter{$0 != "svg"} + HandledVideoExtensions // + ["pdf"] //目录缩略图
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


