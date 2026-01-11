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
    // MARK: - Persistence Related
    private static var dataFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let flowVisionDir = appSupport.appendingPathComponent("FlowVision")
        
        // 确保目录存在
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: flowVisionDir, withIntermediateDirectories: true)
        
        return flowVisionDir.appendingPathComponent("tags.json")
    }
    
    // 保存数据到JSON文件
    // Save data to JSON file
    private static func saveToFile() {
        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            // 将Map转换为可序列化的格式
            // Convert Map to serializable format
            var serializableData: [String: [String]] = [:]
            for (tag, urls) in db {
                serializableData[tag] = urls.map { $0.absoluteString }
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: serializableData, options: .prettyPrinted)
            try jsonData.write(to: dataFileURL)
        } catch {
            print("保存标签数据失败: \(error)")
        }
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        log("saveToFile() execution time: \(String(format: "%.4f", executionTime)) seconds", level: .debug)
    }
    
    // 从JSON文件加载数据
    // Load data from JSON file
    private static func loadFromFile() {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else { 
            let executionTime = CFAbsoluteTimeGetCurrent() - startTime
            log("loadFromFile() execution time: \(String(format: "%.4f", executionTime)) seconds, file does not exist", level: .debug)
            return 
        }
        
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
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        log("loadFromFile() execution time: \(String(format: "%.4f", executionTime)) seconds", level: .debug)
    }
    
    // 添加标签
    // Add tag
    static func add(tag:String? = nil, url: URL){
        let tag = tag ?? defaultTag
        if db[tag] == nil {
            db[tag] = Set<URL>()
        }
        db[tag]?.insert(url)
        // 保存更改
        // Save changes
        saveToFile()
    }
    static func add(tag:String? = nil, urls: [URL]){
        let startTime = CFAbsoluteTimeGetCurrent()
        let tag = tag ?? defaultTag
        
        // 批量插入优化：一次性创建Set并合并
        // Batch insert optimization: create Set once and merge
        if db[tag] == nil {
            db[tag] = Set<URL>()
        }
        // 使用formUnion进行批量合并
        // Use formUnion for batch merge
        db[tag]?.formUnion(Set(urls))
        
        // 保存更改
        // Save changes
        saveToFile()
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        log("add(tag:urls:) execution time: \(String(format: "%.4f", executionTime)) seconds, number of files processed: \(urls.count)", level: .debug)
    }
    
    // 移除标签
    // Remove tag
    static func remove(tag:String? = nil, url: URL){
        let tag = tag ?? defaultTag
        db[tag]?.remove(url)
        if db[tag]?.isEmpty == true {
            db.removeValue(forKey: tag)
        }
        // 保存更改
        // Save changes
        saveToFile()
    }
    static func remove(tag:String? = nil, urls: [URL]){
        let startTime = CFAbsoluteTimeGetCurrent()
        let tag = tag ?? defaultTag
        
        // 批量移除优化：使用subtracting进行批量移除
        // Batch remove optimization: use subtracting for batch removal
        if let existingSet = db[tag] {
            db[tag] = existingSet.subtracting(Set(urls))
            if db[tag]?.isEmpty == true {
                db.removeValue(forKey: tag)
            }
        }
        
        // 保存更改
        // Save changes
        saveToFile()
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        log("remove(tag:urls:) execution time: \(String(format: "%.4f", executionTime)) seconds, number of files processed: \(urls.count)", level: .debug)
    }
    
    // 获取某标签的文件列表
    // Get file list for a tag
    static func getList(tag:String? = nil) -> [URL]{
        let tag = tag ?? defaultTag
        return Array(db[tag] ?? Set<URL>())
    }
    
    // 判断是否被某标签标记
    // Check if tagged with a tag
    static func isTagged(tag:String? = nil, url: URL) -> Bool{
        let tag = tag ?? defaultTag
        return db[tag]?.contains(url) ?? false
    }

    // 判断是否所有文件被某标签标记
    // Check if all files are tagged with a tag
    static func isAllTagged(tag:String? = nil, urls: [URL]) -> Bool{
        let startTime = CFAbsoluteTimeGetCurrent()
        let tag = tag ?? defaultTag
        for url in urls {
            if !isTagged(tag: tag, url: url) {
                let executionTime = CFAbsoluteTimeGetCurrent() - startTime
                log("isAllTagged(tag:urls:) execution time: \(String(format: "%.4f", executionTime)) seconds, number of files checked: \(urls.count), result: false", level: .debug)
                return false
            }
        }
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        log("isAllTagged(tag:urls:) execution time: \(String(format: "%.4f", executionTime)) seconds, number of files checked: \(urls.count), result: true", level: .debug)
        return true
    }

    // 获取文件的所有标签
    // Get all tags for a file
    static func getFileTags(url: URL) -> [String] {
        var tags: [String] = []
        for (tag, urls) in db {
            if urls.contains(url) {
                tags.append(tag)
            }
        }
        // 对标签列表进行排序
        // Sort tag list
        return tags.sorted()
    }

    // 获取所有标签
    // Get all tags
    static func getAllTags() -> [String] {
        // 对标签列表进行排序
        // Sort tag list
        let tags = Array(db.keys).sorted()
        return tags
    }

    static func getAvailableTags() -> [String] {
        let tags = ["⭐", "🔥", "💎", "♥️", "🟢"]
        return tags
    }
    
    // 初始化时加载数据
    // Load data on initialization
    static func initialize() {
        loadFromFile()
    }
}
