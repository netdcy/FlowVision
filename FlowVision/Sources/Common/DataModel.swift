//
//  DataModel.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation
import Cocoa
import BTree

extension Map {
    func elementSafe(atOffset offset: Int) -> Element? {
        guard offset >= 0 && offset < count else {
            return nil
        }
        return element(atOffset: offset)
    }
}

class SortKeyFile: SortKey, NSCopying {
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = SortKeyFile(path, createDate: createDate, modDate: modDate, addDate: addDate, size: size, isDir: isDir, isInSameDir: isInSameDir, sortType: sortType, isSortFolderFirst: isSortFolderFirst, isSortUseFullPath: isSortUseFullPath)
        return copy
    }
}

class SortKeyDir: SortKey {
    override init(_ path: String, createDate: Date = Date(), modDate: Date = Date(), addDate: Date = Date() , size: Int = 0, isDir: Bool = false, isInSameDir: Bool = false, needGetProperties: Bool = false, sortType: SortType = .pathA, isSortFolderFirst: Bool = true, isSortUseFullPath: Bool = true) {
        super.init(path, createDate: createDate, modDate: modDate, addDate: addDate, size: size, isDir: isDir, isInSameDir: isInSameDir, needGetProperties: needGetProperties, sortType: sortType, isSortFolderFirst: isSortFolderFirst, isSortUseFullPath: isSortUseFullPath)
    }
}

class SortKey: Comparable {
    var path: String
    var pathCmp: String
    var createDate: Date
    var modDate: Date
    var addDate: Date
    var size: Int
    var isDir: Bool
    var isInSameDir: Bool
    var sortType: SortType
    var isSortFolderFirst: Bool
    var isSortUseFullPath: Bool
    var seed: Int
    var exifDate: Date = Date(timeIntervalSince1970: 0)
    var exifPixel: Int = 0
    
    static var keyTransformedDict = Dictionary<String,[String]>()
    
    init(_ path: String, createDate: Date = Date(), modDate: Date = Date(), addDate: Date = Date() , size: Int = 0, isDir: Bool = false, isInSameDir: Bool = false, needGetProperties: Bool = false, sortType: SortType, isSortFolderFirst: Bool, isSortUseFullPath: Bool) {
        self.path = path
        self.pathCmp = path.lowercased()
        self.createDate = createDate
        self.modDate = modDate
        self.addDate = addDate
        self.size = size
        self.isDir = isDir
        self.isInSameDir = isInSameDir
        self.sortType = sortType
        self.isSortFolderFirst = isSortFolderFirst
        self.isSortUseFullPath = isSortUseFullPath
        self.seed = globalVar.randomSeed
        
        if needGetProperties,
           let url = URL(string: path) {
            do{
                let properties: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
                let resourceValues = try url.resourceValues(forKeys: Set(properties))
                if let tmp = resourceValues.fileSize {
                    self.size=tmp
                }
                if let tmp = resourceValues.creationDate {
                    self.createDate=tmp
                }
                if let tmp = resourceValues.contentModificationDate {
                    self.modDate=tmp
                }
                if let tmp = resourceValues.addedToDirectoryDate {
                    self.addDate=tmp
                }
            }catch{}
            
            SortKey.writeExifInfo(self)
            
        }
    }
    
    static func removeTrailingSlash(from path: String) -> String {
        guard path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
    
    static func stripCommonPathPrefixOptimized(_ path1: String, _ path2: String) -> (String, String) {
        let chars1 = Array(path1)
        let chars2 = Array(path2)
        
        // 找到最短路径长度，防止越界
        let minLength = min(chars1.count, chars2.count)
        
        // 找到公共前缀的长度
        var lastCommonSlash = -1
        for i in 0..<minLength {
            if chars1[i] == chars2[i] {
                if chars1[i] == "/" {
                    lastCommonSlash = i // 记录最后一个公共斜杠的位置
                }
            } else {
                break
            }
        }

        // 切割公共前缀后的路径部分
        let uniquePart1 = String(chars1[(lastCommonSlash + 1)...])
        let uniquePart2 = String(chars2[(lastCommonSlash + 1)...])

        return (uniquePart1, uniquePart2)
    }
    
    static func localCompare(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }
    
    static func hashFunction(fileName: String, seed: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(fileName)
        hasher.combine(seed)
        return hasher.finalize()
    }
    
    func ext() -> String {
        if self.isDir {
            return ""
        }else{
            return SortKey.ext(self)
        }
    }
    
    static func ext(_ sortKey: SortKey) -> String {
        return (sortKey.path as NSString).pathExtension.lowercased()
    }
    
    static func writeExifInfo(_ sortKey: SortKey) {
        if !sortKey.isDir{
            let ext = ext(sortKey)
            if globalVar.HandledImageAndRawExtensions.contains(ext) {
                let imageInfo = getImageInfo(url: URL(string: sortKey.path)!)
                let exifData = imageInfo?.properties?[kCGImagePropertyExifDictionary as String] as? [String: Any]
                let tiffData = imageInfo?.properties?[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
                //拍摄时间
                var dateTimeString = exifData?[kCGImagePropertyExifDateTimeOriginal as String] as? String
                if dateTimeString == nil { //以数字化时间为备选
                    dateTimeString = exifData?[kCGImagePropertyExifDateTimeDigitized as String] as? String
                }
                if dateTimeString == nil {//以TIFF时间为备选
                    dateTimeString = tiffData?[kCGImagePropertyTIFFDateTime as String] as? String
                }
                if let dateTimeString = dateTimeString {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                    if let date = dateFormatter.date(from: dateTimeString) {
                        sortKey.exifDate = date
                    }
                }
                //分辨率
                if let size = imageInfo?.size {
                    sortKey.exifPixel = Int(size.width * size.height)
                }
            }
            if globalVar.HandledVideoExtensions.contains(ext) {
                if let (width,height,date) = getVideoResolutionAndDateFFmpeg(for: URL(string: sortKey.path)!) {
                    sortKey.exifPixel = width*height
                    if let date = date {
                        sortKey.exifDate = date
                    }
                }
            }
        }
        
        if sortKey.exifDate == Date(timeIntervalSince1970: 0) {
            sortKey.exifDate = Date(timeIntervalSince1970: 1)
        }
        if sortKey.exifPixel == 0 {
            sortKey.exifPixel = 1
        }
    }
    
    static func < (lhs: SortKey, rhs: SortKey) -> Bool {
        if lhs.sortType != rhs.sortType {return false} // 异常情况，认为相等
        
        if lhs.isSortFolderFirst || lhs.sortType == .sizeA || lhs.sortType == .sizeZ {
            //文件夹优先。另外文件夹size为0，按大小排序时还是优先为好
            if lhs.pathCmp != rhs.pathCmp && lhs.isDir && !(rhs.isDir) { return true}
            if lhs.pathCmp != rhs.pathCmp && !(lhs.isDir) && rhs.isDir { return false}
        }
        
        //以各种属性排序
        if lhs.sortType == .sizeA {
            if lhs.size == rhs.size {return isSmallerPath(lhs: lhs, rhs: rhs)}
            return lhs.size < rhs.size
        }else if lhs.sortType == .sizeZ {
            if lhs.size == rhs.size {return isSmallerPath(lhs: lhs, rhs: rhs)}
            return lhs.size > rhs.size
        }else if lhs.sortType == .createDateA {
            if lhs.createDate == rhs.createDate {return isSmallerPath(lhs: lhs, rhs: rhs)}
            return lhs.createDate < rhs.createDate
        }else if lhs.sortType == .createDateZ {
            if lhs.createDate == rhs.createDate {return isSmallerPath(lhs: rhs, rhs: lhs)}
            return lhs.createDate > rhs.createDate
        }else if lhs.sortType == .modDateA {
            if lhs.modDate == rhs.modDate {return isSmallerPath(lhs: lhs, rhs: rhs)}
            return lhs.modDate < rhs.modDate
        }else if lhs.sortType == .modDateZ {
            if lhs.modDate == rhs.modDate {return isSmallerPath(lhs: rhs, rhs: lhs)}
            return lhs.modDate > rhs.modDate
        }else if lhs.sortType == .addDateA {
            if lhs.addDate == rhs.addDate {return isSmallerPath(lhs: lhs, rhs: rhs)}
            return lhs.addDate < rhs.addDate
        }else if lhs.sortType == .addDateZ {
            if lhs.addDate == rhs.addDate {return isSmallerPath(lhs: rhs, rhs: lhs)}
            return lhs.addDate > rhs.addDate
        }else if lhs.sortType == .extA {
            if lhs.ext() == rhs.ext() {return isSmallerPath(lhs: lhs, rhs: rhs)}
            return lhs.ext() < rhs.ext()
        }else if lhs.sortType == .extZ {
            if lhs.ext() == rhs.ext() {return isSmallerPath(lhs: lhs, rhs: rhs)}
            return lhs.ext() > rhs.ext()
        }
        
        //随机排序
        if lhs.sortType == .random {
            let lhs_hash=hashFunction(fileName: lhs.pathCmp, seed: lhs.seed)
            let rhs_hash=hashFunction(fileName: rhs.pathCmp, seed: rhs.seed)
            return lhs_hash<rhs_hash
        }
        
        //Exif日期排序
        if lhs.sortType == .exifDateA || lhs.sortType == .exifDateZ {
            if lhs.exifDate == Date(timeIntervalSince1970: 0) {
                writeExifInfo(lhs)
            }
            if rhs.exifDate == Date(timeIntervalSince1970: 0) {
                writeExifInfo(rhs)
            }
            if lhs.sortType == .exifDateA {
                if lhs.exifDate == rhs.exifDate {return isSmallerPath(lhs: lhs, rhs: rhs)}
                return lhs.exifDate < rhs.exifDate
            }else if lhs.sortType == .exifDateZ {
                if lhs.exifDate == rhs.exifDate {return isSmallerPath(lhs: rhs, rhs: lhs)}
                return lhs.exifDate > rhs.exifDate
            }
        }
        
        //Exif像素数排序
        if lhs.sortType == .exifPixelA || lhs.sortType == .exifPixelZ {
            if lhs.exifPixel == 0 {
                writeExifInfo(lhs)
            }
            if rhs.exifPixel == 0 {
                writeExifInfo(rhs)
            }
            if lhs.sortType == .exifPixelA {
                if lhs.exifPixel == rhs.exifPixel {return isSmallerPath(lhs: lhs, rhs: rhs)}
                return lhs.exifPixel < rhs.exifPixel
            }else if lhs.sortType == .exifPixelZ {
                if lhs.exifPixel == rhs.exifPixel {return isSmallerPath(lhs: lhs, rhs: rhs)}
                return lhs.exifPixel > rhs.exifPixel
            }
        }
        
        //以文件名排序
        if lhs.sortType == .pathZ {
            return isSmallerPath(lhs: rhs, rhs: lhs)
        }else{
            return isSmallerPath(lhs: lhs, rhs: rhs)
        }
    }
    
    static func isSmallerPath (lhs: SortKey, rhs: SortKey) -> Bool {

        //return lhs.path<rhs.path
        //return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        //return lhs.path.compare(rhs.path, options: .numeric) == .orderedAscending
        //注意：不加lowercased会导致不满足传递性
        //return lhs.path.removingPercentEncoding!.localizedStandardCompare(rhs.path.removingPercentEncoding!) == .orderedAscending
        //return lhs.path.lowercased().removingPercentEncoding!.localizedStandardCompare(rhs.path.lowercased().removingPercentEncoding!) == .orderedAscending
        
        if lhs.pathCmp==rhs.pathCmp { return false }
        if lhs.pathCmp=="" { return true }
        if rhs.pathCmp=="" { return false }
            
//        let lhs_paths=lhs.path.replacingOccurrences(of: "file://", with: "").split(separator: "/").map(){String($0).lowercased().removingPercentEncoding!}
//        let rhs_paths=rhs.path.replacingOccurrences(of: "file://", with: "").split(separator: "/").map(){String($0).lowercased().removingPercentEncoding!}
//
//        let lhs_paths=lhs.path.replacingOccurrences(of: "file://", with: "").components(separatedBy: "/").map(){$0.lowercased().removingPercentEncoding!}
//        let rhs_paths=rhs.path.replacingOccurrences(of: "file://", with: "").components(separatedBy: "/").map(){$0.lowercased().removingPercentEncoding!}
        
//        let (x,y) = stripCommonPathPrefixOptimized(lhs.path,rhs.path)
        
        var lhs_paths: [String]
        var rhs_paths: [String]
        if keyTransformedDict[lhs.pathCmp] != nil {
            lhs_paths=keyTransformedDict[lhs.pathCmp]!
        }else{
            lhs_paths=lhs.path.replacingOccurrences(of: "file://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/").map(){$0.removingPercentEncoding!.lowercased()}
            keyTransformedDict[lhs.pathCmp]=lhs_paths
        }
        if keyTransformedDict[rhs.pathCmp] != nil {
            rhs_paths=keyTransformedDict[rhs.pathCmp]!
        }else{
            rhs_paths=rhs.path.replacingOccurrences(of: "file://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/").map(){$0.removingPercentEncoding!.lowercased()}
            keyTransformedDict[rhs.pathCmp]=rhs_paths
        }
        //0.17s

//        return lhs.path<rhs.path
        //0.01s
        
        if lhs_paths.count==0 && rhs_paths.count==0 { return localCompare(lhs.pathCmp,rhs.pathCmp) }
        if lhs_paths.count==0 { return true }
        if rhs_paths.count==0 { return false }
        
        // 先按文件名比较，后按其完整路径（去掉文件名部分）来比较
        if !lhs.isSortUseFullPath && !rhs.isSortUseFullPath {
            let lhsFileName = lhs_paths.last ?? ""
            let rhsFileName = rhs_paths.last ?? ""
            
            if lhsFileName != rhsFileName {
                return localCompare(lhsFileName, rhsFileName)
            }
            
            // 如果文件名相同，则比较去掉文件名部分的路径
            let lhsPathWithoutFileName = lhs_paths.dropLast()
            let rhsPathWithoutFileName = rhs_paths.dropLast()
            
            for i in 0..<min(lhsPathWithoutFileName.count, rhsPathWithoutFileName.count) {
                if lhsPathWithoutFileName[i] == rhsPathWithoutFileName[i] { continue }
                if localCompare(lhsPathWithoutFileName[i], rhsPathWithoutFileName[i]) {
                    return true
                } else {
                    return false
                }
            }
            return lhsPathWithoutFileName.count < rhsPathWithoutFileName.count
        }
        
        if lhs.isInSameDir && rhs.isInSameDir && lhs_paths.count==rhs_paths.count {
            return localCompare(lhs_paths[lhs_paths.count-1],rhs_paths[rhs_paths.count-1])
        }
        
        for i in 0...min(lhs_paths.count,rhs_paths.count)-1 {
            if lhs_paths[i] == rhs_paths[i] { continue }
//            if lhs_paths[i]<rhs_paths[i]{
            if localCompare(lhs_paths[i],rhs_paths[i]){
                return true
            }else{
                return false
            }
        }
        if lhs_paths.count < rhs_paths.count {
            return true
        }else{
            return false
        }

    }
    
    static func == (lhs: SortKey, rhs: SortKey) -> Bool {
        if lhs.sortType != rhs.sortType {return true} // 异常情况，认为相等
        if lhs.sortType == .random {
            return lhs.pathCmp == rhs.pathCmp && lhs.seed == rhs.seed
        }
        return lhs.pathCmp == rhs.pathCmp
    }
}

class ImageInfo {
    var size: NSSize?
    var rating: Int?
    var properties: [String: Any]?
    var metadata: CGImageMetadata?
    var isHDR: Bool = false
    var ext: String?
    
    init(_ size: NSSize?){
        self.size=size
    }
}

class FileModel {
    init(path: String, ver: Int, isDir: Bool = false, fileSize: Int? = nil, createDate: Date? = nil, modDate: Date? = nil, addDate: Date? = nil, doNotActualRead:Bool = false){
        self.path=path
        self.ver=ver
        self.isDir=isDir
        self.fileSize=fileSize
        self.createDate=createDate
        self.modDate=modDate
        self.addDate=addDate
        self.doNotActualRead=doNotActualRead
    }
    var id: Int = 0
    var idInImage: Int = 0
    var idInImageAndVideo: Int = 0
    var path: String
    var ext: String = ""
    var type: FileType = .notSet
    
    var originalSize: NSSize?
    var largeSize: NSSize?
    var isGetImageSizeFail = false
    var thumbSize: NSSize?
    var lineNo: Int = 0
    var image: NSImage?
    var folderImages = [NSImage]()
    var lock: NSLock = NSLock()
    var isLayoutCalcued: Bool = false
    var ver: Int
    var canBeCalcued = false
    var isDir: Bool
    var fileSize: Int?
    var modDate: Date?
    var createDate: Date?
    var addDate: Date?
    var doNotActualRead: Bool = false
    var rotate: Int = 0
    var imageInfo: ImageInfo?
    var getThumbFailed = false
}

class DirModel {
    init(path: String, ver: Int){
        self.path=path
        self.ver=ver
        //self.searchVer=searchVer
    }
    var path: String
    
    var files = Map<SortKeyFile,FileModel>()
    var layoutCalcPos = 0
    var lastLayoutCalcPosUsed = 0
    var ver: Int
    //var searchVer: Int
    var folderCount: Int = 0
    var fileCount: Int = 0
    var imageCount: Int = 0
    var videoCount: Int = 0
    var isMemClearedToAvoidRemainingTask: Bool = false
    var keepScrollPos: Bool = false
    var isRecursiveMode: Bool = false
    var isFiltered: Bool = false
    var lock: NSLock = NSLock()
    
    func changeSortType(_ sortType: SortType, isSortFolderFirst: Bool, isSortUseFullPath: Bool){
        let oldFiles=files
        files=Map<SortKeyFile,FileModel>()
        for oldFile in oldFiles {
            if let tmpKey=oldFile.0.copy() as? SortKeyFile{
                tmpKey.sortType=sortType
                tmpKey.isSortFolderFirst=isSortFolderFirst
                tmpKey.isSortUseFullPath=isSortUseFullPath
                files[tmpKey]=oldFile.1
            }
        }
        
        //暂时无需在此处重设id，因为改变排序后还会重读一遍文件
//        var idInImage=0
//        var id=0
//        for ele in files{
//            ele.1.id=id
//            id+=1
//            if !(ele.1.isDir) {
//                if HandledImageAndRawExtensions.contains(ele.1.ext) {
//                    ele.1.idInImage=idInImage
//                    idInImage+=1
//                }
//            }
//        }
    }
}

class DatabaseModel {
    var db = Map<SortKeyDir,DirModel>()
    var curFolder = "file:///"
    var dblock: NSLock = NSLock()
    var ver = 0
    //var searchVer = 0
    
    func lock(){
        dblock.lock()
    }
    func unlock(){
        dblock.unlock()
    }
}

func getMapKeysFile (_ theMap : Map<SortKeyFile,FileModel>) -> [(SortKeyFile,FileModel)]{
    var keys = [(SortKeyFile,FileModel)]()
    for ele in theMap{
        keys.append((ele.0,ele.1))
    }
    //log(keys)
    return keys
}

class TreeNode: NSObject {
    var name: String
    var fullPath: String
    var children: [TreeNode]?
    var hasChild: Bool = false
    
    init(name: String, children: [TreeNode]? = nil, fullPath: String = "") {
        self.name = name
        self.children = children
        self.fullPath = fullPath
    }
}

class TreeViewModel {
    var root: TreeNode?
    weak var viewController: ViewController!
    
    func initData(path: String) {
        root = TreeNode(name: "Root", fullPath: path)
        expand(node: root!, isLookSub: true)
//        var currentNode = root!
//        //currentNode.children?.append(TreeNode(name: "test", fullPath: "curPath"))
//        let newNode = TreeNode(name: "test", fullPath: "curPath")
//        if currentNode.children == nil {
//            currentNode.children = [newNode]
//        } else {
//            currentNode.children?.append(newNode)
//        }

    }
    
    func hasSubdirectory(at folderURL: URL) -> Bool {
        let fileManager = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions
        if viewController.publicVar.isShowHiddenFile {
            options = [.skipsSubdirectoryDescendants]
        }else{
            options = [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        }

        if let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: options) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]), resourceValues.isDirectory == true {
                    return true
                }
            }
        }

        return false
    }
    
    func expand(node: TreeNode, isLookSub: Bool){
        let folderURL=URL(string: node.fullPath)!
        do{
            var contents = [URL]()
            
            // 检查是否是根目录
            if folderURL.path != "root" {
                contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey, .isUbiquitousItemKey, .isHiddenKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey], options: [])
            }else{

                let fileManager = FileManager.default
                let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey]

                if let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) {
                    for url in urls {
                        do {
                            let resourceValues = try url.resourceValues(forKeys: Set(keys))
//                            if let volumeName = resourceValues.volumeName {
//                                print("Volume Name: \(volumeName)")
//                            }
//                            if let isRemovable = resourceValues.volumeIsRemovable {
//                                print("Is Removable: \(isRemovable)")
//                            }
//                            if let isInternal = resourceValues.volumeIsInternal {
//                                print("Is Internal: \(isInternal)")
//                            }
                            contents.append(url)
                        } catch {
                            log("Error retrieving resource values: \(error)")
                        }
                    }
                } else {
                    log("No mounted volumes found.")
                }
                
                //let volumesURL = URL(fileURLWithPath: "/Volumes")
                //contents.append(volumesURL)
            }
            
            //contents.sort { $0.absoluteString < $1.absoluteString }
            //contents.sort { $0.lastPathComponent.lowercased().localizedStandardCompare($1.lastPathComponent.lowercased()) == .orderedAscending }
            
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
//                if url.path == NSHomeDirectory() + "/Library" {
//                    return true
//                }
                
                // 过滤掉其他隐藏文件
                return !isHidden || viewController.publicVar.isShowHiddenFile
            }
            
            //过滤出目录列表
            var subFolders = contents.filter { url in
                guard let isDirectoryResourceValue = try? url.resourceValues(forKeys: [.isDirectoryKey]), let isDirectory = isDirectoryResourceValue.isDirectory else {
                    return false
                }
                return isDirectory
            }
            
            //排序
            if folderURL.path == "root" { //卷列表保持字母序
                subFolders.sort { $0.lastPathComponent.lowercased().localizedStandardCompare($1.lastPathComponent.lowercased()) == .orderedAscending }
            }else{
                let sortType = SortType(rawValue: Int(viewController.publicVar.profile.getValue(forKey: "dirTreeSortType")) ?? 0)
                if sortType == .pathA {
                    subFolders.sort { $0.lastPathComponent.lowercased().localizedStandardCompare($1.lastPathComponent.lowercased()) == .orderedAscending }
                } else if sortType == .pathZ {
                    subFolders.sort { $0.lastPathComponent.lowercased().localizedStandardCompare($1.lastPathComponent.lowercased()) == .orderedDescending }
                } else if sortType == .createDateA {
                    subFolders.sort { 
                        let date1 = try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                        let date2 = try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                        return date1 ?? Date.distantPast < date2 ?? Date.distantPast
                    }
                } else if sortType == .createDateZ {
                    subFolders.sort { 
                        let date1 = try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                        let date2 = try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                        return date1 ?? Date.distantPast > date2 ?? Date.distantPast
                    }
                } else if sortType == .modDateA {
                    subFolders.sort { 
                        let date1 = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                        let date2 = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                        return date1 ?? Date.distantPast < date2 ?? Date.distantPast
                    }
                } else if sortType == .modDateZ {
                    subFolders.sort { 
                        let date1 = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                        let date2 = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                        return date1 ?? Date.distantPast > date2 ?? Date.distantPast
                    }
                } else if sortType == .addDateA {
                    subFolders.sort { 
                        let date1 = try? $0.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate ?? Date.distantPast
                        let date2 = try? $1.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate ?? Date.distantPast
                        return date1 ?? Date.distantPast < date2 ?? Date.distantPast
                    }
                } else if sortType == .addDateZ {
                    subFolders.sort { 
                        let date1 = try? $0.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate ?? Date.distantPast
                        let date2 = try? $1.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate ?? Date.distantPast
                        return date1 ?? Date.distantPast > date2 ?? Date.distantPast
                    }
                } else {
                    subFolders.sort { $0.lastPathComponent.lowercased().localizedStandardCompare($1.lastPathComponent.lowercased()) == .orderedAscending }
                }
            }
            
            if globalVar.autoHideToolbar && folderURL.path == "root" {
                subFolders.insert(URL(fileURLWithPath: "/PlaceholderForAutoHideToolbar"), at: 0)
            }
            
            let oldChildren=node.children
            node.children=[]
            
            for subFolder in subFolders {
                var name = subFolder.lastPathComponent
                var fullPath = subFolder.absoluteString
                if name == "/" { name = ROOT_NAME }
                if name == "PlaceholderForAutoHideToolbar" {
                    name = "Hidden Volume"
                    fullPath = "file:///"
                }
                var newNode = TreeNode(name: name, fullPath: fullPath)
                
                if oldChildren?.contains(where: { $0.name == newNode.name }) ?? false {
                    newNode = oldChildren!.first(where: { $0.name == newNode.name })!
                }
                node.children?.append(newNode)
                
                if isLookSub{
                    if VolumeManager.shared.isExternalVolume(subFolder) && globalVar.folderSearchDepth_External == 0 {
                        newNode.hasChild=true
                    }else{
                        do{
                            let resourceValues = try subFolder.resourceValues(forKeys: Set([.isUbiquitousItemKey]))
                            if let doNotActualRead = resourceValues.isUbiquitousItem {
                                if doNotActualRead {
                                    newNode.hasChild=true
                                }else{
                                    newNode.hasChild=hasSubdirectory(at: URL(string:newNode.fullPath)!)
                                }
                            }else{
                                newNode.hasChild=hasSubdirectory(at: URL(string:newNode.fullPath)!)
                            }
                        }catch{}
                    }
                }
            }
            
            
        }catch{
            return
        }
    }
    
    func buildTree(from paths: [String]) {
        root = TreeNode(name: "Root")
        
        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            var currentNode = root!
            for (i,component) in components.enumerated() {
                if currentNode.children?.contains(where: { $0.name == component.removingPercentEncoding! }) ?? false {
                    currentNode = currentNode.children!.first(where: { $0.name == component.removingPercentEncoding! })!
                } else {
                    var curPath=""
                    for k in 0...i {
                        curPath+=components[k]+"/"
                    }
                    let newNode = TreeNode(name: component.removingPercentEncoding!, fullPath: curPath)
                    if currentNode.children == nil {
                        currentNode.children = [newNode]
                    } else {
                        currentNode.children?.append(newNode)
                    }
                    currentNode = newNode
                }
            }
        }
        
        //return root
    }

    func findNode(withPath path: String) -> [TreeNode] {
        if root==nil {return []}
        let components = path.split(separator: "/").map(String.init)
        var result=[TreeNode]()
        var currentNode = root!
        result.append(currentNode)
        for component in components {
            if let child = currentNode.children?.first(where: { $0.name == component.removingPercentEncoding! }) {
                currentNode = child
                result.append(currentNode)
            } else {
                return [] // Path does not exist
            }
        }
        //log(currentNode.name)
        return result
    }
}

typealias TaskType = (String, DirModel, SortKeyFile, FileModel, Int, OtherTaskInfo)

class OtherTaskInfo {
    var isFromScroll: Bool
    var isPriorityScheduled: Bool
    
    init(isFromScroll: Bool = false, isPriorityScheduled: Bool = false) {
        self.isFromScroll = isFromScroll
        self.isPriorityScheduled = isPriorityScheduled
    }
}

class TaskPool {
    var pool = Dictionary<String,[TaskType]>()
    var priority = Dictionary<String,Double>()
    var lock = NSLock()
    func makeQueue(_ queueName: String){
        if pool[queueName] == nil {
            pool[queueName]=[TaskType]()
            priority[queueName]=10.0
        }
    }
    func push(_ queueName: String, _ ele: TaskType){
        if pool[queueName] != nil {
            pool[queueName]?.append(ele)
        }else{
            pool[queueName]=[TaskType]()
            pool[queueName]?.append(ele)
            priority[queueName]=10.0
        }
    }
    func pop() -> TaskType? {
        if pool.count == 0 {return nil}
        
        var prioritySum=0.0
        for (key,pri) in priority {
            if pool[key]!.count != 0 {
                prioritySum+=pri
            }
        }
        let randPos=Double.random(in: 0.0...prioritySum)
        prioritySum=0.0
        var queueName=pool.first!.key
        for (key,pri) in priority {
            if pool[key]!.count != 0 {
                prioritySum+=pri
            }
            if randPos<=prioritySum {
                queueName=key
                break
            }
        }
        if pool[queueName]!.count != 0 {
            return pool[queueName]!.removeFirst()
        }else{
            return nil
        }
    }
    func popSafe0() -> TaskType? {
        lock.lock()
        let tmp = pop()
        lock.unlock()
        return tmp
    }
    func removeQueue(queueName: String) {
        pool.removeValue(forKey: queueName)
        priority.removeValue(forKey: queueName)
    }
    func setMostPriority(queueName: String) {
        if pool.count == 0 {return}
        
        for (key,_) in priority {
            if key == queueName {
                priority[key]=10.0
            }else{
                priority[key]=2.0
            }
        }
    }
    func getTaskNum() -> Int {
        var count = 0
        for (_,aPool) in pool {
            count += aPool.count
        }
        return count
    }
    func removeAllQueue(){
        if pool.count == 0 {return}
        var keysToRemove: [String] = []
        for (key,_) in priority {
            keysToRemove.append(key)
        }
        for key in keysToRemove {
            removeQueue(queueName: key)
        }
    }
}
