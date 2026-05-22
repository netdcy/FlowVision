//
//  KeyShortcut.swift
//  FlowVision
//
//  Dispatcher: receives NSEvent keyDowns, matches against ShortcutStore.reverseIndex,
//  fires the appropriate action handler. Non-rebindable text-input branches
//  (quick-search, OCR/rename text ops) are handled before lookup.
//

import Foundation
import Cocoa

extension ViewController {

    func KeyShortcutManager(event: NSEvent) -> NSEvent? {
        // Window-active gate (preserved).
        if event.window != self.view.window && publicVar.isKeyEventEnabled {
            return event
        }

        // Non-rebindable text-input branches run first and short-circuit.
        if handleNonRebindable(event) { return nil }

        // OCR / rename text-system fallthrough (Home/End cursor + Cmd+ACVXZ).
        // Preserves prior behavior at lines 953-988 of legacy KeyShortcut.swift.
        if handleTextSystemFallthrough(event) { return nil }

        // 0.1s debounce — held-down keys still rate-limited.
        if !publicVar.timer.intervalSafe(name: "keyEvent", second: 0.1) {
            return event
        }

        // Non-rebindable browser navigation: outline-row arrows, collection-grid
        // findClosestItem arrows, Tab focus swap, F2/Enter rename, Enter-to-open.
        // These pre-empt chord dispatch because they're context-dynamic (selection
        // geometry, first-responder identity, isEnterKeyToOpen setting) rather
        // than fixed bindings.
        if handleNonRebindableNavigation(event) { return nil }

        let chord = KeyChord(event: event)
        let candidates = ShortcutStore.shared.reverseIndex[chord] ?? []

        for action in candidates where stateGateOpen(for: action) && scopeMatches(action.scope) {
            if dispatch(action) { return nil }
        }
        return event
    }

    // MARK: - Helpers

    private func stateGateOpen(for action: ShortcutAction) -> Bool {
        action.firesDuringSearch
            ? (publicVar.isInSearchState || publicVar.isKeyEventEnabled)
            : publicVar.isKeyEventEnabled
    }

    private func scopeMatches(_ s: ContextScope) -> Bool {
        switch s {
        case .browserOnly: return !publicVar.isInLargeView
        case .viewerOnly:  return  publicVar.isInLargeView
        case .both:        return true
        }
    }

    private var isInFullScreen: Bool {
        view.window?.styleMask.contains(.fullScreen) == true
    }

    /// Returns true if the event was consumed by a non-rebindable text-input branch.
    /// Mirrors quick-search input from the legacy dispatcher head.
    func handleNonRebindable(_ event: NSEvent) -> Bool {
        let modifierFlags = event.modifierFlags
        let isCommandPressed = modifierFlags.contains(.command)
        let isAltPressed     = modifierFlags.contains(.option)
        let isCtrlPressed    = modifierFlags.contains(.control)
        let isShiftPressed   = modifierFlags.contains(.shift)
        let noModifierKey    = !isCommandPressed && !isAltPressed && !isCtrlPressed && !isShiftPressed
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()
        let specialKey = event.specialKey ?? .f30

        // Quick-search letter/digit text input
        if publicVar.isKeyEventEnabled && characters.count == 1
            && (characters.first!.isLetter || characters.first!.isNumber) && noModifierKey
            && !publicVar.isInLargeView
            && (quickSearchState || globalVar.useQuickSearch) {
            quickSearch(characters)
            return true
        }

        // Quick-search backspace
        if publicVar.isKeyEventEnabled && specialKey == .delete && noModifierKey
            && !publicVar.isInLargeView {
            if quickSearchState { quickSearch("backspace"); return true }
            if globalVar.useQuickSearch { return true }
        }

        // Quick-search Esc
        if publicVar.isKeyEventEnabled && event.keyCode == KeyChord.escKeyCode
            && !publicVar.isInLargeView && quickSearchState {
            quickSearchText = ""
            quickSearchState = false
            coreAreaView.hideInfo(force: true)
            return true
        }
        return false
    }

    /// Non-rebindable browser navigation. Returns true if consumed.
    /// Mirrors legacy KeyShortcut.swift behavior at lines 499-529, 733-743, and
    /// 745-865: F2/Enter rename, Tab focus swap, outline arrows + space/enter
    /// expand-toggle, collection-view findClosestItem arrows.
    private func handleNonRebindableNavigation(_ event: NSEvent) -> Bool {
        // Suppress navigation while a modal text field (rename, OCR) owns the
        // key window — legacy kept the entire block inside `isKeyEventEnabled`.
        guard publicVar.isKeyEventEnabled else { return false }

        let modifierFlags = event.modifierFlags
        let isCommandPressed = modifierFlags.contains(.command)
        let isAltPressed     = modifierFlags.contains(.option)
        let isCtrlPressed    = modifierFlags.contains(.control)
        let isShiftPressed   = modifierFlags.contains(.shift)
        let noModifierKey    = !isCommandPressed && !isAltPressed && !isCtrlPressed && !isShiftPressed
        let isOnlyShiftPressed = !isCommandPressed && !isAltPressed && !isCtrlPressed && isShiftPressed
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()
        let specialKey = event.specialKey ?? .f30

        // F2 / Enter: rename when F2 OR (Enter && !isEnterKeyToOpen);
        // otherwise (Enter && isEnterKeyToOpen) → close viewer / open large.
        if (specialKey == .f2 || specialKey == .carriageReturn || specialKey == .enter)
            && noModifierKey {
            if specialKey == .f2 || !globalVar.isEnterKeyToOpen {
                if publicVar.isOutlineViewFirstResponder {
                    outlineView.actRename(isByKeyboard: true)
                    return true
                }
                if publicVar.isCollectionViewFirstResponder {
                    _ = handleRename(urls: publicVar.selectedUrls())
                    return true
                }
            } else {
                if publicVar.isInLargeView {
                    closeLargeImage(0)
                    return true
                }
                if let indexPath = collectionView.selectionIndexPaths.min(),
                   publicVar.isCollectionViewFirstResponder {
                    openLargeImage(indexPath)
                    return true
                }
            }
        }

        // Tab: swap focus between outline and collection view (browser only).
        if specialKey == .tab && noModifierKey && !publicVar.isInLargeView {
            if publicVar.isOutlineViewFirstResponder {
                view.window?.makeFirstResponder(collectionView)
                return true
            }
            if publicVar.isCollectionViewFirstResponder {
                view.window?.makeFirstResponder(outlineView)
                return true
            }
        }

        // Arrow keys + space + enter-to-open in browser views.
        let isArrow = specialKey == .leftArrow || specialKey == .rightArrow
            || specialKey == .upArrow || specialKey == .downArrow
        let isSpace = characters == " "
        let isEnterToOpen = (specialKey == .carriageReturn || specialKey == .enter)
            && globalVar.isEnterKeyToOpen
        guard (isArrow || isSpace || isEnterToOpen)
              && (noModifierKey || isOnlyShiftPressed)
              && !publicVar.isInLargeView else {
            return false
        }

        // Outline branch: arrows navigate rows, ← → / space / enter toggle expand.
        if publicVar.isOutlineViewFirstResponder, let outlineView {
            let selectedRow = outlineView.selectedRow
            if specialKey == .upArrow {
                if selectedRow > 0 {
                    let previousRow = selectedRow - 1
                    outlineView.selectRowIndexes(IndexSet(integer: previousRow),
                                                  byExtendingSelection: false)
                    outlineView.scrollRowToVisible(previousRow)
                }
            } else if specialKey == .downArrow {
                if selectedRow != -1 && selectedRow < outlineView.numberOfRows - 1 {
                    let nextRow = selectedRow + 1
                    outlineView.selectRowIndexes(IndexSet(integer: nextRow),
                                                  byExtendingSelection: false)
                    outlineView.scrollRowToVisible(nextRow)
                }
            } else if let item = outlineView.item(atRow: selectedRow),
                      outlineView.isExpandable(item) {
                if outlineView.isItemExpanded(item) {
                    outlineView.collapseItem(item)
                } else {
                    outlineView.expandItem(item)
                }
            }
            return true
        }

        // Collection branch: only arrows. Space / Enter fall through to chord
        // dispatch so the user-rebindable `viewerOpenFromSelection` action wins.
        guard publicVar.isCollectionViewFirstResponder && isArrow,
              let collectionView,
              let scrollView = collectionView.enclosingScrollView else {
            return false
        }

        if !collectionView.selectionIndexPaths.isEmpty {
            let sortedIndexPaths = collectionView.selectionIndexPaths.sorted()
            var currentIndexPath = sortedIndexPaths.first!
            if specialKey == .rightArrow || specialKey == .downArrow {
                currentIndexPath = sortedIndexPaths.last!
            }
            // findClosestItem scrolls multiple times internally; snapshot and
            // restore the scroll position so the user doesn't see a jitter.
            let savedContentOffset = scrollView.contentView.bounds.origin
            let newIndexPath = findClosestItem(currentIndexPath: currentIndexPath,
                                                direction: specialKey)
            scrollView.contentView.setBoundsOrigin(savedContentOffset)
            scrollView.reflectScrolledClipView(scrollView.contentView)

            if let newIndexPath {
                if !(isCommandKeyPressed() || isShiftKeyPressed()) {
                    collectionView.deselectAll(nil)
                }
                if let toSelect = collectionView.delegate?.collectionView?(collectionView,
                                                                            shouldSelectItemsAt: [newIndexPath]) {
                    collectionView.scrollToItems(at: [newIndexPath],
                                                  scrollPosition: .nearestHorizontalEdge)
                    collectionView.selectItems(at: toSelect, scrollPosition: [])
                    collectionView.delegate?.collectionView?(collectionView,
                                                              didSelectItemsAt: toSelect)
                    setLoadThumbPriority(ifNeedVisable: true)
                }
            }
            return true
        }

        // No selection: pick first visible item as anchor.
        let visibleRect = mainScrollView.contentView.visibleRect
        let visiblePaths = collectionView.indexPathsForVisibleItems().filter { ip in
            (collectionView.layoutAttributesForItem(at: ip)?.frame ?? .zero).intersects(visibleRect)
        }
        if let newIndexPath = visiblePaths.sorted(by: { $0.item < $1.item }).first,
           let toSelect = collectionView.delegate?.collectionView?(collectionView,
                                                                    shouldSelectItemsAt: [newIndexPath]) {
            collectionView.scrollToItems(at: [newIndexPath],
                                          scrollPosition: .nearestHorizontalEdge)
            collectionView.selectItems(at: toSelect, scrollPosition: [])
            collectionView.delegate?.collectionView?(collectionView,
                                                      didSelectItemsAt: [newIndexPath])
            setLoadThumbPriority(ifNeedVisable: true)
        }
        return true
    }

    /// Text-system fallthrough for rename dialog / OCR state. Returns true if consumed.
    private func handleTextSystemFallthrough(_ event: NSEvent) -> Bool {
        let isOnlyCommandPressed = event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.control)
            && !event.modifierFlags.contains(.shift)
        let specialKey = event.specialKey ?? .f30

        if !publicVar.isKeyEventEnabled || largeImageView.isInOcrState {
            if specialKey == .home {
                NSApp.keyWindow?.firstResponder?.moveToBeginningOfDocument(nil)
                return true
            }
            if specialKey == .end {
                NSApp.keyWindow?.firstResponder?.moveToEndOfDocument(nil)
                return true
            }
        }

        if (!publicVar.isKeyEventEnabled || largeImageView.isInOcrState) && isOnlyCommandPressed {
            // Lowercased so Caps Lock doesn't break Cmd+ACVXZ.
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a":
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                return true
            case "c":
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                return true
            case "v":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                return true
            case "x":
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                return true
            case "z":
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                return true
            default:
                break
            }
        }
        return false
    }

    // MARK: - Dispatch table

    /// One case per ShortcutAction. Returns true on handled, false when the bound chord
    /// fired but the contextual gate (e.g. CollectionView focus) didn't open — caller
    /// continues to next candidate or lets event propagate.
    func dispatch(_ action: ShortcutAction) -> Bool {
        let isRTL = view.userInterfaceLayoutDirection == .rightToLeft

        switch action {

        // MARK: Browser nav
        //
        // scope=browserOnly already gates these cases on !isInLargeView, so the
        // defensive closeLargeImage(0) calls present in the legacy dispatcher
        // are redundant here.
        case .browserDirLeft:
            switchDirByDirection(direction: isRTL ? .right : .left, stackDeep: 0)
            return true
        case .browserDirRight:
            switchDirByDirection(direction: isRTL ? .left : .right, stackDeep: 0)
            return true
        case .browserDirUp:
            switchDirByDirection(direction: .up, stackDeep: 0)
            return true
        case .browserDirDown:
            switchDirByDirection(direction: .down, stackDeep: 0)
            return true
        case .browserDirDownRight:
            switchDirByDirection(direction: .down_right, stackDeep: 0)
            return true
        case .browserBack:
            switchDirByDirection(direction: .back, stackDeep: 0)
            return true
        case .browserForward:
            switchDirByDirection(direction: .forward, stackDeep: 0)
            return true
        case .browserScrollTop:
            if let scrollView = collectionView.enclosingScrollView {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                DispatchQueue.main.async { [weak self] in
                    self?.setLoadThumbPriority(ifNeedVisable: true)
                }
            }
            return true
        case .browserScrollBottom:
            if let scrollView = collectionView.enclosingScrollView {
                let newOrigin = NSPoint(x: 0,
                                         y: collectionView.bounds.height - scrollView.contentSize.height)
                scrollView.contentView.scroll(to: newOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                DispatchQueue.main.async { [weak self] in
                    self?.setLoadThumbPriority(ifNeedVisable: true)
                }
            }
            return true
        case .browserPageUp:
            if let scrollView = collectionView.enclosingScrollView {
                let currentOrigin = scrollView.contentView.bounds.origin
                let pageHeight = scrollView.contentSize.height
                let newY = max(currentOrigin.y - pageHeight, 0)
                scrollView.contentView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                DispatchQueue.main.async { [weak self] in
                    self?.setLoadThumbPriority(ifNeedVisable: true)
                }
            }
            return true
        case .browserPageDown:
            if let scrollView = collectionView.enclosingScrollView {
                let currentOrigin = scrollView.contentView.bounds.origin
                let pageHeight = scrollView.contentSize.height
                let newY = min(currentOrigin.y + pageHeight,
                                collectionView.bounds.height - pageHeight)
                scrollView.contentView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                DispatchQueue.main.async { [weak self] in
                    self?.setLoadThumbPriority(ifNeedVisable: true)
                }
            }
            return true
        case .browserDeselect:
            if publicVar.isCollectionViewFirstResponder {
                collectionView.deselectAll(nil)
            }
            return true
        case .browserToggleSidebar:
            NSApp.sendAction(#selector(AppDelegate.toggleSidebar(_:)), to: nil, from: nil)
            return true

        // MARK: Viewer nav
        case .viewerPrev:
            isRTL ? nextLargeImage() : previousLargeImage()
            return true
        case .viewerNext:
            isRTL ? previousLargeImage() : nextLargeImage()
            return true
        case .viewerLocateFirst:
            locateLargeImage(direction: -2)
            return true
        case .viewerLocateLast:
            locateLargeImage(direction: 2)
            return true
        case .viewerClose:
            closeLargeImage(0)
            return true
        case .viewerOpenFromSelection:
            guard let indexPath = collectionView.selectionIndexPaths.min(),
                  publicVar.isCollectionViewFirstResponder else { return false }
            openLargeImage(indexPath)
            return true

        // MARK: Viewer ops
        case .viewerZoomIn:
            if largeImageView.file.type == .video {
                largeImageView.increaseVolume()
            } else {
                largeImageView.zoom(direction: +1)
            }
            return true
        case .viewerZoomOut:
            if largeImageView.file.type == .video {
                largeImageView.decreaseVolume()
            } else {
                largeImageView.zoom(direction: -1)
            }
            return true
        case .viewerZoom100:
            largeImageView.zoom100()
            return true
        case .viewerZoomFit:
            largeImageView.zoomFit()
            return true
        case .viewerZoomReset:
            changeLargeImage(firstShowThumb: false, resetSize: true, triggeredByLongPress: true)
            return true
        case .viewerRotateLeft:
            largeImageView.actRotateL()
            return true
        case .viewerRotateRight:
            largeImageView.actRotateR()
            return true
        case .viewerMirrorH:
            largeImageView.actMirrorH()
            return true
        case .viewerOCR:
            largeImageView.actOCR()
            return true
        case .viewerQRCode:
            largeImageView.actQRCode()
            return true
        case .viewerGetInfo:
            handleGetInfo()
            return true
        case .viewerShowExif:
            largeImageView.actShowExif()
            return true
        case .viewerEditMode:
            guard EDIT_FEATURE_ENABLED else { return false }
            largeImageView.enterEditMode { [weak self] editedImage in
                self?.largeImageView.imageView.image = editedImage
            }
            return true

        // MARK: Video
        case .videoPauseResume:
            if largeImageView.file.type == .video {
                largeImageView.pauseOrResumeVideo()
            } else {
                closeLargeImage(0)
            }
            return true
        case .videoSeekFwd:
            // Folded: video → seek; image → next image. Mirrors legacy ← / →
            // behavior so a default ←/→ chord works as "prev / next" on images.
            if largeImageView.file.type == .video {
                largeImageView.seekVideo(direction: isRTL ? -1 : 1)
            } else {
                isRTL ? previousLargeImage() : nextLargeImage()
            }
            return true
        case .videoSeekBack:
            if largeImageView.file.type == .video {
                largeImageView.seekVideo(direction: isRTL ? 1 : -1)
            } else {
                isRTL ? nextLargeImage() : previousLargeImage()
            }
            return true
        case .videoSeekFrameFwd:
            guard largeImageView.file.type == .video else { return false }
            largeImageView.seekVideoByFrame(direction: isRTL ? -1 : 1)
            return true
        case .videoSeekFrameBack:
            guard largeImageView.file.type == .video else { return false }
            largeImageView.seekVideoByFrame(direction: isRTL ? 1 : -1)
            return true
        case .videoSetA:
            guard largeImageView.file.type == .video else { return false }
            largeImageView.specifyABPlayPositionA()
            return true
        case .videoSetB:
            guard largeImageView.file.type == .video else { return false }
            largeImageView.specifyABPlayPositionB()
            return true
        case .videoABPlay:
            guard largeImageView.file.type == .video else { return false }
            largeImageView.actABPlay()
            return true
        case .videoSequentialPlay:
            guard largeImageView.file.type == .video else { return false }
            largeImageView.actSequentialPlay()
            return true
        case .videoRememberPosition:
            guard largeImageView.file.type == .video else { return false }
            largeImageView.actRememberPlayPosition()
            return true

        // MARK: Window
        case .windowMaximize:
            guard !isInFullScreen else { return false }
            adjustWindowMaximize()
            return true
        case .windowSuitable:
            guard !isInFullScreen else { return false }
            adjustWindowSuitable()
            return true
        case .windowImageActual:
            guard !isInFullScreen else { return false }
            adjustWindowImageActual()
            return true
        case .windowImageCurrent:
            guard !isInFullScreen else { return false }
            adjustWindowImageCurrent()
            return true
        case .windowCenter:
            guard !isInFullScreen else { return false }
            adjustWindowToCenter()
            return true
        case .windowToggleFullscreen:
            view.window?.toggleFullScreen(nil)
            return true
        case .windowToggleOnTop:
            NSApp.sendAction(#selector(AppDelegate.toggleOnTop(_:)), to: nil, from: nil)
            return true
        case .windowRefresh:
            handleUserRefresh()
            return true
        case .windowNew:
            NSApp.sendAction(#selector(AppDelegate.fileNewWindow(_:)), to: nil, from: nil)
            return true
        case .windowNewTab:
            NSApp.sendAction(#selector(AppDelegate.fileNewTab(_:)), to: nil, from: nil)
            return true
        case .windowClose, .windowCloseTab:
            view.window?.performClose(nil)
            return true
        case .windowReopenClosedTab:
            handleReopenClosedTabs()
            return true
        case .quitApp:
            NSApp.terminate(nil)
            return true

        // MARK: File ops
        case .fileRename:
            if publicVar.isOutlineViewFirstResponder {
                outlineView.actRename(isByKeyboard: true)
                return true
            }
            if publicVar.isCollectionViewFirstResponder {
                handleRename(urls: publicVar.selectedUrls())
                return true
            }
            return false
        case .fileDelete:
            if publicVar.isOutlineViewFirstResponder {
                outlineView.actDelete(isByKeyboard: true, isShowPrompt: true)
                return true
            }
            if publicVar.isCollectionViewFirstResponder {
                _ = handleDelete(isShowPrompt: true)
                return true
            }
            return false
        case .fileDeleteNoPrompt:
            if publicVar.isOutlineViewFirstResponder {
                outlineView.actDelete(isByKeyboard: true, isShowPrompt: false)
                return true
            }
            if publicVar.isCollectionViewFirstResponder {
                _ = handleDelete(isShowPrompt: false)
                return true
            }
            return false
        case .fileNewFolder:
            _ = handleNewFolder()
            return true
        case .fileCopyToDownload:
            guard publicVar.isCollectionViewFirstResponder else { return false }
            handleCopyToDownload()
            return true
        case .fileMoveToDownload:
            guard publicVar.isCollectionViewFirstResponder else { return false }
            handleMoveToDownload()
            return true
        case .fileGetInfo:
            if publicVar.isOutlineViewFirstResponder {
                outlineView.actGetInfo(isByKeyboard: true)
                return true
            }
            if publicVar.isCollectionViewFirstResponder {
                handleGetInfo()
                return true
            }
            return false

        // MARK: Thumb size
        case .thumbSizeUp:
            adjustThumbSizeByDirection(direction: +1)
            return true
        case .thumbSizeDown:
            adjustThumbSizeByDirection(direction: -1)
            return true
        case .thumbSizeReset:
            adjustThumbSizeByDirection(direction: 0)
            return true

        // MARK: View mode
        case .viewModeJustified:
            NSApp.sendAction(#selector(AppDelegate.switchToJustifiedView(_:)), to: nil, from: nil)
            return true
        case .viewModeWaterfall:
            NSApp.sendAction(#selector(AppDelegate.switchToWaterfallView(_:)), to: nil, from: nil)
            return true
        case .viewModeGrid:
            NSApp.sendAction(#selector(AppDelegate.switchToGridView(_:)), to: nil, from: nil)
            return true
        case .viewModeDetail:
            NSApp.sendAction(#selector(AppDelegate.switchToDetailView(_:)), to: nil, from: nil)
            return true

        // MARK: Visibility toggles
        case .toggleHiddenFiles:
            NSApp.sendAction(#selector(AppDelegate.toggleIsShowHiddenFile(_:)), to: nil, from: nil)
            return true
        case .toggleImageFiles:
            NSApp.sendAction(#selector(AppDelegate.toggleIsShowImageFile(_:)), to: nil, from: nil)
            return true
        case .toggleRawFiles:
            NSApp.sendAction(#selector(AppDelegate.toggleIsShowRawFile(_:)), to: nil, from: nil)
            return true
        case .toggleVideoFiles:
            NSApp.sendAction(#selector(AppDelegate.toggleIsShowVideoFile(_:)), to: nil, from: nil)
            return true
        case .toggleAllFiles:
            NSApp.sendAction(#selector(AppDelegate.toggleIsShowAllTypeFile(_:)), to: nil, from: nil)
            return true
        case .toggleShowFinderTagsAndRating:
            NSApp.sendAction(#selector(AppDelegate.toggleShowFinderTagsAndRating(_:)), to: nil, from: nil)
            return true
        case .toggleRawUseEmbeddedThumb:
            NSApp.sendAction(#selector(AppDelegate.toggleRawUseEmbeddedThumb(_:)), to: nil, from: nil)
            return true
        case .toggleAutoPlayVideo:
            toggleAutoPlayVisibleVideo()
            return true

        // MARK: Viewer behavior
        case .lockRotation:
            NSApp.sendAction(#selector(AppDelegate.toggleLockRotation(_:)), to: nil, from: nil)
            return true
        case .lockZoom:
            NSApp.sendAction(#selector(AppDelegate.toggleLockZoom(_:)), to: nil, from: nil)
            return true
        case .lockMirror:
            NSApp.sendAction(#selector(AppDelegate.toggleLockMirror(_:)), to: nil, from: nil)
            return true
        case .activatePanScroll:
            NSApp.sendAction(#selector(AppDelegate.toggleActivatePanScroll(_:)), to: nil, from: nil)
            return true

        // MARK: Rating (only when CollectionView focused — matches legacy gate)
        case .rating0, .rating1, .rating2, .rating3, .rating4, .rating5:
            guard publicVar.isCollectionViewFirstResponder,
                  let rating = action.ratingValue else { return false }
            handleRating(rating: rating)
            return true

        // MARK: Finder tags (only when CollectionView focused)
        case .tag1, .tag2, .tag3, .tag4, .tag5, .tag6, .tag7, .tag8, .tag9:
            guard publicVar.isCollectionViewFirstResponder,
                  let index = action.tagIndex,
                  index < FinderTag.all.count else { return false }
            handleToggleFinderTag(FinderTag.all[index].name)
            return true

        // MARK: Profile use / save. scope=browserOnly handles the
        // !isInLargeView gate; only the slot lookup needs to be unwrapped here.
        case .profileUse1, .profileUse2, .profileUse3, .profileUse4, .profileUse5,
             .profileUse6, .profileUse7, .profileUse8, .profileUse9:
            guard let slot = action.profileSlot else { return false }
            useCustomProfile(String(slot))
            return true
        case .profileSave1, .profileSave2, .profileSave3, .profileSave4, .profileSave5,
             .profileSave6, .profileSave7, .profileSave8, .profileSave9:
            guard let slot = action.profileSlot else { return false }
            setCustomProfileTo(String(slot))
            return true

        // MARK: Search
        case .searchToggleOverlay:
            toggleSearchOverlay()
            return true
        case .searchToggleRecursive:
            toggleRecursiveMode()
            return true
        case .searchToggleRecursiveFolder:
            toggleRecursiveContainFolder()
            return true

        // MARK: Quick search
        case .quickSearchActivate:
            guard !quickSearchState, !globalVar.useQuickSearch else { return false }
            quickSearch("backspace")
            return true
        }
    }
}

private extension ShortcutAction {
    /// 1-based slot for profile use/save actions; nil for any non-profile case.
    var profileSlot: Int? {
        switch self {
        case .profileUse1, .profileSave1: return 1
        case .profileUse2, .profileSave2: return 2
        case .profileUse3, .profileSave3: return 3
        case .profileUse4, .profileSave4: return 4
        case .profileUse5, .profileSave5: return 5
        case .profileUse6, .profileSave6: return 6
        case .profileUse7, .profileSave7: return 7
        case .profileUse8, .profileSave8: return 8
        case .profileUse9, .profileSave9: return 9
        default: return nil
        }
    }

    /// 0..5 rating value for rating actions; nil otherwise.
    var ratingValue: Int? {
        switch self {
        case .rating0: return 0
        case .rating1: return 1
        case .rating2: return 2
        case .rating3: return 3
        case .rating4: return 4
        case .rating5: return 5
        default: return nil
        }
    }

    /// 0-based index into `FinderTag.all` for tag actions; nil otherwise.
    var tagIndex: Int? {
        switch self {
        case .tag1: return 0
        case .tag2: return 1
        case .tag3: return 2
        case .tag4: return 3
        case .tag5: return 4
        case .tag6: return 5
        case .tag7: return 6
        case .tag8: return 7
        case .tag9: return 8
        default: return nil
        }
    }
}
