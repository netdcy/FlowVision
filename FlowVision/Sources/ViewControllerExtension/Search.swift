//
//  Search.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    class SearchOverlayView: NSView {
        // weak var searchField: NSSearchField?
        weak var containerView: NSView?
        weak var viewController: ViewController?
        
        override func mouseDown(with event: NSEvent) {
            let location = event.locationInWindow
            let point = convert(location, from: nil)
            
            if let containerView = containerView, !containerView.frame.contains(point) {
                viewController?.closeSearchOverlay()
            }
        }
    }

    func showSearchOverlay() {
        if publicVar.isInLargeView {return}
        if searchOverlay == nil {

            // 创建半透明背景，使用自定义 SearchOverlayView
            // Create semi-transparent background using custom SearchOverlayView
            let overlay = SearchOverlayView(frame: view.bounds)
            overlay.wantsLayer = true
            overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.0).cgColor
            
            let caseSensitiveCheckboxTitle = NSLocalizedString("Case Sensitive", comment: "区分大小写")
            let caseSensitiveCheckboxWidth = 25 + caseSensitiveCheckboxTitle.size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
            let regexCheckboxTitle = NSLocalizedString("Regex", comment: "正则表达式")
            let regexCheckboxWidth = 25 + regexCheckboxTitle.size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
            let fullPathCheckboxTitle = NSLocalizedString("Use Full Path", comment: "使用完整路径")
            let fullPathCheckboxWidth = 25 + fullPathCheckboxTitle.size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
            let filterButtonTitle = NSLocalizedString("Apply Filter", comment: "执行过滤")
            let filterButtonFont = NSFont.systemFont(ofSize: 12.6)
            let filterButtonWidth = 25 + filterButtonTitle.size(withAttributes: [.font: filterButtonFont]).width.rounded()
            // 用于整体调整宽度
            // Used for overall width adjustment
            var withAdjust = caseSensitiveCheckboxWidth + regexCheckboxWidth + filterButtonWidth
            withAdjust += publicVar.isRecursiveMode ? fullPathCheckboxWidth : 0
            withAdjust += -50
            
            // 创建搜索框容器视图 - 增加高度以容纳两行
            // Create search box container view - increase height to accommodate two rows
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 210+withAdjust, height: 66))
            
            // 创建搜索框 - 放在上面一行
            // Create search box - place on top row
            searchField = NSSearchField(frame: NSRect(x: 5, y: 31, width: 200+withAdjust, height: 30))
            searchField?.placeholderString = NSLocalizedString("Search...", comment: "搜索...")
            searchField?.stringValue = search_searchText
            searchField?.delegate = self
            searchField?.target = self
            searchField?.action = #selector(searchFieldDidChange(_:))
            searchField?.focusRingType = .none
            
            // 创建区分大小写复选框 - 放在下面一行
            // Create case sensitive checkbox - place on bottom row
            let caseSensitiveCheckbox = NSButton(checkboxWithTitle: caseSensitiveCheckboxTitle, target: self, action: #selector(caseSensitiveCheckboxChanged(_:)))
            caseSensitiveCheckbox.frame = NSRect(x: 5, y: 6, width: caseSensitiveCheckboxWidth, height: 20)
            caseSensitiveCheckbox.state = search_isCaseSensitive ? .on : .off
            
            // 创建正则表达式复选框 - 放在下面一行
            // Create regex checkbox - place on bottom row
            let regexCheckbox = NSButton(checkboxWithTitle: regexCheckboxTitle, target: self, action: #selector(regexCheckboxChanged(_:)))
            regexCheckbox.frame = NSRect(x: 5 + caseSensitiveCheckboxWidth + 5, y: 6, width: regexCheckboxWidth, height: 20)
            regexCheckbox.state = search_useRegex ? .on : .off
            
            // 创建使用完整路径复选框 - 放在正则表达式复选框后面
            // Create use full path checkbox - place after regex checkbox
            let fullPathCheckbox = NSButton(checkboxWithTitle: fullPathCheckboxTitle, target: self, action: #selector(fullPathCheckboxChanged(_:)))
            fullPathCheckbox.frame = NSRect(x: 5 + caseSensitiveCheckboxWidth + 5 + regexCheckboxWidth + 5, y: 6, width: fullPathCheckboxWidth, height: 20)
            fullPathCheckbox.state = search_isUseFullPath ? .on : .off
            
            // 创建向前搜索按钮 - 放在下面一行
            // Create previous search button - place on bottom row
            let prevButton = NSButton(frame: NSRect(x: 147+withAdjust, y: 3, width: 30, height: 25))
            prevButton.bezelStyle = .regularSquare
            prevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
            prevButton.target = self
            prevButton.action = #selector(prevButtonClicked(_:))
            
            // 创建向后搜索按钮 - 放在下面一行
            // Create next search button - place on bottom row
            let nextButton = NSButton(frame: NSRect(x: 177+withAdjust, y: 3, width: 30, height: 25))
            nextButton.bezelStyle = .regularSquare
            nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            nextButton.target = self
            nextButton.action = #selector(nextButtonClicked(_:))

            // 创建执行过滤按钮 - 放在正则表达式复选框后面
            // Create apply filter button - place after regex checkbox
            let filterButtonX = prevButton.frame.origin.x - filterButtonWidth
            let filterButton = NSButton(frame: NSRect(x: filterButtonX, y: 3, width: filterButtonWidth, height: 25))
            filterButton.title = filterButtonTitle
            filterButton.font = filterButtonFont
            filterButton.bezelStyle = .regularSquare
            filterButton.target = self
            filterButton.action = #selector(filterButtonClicked(_:))

            // 创建问号按钮 - 放在过滤按钮左边
            // Create help button - place to the left of filter button
            // 5是按钮间距
            // 5 is button spacing
            let helpButtonX = filterButtonX - 25
            let helpButton = NSButton(frame: NSRect(x: helpButtonX, y: 4, width: 24, height: 24))
            helpButton.bezelStyle = .circular
            helpButton.title = "?"
            helpButton.font = NSFont.systemFont(ofSize: 15, weight: .regular)
            helpButton.target = self
            helpButton.action = #selector(helpButtonClicked(_:))
            
            // 添加所有控件到容器视图
            // Add all controls to container view
            containerView.addSubview(searchField!)
            containerView.addSubview(regexCheckbox)
            containerView.addSubview(caseSensitiveCheckbox)
            if publicVar.isRecursiveMode {
                containerView.addSubview(fullPathCheckbox)
            }
            containerView.addSubview(helpButton)
            containerView.addSubview(filterButton)
            containerView.addSubview(prevButton)
            containerView.addSubview(nextButton)
            
            // 设置容器视图位置
            // Set container view position
            containerView.frame.origin.x = view.bounds.width - containerView.frame.width - 30
            containerView.frame.origin.y = view.bounds.height - containerView.frame.height - 20
            // 另外注意在viewDidLayout()中实时调整位置
            // Also note: adjust position in real-time in viewDidLayout()
            
            overlay.addSubview(containerView)
            
            // 设置引用
            // Set references
            overlay.containerView = containerView
            overlay.viewController = self
            searchOverlay = overlay
            
            view.addSubview(searchOverlay!)
            
        }
        
        if let containerView = searchOverlay?.containerView {
            // 设置样式
            // Set style
            containerView.wantsLayer = true
            containerView.layer?.cornerRadius = 8
            containerView.layer?.masksToBounds = false
            let theme = NSApp.effectiveAppearance.name
            if theme == .darkAqua {
                containerView.layer?.backgroundColor = hexToNSColor(hex: "#404040", alpha: 0.8).cgColor
            } else {
                containerView.layer?.backgroundColor = hexToNSColor(hex: "#EEEEEE", alpha: 0.9).cgColor
            }
            containerView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.4).cgColor
            containerView.layer?.shadowOffset = CGSize(width: 1.3, height: -1.3)
            containerView.layer?.shadowRadius = 2.5
            containerView.layer?.shadowOpacity = 1
        }
        
        publicVar.isKeyEventEnabled = false
        publicVar.isInSearchState = true
        // searchOverlay?.isHidden = false
        searchField?.becomeFirstResponder()
    }

    @objc func closeSearchOverlay() {
        publicVar.isKeyEventEnabled = true
        publicVar.isInSearchState = false
//        if searchOverlay?.isHidden == false {
//            searchOverlay?.isHidden = true
//            view.window?.makeFirstResponder(collectionView)
//        }
        if searchOverlay != nil {
            searchOverlay?.removeFromSuperview()
            searchOverlay = nil
            searchField = nil
            view.window?.makeFirstResponder(collectionView)
        }
    }
    
    func toggleSearchOverlay() {
        if publicVar.isInLargeView {return}
        if searchOverlay == nil {
            showSearchOverlay()
        }else{
            closeSearchOverlay()
        }
    }
    
    func getFileNameForSearch(path: String) -> String? {
        if search_isUseFullPath && publicVar.isRecursiveMode {
            return path.removingPercentEncoding?.replacingOccurrences(of: "file://", with: "")
        } else {
            if path.hasSuffix("/") {
                return path.dropLast().components(separatedBy: "/").last?.removingPercentEncoding
            }
            return path.components(separatedBy: "/").last?.removingPercentEncoding
        }
    }

    func performSearch(searchText: String, isEnterKey: Bool, isReverse: Bool = false, forceUseRegex: Bool = false, firstMatch: Bool = false) -> Bool {
        // 如果搜索文本为空，不执行搜索
        // If search text is empty, don't perform search
        if searchText.isEmpty {
            return true
        }
        
        // 获取当前选中的索引
        // Get currently selected index
        let currentSelectedIndex = collectionView.selectionIndexPaths.first?.item ?? -1
        
        fileDB.lock()
        let files = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files ?? [:]
        
        // 检查当前选中项是否符合搜索条件
        // Check if currently selected item matches search condition
        if !firstMatch,
           let currentIndex = collectionView.selectionIndexPaths.first?.item,
           let currentFileName = getFileNameForSearch(path: files.element(atOffset: currentIndex).1.path),
           isSearchMatch(fileName: currentFileName, searchText: searchText, forceUseRegex: forceUseRegex) {
            if isEnterKey {
                // 查找下一个或上一个匹配项
                // Find next or previous match
                var foundIndex: Int?
                if isReverse {
                    for (index, file) in files.enumerated().reversed() {
                        if let fileName = getFileNameForSearch(path: file.1.path) {
                            if isSearchMatch(fileName: fileName, searchText: searchText, forceUseRegex: forceUseRegex) && index < currentSelectedIndex {
                                foundIndex = index
                                break
                            }
                        }
                    }
                    
                    // 如果到头了，则跳转到末尾，直到当前项之后（从而实现循环跳转）
                    // If reached beginning, jump to end until after current item (to achieve circular navigation)
                    if foundIndex == nil {
                        for (index, file) in files.enumerated().reversed() {
                            if let fileName = getFileNameForSearch(path: file.1.path) {
                                if isSearchMatch(fileName: fileName, searchText: searchText, forceUseRegex: forceUseRegex) && index >= currentSelectedIndex {
                                    foundIndex = index
                                    break
                                }
                            }
                        }
                    }
                } else {
                    for (index, file) in files.enumerated() {
                        if let fileName = getFileNameForSearch(path: file.1.path) {
                            if isSearchMatch(fileName: fileName, searchText: searchText, forceUseRegex: forceUseRegex) && index > currentSelectedIndex {
                                foundIndex = index
                                break
                            }
                        }
                    }
                    
                    // 如果到底了，则跳转到开头，直到当前项之前（从而实现循环跳转）
                    // If reached end, jump to beginning until before current item (to achieve circular navigation)
                    if foundIndex == nil {
                        for (index, file) in files.enumerated() {
                            if let fileName = getFileNameForSearch(path: file.1.path) {
                                if isSearchMatch(fileName: fileName, searchText: searchText, forceUseRegex: forceUseRegex) && index <= currentSelectedIndex {
                                    foundIndex = index
                                    break
                                }
                            }
                        }
                    }
                }
                
                fileDB.unlock()
                
                // 如果找到匹配项，选中并滚动到该项
                // If match found, select and scroll to that item
                if let index = foundIndex {
                    if index >= 0 && index < collectionView.numberOfItems(inSection: 0) {
                        let indexPath = IndexPath(item: index, section: 0)
                        collectionView.deselectAll(nil)
                        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                        collectionView.reloadData()
                        collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [indexPath])
                        collectionView.selectItems(at: [indexPath], scrollPosition: [])
                        collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
                        setLoadThumbPriority(ifNeedVisable: true)
                        return true
                    }
                }
                
                return true
            } else {
                fileDB.unlock()
                return true
            }
        } else {
            // 当前选中项不符合搜索条件，取消所有选择
            // Currently selected item doesn't match search condition, deselect all
            collectionView.deselectAll(nil)
        }
        
        // 从头开始查找第一个匹配项
        // Search from beginning for first match
        var foundIndex: Int?
        for (index, file) in files.enumerated() {
            if let fileName = getFileNameForSearch(path: file.1.path) {
                if isSearchMatch(fileName: fileName, searchText: searchText, forceUseRegex: forceUseRegex) {
                    foundIndex = index
                    break
                }
            }
        }
        fileDB.unlock()
        
        // 如果找到匹配项，选中并滚动到该项
        // If match found, select and scroll to that item
        if let index = foundIndex {
            if index >= 0 && index < collectionView.numberOfItems(inSection: 0) {
                let indexPath = IndexPath(item: index, section: 0)
                collectionView.deselectAll(nil)
                collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                collectionView.reloadData()
                collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [indexPath])
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
                collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [indexPath])
                setLoadThumbPriority(ifNeedVisable: true)
                return true
            }
        }
        
        return false
    }
    
    func isSearchMatch(fileName _fileName: String, searchText _searchText: String, forceUseRegex: Bool) -> Bool {
        if search_useRegex || forceUseRegex {
            // 使用正则表达式进行匹配
            // Use regular expression for matching
            do {
                let fileName = _fileName
                let searchText = _searchText
                let options: NSRegularExpression.Options = search_isCaseSensitive ? [] : [.caseInsensitive]
                let regex = try NSRegularExpression(pattern: searchText, options: options)
                let range = NSRange(location: 0, length: fileName.utf16.count)
                return regex.firstMatch(in: fileName, options: [], range: range) != nil
            } catch {
                // 如果正则表达式无效，返回false
                // If regular expression is invalid, return false
                return false
            }
        } else {
            // 使用普通文本匹配
            // Use plain text matching
            var fileName = _fileName
            var searchText = _searchText
            if !search_isCaseSensitive {
                fileName = fileName.lowercased()
                searchText = searchText.lowercased()
            }
            var result = fileName.contains(searchText)
            if globalVar.usePinyinSearch {
                result = result || convertToPinyin(fileName, toPinyinFull: true).contains(searchText)
            }
            if globalVar.usePinyinInitialSearch {
                result = result || convertToPinyin(fileName, toPinyinFull: false).contains(searchText)
            }
            return result
        }
    }

    @objc private func searchFieldDidChange(_ sender: NSSearchField) {
        let searchText = sender.stringValue
        
        // 标记并移除 ASCII 值为 3 的字符 (Shift+小键盘Enter)
        // Mark and remove character with ASCII value 3 (Shift+numpad Enter)
        var containsSpecialCharacter = false
        let filteredText = searchText.filter { character in
            if character.asciiValue == 3 {
                containsSpecialCharacter = true
                // 过滤掉该字符
                // Filter out this character
                return false
            }
            return true
        }
        
        // 如果存在特殊字符，则执行向上搜索
        // If special character exists, perform reverse search
        if containsSpecialCharacter {
            sender.stringValue = filteredText
            search_searchText = filteredText
            _ = performSearch(searchText: filteredText, isEnterKey: true, isReverse: true)
        }else{
            search_searchText = filteredText
            _ = performSearch(searchText: filteredText, isEnterKey: false)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let searchText = searchField?.stringValue ?? ""
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            _ = performSearch(searchText: searchText, isEnterKey: true, isReverse: isShiftPressed)
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            closeSearchOverlay()
            return true
        }
        return false
    }

    @objc private func regexCheckboxChanged(_ sender: NSButton) {
        search_useRegex = (sender.state == .on)
        // 当切换正则表达式选项时，重新执行搜索
        // When toggling regex option, re-execute search
        let searchText = searchField?.stringValue ?? ""
        _ = performSearch(searchText: searchText, isEnterKey: false)
    }

    @objc private func caseSensitiveCheckboxChanged(_ sender: NSButton) {
        search_isCaseSensitive = (sender.state == .on)
        // 当切换区分大小写选项时，重新执行搜索
        // When toggling case sensitive option, re-execute search
        let searchText = searchField?.stringValue ?? ""
        _ = performSearch(searchText: searchText, isEnterKey: false)
    }

    @objc private func prevButtonClicked(_ sender: NSButton) {
        let searchText = searchField?.stringValue ?? ""
        _ = performSearch(searchText: searchText, isEnterKey: true, isReverse: true)
    }

    @objc private func nextButtonClicked(_ sender: NSButton) {
        let searchText = searchField?.stringValue ?? ""
        _ = performSearch(searchText: searchText, isEnterKey: true, isReverse: false)
    }

    @objc private func helpButtonClicked(_ sender: NSButton) {
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("search-help", comment: "关于搜索的说明"))
    }

    @objc private func filterButtonClicked(_ sender: NSButton) {
        applyFilter()
    }
    
    func applyFilter(isReset: Bool = false) {
        if isReset {
            searchField?.stringValue = ""
        }
        let searchText = searchField?.stringValue ?? ""
        publicVar.isFilenameFilterOn = searchText == "" ? false : true
        refreshCollectionView(needLoadThumbPriority: true)
    }
    
    // 添加新的响应方法
    // Add new response method
    @objc private func fullPathCheckboxChanged(_ sender: NSButton) {
        search_isUseFullPath = (sender.state == .on)
        // 当切换使用完整路径选项时，重新执行搜索
        // When toggling use full path option, re-execute search
        let searchText = searchField?.stringValue ?? ""
        _ = performSearch(searchText: searchText, isEnterKey: false)
    }
    
    func quickSearch(_ character: String) {
        // 清除之前的计时器
        // Clear previous timer
        quickSearchTimer?.invalidate()
        
        // 添加新字符到搜索文本
        // Add new character to search text
        if character == "backspace" {
            quickSearchText = String(quickSearchText.dropLast())
        }else{
            quickSearchText += character
        }
        
        // 执行搜索
        // Execute search
        if quickSearchText != "" {
            if !performSearch(searchText: "^"+quickSearchText, isEnterKey: false, forceUseRegex: true, firstMatch: true) {
                _ = performSearch(searchText: quickSearchText, isEnterKey: false, forceUseRegex: false, firstMatch: true)
            }
        }
        coreAreaView.showInfo(NSLocalizedString("Quick Search", comment: "快速搜索")+": "+quickSearchText, timeOut: 1.8, duration: 0.1, cannotBeCleard: true)
        
        if !publicVar.isCollectionViewFirstResponder {
            view.window?.makeFirstResponder(collectionView)
        }
        
        // 设置新的计时器,n秒后清空搜索文本
        // Set new timer, clear search text after n seconds
        quickSearchState = true
        quickSearchTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            self?.quickSearchText = ""
            self?.quickSearchState = false
        }
    }
}
