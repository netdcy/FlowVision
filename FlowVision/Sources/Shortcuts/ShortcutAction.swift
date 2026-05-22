//
//  ShortcutAction.swift
//  FlowVision
//
//  Canonical catalog of every rebindable keyboard action. Backs ShortcutStore.
//
//  ── Adding a new action ────────────────────────────────────────────────
//  1. Add the case below in the appropriate MARK group.
//  2. Add a `case` to the `buildDef` switch returning a `ShortcutDef` —
//     compiler enforces every action has metadata.
//  3. Add a `dispatch` case in KeyShortcut.swift that runs the handler.
//  4. (Optional) If exposed via a menu item, add an `identifier=` matching
//     the case rawValue in Main.storyboard so AppDelegate.syncMenuShortcuts
//     can wire its keyEquivalent.
//

import Cocoa

enum ShortcutAction: String, CaseIterable, Codable {
    // MARK: Browser nav
    case browserDirLeft, browserDirRight, browserDirUp, browserDirDown
    case browserDirDownRight, browserBack, browserForward
    case browserScrollTop, browserScrollBottom
    case browserPageUp, browserPageDown
    case browserDeselect, browserToggleSidebar

    // MARK: Viewer nav
    case viewerPrev, viewerNext
    case viewerLocateFirst, viewerLocateLast
    case viewerClose, viewerOpenFromSelection

    // MARK: Viewer ops
    case viewerZoomIn, viewerZoomOut, viewerZoom100, viewerZoomFit
    case viewerZoomReset
    case viewerRotateLeft, viewerRotateRight, viewerMirrorH
    case viewerOCR, viewerQRCode, viewerGetInfo, viewerShowExif, viewerEditMode

    // MARK: Video (non-overlapping with zoom keys)
    case videoPauseResume
    case videoSeekFwd, videoSeekBack
    case videoSeekFrameFwd, videoSeekFrameBack
    case videoSetA, videoSetB, videoABPlay
    case videoSequentialPlay, videoRememberPosition

    // MARK: Window
    case windowMaximize, windowSuitable, windowImageActual
    case windowImageCurrent, windowCenter, windowToggleFullscreen
    case windowToggleOnTop, windowRefresh
    case windowNew, windowNewTab, windowClose, windowCloseTab
    case windowReopenClosedTab
    case quitApp

    // MARK: File ops
    case fileRename, fileDelete, fileDeleteNoPrompt, fileNewFolder
    case fileCopyToDownload, fileMoveToDownload, fileGetInfo

    // MARK: Thumb size (in fileOps category)
    case thumbSizeUp, thumbSizeDown, thumbSizeReset

    // MARK: View mode
    case viewModeJustified, viewModeWaterfall, viewModeGrid, viewModeDetail

    // MARK: Visibility toggles
    case toggleHiddenFiles, toggleImageFiles, toggleRawFiles, toggleVideoFiles, toggleAllFiles
    case toggleShowFinderTagsAndRating, toggleRawUseEmbeddedThumb
    case toggleAutoPlayVideo

    // MARK: Viewer behavior toggles
    case lockRotation, lockZoom, lockMirror, activatePanScroll

    // MARK: Rating
    case rating0, rating1, rating2, rating3, rating4, rating5

    // MARK: Finder tags
    case tag1, tag2, tag3, tag4, tag5, tag6, tag7, tag8, tag9

    // MARK: Profiles
    case profileUse1, profileUse2, profileUse3, profileUse4, profileUse5
    case profileUse6, profileUse7, profileUse8, profileUse9
    case profileSave1, profileSave2, profileSave3, profileSave4, profileSave5
    case profileSave6, profileSave7, profileSave8, profileSave9

    // MARK: Search (these fire while search overlay is open)
    case searchToggleOverlay, searchToggleRecursive, searchToggleRecursiveFolder

    // MARK: Quick search
    case quickSearchActivate
}

// MARK: - Definition

/// All static metadata for a shortcut action. Built once at first access via
/// `ShortcutAction.table` and looked up by enum case. Handlers live separately
/// in `KeyShortcut.swift` (`ViewController.dispatch(_:)`).
struct ShortcutDef {
    let category: ShortcutCategory
    let scope: ContextScope
    let englishName: String
    let defaultChords: [KeyChord]

    /// Action fires even when the search overlay holds focus.
    /// Defaults false — only menu-style actions opt in.
    var firesDuringSearch: Bool = false

    /// Chord is a macOS HIG convention (Cmd+Q, Cmd+W, etc.). Recorder prompts
    /// before letting the user override.
    var isSystemConventional: Bool = false

    /// Primary (index 0) slot is rendered disabled and cannot be reassigned.
    /// Currently only `quitApp` — Cmd+Q is owned by macOS.
    var hasLockedPrimary: Bool = false
}

/// Shorthand for table readability. Order: keyCode, character, modifiers.
private func k(_ code: UInt16, _ ch: String = "", _ mods: Modifiers = []) -> KeyChord {
    KeyChord(keyCode: code, character: ch, modifiers: mods)
}

extension ShortcutAction {
    /// Metadata lookup. Force-unwrap is safe — `table` is built from `allCases`.
    var def: ShortcutDef { Self.table[self]! }

    var category: ShortcutCategory { def.category }
    var scope: ContextScope        { def.scope }
    var englishName: String        { def.englishName }
    var defaultChords: [KeyChord]  { def.defaultChords }
    var firesDuringSearch: Bool    { def.firesDuringSearch }
    var isSystemConventional: Bool { def.isSystemConventional }
    var hasLockedPrimary: Bool     { def.hasLockedPrimary }

    var displayName: String {
        NSLocalizedString("shortcut.action.\(rawValue)",
                          value: englishName,
                          comment: "shortcut display name")
    }

    private static let table: [ShortcutAction: ShortcutDef] = {
        var d: [ShortcutAction: ShortcutDef] = [:]
        d.reserveCapacity(ShortcutAction.allCases.count)
        for a in ShortcutAction.allCases { d[a] = a.buildDef() }
        return d
    }()

    private func buildDef() -> ShortcutDef {
        switch self {

        // MARK: Browser nav
        case .browserDirLeft: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Switch directory left",
            defaultChords: [k(0x00, "a")])
        case .browserDirRight: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Switch directory right",
            defaultChords: [k(0x02, "d")])
        case .browserDirUp: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Switch directory up",
            defaultChords: [k(0x0D, "w")])
        case .browserDirDown: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Switch directory down",
            defaultChords: [k(0x01, "s")])
        case .browserDirDownRight: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Switch directory down-right",
            defaultChords: [k(0x0E, "e")])
        case .browserBack: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Go back",
            defaultChords: [k(0x21, "[", .command)])
        case .browserForward: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Go forward",
            defaultChords: [k(0x1E, "]", .command)])
        case .browserScrollTop: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Scroll to top",
            defaultChords: [k(0x73)])  // Home
        case .browserScrollBottom: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Scroll to bottom",
            defaultChords: [k(0x77)])  // End
        case .browserPageUp: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Page up",
            defaultChords: [k(0x74), k(0x7E, "", .option)])  // PageUp, Opt+↑
        case .browserPageDown: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Page down",
            defaultChords: [k(0x79), k(0x7D, "", .option)])  // PageDn, Opt+↓
        case .browserDeselect: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Deselect",
            defaultChords: [k(0x35)])  // Esc
        case .browserToggleSidebar: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Toggle sidebar",
            defaultChords: [k(0x03, "f")])

        // MARK: Viewer nav
        // Multi-chord: A/↑/PageUp/Cmd+[ for prev; symmetric set for next.
        // ←/→ arrows bind to videoSeekBack/Fwd whose dispatch folds to
        // prev/next when the active item is an image.
        case .viewerPrev: return .init(
            category: .navigation, scope: .viewerOnly,
            englishName: "Previous image",
            defaultChords: [k(0x00, "a"), k(0x7E), k(0x74), k(0x21, "[", .command)])
        case .viewerNext: return .init(
            category: .navigation, scope: .viewerOnly,
            englishName: "Next image",
            defaultChords: [k(0x02, "d"), k(0x7D), k(0x79), k(0x1E, "]", .command)])
        case .viewerLocateFirst: return .init(
            category: .navigation, scope: .viewerOnly,
            englishName: "Locate first",
            defaultChords: [k(0x73), k(0x7E, "", .command)])  // Home, Cmd+↑
        case .viewerLocateLast: return .init(
            category: .navigation, scope: .viewerOnly,
            englishName: "Locate last",
            defaultChords: [k(0x77), k(0x7D, "", .command)])  // End, Cmd+↓
        case .viewerClose: return .init(
            category: .navigation, scope: .viewerOnly,
            englishName: "Close viewer",
            defaultChords: [k(0x35)])
        case .viewerOpenFromSelection: return .init(
            category: .navigation, scope: .browserOnly,
            englishName: "Open selection in viewer",
            defaultChords: [k(0x31, " ")])

        // MARK: Viewer ops
        // viewerZoomIn / Out: W and S share keys with browserDirUp/Down via
        // disjoint scope (viewer vs browser).
        case .viewerZoomIn: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Zoom in / Volume up",
            defaultChords: [k(0x18, "="), k(0x0D, "w")])
        case .viewerZoomOut: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Zoom out / Volume down",
            defaultChords: [k(0x1B, "-"), k(0x01, "s")])
        case .viewerZoom100: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Zoom 100%",
            defaultChords: [k(0x06, "z")])
        case .viewerZoomFit: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Zoom fit",
            defaultChords: [k(0x07, "x")])
        case .viewerZoomReset: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Reset zoom",
            defaultChords: [k(0x1D, "0")])
        case .viewerRotateLeft: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Rotate left",
            defaultChords: [k(0x0C, "q")])
        case .viewerRotateRight: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Rotate right",
            defaultChords: [k(0x0E, "e")])
        case .viewerMirrorH: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Mirror horizontal",
            defaultChords: [k(0x03, "f")])
        case .viewerOCR: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "OCR",
            defaultChords: [k(0x1F, "o")])
        case .viewerQRCode: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "QR code",
            defaultChords: [k(0x23, "p")])
        case .viewerGetInfo: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Get info (viewer)",
            defaultChords: [k(0x20, "u")])
        case .viewerShowExif: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Show EXIF",
            defaultChords: [k(0x22, "i")])
        case .viewerEditMode: return .init(
            category: .viewer, scope: .viewerOnly,
            englishName: "Edit image",
            defaultChords: [k(0x0E, "e", [.command, .shift])])

        // MARK: Video — seek arrows fold to prev/next on non-video at dispatch.
        case .videoPauseResume: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Play / Pause",
            defaultChords: [k(0x31, " ")])
        case .videoSeekFwd: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Seek forward",
            defaultChords: [k(0x7C)])
        case .videoSeekBack: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Seek backward",
            defaultChords: [k(0x7B)])
        case .videoSeekFrameFwd: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Seek forward 1 frame",
            defaultChords: [k(0x7C, "", .command)])
        case .videoSeekFrameBack: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Seek backward 1 frame",
            defaultChords: [k(0x7B, "", .command)])
        case .videoSetA: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Set A point",
            defaultChords: [k(0x2B, ",")])
        case .videoSetB: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Set B point",
            defaultChords: [k(0x2F, ".")])
        case .videoABPlay: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "A-B play",
            defaultChords: [k(0x28, "k")])
        case .videoSequentialPlay: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Sequential play",
            defaultChords: [k(0x25, "l")])
        case .videoRememberPosition: return .init(
            category: .video, scope: .viewerOnly,
            englishName: "Remember play position",
            defaultChords: [k(0x26, "j")])

        // MARK: Window
        case .windowMaximize: return .init(
            category: .window, scope: .both,
            englishName: "Maximize window",
            defaultChords: [k(0x12, "1")])
        case .windowSuitable: return .init(
            category: .window, scope: .both,
            englishName: "Suitable window size",
            defaultChords: [k(0x13, "2")])
        case .windowImageActual: return .init(
            category: .window, scope: .viewerOnly,
            englishName: "Window to image (actual)",
            defaultChords: [k(0x14, "3")])
        case .windowImageCurrent: return .init(
            category: .window, scope: .viewerOnly,
            englishName: "Window to image (current)",
            defaultChords: [k(0x15, "4")])
        case .windowCenter: return .init(
            category: .window, scope: .both,
            englishName: "Center window",
            defaultChords: [k(0x17, "5")])
        case .windowToggleFullscreen: return .init(
            category: .window, scope: .both,
            englishName: "Toggle full screen",
            defaultChords: [k(0x03, "f", [.command, .control]),
                            k(0x24, "\r", .option)])  // Cmd+Ctrl+F, Opt+Return
        case .windowToggleOnTop: return .init(
            category: .window, scope: .both,
            englishName: "Toggle always on top",
            defaultChords: [k(0x11, "t")])
        case .windowRefresh: return .init(
            category: .window, scope: .both,
            englishName: "Refresh",
            defaultChords: [k(0x0F, "r", .command), k(0x60)],  // Cmd+R, F5
            isSystemConventional: true)
        case .windowNew: return .init(
            category: .window, scope: .both,
            englishName: "New window",
            defaultChords: [k(0x2D, "n", .command)],
            isSystemConventional: true)
        case .windowNewTab: return .init(
            category: .window, scope: .both,
            englishName: "New tab",
            defaultChords: [k(0x11, "t", .command)],
            isSystemConventional: true)
        case .windowClose: return .init(
            category: .window, scope: .both,
            englishName: "Close window",
            defaultChords: [k(0x0D, "w", .command)],
            isSystemConventional: true)
        case .windowCloseTab: return .init(
            category: .window, scope: .both,
            englishName: "Close tab",
            defaultChords: [])
        case .windowReopenClosedTab: return .init(
            category: .window, scope: .both,
            englishName: "Reopen closed tab",
            defaultChords: [k(0x11, "t", [.command, .shift])],
            firesDuringSearch: true,
            isSystemConventional: true)
        case .quitApp: return .init(
            category: .window, scope: .both,
            englishName: "Quit application",
            defaultChords: [k(0x0C, "q", .command)],
            isSystemConventional: true,
            hasLockedPrimary: true)

        // MARK: File ops
        case .fileRename: return .init(
            category: .fileOps, scope: .browserOnly,
            englishName: "Rename",
            defaultChords: [k(0x0F, "r")])
        case .fileDelete: return .init(
            category: .fileOps, scope: .both,
            englishName: "Delete",
            defaultChords: [k(0x33), k(0x75)])  // Backspace, Forward-Delete
        case .fileDeleteNoPrompt: return .init(
            category: .fileOps, scope: .both,
            englishName: "Delete (no prompt)",
            defaultChords: [k(0x33, "", .command), k(0x75, "", .command)])
        case .fileNewFolder: return .init(
            category: .fileOps, scope: .browserOnly,
            englishName: "New folder",
            defaultChords: [k(0x2D, "n", [.command, .shift])])
        case .fileCopyToDownload: return .init(
            category: .fileOps, scope: .browserOnly,
            englishName: "Copy to Downloads",
            defaultChords: [k(0x2D, "n")])
        case .fileMoveToDownload: return .init(
            category: .fileOps, scope: .browserOnly,
            englishName: "Move to Downloads",
            defaultChords: [k(0x2E, "m")])
        case .fileGetInfo: return .init(
            category: .fileOps, scope: .browserOnly,
            englishName: "Get info",
            defaultChords: [k(0x22, "i")])

        // MARK: Thumb size
        case .thumbSizeUp: return .init(
            category: .fileOps, scope: .browserOnly,
            englishName: "Thumbnail size up",
            defaultChords: [k(0x18, "=")])
        case .thumbSizeDown: return .init(
            category: .fileOps, scope: .browserOnly,
            englishName: "Thumbnail size down",
            defaultChords: [k(0x1B, "-")])
        case .thumbSizeReset: return .init(
            category: .fileOps, scope: .browserOnly,
            englishName: "Reset thumbnail size",
            defaultChords: [k(0x1D, "0")])

        // MARK: View mode — no defaults
        case .viewModeJustified: return .init(
            category: .viewMode, scope: .browserOnly,
            englishName: "Justified view", defaultChords: [])
        case .viewModeWaterfall: return .init(
            category: .viewMode, scope: .browserOnly,
            englishName: "Waterfall view", defaultChords: [])
        case .viewModeGrid: return .init(
            category: .viewMode, scope: .browserOnly,
            englishName: "Grid view", defaultChords: [])
        case .viewModeDetail: return .init(
            category: .viewMode, scope: .browserOnly,
            englishName: "Detail view", defaultChords: [])

        // MARK: Visibility toggles
        case .toggleHiddenFiles: return .init(
            category: .visibility, scope: .browserOnly,
            englishName: "Show hidden files",
            defaultChords: [k(0x2F, ".", [.command, .shift])])
        case .toggleImageFiles: return .init(
            category: .visibility, scope: .browserOnly,
            englishName: "Show image files", defaultChords: [])
        case .toggleRawFiles: return .init(
            category: .visibility, scope: .browserOnly,
            englishName: "Show RAW files", defaultChords: [])
        case .toggleVideoFiles: return .init(
            category: .visibility, scope: .browserOnly,
            englishName: "Show video files", defaultChords: [])
        case .toggleAllFiles: return .init(
            category: .visibility, scope: .browserOnly,
            englishName: "Show all file types",
            defaultChords: [k(0x2B, ",", [.command, .shift])])
        case .toggleShowFinderTagsAndRating: return .init(
            category: .visibility, scope: .browserOnly,
            englishName: "Show Finder tags and rating", defaultChords: [])
        case .toggleRawUseEmbeddedThumb: return .init(
            category: .visibility, scope: .browserOnly,
            englishName: "Use embedded RAW thumbnail", defaultChords: [])
        case .toggleAutoPlayVideo: return .init(
            category: .visibility, scope: .browserOnly,
            englishName: "Auto-play videos in grid",
            defaultChords: [k(0x09, "v", [.command, .shift])])

        // MARK: Viewer behavior — no defaults
        case .lockRotation: return .init(
            category: .viewerBehavior, scope: .viewerOnly,
            englishName: "Lock rotation", defaultChords: [])
        case .lockZoom: return .init(
            category: .viewerBehavior, scope: .viewerOnly,
            englishName: "Lock zoom", defaultChords: [])
        case .lockMirror: return .init(
            category: .viewerBehavior, scope: .viewerOnly,
            englishName: "Lock mirror", defaultChords: [])
        case .activatePanScroll: return .init(
            category: .viewerBehavior, scope: .viewerOnly,
            englishName: "Activate pan scroll", defaultChords: [])

        // MARK: Rating (Ctrl+0..5)
        case .rating0: return .init(
            category: .rating, scope: .browserOnly,
            englishName: "Rating: clear", defaultChords: [k(0x1D, "0", .control)])
        case .rating1: return .init(
            category: .rating, scope: .browserOnly,
            englishName: "Rating: 1", defaultChords: [k(0x12, "1", .control)])
        case .rating2: return .init(
            category: .rating, scope: .browserOnly,
            englishName: "Rating: 2", defaultChords: [k(0x13, "2", .control)])
        case .rating3: return .init(
            category: .rating, scope: .browserOnly,
            englishName: "Rating: 3", defaultChords: [k(0x14, "3", .control)])
        case .rating4: return .init(
            category: .rating, scope: .browserOnly,
            englishName: "Rating: 4", defaultChords: [k(0x15, "4", .control)])
        case .rating5: return .init(
            category: .rating, scope: .browserOnly,
            englishName: "Rating: 5", defaultChords: [k(0x17, "5", .control)])

        // MARK: Finder tags (Cmd+1..9)
        case .tag1: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 1", defaultChords: [k(0x12, "1", .command)])
        case .tag2: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 2", defaultChords: [k(0x13, "2", .command)])
        case .tag3: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 3", defaultChords: [k(0x14, "3", .command)])
        case .tag4: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 4", defaultChords: [k(0x15, "4", .command)])
        case .tag5: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 5", defaultChords: [k(0x17, "5", .command)])
        case .tag6: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 6", defaultChords: [k(0x16, "6", .command)])
        case .tag7: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 7", defaultChords: [k(0x1A, "7", .command)])
        case .tag8: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 8", defaultChords: [k(0x1C, "8", .command)])
        case .tag9: return .init(
            category: .finderTags, scope: .browserOnly,
            englishName: "Toggle Finder tag 9", defaultChords: [k(0x19, "9", .command)])

        // MARK: Profile use (Opt+1..9)
        case .profileUse1: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 1", defaultChords: [k(0x12, "1", .option)])
        case .profileUse2: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 2", defaultChords: [k(0x13, "2", .option)])
        case .profileUse3: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 3", defaultChords: [k(0x14, "3", .option)])
        case .profileUse4: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 4", defaultChords: [k(0x15, "4", .option)])
        case .profileUse5: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 5", defaultChords: [k(0x17, "5", .option)])
        case .profileUse6: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 6", defaultChords: [k(0x16, "6", .option)])
        case .profileUse7: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 7", defaultChords: [k(0x1A, "7", .option)])
        case .profileUse8: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 8", defaultChords: [k(0x1C, "8", .option)])
        case .profileUse9: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Use profile 9", defaultChords: [k(0x19, "9", .option)])

        // MARK: Profile save (Cmd+Opt+1..9)
        case .profileSave1: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 1", defaultChords: [k(0x12, "1", [.command, .option])])
        case .profileSave2: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 2", defaultChords: [k(0x13, "2", [.command, .option])])
        case .profileSave3: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 3", defaultChords: [k(0x14, "3", [.command, .option])])
        case .profileSave4: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 4", defaultChords: [k(0x15, "4", [.command, .option])])
        case .profileSave5: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 5", defaultChords: [k(0x17, "5", [.command, .option])])
        case .profileSave6: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 6", defaultChords: [k(0x16, "6", [.command, .option])])
        case .profileSave7: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 7", defaultChords: [k(0x1A, "7", [.command, .option])])
        case .profileSave8: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 8", defaultChords: [k(0x1C, "8", [.command, .option])])
        case .profileSave9: return .init(
            category: .profiles, scope: .browserOnly,
            englishName: "Save profile 9", defaultChords: [k(0x19, "9", [.command, .option])])

        // MARK: Search
        case .searchToggleOverlay: return .init(
            category: .search, scope: .browserOnly,
            englishName: "Toggle search",
            defaultChords: [k(0x03, "f", .command), k(0x63)],  // Cmd+F, F3
            firesDuringSearch: true,
            isSystemConventional: true)
        case .searchToggleRecursive: return .init(
            category: .search, scope: .browserOnly,
            englishName: "Toggle recursive search",
            defaultChords: [k(0x0F, "r", [.command, .shift])],
            firesDuringSearch: true)
        case .searchToggleRecursiveFolder: return .init(
            category: .search, scope: .browserOnly,
            englishName: "Toggle recursive folder search",
            defaultChords: [k(0x03, "f", [.command, .shift])],
            firesDuringSearch: true)

        // MARK: Quick search
        case .quickSearchActivate: return .init(
            category: .quickSearch, scope: .browserOnly,
            englishName: "Activate quick search",
            defaultChords: [k(0x0C, "q")])
        }
    }
}
