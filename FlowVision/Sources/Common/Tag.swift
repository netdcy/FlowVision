//
//  Tag.swift
//  FlowVision
//
//  Created by netdcy on 2025/7/9.
//

import Foundation
import Cocoa
import BTree

class TaggingSystem {
    
    static var db = Map<String,Set<URL>>()
    static var defaultTag = "⭐"
    
    // MARK: - 持久化相关
    private static var dataFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let flowVisionDir = appSupport.appendingPathComponent("FlowVision")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: flowVisionDir, withIntermediateDirectories: true)
        
        return flowVisionDir.appendingPathComponent("tags.json")
    }
    
    // 保存数据到JSON文件
    private static func saveToFile() {
        do {
            // 将Map转换为可序列化的格式
            var serializableData: [String: [String]] = [:]
            for (tag, urls) in db {
                serializableData[tag] = urls.map { $0.absoluteString }
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: serializableData, options: .prettyPrinted)
            try jsonData.write(to: dataFileURL)
        } catch {
            print("保存标签数据失败: \(error)")
        }
    }
    
    // 从JSON文件加载数据
    private static func loadFromFile() {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return }
        
        do {
            let jsonData = try Data(contentsOf: dataFileURL)
            if let serializableData = try JSONSerialization.jsonObject(with: jsonData) as? [String: [String]] {
                db.removeAll()
                for (tag, urlStrings) in serializableData {
                    let urls = Set(urlStrings.compactMap { URL(string: $0) })
                    db[tag] = urls
                }
            }
        } catch {
            print("加载标签数据失败: \(error)")
        }
    }
    
    // 添加标签
    static func add(tag:String? = nil, url: URL, needSave:Bool = true){
        let tag = tag ?? defaultTag
        if db[tag] == nil {
            db[tag] = Set<URL>()
        }
        db[tag]?.insert(url)
        if needSave {
            saveToFile() // 保存更改
        }
    }
    static func add(tag:String? = nil, urls: [URL]){
        for url in urls {
            add(tag: tag, url: url, needSave: false)
        }
        saveToFile() // 保存更改
    }
    
    // 移除标签
    static func remove(tag:String? = nil, url: URL, needSave:Bool = true){
        let tag = tag ?? defaultTag
        db[tag]?.remove(url)
        if db[tag]?.isEmpty == true {
            db.removeValue(forKey: tag)
        }
        if needSave {
            saveToFile() // 保存更改
        }
    }
    static func remove(tag:String? = nil, urls: [URL]){
        for url in urls {
            remove(tag: tag, url: url, needSave: false)
        }
        saveToFile() // 保存更改
    }
    
    // 获取某标签的文件列表
    static func getList(tag:String? = nil) -> [URL]{
        let tag = tag ?? defaultTag
        return Array(db[tag] ?? Set<URL>())
    }
    
    // 判断是否被某标签标记
    static func isTagged(tag:String? = nil, url: URL) -> Bool{
        let tag = tag ?? defaultTag
        return db[tag]?.contains(url) ?? false
    }

    // 判断是否所有文件被某标签标记
    static func isAllTagged(tag:String? = nil, urls: [URL]) -> Bool{
        let tag = tag ?? defaultTag
        for url in urls {
            if !isTagged(tag: tag, url: url) {
                return false
            }
        }
        return true
    }

    // 获取文件的所有标签
    static func getFileTags(url: URL) -> [String] {
        var tags: [String] = []
        for (tag, urls) in db {
            if urls.contains(url) {
                tags.append(tag)
            }
        }
        return tags.sorted() // 对标签列表进行排序
    }

    // 获取所有标签
    static func getAllTags() -> [String] {
        let tags = Array(db.keys).sorted() // 对标签列表进行排序
        return tags
    }

    static func getAvailableTags() -> [String] {
        let tags = ["⭐", "🔥", "💎", "♥️", "🟢"]
        return tags
    }
    
    // 初始化时加载数据
    static func initialize() {
        loadFromFile()
    }
}
