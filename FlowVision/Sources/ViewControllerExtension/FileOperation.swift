//
//  FileOperation.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func getUniqueDestinationURL(for url: URL, isInPlace: Bool = false) -> URL {
        var newURL = url
        var counter = 1
        
        while FileManager.default.fileExists(atPath: newURL.path) {
            let baseName = url.deletingPathExtension().lastPathComponent
            let extensionName = url.pathExtension
            var duplicateName = ""
            var newName = "\(baseName)_\(duplicateName)\(counter > 0 ? "\(counter+1)" : "")"
            if isInPlace {
                duplicateName = NSLocalizedString("copy-lowercase", comment: "copy(首字母小写)")
                newName = "\(baseName)_\(duplicateName)\(counter > 1 ? "\(counter)" : "")"
            }
            
            
            newURL = url.deletingLastPathComponent().appendingPathComponent(newName).appendingPathExtension(extensionName)
            counter += 1
        }
        
        return newURL
    }
    
    func handleNewFolder(targetURL: URL? = nil) -> (Bool,URL?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("New Folder", comment: "新建文件夹")
        alert.informativeText = NSLocalizedString("input-new-folder-name", comment: "请输入文件夹名称：")
        alert.alertStyle = .informational
        // 设置系统通知图标
        // Set system notification icon
        alert.icon = NSImage(named: NSImage.infoName)
        
        // 添加一个文本输入框
        // Add a text input field
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
            textFieldCell.usesSingleLineMode = true
            textFieldCell.wraps = false
            textFieldCell.isScrollable = true
        }
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled=false
        DispatchQueue.main.async {
            _ = inputTextField.becomeFirstResponder()
        }
        let response = alert.runModal()
        publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
        
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
                // Check if file with same name exists
                if FileManager.default.fileExists(atPath: newFolderURL.path) {
                    showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                }else{
                    // 执行新建操作
                    // Execute create operation
                    do {
                        // 文件更改计数
                        // File change count
                        publicVar.fileChangedCount += 1
                        
                        try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: true, attributes: nil)
                        log("Successfully created folder: \(newFolderURL.path)")
                        // Create folder succeeded
                        return (true,newFolderURL)
                    } catch {
                        log("Failed to create folder: \(error)")
                        // Create folder failed
                    }
                }
            }
        }
        return (false,nil)
    }

    func handleNewTextFile(targetURL: URL? = nil) -> (Bool,URL?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("New Text File", comment: "新建文本文件")
        alert.informativeText = NSLocalizedString("input-new-textfile-name", comment: "请输入文件名称：")
        alert.alertStyle = .informational
        // 设置系统通知图标
        // Set system notification icon
        alert.icon = NSImage(named: NSImage.infoName)
        
        // 添加一个文本输入框
        // Add a text input field
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        if let textFieldCell = inputTextField.cell as? NSTextFieldCell {
            textFieldCell.usesSingleLineMode = true
            textFieldCell.wraps = false
            textFieldCell.isScrollable = true
        }
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "确定"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled=false
        DispatchQueue.main.async {
            _ = inputTextField.becomeFirstResponder()
        }
        let response = alert.runModal()
        publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
        
        if response == .alertFirstButtonReturn {
            var fileName = inputTextField.stringValue
            
            if !fileName.isEmpty {
                // 如果用户没有输入扩展名，则加.txt后缀
                // If user didn't enter extension, add .txt suffix
                if !fileName.contains(".") {
                    fileName += ".txt"
                }
                
                fileDB.lock()
                let curFolder = fileDB.curFolder
                fileDB.unlock()
                
                var destinationURL = URL(string: curFolder)
                if targetURL != nil {destinationURL=targetURL}
                guard let destinationURL=destinationURL else {return (false,nil)}
                
                let newFileURL = destinationURL.appendingPathComponent(fileName)
                
                // 检查是否存在同名文件
                // Check if file with same name exists
                if FileManager.default.fileExists(atPath: newFileURL.path) {
                    showAlert(message: NSLocalizedString("renaming-conflict", comment: "该名称的文件已存在，请选择其他名称。"))
                }else{
                    // 执行新建操作
                    // Execute create operation
                    do {
                        // 创建空文本文件
                        // Create empty text file
                        try "".write(to: newFileURL, atomically: true, encoding: .utf8)
                        
                        // 文件更改计数
                        // File change count
                        publicVar.fileChangedCount += 1
                        
                        log("Successfully created text file: \(newFileURL.path)")
                        return (true,newFileURL)
                    } catch {
                        log("Failed to create text file: \(error)")
                    }
                }
            }
        }
        return (false,nil)
    }
    
    func handleNewFolderWithSelection() {
        var urls = publicVar.selectedUrls()
        if urls.isEmpty {return}
        
        let (ifSuccess,newFolderURL) = handleNewFolder()
        
        if ifSuccess {
            // 备份剪贴板内容
            // Backup pasteboard content
            let backupItems = backupPasteboard()
            
            handleCopy()
            handleMove(targetURL: newFolderURL)
            
            // 还原剪贴板内容
            // Restore pasteboard content
            restorePasteboard(items: backupItems)
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
    // Function to restore pasteboard content
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
        // 清除剪贴板现有内容
        // Clear existing pasteboard content
        pasteboard.clearContents()
        // 将文件URL添加到剪贴板
        // Add file URLs to pasteboard
        pasteboard.writeObjects(publicVar.selectedUrls() as [NSPasteboardWriting])
    }
    
    func handleCopyToDownload() {
        if publicVar.selectedUrls().isEmpty {return}
        
        // 备份剪贴板内容
        // Backup pasteboard content
        let backupItems = backupPasteboard()
        
        handleCopy()
        handlePaste(targetURL: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        
        // 还原剪贴板内容
        // Restore pasteboard content
        restorePasteboard(items: backupItems)
    }
    
    func handlePaste(targetURL: URL? = nil, pasteboard: NSPasteboard = NSPasteboard.general) {
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
        // Check list of files/folders to copy
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            
            // 检查是否包含目标目录自身或者它的父目录
            // Check if includes destination directory itself or its parent directory
            if fileURL == destinationURL || destinationURL.path.hasPrefix(fileURL.path) {
                showAlert(message: NSLocalizedString("cannot-copy-to-self", comment: "不能将文件/文件夹复制到自身或其子目录中。"))
                return
            }
        }

        // 检查来源是否有同名文件
        // Check if source has files with same name
        var ifAutoRenameWhenDifferentSource = false
        var fileNames = Set<String>()
        var hasDuplicates = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            let fileName = fileURL.lastPathComponent
            if fileNames.contains(fileName) {
                hasDuplicates = true
                break
            }
            fileNames.insert(fileName)
        }
        
        // 如果有同名文件,弹窗询问是否继续
        // If there are files with same name, show dialog asking whether to continue
        if hasDuplicates {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("has-same-name-files", comment: "发现同名文件")
            alert.informativeText = NSLocalizedString("has-same-name-files-info", comment: "来源文件中包含同名文件，是否自动重命名？")
            alert.alertStyle = .warning
            // 设置系统提示图标
            // Set system notification icon
            alert.icon = NSImage(named: NSImage.infoName)
            alert.addButton(withTitle: NSLocalizedString("Auto Rename", comment: "自动重命名"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
            
            let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled = false
            defer {
                publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
            }
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                ifAutoRenameWhenDifferentSource = true
            } else {
                return
            }
        }

        // 记录操作到日志
        // Record operation to log
        var sourceFiles = items.compactMap { item -> String? in
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { return nil }
            return fileURL.lastPathComponent
        }
        
        let sourceFilesStr: String
        if sourceFiles.count > 3 {
            sourceFilesStr = sourceFiles[0...2].joined(separator: ", ") + "..."
        } else {
            sourceFilesStr = sourceFiles.joined(separator: ", ")
        }
        
        let operationLog = "[Paste] \(sourceFilesStr) -> \(destinationURL.lastPathComponent)"
        globalVar.operationLogs.append(operationLog)
        
        // 播放提示音
        // Play notification sound
        var changeCount = 0
        defer {
            if changeCount > 0 {
                triggerFinderSound()
            }
        }
        
        // 针对递归模式处理
        // Handle recursive mode
        var currentFolderChangeCount = 0
        defer {
            if publicVar.isRecursiveMode {
                if currentFolderChangeCount > 0 {
                    fileDB.lock()
                    let ifRefresh = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
                    fileDB.unlock()
                    if ifRefresh {
                        scheduledRefresh()
                    }
                }
            }
        }
        
        var shouldReplaceAll = false
        var shouldSkipAll = false
        var shouldAutoRenameAll = false
        
        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            var destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)

            if ifAutoRenameWhenDifferentSource {
                destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
            }
            
            // 如果是在同一目录复制粘贴，则修改名称
            // If copying/pasting in same directory, modify name
            var isInSameFolder = fileURL.deletingLastPathComponent() == destinationURL
            if isInSameFolder {
                destURL = getUniqueDestinationURL(for: destURL, isInPlace: true)
            }
            
            if FileManager.default.fileExists(atPath: destURL.path) {
                if shouldReplaceAll {
                    do {
                        changeCount += 1
                        if isInSameFolder {
                            currentFolderChangeCount += 1
                            publicVar.fileChangedCount += 1
                        }
                        try FileManager.default.removeItem(at: destURL)
                        try FileManager.default.copyItem(at: fileURL, to: destURL)
                    } catch {
                        log("Failed to paste \(fileURL): \(error)")
                    }
                } else if shouldSkipAll {
                    continue
                } else if shouldAutoRenameAll {
                    destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                    do {
                        changeCount += 1
                        if isInSameFolder {
                            currentFolderChangeCount += 1
                            publicVar.fileChangedCount += 1
                        }
                        try FileManager.default.copyItem(at: fileURL, to: destURL)
                    } catch {
                        log("Failed to paste \(fileURL): \(error)")
                    }
                } else {
                    let userChoice = showReplaceDialog(for: destURL, isSingle: items.count == 1, isMove: false)
                    switch userChoice {
                    case .replace:
                        do {
                            changeCount += 1
                            if isInSameFolder {
                                currentFolderChangeCount += 1
                                publicVar.fileChangedCount += 1
                            }
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                        } catch {
                            log("Failed to paste \(fileURL): \(error)")
                        }
                    case .replaceAll:
                        shouldReplaceAll = true
                        do {
                            changeCount += 1
                            if isInSameFolder {
                                currentFolderChangeCount += 1
                                publicVar.fileChangedCount += 1
                            }
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                        } catch {
                            log("Failed to paste \(fileURL): \(error)")
                        }
                    case .autoRename:
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        do {
                            changeCount += 1
                            if isInSameFolder {
                                currentFolderChangeCount += 1
                                publicVar.fileChangedCount += 1
                            }
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                        } catch {
                            log("Failed to paste \(fileURL): \(error)")
                        }
                    case .autoRenameAll:
                        shouldAutoRenameAll = true
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        do {
                            changeCount += 1
                            if isInSameFolder {
                                currentFolderChangeCount += 1
                                publicVar.fileChangedCount += 1
                            }
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                        } catch {
                            log("Failed to paste \(fileURL): \(error)")
                        }
                    case .skip:
                        continue
                    case .skipAll:
                        shouldSkipAll = true
                        continue
                    case .cancel:
                        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                        return
                    }
                }
            } else {
                do {
                    changeCount += 1
                    if isInSameFolder {
                        currentFolderChangeCount += 1
                        publicVar.fileChangedCount += 1
                    }
                    try FileManager.default.copyItem(at: fileURL, to: destURL)
                } catch {
                    log("Failed to paste \(fileURL): \(error)")
                }
            }
        }
        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
    }
    
    func handleMoveToDownload() {
        if publicVar.selectedUrls().isEmpty {return}
        
        // 备份剪贴板内容
        // Backup pasteboard content
        let backupItems = backupPasteboard()
        
        handleCopy()
        handleMove(targetURL: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        
        // 还原剪贴板内容
        // Restore pasteboard content
        restorePasteboard(items: backupItems)
    }

    func handleMove(targetURL: URL? = nil, pasteboard: NSPasteboard = NSPasteboard.general) {
        
        // 按住Option则为复制
        // Hold Option to copy
        if isOptionKeyPressed() && !isCommandKeyPressed() {
            handlePaste(targetURL: targetURL, pasteboard: pasteboard)
            return
        }
        
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
        // Check list of files/folders to move
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            
            // 检查是否包含目标目录自身或者它的父目录
            // Check if includes destination directory itself or its parent directory
            if fileURL == destinationURL || destinationURL.path.hasPrefix(fileURL.path) {
                showAlert(message: NSLocalizedString("cannot-move-to-self", comment: "不能将文件/文件夹移动到自身或其子目录中。"))
                return
            }
        }

        // 检查来源是否有同名文件
        // Check if source has files with same name
        var ifAutoRenameWhenDifferentSource = false
        var fileNames = Set<String>()
        var hasDuplicates = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            let fileName = fileURL.lastPathComponent
            if fileNames.contains(fileName) {
                hasDuplicates = true
                break
            }
            fileNames.insert(fileName)
        }
        
        // 如果有同名文件,弹窗询问是否继续
        // If there are files with same name, show dialog asking whether to continue
        if hasDuplicates {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("has-same-name-files", comment: "发现同名文件")
            alert.informativeText = NSLocalizedString("has-same-name-files-info", comment: "来源文件中包含同名文件，是否自动重命名？")
            alert.alertStyle = .warning
            // 设置系统提示图标
            // Set system notification icon
            alert.icon = NSImage(named: NSImage.infoName)
            alert.addButton(withTitle: NSLocalizedString("Auto Rename", comment: "自动重命名"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
            
            let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled = false
            defer {
                publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
            }
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                ifAutoRenameWhenDifferentSource = true
            } else {
                return
            }
        }
        
        // 记录操作到日志
        // Record operation to log
        var sourceFiles = items.compactMap { item -> String? in
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { return nil }
            return fileURL.lastPathComponent
        }
        
        let sourceFilesStr: String
        if sourceFiles.count > 3 {
            sourceFilesStr = sourceFiles[0...2].joined(separator: ", ") + "..."
        } else {
            sourceFilesStr = sourceFiles.joined(separator: ", ")
        }
        
        let operationLog = "[Move] \(sourceFilesStr) -> \(destinationURL.lastPathComponent)"
        globalVar.operationLogs.append(operationLog)
        
        // 播放提示音
        // Play notification sound
        var changeCount = 0
        defer {
            if changeCount > 0 {
                triggerFinderSound()
            }
        }
        
        // 针对递归模式处理
        // Handle recursive mode
        var currentFolderChangeCount = 0
        defer {
            if publicVar.isRecursiveMode {
                if currentFolderChangeCount > 0 {
                    fileDB.lock()
                    let ifRefresh = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
                    fileDB.unlock()
                    if ifRefresh {
                        scheduledRefresh()
                    }
                }
            }
        }
        
        var shouldReplaceAll = false
        var shouldSkipAll = false
        var shouldAutoRenameAll = false
        
        let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
        publicVar.isKeyEventEnabled = false
        for item in items {
            guard let fileURL = URL(string: item.string(forType: .fileURL) ?? "") else { continue }
            var destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)
            
            // 如果是在同一目录移动，则不作动作
            // If moving in same directory, do nothing
            var isInSameFolder = fileURL.deletingLastPathComponent() == destinationURL
            if isInSameFolder {
                continue
            }

            if ifAutoRenameWhenDifferentSource {
                destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
            }

            if FileManager.default.fileExists(atPath: destURL.path) {
                if shouldReplaceAll {
                    do {
                        changeCount += 1
                        if isInSameFolder {
                            currentFolderChangeCount += 1
                            publicVar.fileChangedCount += 1
                        }
                        try FileManager.default.removeItem(at: destURL)
                        try FileManager.default.moveItem(at: fileURL, to: destURL)
                    } catch {
                        log("Failed to move \(fileURL): \(error)")
                    }
                } else if shouldSkipAll {
                    continue
                } else if shouldAutoRenameAll {
                    destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                    do {
                        changeCount += 1
                        if isInSameFolder {
                            currentFolderChangeCount += 1
                            publicVar.fileChangedCount += 1
                        }
                        try FileManager.default.moveItem(at: fileURL, to: destURL)
                    } catch {
                        log("Failed to move \(fileURL): \(error)")
                    }
                } else {
                    let userChoice = showReplaceDialog(for: destURL, isSingle: items.count == 1, isMove: true)
                    switch userChoice {
                    case .replace:
                        do {
                            changeCount += 1
                            if isInSameFolder {
                                currentFolderChangeCount += 1
                                publicVar.fileChangedCount += 1
                            }
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                        } catch {
                            log("Failed to move \(fileURL): \(error)")
                        }
                    case .replaceAll:
                        shouldReplaceAll = true
                        do {
                            changeCount += 1
                            if isInSameFolder {
                                currentFolderChangeCount += 1
                                publicVar.fileChangedCount += 1
                            }
                            try FileManager.default.removeItem(at: destURL)
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                        } catch {
                            log("Failed to move \(fileURL): \(error)")
                        }
                    case .autoRename:
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        do {
                            changeCount += 1
                            if isInSameFolder {
                                currentFolderChangeCount += 1
                                publicVar.fileChangedCount += 1
                            }
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                        } catch {
                            log("Failed to move \(fileURL): \(error)")
                        }
                    case .autoRenameAll:
                        shouldAutoRenameAll = true
                        destURL = getUniqueDestinationURL(for: destURL, isInPlace: false)
                        do {
                            changeCount += 1
                            if isInSameFolder {
                                currentFolderChangeCount += 1
                                publicVar.fileChangedCount += 1
                            }
                            try FileManager.default.moveItem(at: fileURL, to: destURL)
                        } catch {
                            log("Failed to move \(fileURL): \(error)")
                        }
                    case .skip:
                        continue
                    case .skipAll:
                        shouldSkipAll = true
                        continue
                    case .cancel:
                        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
                        return
                    }
                }
            } else {
                do {
                    changeCount += 1
                    if isInSameFolder {
                        currentFolderChangeCount += 1
                        publicVar.fileChangedCount += 1
                    }
                    try FileManager.default.moveItem(at: fileURL, to: destURL)
                } catch {
                    log("Failed to move \(fileURL): \(error)")
                }
            }
        }
        publicVar.isKeyEventEnabled = StoreIsKeyEventEnabled
    }
    
    func handleDelete(fileUrls: [URL] = [], isShowPrompt: Bool = true) -> Bool {
        var urls = fileUrls
        if urls.count == 0 {
            urls = publicVar.selectedUrls()
        }
        guard urls.count != 0 else {return false}
        
        let ifHasPermission = requestAppleEventsPermission()
        let isShiftPressed = isShiftKeyPressed()
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete", comment: "删除")
        if isShiftPressed {
            alert.informativeText = NSLocalizedString("ask-to-delete-shift", comment: "你确定要将这些文件永久删除吗？此操作无法撤销。")
        }else if VolumeManager.shared.isExternalVolume(urls.first!) {
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
        // 设置系统警告图标
        // Set system warning icon
        alert.icon = NSImage(named: NSImage.cautionName)

        var response: NSApplication.ModalResponse = .alertFirstButtonReturn
        if isShowPrompt || !ifHasPermission || VolumeManager.shared.isExternalVolume(urls.first!) {
            let StoreIsKeyEventEnabled = publicVar.isKeyEventEnabled
            publicVar.isKeyEventEnabled=false
            response = alert.runModal()
            publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
        }

        if response == .alertFirstButtonReturn {
            // 用户确认删除
            // User confirmed deletion
            let fileManager = FileManager.default
            var urlsToDelete = [URL]()
            
            for url in urls {
                if fileManager.fileExists(atPath: url.path) {
                    urlsToDelete.append(url)
                } else {
                    log("File does not exist: \(url.path)")
                }
            }
            
            // 记录操作到日志
            // Record operation to log
            var sourceFiles = urlsToDelete.map { url -> String in
                return url.lastPathComponent
            }
            
            let sourceFilesStr: String
            if sourceFiles.count > 3 {
                sourceFilesStr = sourceFiles[0...2].joined(separator: ", ") + "..."
            } else {
                sourceFilesStr = sourceFiles.joined(separator: ", ")
            }
            
            let operationLog = "[Delete] \(sourceFilesStr)"
            globalVar.operationLogs.append(operationLog)
            
            if !urlsToDelete.isEmpty {
                // 永久删除
                // Permanently delete
                if isShiftPressed {
                    for url in urlsToDelete {
                        try? fileManager.removeItem(at: url)
                    }
                // 删除到回收站
                // Delete to trash
                } else {
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
                            NSWorkspace.shared.recycle(urlsToDelete, completionHandler: { (newURLs, error) in
                                if let error = error {
                                    log("Failed to delete: \(error)")
                                } else {
                                    log("File moved to trash")
                                }
                            })
                        } else if let error = error {
                            log("Failed to delete: \(error)")
                        } else {
                            log("File moved to trash")
                        }
                    }
                }
                
                // 文件更改计数
                // File change count
                publicVar.fileChangedCount += 1

                // 针对递归模式处理
                // Handle recursive mode
                if publicVar.isRecursiveMode {
                    fileDB.lock()
                    let ifRefresh = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0 <= RESET_VIEW_FILE_NUM_THRESHOLD
                    fileDB.unlock()
                    if ifRefresh {
                        scheduledRefresh()
                    }
                }
                
            } else {
                log("File to delete does not exist")
            }
            return true
        } else {
            // 用户取消操作
            // User cancelled operation
            log("Delete operation cancelled")
            return false
        }
    }
    
    enum ReplaceDialogUserChoice {
        case replace
        case replaceAll
        case skip
        case skipAll
        case autoRename
        case autoRenameAll
        case cancel
    }

    func showReplaceDialog(for url: URL, isSingle: Bool, isMove: Bool) -> ReplaceDialogUserChoice {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("has-exist-in-dest", comment: "目标文件夹中已存在名为xx的文件。"), url.lastPathComponent)
        if isMove {
            alert.informativeText = NSLocalizedString("do-you-want-replace(move)", comment: "你要用正在移动的文件替换它吗？")
        }else{
            alert.informativeText = NSLocalizedString("do-you-want-replace(paste)", comment: "你要用正在粘贴的文件替换它吗？")
        }
        alert.alertStyle = .warning
        // 设置系统提示图标
        // Set system notification icon
        alert.icon = NSImage(named: NSImage.infoName)
        alert.addButton(withTitle: NSLocalizedString("Replace", comment: "替换"))
        alert.addButton(withTitle: NSLocalizedString("Auto Rename", comment: "自动重命名"))
        if !isSingle {
            alert.addButton(withTitle: NSLocalizedString("Skip", comment: "跳过"))
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        
        // 添加复选框
        // Add checkbox
        let applyToAllCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Apply to all", comment: "应用到全部"), target: nil, action: nil)
        if !isSingle {
            alert.accessoryView = applyToAllCheckbox
        }
        
        let response = alert.runModal()
        let applyToAll = applyToAllCheckbox.state == .on
        
        switch response {
        case .alertFirstButtonReturn:
            return applyToAll ? .replaceAll : .replace
        case .alertSecondButtonReturn:
            return applyToAll ? .autoRenameAll : .autoRename
        case .alertThirdButtonReturn:
            return applyToAll ? .skipAll : .skip
        case NSApplication.ModalResponse(rawValue: 1003):
            return .cancel
        default:
            return .cancel
        }
    }
}
