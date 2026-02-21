//
//  KeyShutcut.swift
//  FlowVision
//

import Foundation
import Cocoa

extension ViewController {
    
    func KeyShortcutManager (event: NSEvent) -> NSEvent?
    {
        // 检查事件的窗口是否是当前窗口，如果不是、也非弹窗状态，就不处理，事件继续传递
        // Check if event's window is current window, if not and not popup state, don't process, continue passing event
        if event.window != self.view.window && publicVar.isKeyEventEnabled {
            return event
        }
        
        // 获取修饰键
        // Get modifier keys
        let modifierFlags = event.modifierFlags
        // 检测是否按下了 Control 键
        // Detect if Control key is pressed
        let isCtrlPressed = modifierFlags.contains(.control)
        // 检测是否按下了 Command 键
        // Detect if Command key is pressed
        let isCommandPressed = modifierFlags.contains(.command)
        // 检测是否按下了 Option 键
        // Detect if Option key is pressed
        let isAltPressed = modifierFlags.contains(.option)
        // 检测是否按下了 Shift 键
        // Detect if Shift key is pressed
        let isShiftPressed = modifierFlags.contains(.shift)
        // 检测是否按下了 Fn 键 (部分按键例如方向键按下时此值也为true)
        // Detect if Fn key is pressed (some keys like arrow keys also set this to true)
        let isFnPressed = modifierFlags.contains(.function)
        
        let noModifierKey = !isCommandPressed && !isAltPressed && !isCtrlPressed && !isShiftPressed
        let isOnlyCommandPressed = isCommandPressed && !isAltPressed && !isCtrlPressed && !isShiftPressed
        let isOnlyAltPressed = !isCommandPressed && isAltPressed && !isCtrlPressed && !isShiftPressed
        let isOnlyCtrlPressed = !isCommandPressed && !isAltPressed && isCtrlPressed && !isShiftPressed
        let isOnlyShiftPressed = !isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed
        
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()
        let specialKey = event.specialKey ?? .f30
        
        // 快速搜索
        // Quick search
        if publicVar.isKeyEventEnabled && characters.count == 1 && (characters.first!.isLetter || characters.first!.isNumber) && noModifierKey {
            if !publicVar.isInLargeView {
                if quickSearchState || globalVar.useQuickSearch {
                    quickSearch(characters)
                    return nil
                }
            }
        }
        
        // 快速搜索唤起键
        // Quick search activation key
        if publicVar.isKeyEventEnabled && characters == "q" && noModifierKey {
            if !publicVar.isInLargeView {
                if !quickSearchState && !globalVar.useQuickSearch {
                    quickSearch("backspace")
                    return nil
                }
            }
        }
        
        // 快速搜索删除键
        // Quick search delete key
        if publicVar.isKeyEventEnabled && specialKey == .delete && noModifierKey {
            if !publicVar.isInLargeView {
                if quickSearchState {
                    quickSearch("backspace")
                    return nil
                }
                if globalVar.useQuickSearch {
                    return nil
                }
            }
        }
        
        // 快速搜索Esc退出键
        // Quick search Esc exit key
        if publicVar.isKeyEventEnabled && event.keyCode == 53 {
            if !publicVar.isInLargeView {
                if quickSearchState {
                    quickSearchText = ""
                    quickSearchState = false
                    coreAreaView.hideInfo(force: true)
                    return nil
                }
            }
        }
        
        // 防止过快触发事件
        // Prevent events from triggering too quickly
        if !publicVar.timer.intervalSafe(name: "keyEvent", second: 0.1) {
            return event
        }
        
        if publicVar.isInSearchState || publicVar.isKeyEventEnabled {
            // 检查按键是否是 Command+Shift+"R" 键
            // Check if key is Command+Shift+"R"
            if characters == "r" && isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed {
                if !publicVar.isInLargeView{
                    toggleRecursiveMode()
                    return nil
                }
            }
            // 检查按键是否是 Command+Shift+"F" 键
            // Check if key is Command+Shift+"F"
            if characters == "f" && isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed {
                if !publicVar.isInLargeView{
                    toggleRecursiveContainFolder()
                    return nil
                }
            }
            // 检查按键是否是 Command+Shift+"T" 键
            // Check if key is Command+Shift+"T"
            if characters == "t" && isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed {
                handleReopenClosedTabs()
                return nil
            }
            // 检查按键是否是 F3 键
            // Check if key is F3
            if specialKey == .f3 {
                if !publicVar.isInLargeView{
                    toggleSearchOverlay()
                    return nil
                }
            }
        }
        
        if publicVar.isKeyEventEnabled {
            
            // 检查按键是否是 "A" 键
            // Check if key is "A"
            if characters == "a" && noModifierKey {
                if publicVar.isInLargeView{
                    previousLargeImage()
                }else{
                    closeLargeImage(0)
                    switchDirByDirection(direction: .left, stackDeep: 0)
                }
                return nil
            }
            // 检查按键是否是 "D" 键
            // Check if key is "D"
            if characters == "d" && noModifierKey {
                if publicVar.isInLargeView{
                    nextLargeImage()
                }else{
                    closeLargeImage(0)
                    switchDirByDirection(direction: .right, stackDeep: 0)
                }
                return nil
            }
            // 检查按键是否是 "W" 键
            // Check if key is "W"
            if characters == "w" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.zoom(direction: +1)
                }else{
                    closeLargeImage(0)
                    switchDirByDirection(direction: .up, stackDeep: 0)
                }
                return nil
            }
            
            // 检查按键是否是 "Z" 键
            // Check if key is "Z"
            if characters == "z" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.zoom100()
                }
            }
            
            // 检查按键是否是 "X" 键
            // Check if key is "X"
            if characters == "x" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.zoomFit()
                }
            }
            
            // 检查按键是否是 "S" 键
            // Check if key is "S"
            if characters == "s" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.zoom(direction: -1)
                }else{
                    closeLargeImage(0)
                    switchDirByDirection(direction: .down, stackDeep: 0)
                }
                return nil
            }
            
            // 检查按键是否是 "Q"
            // Check if key is "Q"
            if characters == "q" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.actRotateL()
                }
                return nil
            }
            
            // 检查按键是否是 "E"
            // Check if key is "E"
            if characters == "e" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.actRotateR()
                }else{
                    switchDirByDirection(direction: .down_right, stackDeep: 0)
                }
                return nil
            }
            
            // 检查按键是否是 "R" 键
            // Check if key is "R"
            if characters == "r" && noModifierKey {
                // 如果焦点在OutlineView
                // If focus is in OutlineView
                if publicVar.isOutlineViewFirstResponder{
                    outlineView.actRename(isByKeyboard: true)
                    return nil
                }
                
                // 如果焦点在CollectionView
                // If focus is in CollectionView
                if publicVar.isCollectionViewFirstResponder{
                    renameAlert(urls: publicVar.selectedUrls())
                    return nil
                }
            }
            
            // 检查按键是否是 "," 键
            // Check if key is ","
            if characters == "," && noModifierKey {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    largeImageView.specifyABPlayPositionA()
                }
                return nil
            }
            
            // 检查按键是否是 "." 键
            // Check if key is "."
            if characters == "." && noModifierKey {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    largeImageView.specifyABPlayPositionB()
                }
                return nil
            }
            
            // 检查按键是否是 "L" 键
            // Check if key is "L"
            if characters == "l" && noModifierKey {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    largeImageView.specifyABPlayPositionAuto()
                }
                return nil
            }
            
            // 检查按键是否是 "K" 键
            // Check if key is "K"
            if characters == "k" && noModifierKey {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    largeImageView.actRememberPlayPosition()
                }
                return nil
            }
            
            // 检查按键是否是 Cmd + "R" / F5 键
            // Check if key is Cmd + "R" / F5
            if (characters == "r" && isOnlyCommandPressed) || specialKey == .f5 {
                handleUserRefresh()
                return nil
            }
            
            // 检查按键是否是 Command+[ 键
            // Check if key is Command+[
            if characters == "[" && isOnlyCommandPressed {
                if !publicVar.isInLargeView{
                    switchDirByDirection(direction: .back, stackDeep: 0)
                }
                return nil
            }
            
            // 检查按键是否是 Command+] 键
            // Check if key is Command+]
            if characters == "]" && isOnlyCommandPressed {
                if !publicVar.isInLargeView{
                    switchDirByDirection(direction: .forward, stackDeep: 0)
                }
                return nil
            }
            
            // 检查按键是否是 Command+Shift+"N" 键
            // Check if key is Command+Shift+"N"
            if characters == "n" && isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed {
                if !publicVar.isInLargeView{
                    _ = handleNewFolder()
                    return nil
                }
            }
            
            // 检查按键是否是 Command+Shift+"V" 键
            // Check if key is Command+Shift+"V"
            if characters == "v" && isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed {
                if !publicVar.isInLargeView{
                    toggleAutoPlayVisibleVideo()
                    return nil
                }
            }
            
            // 检查按键是否是 Command+⬅️➡️ 键
            // Check if key is Command+⬅️➡️
            if (specialKey == .leftArrow || specialKey == .rightArrow) && isOnlyCommandPressed {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    if specialKey == .leftArrow {
                        largeImageView.seekVideoByFrame(direction: -1)
                    }else{
                        largeImageView.seekVideoByFrame(direction: 1)
                    }
                    return nil
                }
            }
            
            // 检查按键是否是 Command+⬆️ 键
            // Check if key is Command+⬆️
            if (specialKey == .upArrow && isOnlyCommandPressed) || (specialKey == .home && noModifierKey) {
                if publicVar.isInLargeView{
                    locateLargeImage(direction: -2)
                }else{
                    if let scrollView = collectionView.enclosingScrollView {
                        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        DispatchQueue.main.async { [weak self] in
                            self?.setLoadThumbPriority(ifNeedVisable: true)
                        }
                    }
                }
                return nil
            }
            
            // 检查按键是否是 Command+⬇️ 键
            // Check if key is Command+⬇️
            if (specialKey == .downArrow && isOnlyCommandPressed) || (specialKey == .end && noModifierKey) {
                if publicVar.isInLargeView{
                    locateLargeImage(direction: 2)
                }else{
                    if let scrollView = collectionView.enclosingScrollView {
                        let newOrigin = NSPoint(x: 0, y: collectionView.bounds.height - scrollView.contentSize.height)
                        scrollView.contentView.scroll(to: newOrigin)
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        DispatchQueue.main.async { [weak self] in
                            self?.setLoadThumbPriority(ifNeedVisable: true)
                        }
                    }
                }
                return nil
            }
            
            // 检查按键是否是 Opt+⬆️ 键
            // Check if key is Opt+⬆️
            if (specialKey == .upArrow && isOnlyAltPressed) || (specialKey == .pageUp && noModifierKey) {
                if !publicVar.isInLargeView{
                    if let scrollView = collectionView.enclosingScrollView {
                        let currentOrigin = scrollView.contentView.bounds.origin
                        let pageHeight = scrollView.contentSize.height
                        
                        // Calculate the new y position by subtracting the page height from the current y position.
                        let newY = max(currentOrigin.y - pageHeight, 0)
                        let newOrigin = NSPoint(x: currentOrigin.x, y: newY)
                        
                        // Scroll to the new origin
                        scrollView.contentView.scroll(to: newOrigin)
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        
                        DispatchQueue.main.async { [weak self] in
                            self?.setLoadThumbPriority(ifNeedVisable: true)
                        }
                    }
                    return nil
                }
            }
            
            
            // 检查按键是否是 Opt+⬇️ 键
            // Check if key is Opt+⬇️
            if (specialKey == .downArrow && isOnlyAltPressed) || (specialKey == .pageDown && noModifierKey) {
                if !publicVar.isInLargeView{
                    if let scrollView = collectionView.enclosingScrollView {
                        let currentOrigin = scrollView.contentView.bounds.origin
                        let pageHeight = scrollView.contentSize.height
                        
                        // Calculate the new y position by adding the page height to the current y position.
                        let newY = min(currentOrigin.y + pageHeight, collectionView.bounds.height - pageHeight)
                        let newOrigin = NSPoint(x: currentOrigin.x, y: newY)
                        
                        // Scroll to the new origin
                        scrollView.contentView.scroll(to: newOrigin)
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        
                        DispatchQueue.main.async { [weak self] in
                            self?.setLoadThumbPriority(ifNeedVisable: true)
                        }
                    }
                    return nil
                }
            }
            
            // 检查按键是否是 Esc 键
            // Check if key is Esc
            if event.keyCode == 53 {
                //                    self.view.window?.close()
                if publicVar.isInLargeView{
                    closeLargeImage(0)
                    return nil
                }else{
                    if publicVar.isCollectionViewFirstResponder{
                        collectionView.deselectAll(nil)
                    }
                    return nil
                }
            }
            
            // 检查按键是否是 Delete(117) Backspace(51) 键
            // Check if key is Delete(117) Backspace(51)
            if specialKey == .delete || specialKey == .backspace || specialKey == .deleteForward {
                // 如果焦点在OutlineView
                // If focus is on OutlineView
                if publicVar.isOutlineViewFirstResponder{
                    outlineView.actDelete(isByKeyboard: true, isShowPrompt: !isCommandPressed)
                    return nil
                }
                // 如果焦点在CollectionView
                // If focus is on CollectionView
                if publicVar.isCollectionViewFirstResponder{
                    handleDelete(isShowPrompt: !isCommandPressed)
                    return nil
                }
            }
            
            // 检查按键是否是 Opt + 回车、小键盘回车 键
            // Check if key is Opt + Enter, numpad Enter
            if (specialKey == .carriageReturn || specialKey == .enter) && isOnlyAltPressed {
                if let window = view.window {
                    window.toggleFullScreen(nil)
                }
                return nil
            }
            
            // 检查按键是否是 F2、回车、小键盘回车 键
            // Check if key is F2, Enter, numpad Enter
            if (specialKey == .f2 || specialKey == .carriageReturn || specialKey == .enter) && noModifierKey {
                if specialKey == .f2 || !globalVar.isEnterKeyToOpen {
                    // 如果焦点在OutlineView
                    // If focus is in OutlineView
                    if publicVar.isOutlineViewFirstResponder{
                        outlineView.actRename(isByKeyboard: true)
                        return nil
                    }
                    
                    // 如果焦点在CollectionView
                    // If focus is in CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        renameAlert(urls: publicVar.selectedUrls())
                        return nil
                    }
                }else{
                    if publicVar.isInLargeView{
                        closeLargeImage(0)
                        return nil
                    }else{
                        if let indexPath = collectionView.selectionIndexPaths.first {
                            if publicVar.isCollectionViewFirstResponder{
                                openLargeImage(indexPath)
                                return nil
                            }
                        }
                    }
                }
            }
            
            // 检查按键是否是 空格 键
            // Check if key is Space
            if characters == " " && noModifierKey {
                if publicVar.isInLargeView{
                    if largeImageView.file.type == .video {
                        largeImageView.pauseOrResumeVideo()
                    }else{
                        closeLargeImage(0)
                    }
                    return nil
                }else{
                    if let indexPath = collectionView.selectionIndexPaths.first {
                        if publicVar.isCollectionViewFirstResponder{
                            openLargeImage(indexPath)
                            return nil
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
            
            // 检查按键是否是 12345 键
            // Check if key is 12345
            if (["1","2","3","4","5"].contains(characters)) && noModifierKey {
                if view.window?.styleMask.contains(.fullScreen) == true {
                    return nil
                }
                if characters == "1" { // 1
                    adjustWindowMaximize()
                    return nil
                }else if characters == "2"{ // 2
                    adjustWindowSuitable()
                    return nil
                }else if characters == "5"{ // 5
                    adjustWindowToCenter()
                    return nil
                }else{
                    if publicVar.isInLargeView {
                        if characters == "3"{ // 3
                            adjustWindowImageActual()
                            return nil
                        }else if characters == "4"{ // 4
                            adjustWindowImageCurrent()
                            return nil
                        }
                    }
                }
            }
            
            // 检查按键是否是 Opt+1~9 键
            // Check if key is Opt+1~9
            if (["1","2","3","4","5","6","7","8","9"].contains(characters)) && isOnlyAltPressed {
                if !publicVar.isInLargeView {
                    useCustomProfile(characters)
                    return nil
                }
            }
            
            // 检查按键是否是 Cmd+Opt+1~9 键
            // Check if key is Cmd+Opt+1~9
            if (["1","2","3","4","5","6","7","8","9"].contains(characters)) && isCommandPressed && isAltPressed && !isCtrlPressed && !isShiftPressed {
                if !publicVar.isInLargeView {
                    setCustomProfileTo(characters)
                    return nil
                }
            }
            
            // 检查按键是否是 "U"
            // Check if key is "U"
            if characters == "u" && noModifierKey {
                if publicVar.isInLargeView {
                    handleGetInfo()
                    return nil
                }
            }
            
            // 检查按键是否是 "I"
            // Check if key is "I"
            if characters == "i" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.actShowExif()
                    return nil
                }else{
                    if publicVar.isOutlineViewFirstResponder{
                        outlineView.actGetInfo(isByKeyboard: true)
                        return nil
                    }
                    if publicVar.isCollectionViewFirstResponder{
                        handleGetInfo()
                        return nil
                    }
                }
            }
            
            // 检查按键是否是 "O"
            // Check if key is "O"
            if characters == "o" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.actOCR()
                    return nil
                }
            }
            
            // 检查按键是否是 "P"
            // Check if key is "P"
            if characters == "p" && noModifierKey {
                if publicVar.isInLargeView{
                    largeImageView.actQRCode()
                    return nil
                }
            }
            
            // 检查按键是否是 ➡️、⬇️、PageDown 键
            // Check if key is ➡️, ⬇️, PageDown
            if (specialKey == .rightArrow || specialKey == .downArrow || specialKey == .pageDown || specialKey == .next) && noModifierKey {
                if publicVar.isInLargeView{
                    if largeImageView.file.type == .video && specialKey == .rightArrow {
                        largeImageView.seekVideo(direction: 1)
                    }else{
                        nextLargeImage()
                    }
                    return nil
                }
            }
            // 检查按键是否是 ⬅️、⬆️、PageUp 键
            // Check if key is ⬅️, ⬆️, PageUp
            if (specialKey == .leftArrow || specialKey == .upArrow || specialKey == .pageUp || specialKey == .prev) && noModifierKey {
                if publicVar.isInLargeView{
                    if largeImageView.file.type == .video && specialKey == .leftArrow {
                        largeImageView.seekVideo(direction: -1)
                    }else{
                        previousLargeImage()
                    }
                    return nil
                }
            }
            
            // 检查按键是否是 Tab 键
            // Check if key is Tab
            if specialKey == .tab && noModifierKey {
                if !publicVar.isInLargeView{
                    if publicVar.isOutlineViewFirstResponder{
                        view.window?.makeFirstResponder(collectionView)
                        return nil
                    }else if publicVar.isCollectionViewFirstResponder{
                        view.window?.makeFirstResponder(outlineView)
                        return nil
                    }
                }
            }
            
            // 检查按键是否是 "⬅️➡️⬆️⬇️" 或 Space/Enter 键
            // Check if key is "⬅️➡️⬆️⬇️" or Space/Enter
            if (specialKey == .leftArrow || specialKey == .rightArrow || specialKey == .upArrow || specialKey == .downArrow || characters == " " || ((specialKey == .carriageReturn || specialKey == .enter) && globalVar.isEnterKeyToOpen))
                && (noModifierKey || isOnlyShiftPressed) {
                if !publicVar.isInLargeView{
                    // 如果焦点在OutlineView
                    // If focus is in OutlineView
                    if publicVar.isOutlineViewFirstResponder{
                        if let outlineView = outlineView {
                            let selectedRow=outlineView.selectedRow
                            // ⬆️
                            if specialKey == .upArrow {
                                if selectedRow > 0 {
                                    let previousRow = selectedRow - 1
                                    outlineView.selectRowIndexes(IndexSet(integer: previousRow), byExtendingSelection: false)
                                    // 可选：滚动视图以确保选中的项可见
                                    // Optional: Scroll view to ensure selected item is visible
                                    outlineView.scrollRowToVisible(previousRow)
                                }
                                // ⬇️
                            } else if specialKey == .downArrow {
                                if selectedRow != -1 && selectedRow < outlineView.numberOfRows - 1 {
                                    let nextRow = selectedRow + 1
                                    outlineView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
                                    // 可选：滚动视图以确保选中的项可见
                                    // Optional: Scroll view to ensure selected item is visible
                                    outlineView.scrollRowToVisible(nextRow)
                                }
                                // ⬅️➡️、Space/Enter
                                // ⬅️➡️, Space/Enter
                            }else {
                                // 获取行对应的条目
                                // Get item corresponding to row
                                if let item = outlineView.item(atRow: selectedRow) {
                                    if outlineView.isExpandable(item) {
                                        if outlineView.isItemExpanded(item) {
                                            outlineView.collapseItem(item)
                                        } else {
                                            outlineView.expandItem(item)
                                        }
                                    }
                                }
                            }
                            return nil
                        }
                    }
                    
                    // 如果焦点在CollectionView
                    // If focus is in CollectionView
                    if publicVar.isCollectionViewFirstResponder{
                        if let collectionView = collectionView,
                           let scrollView = collectionView.enclosingScrollView,
                           // 有选中项
                           // Has selected items
                            !collectionView.selectionIndexPaths.isEmpty
                        {
                            if specialKey == .leftArrow || specialKey == .rightArrow || specialKey == .upArrow || specialKey == .downArrow {
                                let sortedIndexPaths = collectionView.selectionIndexPaths.sorted()
                                var currentIndexPath = sortedIndexPaths.first!
                                if specialKey == .rightArrow || specialKey == .downArrow {
                                    currentIndexPath = sortedIndexPaths.last!
                                }
                                
                                // 存储当前滚动位置，因为findClosestItem期间会多次滚动
                                // Store current scroll position, as findClosestItem will scroll multiple times
                                let savedContentOffset = scrollView.contentView.bounds.origin
                                
                                var newIndexPath: IndexPath?
                                newIndexPath = findClosestItem(currentIndexPath: currentIndexPath, direction: specialKey)
                                
                                // 还原滚动位置
                                // Restore scroll position
                                scrollView.contentView.setBoundsOrigin(savedContentOffset)
                                scrollView.reflectScrolledClipView(scrollView.contentView)
                                
                                if let newIndexPath = newIndexPath {
                                    if !(isCommandKeyPressed() || isShiftKeyPressed()) {
                                        collectionView.deselectAll(nil)
                                    }
                                    if let toSelect = collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [newIndexPath]) {
                                        collectionView.scrollToItems(at: [newIndexPath], scrollPosition: .nearestHorizontalEdge)
                                        // collectionView.reloadData()
                                        collectionView.selectItems(at: toSelect, scrollPosition: [])
                                        collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: toSelect)
                                        setLoadThumbPriority(ifNeedVisable: true)
                                    }
                                }
                            }
                            
                            // 无选中项
                            // No selected items
                        }else if let collectionView = collectionView {
                            
                            var indexPaths = collectionView.indexPathsForVisibleItems()
                            
                            let visibleRectRaw = mainScrollView.contentView.visibleRect
                            let scrollPos = visibleRectRaw.origin
                            let scrollWidth = visibleRectRaw.width
                            let scrollHeight = visibleRectRaw.height
                            // 注意这里乘了1
                            // Note: multiplied by 1 here
                            let visibleRect = NSRect(origin: scrollPos, size: CGSize(width: scrollWidth, height: scrollHeight*1))
                            indexPaths = indexPaths.filter { indexPath in
                                let itemFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
                                return itemFrame.intersects(visibleRect)
                            }
                            let sortedIndexPaths = indexPaths.sorted { $0.item < $1.item }
                            
                            if let newIndexPath = sortedIndexPaths.first,
                               let toSelect = collectionView.delegate?.collectionView?(collectionView, shouldSelectItemsAt: [newIndexPath]) {
                                collectionView.scrollToItems(at: [newIndexPath], scrollPosition: .nearestHorizontalEdge)
                                // collectionView.reloadData()
                                collectionView.selectItems(at: toSelect, scrollPosition: [])
                                collectionView.delegate?.collectionView?(collectionView, didSelectItemsAt: [newIndexPath])
                                setLoadThumbPriority(ifNeedVisable: true)
                            }
                        }
                        return nil
                    }
                }
            }
            
            // 检查按键是否是 "F" 键
            // Check if key is "F"
            if characters == "f" && noModifierKey && !isFnPressed {
                if publicVar.isInLargeView{
                    largeImageView.actMirrorH()
                }else{
                    toggleSidebar()
                    return nil
                }
            }
            
            // 检查按键是否是 "T" 键
            // Check if key is "T"
            if characters == "t" && noModifierKey {
                toggleOnTop()
                return nil
            }
            
            // 检查按键是否是 -、-(小键盘) 键
            // Check if key is -, -(numpad)
            if characters == "-" && noModifierKey {
                if publicVar.isInLargeView{
                    if largeImageView.file.type == .video {
                        largeImageView.decreaseVolume()
                    }else{
                        largeImageView.zoom(direction: -1)
                    }
                    return nil
                }else{
                    adjustThumbSizeByDirection(direction: -1)
                    return nil
                }
            }
            
            // 检查按键是否是 +(=)、+(小键盘) 键
            // Check if key is +(=), +(numpad)
            if (characters == "=" || characters == "+") && noModifierKey {
                if publicVar.isInLargeView {
                    if largeImageView.file.type == .video {
                        largeImageView.increaseVolume()
                    }else{
                        largeImageView.zoom(direction: +1)
                    }
                    return nil
                }else{
                    adjustThumbSizeByDirection(direction: +1)
                    return nil
                }
            }
            
            // 检查按键是否是 0、0(小键盘) 键
            // Check if key is 0, 0(numpad)
            if characters == "0" && noModifierKey {
                if publicVar.isInLargeView {
                    changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: true)
                    return nil
                }else{
                    adjustThumbSizeByDirection(direction: 0)
                    return nil
                }
            }
            
            // 检查按键是否是 "N" 键
            // Check if key is "N"
            if characters == "n" && noModifierKey {
                // 如果焦点在CollectionView
                // If focus is in CollectionView
                if publicVar.isCollectionViewFirstResponder{
                    handleCopyToDownload()
                    return nil
                }
            }
            
            // 检查按键是否是 "M" 键
            // Check if key is "M"
            if characters == "m" && noModifierKey {
                // 如果焦点在CollectionView
                // If focus is in CollectionView
                if publicVar.isCollectionViewFirstResponder{
                    handleMoveToDownload()
                    return nil
                }
            }
            
            // 检查按键是否是 "B" 键
            // Check if key is "B"
            if characters == "b" && noModifierKey && TAGGING_FEATURE_ENABLED {
                // 如果焦点在CollectionView
                // If focus is in CollectionView
                if publicVar.isCollectionViewFirstResponder{
                    handleTagging()
                    return nil
                }
            }

            // 检查按键是否是 "E" 键
            // Check if key is "E"
            if characters == "e" && isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed {
                if publicVar.isInLargeView{
                    largeImageView.enterEditMode(){ editedImage in
                        // editedImage 是编辑完成后的图片
                        // 你可以在这里保存或处理编辑后的图片
                        self.largeImageView.imageView.image = editedImage
                    }
                    print("Enter edit mode")
                }
                return nil
            }
            
        }
        
        // 处理弹出重命名对话框、OCR状态的复制粘贴操作
        // Handle copy/paste operations for rename dialog popup and OCR state
        if (!publicVar.isKeyEventEnabled || largeImageView.isInOcrState) && isOnlyCommandPressed {
            switch event.charactersIgnoringModifiers {
            case "a":
                if let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: #selector(NSText.selectAll(_:))) {
                    responder.perform(#selector(NSText.selectAll(_:)), with: nil)
                    // 事件已处理，返回 nil 以防止传递给下一个响应者
                    // Event handled, return nil to prevent passing to next responder
                    return nil
                } else {
                    // 处理自定义 Command+A 操作
                    // Handle custom Command+A action
                    log("Custom Command+A action")
                    // 事件已处理，返回 nil 以防止传递给下一个响应者
                    // Event handled, return nil to prevent passing to next responder
                    return nil
                }
            case "c":
                if let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: #selector(NSText.copy(_:))) {
                    responder.perform(#selector(NSText.copy(_:)), with: nil)
                    // 事件已处理，返回 nil 以防止传递给下一个响应者
                    // Event handled, return nil to prevent passing to next responder
                    return nil
                } else {
                    // 处理自定义 Command+C 操作
                    // Handle custom Command+C action
                    log("Custom Command+C action")
                    // 事件已处理，返回 nil 以防止传递给下一个响应者
                    // Event handled, return nil to prevent passing to next responder
                    return nil
                }
            case "v":
                if let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: #selector(NSText.paste(_:))) {
                    responder.perform(#selector(NSText.paste(_:)), with: nil)
                    // 事件已处理，返回 nil 以防止传递给下一个响应者
                    // Event handled, return nil to prevent passing to next responder
                    return nil
                } else {
                    // 处理自定义 Command+V 操作
                    // Handle custom Command+V action
                    log("Custom Command+V action")
                    // 事件已处理，返回 nil 以防止传递给下一个响应者
                    // Event handled, return nil to prevent passing to next responder
                    return nil
                }
            case "x":
                if let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: #selector(NSText.cut(_:))) {
                    responder.perform(#selector(NSText.cut(_:)), with: nil)
                    // 事件已处理，返回 nil 以防止传递给下一个响应者
                    // Event handled, return nil to prevent passing to next responder
                    return nil
                } else {
                    // 处理自定义 Command+X 操作
                    // Handle custom Command+X action
                    log("Custom Command+X action")
                    // 事件已处理，返回 nil 以防止传递给下一个响应者
                    // Event handled, return nil to prevent passing to next responder
                    return nil
                }
            default:
                break
            }
        }
        
        return event
        // return nil
    }
}
