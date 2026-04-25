//
//  KeyShutcut.swift
//  FlowVision
//

import Foundation
import Cocoa

extension ViewController {
    
    private func isConfiguredFolderCopyShortcutTriggered(_ configuredShortcut: String, characters: String, specialKey: NSEvent.SpecialKey, noModifierKey: Bool) -> Bool {
        guard noModifierKey else { return false }
        
        let shortcut = configuredShortcut.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if shortcut.isEmpty { return false }
        
        switch shortcut {
        case "F1": return specialKey == .f1
        case "F2": return specialKey == .f2
        case "F3": return specialKey == .f3
        case "F4": return specialKey == .f4
        case "F5": return specialKey == .f5
        case "F6": return specialKey == .f6
        case "F7": return specialKey == .f7
        case "F8": return specialKey == .f8
        case "F9": return specialKey == .f9
        case "F10": return specialKey == .f10
        case "F11": return specialKey == .f11
        case "F12": return specialKey == .f12
        default:
            return characters.uppercased() == shortcut
        }
    }

    private func isPhotoFolder1CopyShortcutTriggered(characters: String, specialKey: NSEvent.SpecialKey, noModifierKey: Bool) -> Bool {
        isConfiguredFolderCopyShortcutTriggered(globalVar.photoFolder1CopyShortcut, characters: characters, specialKey: specialKey, noModifierKey: noModifierKey)
    }

    private func isPhotoFolder2CopyShortcutTriggered(characters: String, specialKey: NSEvent.SpecialKey, noModifierKey: Bool) -> Bool {
        isConfiguredFolderCopyShortcutTriggered(globalVar.photoFolder2CopyShortcut, characters: characters, specialKey: specialKey, noModifierKey: noModifierKey)
    }
    
    @discardableResult
    private func enterSelectedFolderFromKeyboard() -> Bool {
        guard let selectedURL = publicVar.selectedUrls().first else { return false }
        
        var targetFolderURL: URL? = nil
        if selectedURL.hasDirectoryPath {
            targetFolderURL = selectedURL
        } else if let values = try? selectedURL.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]),
                  values.isAliasFile == true,
                  let resolved = try? URL(resolvingAliasFileAt: selectedURL),
                  resolved.hasDirectoryPath {
            targetFolderURL = resolved
        }
        
        guard let folderURL = targetFolderURL else { return false }
        switchDirByDirection(direction: .zero, dest: folderURL.absoluteString, stackDeep: 0)
        return true
    }
    
    @discardableResult
    private func openSelectedItemFromKeyboard() -> Bool {
        guard !publicVar.isInLargeView,
              publicVar.isCollectionViewFirstResponder,
              let indexPath = collectionView.selectionIndexPaths.min() else {
            return false
        }
        
        openLargeImage(indexPath)
        return true
    }
    
    @discardableResult
    private func triggerRightClickContextMenuFromKeyboard() -> Bool {
        guard let window = view.window else { return false }
        
        let targetView: NSView
        if let selectedIndexPath = collectionView.selectionIndexPaths.first,
           let item = collectionView.item(at: selectedIndexPath) as? CustomCollectionViewItem {
            targetView = item.view
        } else {
            targetView = collectionView
        }
        
        let localCenter = NSPoint(x: targetView.bounds.midX, y: targetView.bounds.midY)
        let windowPoint = targetView.convert(localCenter, to: nil)
        let timestamp = ProcessInfo.processInfo.systemUptime
        
        guard let downEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        ),
              let upEvent = NSEvent.mouseEvent(
                with: .rightMouseUp,
                location: windowPoint,
                modifierFlags: [],
                timestamp: timestamp + 0.01,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 0.0
              ) else {
            return false
        }
        
        targetView.rightMouseDown(with: downEvent)
        targetView.rightMouseUp(with: upEvent)
        return true
    }
    
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

        if publicVar.isInLargeView && largeImageView.isInVideoCropSelectionMode {
            if event.keyCode == 53 {
                largeImageView.cancelVideoCropSelection()
                return nil
            }
            return event
        }

        // 把按键信息打印出来，用于调试不同键盘的键值差异
        // var modifierStrings: [String] = []
        // if isCommandPressed { modifierStrings.append("Command") }
        // if isAltPressed { modifierStrings.append("Option") }
        // if isCtrlPressed { modifierStrings.append("Control") }
        // if isShiftPressed { modifierStrings.append("Shift") }
        // if isFnPressed { modifierStrings.append("Fn") }
        // let modifierDescription = modifierStrings.isEmpty ? "None" : modifierStrings.joined(separator: "+")
        // log("Key Event Debug - characters: \(characters), keyCode: \(event.keyCode), specialKey: \(specialKey), modifierFlags: \(modifierFlags.rawValue), Modifiers: \(modifierDescription)", level: .debug)
        
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

        // 主界面撤销 / 重做
        // Undo / redo in normal browsing state
        if publicVar.isKeyEventEnabled && isCommandPressed && !isAltPressed && !isCtrlPressed {
            if characters == "z" && !isShiftPressed {
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                return nil
            }
            if characters == "z" && isShiftPressed {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                return nil
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
            // 自定义快捷键：复制到图片文件夹1
            // Custom shortcut: copy to Photo Folder 1
            if publicVar.isCollectionViewFirstResponder &&
               isPhotoFolder1CopyShortcutTriggered(characters: characters, specialKey: specialKey, noModifierKey: noModifierKey) {
                handleCopyToPhotoFolder1()
                return nil
            }

            // 自定义快捷键：复制视频到文件夹2
            // Custom shortcut: copy video to Folder 2
            if isPhotoFolder2CopyShortcutTriggered(characters: characters, specialKey: specialKey, noModifierKey: noModifierKey) {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    handleCopyCurrentVideoToPhotoFolder2()
                    return nil
                }
                if publicVar.isCollectionViewFirstResponder {
                    handleCopySelectedVideosToPhotoFolder2()
                    return nil
                }
            }
            
            // 检查按键是否是 "A" 键
            // Check if key is "A"
            // RTL: A/D swap large image and folder direction
            let isRTL_AD = view.userInterfaceLayoutDirection == .rightToLeft
            if characters == "a" && noModifierKey {
                if publicVar.isInLargeView{
                    isRTL_AD ? nextLargeImage() : previousLargeImage()
                }else{
                    closeLargeImage(0)
                    switchDirByDirection(direction: isRTL_AD ? .right : .left, stackDeep: 0)
                }
                return nil
            }
            // 检查按键是否是 "D" 键
            // Check if key is "D"
            if characters == "d" && noModifierKey {
                if publicVar.isInLargeView{
                    isRTL_AD ? previousLargeImage() : nextLargeImage()
                }else{
                    closeLargeImage(0)
                    switchDirByDirection(direction: isRTL_AD ? .left : .right, stackDeep: 0)
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
                    handleRename(urls: publicVar.selectedUrls())
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

            // 检查按键是否是 "J" 键
            // Check if key is "J"
            if characters == "j" && noModifierKey {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    largeImageView.actRememberPlayPosition()
                }
                return nil
            }
            
            // 检查按键是否是 "K" 键
            // Check if key is "K"
            if characters == "k" && noModifierKey {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    largeImageView.actABPlay()
                }
                return nil
            }

            // 检查按键是否是 "L" 键
            // Check if key is "L"
            if characters == "l" && noModifierKey {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    largeImageView.actSequentialPlay()
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
                if publicVar.isInLargeView{
                    previousLargeImage()
                } else {
                    switchDirByDirection(direction: .back, stackDeep: 0)
                }
                return nil
            }
            
            // 检查按键是否是 Command+] 键
            // Check if key is Command+]
            if characters == "]" && isOnlyCommandPressed {
                if publicVar.isInLargeView{
                    nextLargeImage()
                } else {
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

            // 检查按键是否是 Command+Shift+"E" 键
            // Check if key is Command+Shift+"E"
            if characters == "e" && isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed && EDIT_FEATURE_ENABLED {
                if publicVar.isInLargeView{
                    largeImageView.enterEditMode(){ editedImage in
                        // editedImage 是编辑完成后的图片
                        self.largeImageView.imageView.image = editedImage
                    }
                }
                return nil
            }

            // 检查按键是否是 Command+"E" 键（视频截图到当前文件夹）
            // Check if key is Command+"E" (capture current video frame to current folder)
            if characters == "e" && isOnlyCommandPressed {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    handleCaptureCurrentVideoFrameToCurrentFolder()
                    return nil
                }
            }
            
            // 检查按键是否是 Command+⬅️➡️ 键
            // Check if key is Command+⬅️➡️
            // RTL: swap frame seek direction
            if (specialKey == .leftArrow || specialKey == .rightArrow) && isOnlyCommandPressed {
                if publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    let isRTL_Cmd = view.userInterfaceLayoutDirection == .rightToLeft
                    if specialKey == .leftArrow {
                        largeImageView.seekVideoByFrame(direction: isRTL_Cmd ? 1 : -1)
                    }else{
                        largeImageView.seekVideoByFrame(direction: isRTL_Cmd ? -1 : 1)
                    }
                    return nil
                } else if !publicVar.isInLargeView,
                          specialKey == .rightArrow {
                    // Keyboard equivalent of mouse right click context menu.
                    if triggerRightClickContextMenuFromKeyboard() {
                        return nil
                    }
                }
            }

            // 检查按键是否是 Shift+⬅️➡️ 键（视频切换上/下文件）
            // Check if key is Shift+⬅️➡️ (video switch previous/next file)
            if (specialKey == .leftArrow || specialKey == .rightArrow) && isOnlyShiftPressed {
                if globalVar.videoShiftArrowSwitchFile,
                   publicVar.isInLargeView,
                   largeImageView.file.type == .video {
                    if specialKey == .leftArrow {
                        previousLargeImage()
                    } else {
                        nextLargeImage()
                    }
                    return nil
                }
            }
            
            // 检查按键是否是 Command+⬆️ 键（查看时退出查看，缩略图时返回上一级目录）
            // Check if key is Command+⬆️ (exit large view, or go to parent folder)
            if specialKey == .upArrow && isOnlyCommandPressed {
                if publicVar.isInLargeView {
                    closeLargeImage(0)
                } else {
                    switchDirByDirection(direction: .up, stackDeep: 0)
                }
                return nil
            }
            
            // 检查按键是否是 Home 键（滚动到顶部）
            // Check if key is Home key (scroll to top)
            if specialKey == .home && noModifierKey {
                if publicVar.isInLargeView {
                    locateLargeImage(direction: -2)
                } else {
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
            
            // 检查按键是否是 Command+⬇️ 键（打开选中文件/进入选中文件夹）
            // Check if key is Command+⬇️ (open selected item, or enter selected folder)
            if specialKey == .downArrow && isOnlyCommandPressed {
                if publicVar.isInLargeView {
                    return nil
                } else {
                    if enterSelectedFolderFromKeyboard() {
                        return nil
                    }
                    if openSelectedItemFromKeyboard() {
                        return nil
                    }
                    // Fallback: keep original behavior when selection is not a folder.
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
            
            // 检查按键是否是 End 键
            // Check if key is End key
            if specialKey == .end && noModifierKey {
                if publicVar.isInLargeView {
                    locateLargeImage(direction: 2)
                } else if let scrollView = collectionView.enclosingScrollView {
                    let newOrigin = NSPoint(x: 0, y: collectionView.bounds.height - scrollView.contentSize.height)
                    scrollView.contentView.scroll(to: newOrigin)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    DispatchQueue.main.async { [weak self] in
                        self?.setLoadThumbPriority(ifNeedVisable: true)
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
                        handleRename(urls: publicVar.selectedUrls())
                        return nil
                    }
                }else{
                    if publicVar.isInLargeView{
                        closeLargeImage(0)
                        return nil
                    }else{
                        if let indexPath = collectionView.selectionIndexPaths.min() {
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
                    if let indexPath = collectionView.selectionIndexPaths.min() {
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

            // 检查按键是否是 Command+1~9 键
            // Check if key is Command+1~9
            if ["1","2","3","4","5","6","7","8","9"].contains(characters) && isOnlyCommandPressed {
                if publicVar.isCollectionViewFirstResponder {
                    let index = Int(characters)! - 1
                    handleToggleFinderTag(FinderTag.all[index].name)
                    return nil
                }
            }

            // 检查按键是否是 Command+Shift+1~9 键
            // Check if key is Command+Shift+1~9
            // if ["1","2","3","4","5","6","7","8","9"].contains(characters) && isCommandPressed && isShiftPressed && !isAltPressed && !isCtrlPressed {
            //     if publicVar.isCollectionViewFirstResponder {
            //         let index = Int(characters)! - 1
            //         toggleFinderTagFilter(index)
            //         return nil
            //     }
            // }

            // 检查按键是否是 Control+1~5 键
            // Check if key is Command+1~5
            if ["1","2","3","4","5","0"].contains(characters) && isOnlyCtrlPressed {
                if publicVar.isCollectionViewFirstResponder {
                    let index = Int(characters)!
                    handleRating(rating: index)
                    return nil
                }
            }

            // 检查按键是否是 Control+Shift+1~5 键
            // Check if key is Control+Shift+1~5
            // if ["1","2","3","4","5","0"].contains(characters) && isCtrlPressed && isShiftPressed && !isAltPressed && !isCommandPressed {
            //     if publicVar.isCollectionViewFirstResponder {
            //         let index = Int(characters)!
            //         toggleRatingFilter(index)
            //         return nil
            //     }
            // }
            
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
            let isRTL = view.userInterfaceLayoutDirection == .rightToLeft
            if (specialKey == .rightArrow || specialKey == .downArrow || specialKey == .pageDown || specialKey == .next) && noModifierKey {
                if publicVar.isInLargeView{
                    if largeImageView.file.type == .video && specialKey == .rightArrow {
                        // RTL: right arrow = backward
                        largeImageView.seekVideo(direction: isRTL ? -1 : 1)
                    } else if specialKey == .rightArrow && isRTL {
                        previousLargeImage()
                    } else {
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
                        // RTL: left arrow = forward
                        largeImageView.seekVideo(direction: isRTL ? 1 : -1)
                    } else if specialKey == .leftArrow && isRTL {
                        nextLargeImage()
                    } else {
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
            
        }
        
        // 处理弹出重命名对话框、OCR状态的 Home/End 光标移动操作
        // Handle Home/End cursor movement for rename dialog popup and OCR state
        if !publicVar.isKeyEventEnabled || largeImageView.isInOcrState {
            if specialKey == .home {
                NSApp.keyWindow?.firstResponder?.moveToBeginningOfDocument(nil)
                return nil
            }
            if specialKey == .end {
                NSApp.keyWindow?.firstResponder?.moveToEndOfDocument(nil)
                return nil
            }
        }

        // 处理弹出重命名对话框、OCR状态的复制粘贴、撤销操作
        // Handle copy/paste and undo operations for rename dialog popup and OCR state
        if (!publicVar.isKeyEventEnabled || largeImageView.isInOcrState) && isOnlyCommandPressed {
            switch event.charactersIgnoringModifiers {
            case "a":
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                return nil
            case "c":
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                return nil
            case "v":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                return nil
            case "x":
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                return nil
            case "z":
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                return nil
            default:
                break
            }
        }
        
        return event
        // return nil
    }
}
