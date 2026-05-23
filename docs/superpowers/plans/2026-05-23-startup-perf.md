# FlowVision Startup Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce time from Finder "Open With → FlowVision" click to large-image visible, instrumented and verified end-to-end.

**Architecture:** Stage 1 lands `os_signpost`-based timing for named startup spans and captures a baseline. Stage 2 applies six independent, ordered fix units (defaults batch read, AppDelegate slimming, viewDidLoad pruning, storyboard split, launch-from-file fast path, framework warm/linker audit) each behind a `globalVar.fastStartupEnabled` flag with per-unit revert gate.

**Tech Stack:** Swift (project deploys macOS 11.0+), AppKit, `os_signpost` (C API, available 10.14+), `OSSignposter` (12+ optional). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-23-startup-perf-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `FlowVision/Sources/Common/StartupTiming.swift` | Span IDs enum + `spBegin/spEnd/spMeasure` helpers using `os_signpost` and `log()` |
| `FlowVision/Sources/Common/StartupDefaults.swift` | `AppStartupDefaults` struct batched-read from `UserDefaults.dictionaryRepresentation()`, applies to `globalVar` |
| `FlowVision/Sources/Common/StartupBootstrap.swift` | Off-main bootstrap: FinderTag labels, FFmpeg warm |
| `docs/superpowers/specs/2026-05-23-startup-perf-baseline.md` | Captured median timings before/after each fix unit |

### Modified files

| Path | Why |
|---|---|
| `FlowVision/Sources/AppDelegate.swift` | Wrap launch hooks in spans (T1); slim `applicationWillFinishLaunching` (T2, T3); fast path `createNewWindow_FastPath` (T7) |
| `FlowVision/Sources/ViewController.swift` | Wrap `viewDidLoad` in span (T1); pull defaults from `globalVar` (T2); split deferred UI into `setupDeferredUI()` (T5) |
| `FlowVision/Sources/ViewControllerExtension/LargeImage.swift` | Background decode on Finder open (T7) |
| `FlowVision/Sources/Common/GlobalVariable.swift` | Add `fastStartupEnabled` flag (T2 prep); `THUMB_SIZES` lazy (T3) |
| `FlowVision/Sources/Common/FFmpegKit.swift` | Add `warmLoadAfterDelay(seconds:)` (T8) |
| `FlowVision/Sources/Common/FinderTag.swift` | Allow `EnhancedIndex` and custom-labels load to be invoked off-main from `StartupBootstrap` (T3) |
| `FlowVision/FlowVision.xcodeproj/project.pbxproj` | Add new Swift files to target (every new file task) |
| `FlowVision/Base.xcconfig` (or project Release config) | `DEAD_CODE_STRIPPING = YES` (T8) |

---

## Task 1 — Add startup timing instrumentation

**Files:**
- Create: `FlowVision/Sources/Common/StartupTiming.swift`
- Modify: `FlowVision/Sources/AppDelegate.swift` (lines 64, 250, 254, 276, 343–415)
- Modify: `FlowVision/Sources/ViewController.swift` (lines 444, 853, 956)
- Modify: `FlowVision/Sources/ViewControllerExtension/LargeImage.swift` (line 469)
- Modify: `FlowVision/Sources/ViewControllerExtension/FileSystem.swift` (line 1031)
- Modify: `FlowVision/FlowVision.xcodeproj/project.pbxproj` (add new file to target)

### - [ ] Step 1.1: Create `StartupTiming.swift`

```swift
//
//  StartupTiming.swift
//  FlowVision
//

import Foundation
import os.log
import os.signpost

enum StartupSpan: String {
    case appWillFinish              = "app.willFinish"
    case appWillFinishDefaultsLoad  = "app.willFinish.defaultsLoad"
    case appDidFinish               = "app.didFinish"
    case windowCreate               = "window.create"
    case windowStoryboardInstantiate = "window.storyboardInstantiate"
    case vcViewDidLoad              = "vc.viewDidLoad"
    case vcViewDidLoadDefaultsLoad  = "vc.viewDidLoad.defaultsLoad"
    case fileOpenFromFinderTotal    = "file.openFromFinder.total"
    case fileOpenLargeImageDecode   = "file.openLargeImage.decode"
    case fileSwitchDirScan          = "file.switchDir.scan"
}

private let startupLog = OSLog(subsystem: "app.flowvision.startup", category: .pointsOfInterest)

private struct SpanState {
    var startAbs: CFAbsoluteTime
    var signpostID: OSSignpostID
}

private var activeSpans: [String: SpanState] = [:]
private let spanLock = NSLock()

@inline(__always)
func spBegin(_ span: StartupSpan) {
    let id = OSSignpostID(log: startupLog)
    spanLock.lock()
    activeSpans[span.rawValue] = SpanState(startAbs: CFAbsoluteTimeGetCurrent(), signpostID: id)
    spanLock.unlock()
    os_signpost(.begin, log: startupLog, name: "Span", signpostID: id, "%{public}s", span.rawValue)
    log("[startup] begin \(span.rawValue)")
}

@inline(__always)
func spEnd(_ span: StartupSpan) {
    spanLock.lock()
    let state = activeSpans.removeValue(forKey: span.rawValue)
    spanLock.unlock()
    guard let state = state else {
        log("[startup] WARN spEnd without begin: \(span.rawValue)", level: .warn)
        return
    }
    let elapsedMs = (CFAbsoluteTimeGetCurrent() - state.startAbs) * 1000.0
    os_signpost(.end, log: startupLog, name: "Span", signpostID: state.signpostID, "%{public}s", span.rawValue)
    log(String(format: "[startup] end   %@  %.2f ms", span.rawValue, elapsedMs))
}

@inline(__always)
func spMeasure<T>(_ span: StartupSpan, _ body: () throws -> T) rethrows -> T {
    spBegin(span)
    defer { spEnd(span) }
    return try body()
}
```

### - [ ] Step 1.2: Add file to Xcode target

Open `FlowVision.xcodeproj` in Xcode → drag `StartupTiming.swift` from `Sources/Common/` into the FlowVision target. Verify Target Membership checkbox is checked.

Alternative CLI: use `xcodeproj` Ruby gem or edit `project.pbxproj` by mirroring an existing file's `PBXFileReference` + `PBXBuildFile` + `PBXSourcesBuildPhase` entries. Verify build succeeds: `xcodebuild -project FlowVision.xcodeproj -scheme FlowVision build`.

### - [ ] Step 1.3: Wrap `applicationWillFinishLaunching`

Modify `FlowVision/Sources/AppDelegate.swift` line 64–252.

Replace the opening line (currently `log("Start applicationWillFinishLaunching")`) with `spBegin(.appWillFinish)`. Replace the closing `log("End applicationWillFinishLaunching")` with `spEnd(.appWillFinish)`.

Wrap the defaults-loading block (lines 96–225, starting at `let defaults = UserDefaults.standard` through the last `if let collectionViewItemShowTooltip ...`) by inserting `spBegin(.appWillFinishDefaultsLoad)` just before line 96 and `spEnd(.appWillFinishDefaultsLoad)` just after line 225.

### - [ ] Step 1.4: Wrap `applicationDidFinishLaunching`

Modify `FlowVision/Sources/AppDelegate.swift` line 254–278.

Replace `log("Start applicationDidFinishLaunching")` with `spBegin(.appDidFinish)`. Replace `log("End applicationDidFinishLaunching")` with `spEnd(.appDidFinish)`.

### - [ ] Step 1.5: Wrap `createNewWindow`

Modify `FlowVision/Sources/AppDelegate.swift` line 343–416.

Replace `log("Start createNewWindow")` (line 344) with `spBegin(.windowCreate)`. Add `defer { spEnd(.windowCreate) }` immediately after.

Wrap the storyboard instantiation:

```swift
let windowController = spMeasure(.windowStoryboardInstantiate) { () -> WindowController in
    let storyboard = NSStoryboard(name: "Main", bundle: nil)
    guard let wc = storyboard.instantiateController(withIdentifier: "WindowController") as? WindowController else {
        fatalError("Cannot find WindowController in Main.storyboard")
    }
    return wc
}
```

(Replace existing lines 381–387 which currently do this in two statements.)

### - [ ] Step 1.6: Wrap `viewDidLoad`

Modify `FlowVision/Sources/ViewController.swift` line 444–856.

Replace `log("Start viewDidLoad")` (line 447) with `spBegin(.vcViewDidLoad)`. Replace `log("End viewDidLoad")` (line 853) with `spEnd(.vcViewDidLoad)`.

Wrap the defaults block (lines 538–597, starting at `if let isLargeImageFitWindow ...` through the `publicVar.profile = CustomProfile.loadFromUserDefaults(...)` line): insert `spBegin(.vcViewDidLoadDefaultsLoad)` before line 538 and `spEnd(.vcViewDidLoadDefaultsLoad)` after line 597.

### - [ ] Step 1.7: Add `fileOpenFromFinderTotal` span

Modify `FlowVision/Sources/AppDelegate.swift` `application(_:openFiles:)` (line 424).

Just after line 425 (`NSApplication.shared.reply(toOpenOrPrint: .success)`), add:

```swift
spBegin(.fileOpenFromFinderTotal)
```

Then in `FlowVision/Sources/ViewControllerExtension/LargeImage.swift` `OpenLargeImageFromFinder(path:)` line 469, immediately after the function body's final statement (after line 487), add:

```swift
// Mark Finder-launch first frame
DispatchQueue.main.async {
    spEnd(.fileOpenFromFinderTotal)
}
```

The `main.async` defers `spEnd` until after AppKit commits the frame so we capture the user-visible moment, not the function-return moment.

### - [ ] Step 1.8: Wrap `OpenLargeImageFromFinder` decode

Modify `FlowVision/Sources/ViewControllerExtension/LargeImage.swift` line 469–488.

Wrap the body in:

```swift
func OpenLargeImageFromFinder(path: String){
    spBegin(.fileOpenLargeImageDecode)
    defer { spEnd(.fileOpenLargeImageDecode) }
    // ... existing body unchanged ...
}
```

### - [ ] Step 1.9: Wrap `switchDirByDirection`

Modify `FlowVision/Sources/ViewControllerExtension/FileSystem.swift` line 1031.

Add at function start:

```swift
spBegin(.fileSwitchDirScan)
defer { spEnd(.fileSwitchDirScan) }
```

### - [ ] Step 1.10: Build

Run: `xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`

Expected: BUILD SUCCEEDED. If errors, fix and re-build.

### - [ ] Step 1.11: Verify spans log

Launch the built `.app` by opening a PNG with it from Finder. Check `~/Library/Logs/FlowVision/` (or wherever `log()` writes; check `Log.swift`). Confirm lines like `[startup] begin app.willFinish` and `[startup] end app.willFinish 32.10 ms` appear.

### - [ ] Step 1.12: Commit

```bash
git add FlowVision/Sources/Common/StartupTiming.swift \
        FlowVision/Sources/AppDelegate.swift \
        FlowVision/Sources/ViewController.swift \
        FlowVision/Sources/ViewControllerExtension/LargeImage.swift \
        FlowVision/Sources/ViewControllerExtension/FileSystem.swift \
        FlowVision/FlowVision.xcodeproj/project.pbxproj
git commit -m "feat: instrument startup spans for perf measurement"
```

---

## Task 2 — Capture baseline + add fastStartupEnabled flag

**Files:**
- Modify: `FlowVision/Sources/Common/GlobalVariable.swift` (line 107 area)
- Modify: `FlowVision/Sources/AppDelegate.swift` (lines 220-225 area, defaults block)
- Create: `docs/superpowers/specs/2026-05-23-startup-perf-baseline.md`

### - [ ] Step 2.1: Add `fastStartupEnabled` to `GlobalVar`

Modify `FlowVision/Sources/Common/GlobalVariable.swift` after line 107 (after `collectionViewItemShowTooltip`):

```swift
var fastStartupEnabled = true
```

### - [ ] Step 2.2: Wire default into AppDelegate

Modify `FlowVision/Sources/AppDelegate.swift` inside the defaults block (after line 224, the `collectionViewItemShowTooltip` block):

```swift
if let fastStartupEnabled = UserDefaults.standard.value(forKey: "fastStartupEnabled") as? Bool {
    globalVar.fastStartupEnabled = fastStartupEnabled
}
```

### - [ ] Step 2.3: Capture baseline

Build Release: `xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`

For each file type in {PNG, JPG, HEIC, RAW CR2, RAW NEF, animated GIF, WEBP, MP4 video}:
1. `killall FlowVision; sleep 30`
2. `open -a <built-app-path> <sample-file>` 5 times
3. Record `file.openFromFinder.total` median from log lines.

Also capture: `app.willFinish`, `app.willFinish.defaultsLoad`, `app.didFinish`, `window.create`, `window.storyboardInstantiate`, `vc.viewDidLoad`, `vc.viewDidLoad.defaultsLoad`, `file.openLargeImage.decode`, `file.switchDir.scan` medians (use PNG run for these — they're not file-type-dependent).

### - [ ] Step 2.4: Write baseline doc

Create `docs/superpowers/specs/2026-05-23-startup-perf-baseline.md` with a table:

```markdown
# Startup Perf Baseline (2026-05-23)

Hardware: <model, CPU, RAM>
macOS: <version>
Build: Release, commit <sha>

## file.openFromFinder.total (ms, median of 5 cold runs)

| Type | Median |
|---|---|
| PNG  | … |
| JPG  | … |
| HEIC | … |
| CR2  | … |
| NEF  | … |
| GIF  | … |
| WEBP | … |
| MP4  | … |

## Per-span medians (PNG cold launch)

| Span | Median (ms) |
|---|---|
| app.willFinish | … |
| app.willFinish.defaultsLoad | … |
| app.didFinish | … |
| window.create | … |
| window.storyboardInstantiate | … |
| vc.viewDidLoad | … |
| vc.viewDidLoad.defaultsLoad | … |
| file.openLargeImage.decode | … |
| file.switchDir.scan | … |
```

Fill in actual numbers from Step 2.3.

### - [ ] Step 2.5: Commit

```bash
git add FlowVision/Sources/Common/GlobalVariable.swift \
        FlowVision/Sources/AppDelegate.swift \
        docs/superpowers/specs/2026-05-23-startup-perf-baseline.md
git commit -m "feat: add fastStartupEnabled flag; record baseline"
```

---

## Task 3 — Fix unit 1: batched defaults read

Replaces 60+ individual `value(forKey:)` calls with a single `dictionaryRepresentation()` fetch.

**Files:**
- Create: `FlowVision/Sources/Common/StartupDefaults.swift`
- Modify: `FlowVision/Sources/AppDelegate.swift` (lines 96–225)
- Modify: `FlowVision/Sources/ViewController.swift` (lines 538–597)
- Modify: `FlowVision.xcodeproj/project.pbxproj`

### - [ ] Step 3.1: Create `StartupDefaults.swift`

```swift
//
//  StartupDefaults.swift
//  FlowVision
//

import Foundation

struct AppStartupDefaults {
    // GlobalVar keys (loaded in applicationWillFinishLaunching)
    var appearance: String?
    var openLastFolder: Bool?
    var homeFolder: String?
    var hasNormalExit: Bool?
    var isFirstTimeUse: Bool?
    var terminateAfterLastWindowClosed: Bool?
    var autoHideToolbar: Bool?
    var autoHideCursorWhenFullscreen: Bool?
    var randomFolderThumb: Bool?
    var thumbnailOfFolderUseStacking: Bool?
    var loopBrowsing: Bool?
    var blackBgInFullScreen: Bool?
    var blackBgAlways: Bool?
    var blackBgInFullScreenForVideo: Bool?
    var blackBgAlwaysForVideo: Bool?
    var thumbnailExcludeList: [String]?
    var usePinyinSearch: Bool?
    var usePinyinInitialSearch: Bool?
    var memUseLimit: Int?
    var thumbThreadNum: Int?
    var folderSearchDepth: Int?
    var thumbThreadNum_External: Int?
    var folderSearchDepth_External: Int?
    var doNotUseFFmpeg: Bool?
    var videoPlayRememberPosition: Bool?
    var videoPlaySequentialPlay: Bool?
    var videoVolume: Float?
    var videoPlaybackRate: Float?
    var useInternalPlayer: Bool?
    var isEnterKeyToOpen: Bool?
    var clickEdgeToSwitchImage: Bool?
    var scrollMouseWheelToZoom: Bool?
    var scrollSensitivity: Double?
    var keepFilterStateWhenSwitchFolder: Bool?
    var dirTreeAutoExpand: Bool?
    var largeImageViewShowTagsAndRating: Bool?
    var enhancedIndexEnabled: Bool?
    var collectionViewItemShowTooltip: Bool?
    var fastStartupEnabled: Bool?
    var myFavoritesArray: [String]?
    var customTagLabels: [[String: Any]]?

    // publicVar keys (loaded in ViewController.viewDidLoad)
    var isLargeImageFitWindow: Bool?
    var isShowHiddenFile: Bool?
    var isShowImageFile: Bool?
    var isShowRawFile: Bool?
    var isShowAllTypeFile: Bool?
    var isShowVideoFile: Bool?
    var isGenHdThumb: Bool?
    var isPreferInternalThumb: Bool?
    var isEnableHDR: Bool?
    var isRawUseEmbeddedThumb: Bool?
    var isRecursiveContainFolder: Bool?
    var autoPlayVisibleVideo: Bool?
    var autoPlaySelectedVideo: Bool?
    var isRotationLocked: Bool?
    var isZoomLocked: Bool?
    var isMirrorLocked: Bool?
    var isPanWhenZoomed: Bool?
    var currentTag: String?

    static func load() -> AppStartupDefaults {
        let dict = UserDefaults.standard.dictionaryRepresentation()
        var d = AppStartupDefaults()
        d.appearance                       = dict["appearance"]                        as? String
        d.openLastFolder                   = dict["openLastFolder"]                    as? Bool
        d.homeFolder                       = dict["homeFolder"]                        as? String
        d.hasNormalExit                    = dict["hasNormalExit"]                     as? Bool
        d.isFirstTimeUse                   = dict["isFirstTimeUse"]                    as? Bool
        d.terminateAfterLastWindowClosed   = dict["terminateAfterLastWindowClosed"]    as? Bool
        d.autoHideToolbar                  = dict["autoHideToolbar"]                   as? Bool
        d.autoHideCursorWhenFullscreen     = dict["autoHideCursorWhenFullscreen"]      as? Bool
        d.randomFolderThumb                = dict["randomFolderThumb"]                 as? Bool
        d.thumbnailOfFolderUseStacking     = dict["thumbnailOfFolderUseStacking"]      as? Bool
        d.loopBrowsing                     = dict["loopBrowsing"]                      as? Bool
        d.blackBgInFullScreen              = dict["blackBgInFullScreen"]               as? Bool
        d.blackBgAlways                    = dict["blackBgAlways"]                     as? Bool
        d.blackBgInFullScreenForVideo      = dict["blackBgInFullScreenForVideo"]       as? Bool
        d.blackBgAlwaysForVideo            = dict["blackBgAlwaysForVideo"]             as? Bool
        d.thumbnailExcludeList             = dict["thumbnailExcludeList"]              as? [String]
        d.usePinyinSearch                  = dict["usePinyinSearch"]                   as? Bool
        d.usePinyinInitialSearch           = dict["usePinyinInitialSearch"]            as? Bool
        d.memUseLimit                      = dict["memUseLimit"]                       as? Int
        d.thumbThreadNum                   = dict["thumbThreadNum"]                    as? Int
        d.folderSearchDepth                = dict["folderSearchDepth"]                 as? Int
        d.thumbThreadNum_External          = dict["thumbThreadNum_External"]           as? Int
        d.folderSearchDepth_External       = dict["folderSearchDepth_External"]        as? Int
        d.doNotUseFFmpeg                   = dict["doNotUseFFmpeg"]                    as? Bool
        d.videoPlayRememberPosition        = dict["videoPlayRememberPosition"]         as? Bool
        d.videoPlaySequentialPlay          = dict["videoPlaySequentialPlay"]           as? Bool
        d.videoVolume                      = dict["videoVolume"]                       as? Float
        d.videoPlaybackRate                = dict["videoPlaybackRate"]                 as? Float
        d.useInternalPlayer                = dict["useInternalPlayer"]                 as? Bool
        d.isEnterKeyToOpen                 = dict["isEnterKeyToOpen"]                  as? Bool
        d.clickEdgeToSwitchImage           = dict["clickEdgeToSwitchImage"]            as? Bool
        d.scrollMouseWheelToZoom           = dict["scrollMouseWheelToZoom"]            as? Bool
        d.scrollSensitivity                = dict["scrollSensitivity"]                 as? Double
        d.keepFilterStateWhenSwitchFolder  = dict["keepFilterStateWhenSwitchFolder"]   as? Bool
        d.dirTreeAutoExpand                = dict["dirTreeAutoExpand"]                 as? Bool
        d.largeImageViewShowTagsAndRating  = dict["largeImageViewShowTagsAndRating"]   as? Bool
        d.enhancedIndexEnabled             = dict["enhancedIndexEnabled"]              as? Bool
        d.collectionViewItemShowTooltip    = dict["collectionViewItemShowTooltip"]     as? Bool
        d.fastStartupEnabled               = dict["fastStartupEnabled"]                as? Bool
        d.myFavoritesArray                 = dict["globalVar.myFavoritesArray"]        as? [String]
        d.customTagLabels                  = dict[CustomTagView.userDefaultsKey]       as? [[String: Any]]
        d.isLargeImageFitWindow            = dict["isLargeImageFitWindow"]             as? Bool
        d.isShowHiddenFile                 = dict["isShowHiddenFile"]                  as? Bool
        d.isShowImageFile                  = dict["isShowImageFile"]                   as? Bool
        d.isShowRawFile                    = dict["isShowRawFile"]                     as? Bool
        d.isShowAllTypeFile                = dict["isShowAllTypeFile"]                 as? Bool
        d.isShowVideoFile                  = dict["isShowVideoFile"]                   as? Bool
        d.isGenHdThumb                     = dict["isGenHdThumb"]                      as? Bool
        d.isPreferInternalThumb            = dict["isPreferInternalThumb"]             as? Bool
        d.isEnableHDR                      = dict["isEnableHDR"]                       as? Bool
        d.isRawUseEmbeddedThumb            = dict["isRawUseEmbeddedThumb"]             as? Bool
        d.isRecursiveContainFolder         = dict["isRecursiveContainFolder"]          as? Bool
        d.autoPlayVisibleVideo             = dict["autoPlayVisibleVideo"]              as? Bool
        d.autoPlaySelectedVideo            = dict["autoPlaySelectedVideo"]             as? Bool
        d.isRotationLocked                 = dict["isRotationLocked"]                  as? Bool
        d.isZoomLocked                     = dict["isZoomLocked"]                      as? Bool
        d.isMirrorLocked                   = dict["isMirrorLocked"]                    as? Bool
        d.isPanWhenZoomed                  = dict["isPanWhenZoomed"]                   as? Bool
        d.currentTag                       = dict["currentTag"]                        as? String
        return d
    }

    func applyToGlobalVar() {
        if let v = openLastFolder                  { globalVar.openLastFolder = v }
        if let v = homeFolder                      { globalVar.homeFolder = v }
        if let v = isFirstTimeUse                  { globalVar.isFirstTimeUse = v }
        if let v = terminateAfterLastWindowClosed  { globalVar.terminateAfterLastWindowClosed = v }
        if let v = autoHideToolbar                 { globalVar.autoHideToolbar = v }
        if let v = autoHideCursorWhenFullscreen    { globalVar.autoHideCursorWhenFullscreen = v }
        if let v = randomFolderThumb               { globalVar.randomFolderThumb = v }
        if let v = thumbnailOfFolderUseStacking    { globalVar.thumbnailOfFolderUseStacking = v }
        if let v = loopBrowsing                    { globalVar.loopBrowsing = v }
        if let v = blackBgInFullScreen             { globalVar.blackBgInFullScreen = v }
        if let v = blackBgAlways                   { globalVar.blackBgAlways = v }
        if let v = blackBgInFullScreenForVideo     { globalVar.blackBgInFullScreenForVideo = v }
        if let v = blackBgAlwaysForVideo           { globalVar.blackBgAlwaysForVideo = v }
        if let v = thumbnailExcludeList            { globalVar.thumbnailExcludeList = v }
        if let v = usePinyinSearch                 { globalVar.usePinyinSearch = v }
        if let v = usePinyinInitialSearch          { globalVar.usePinyinInitialSearch = v }
        if let v = memUseLimit                     { globalVar.memUseLimit = v }
        if let v = thumbThreadNum                  { globalVar.thumbThreadNum = v }
        if let v = folderSearchDepth               { globalVar.folderSearchDepth = v }
        if let v = thumbThreadNum_External         { globalVar.thumbThreadNum_External = v }
        if let v = folderSearchDepth_External      { globalVar.folderSearchDepth_External = v }
        if let v = doNotUseFFmpeg                  { globalVar.doNotUseFFmpeg = v }
        if let v = videoPlayRememberPosition       { globalVar.videoPlayRememberPosition = v }
        if let v = videoPlaySequentialPlay         { globalVar.videoPlaySequentialPlay = v }
        if let v = videoVolume                     { globalVar.videoVolume = v }
        if let v = videoPlaybackRate               { globalVar.videoPlaybackRate = v }
        if let v = useInternalPlayer              { globalVar.useInternalPlayer = v }
        if let v = isEnterKeyToOpen                { globalVar.isEnterKeyToOpen = v }
        if let v = clickEdgeToSwitchImage          { globalVar.clickEdgeToSwitchImage = v }
        if let v = scrollMouseWheelToZoom          { globalVar.scrollMouseWheelToZoom = v }
        if let v = scrollSensitivity               { globalVar.scrollSensitivity = v }
        if let v = keepFilterStateWhenSwitchFolder { globalVar.keepFilterStateWhenSwitchFolder = v }
        if let v = dirTreeAutoExpand               { globalVar.dirTreeAutoExpand = v }
        if let v = largeImageViewShowTagsAndRating { globalVar.largeImageViewShowTagsAndRating = v }
        if let v = enhancedIndexEnabled            { globalVar.enhancedIndexEnabled = v }
        if let v = collectionViewItemShowTooltip   { globalVar.collectionViewItemShowTooltip = v }
        if let v = fastStartupEnabled              { globalVar.fastStartupEnabled = v }
        globalVar.myFavoritesArray = myFavoritesArray ?? [String]()
    }

    func applyToPublicVar(_ publicVar: PublicVar) {
        if let v = isLargeImageFitWindow    { publicVar.isLargeImageFitWindow = v }
        if let v = isShowHiddenFile         { publicVar.isShowHiddenFile = v }
        if let v = isShowImageFile          { publicVar.isShowImageFile = v }
        if let v = isShowRawFile            { publicVar.isShowRawFile = v }
        if let v = isShowAllTypeFile        { publicVar.isShowAllTypeFile = v }
        if let v = isShowVideoFile          { publicVar.isShowVideoFile = v }
        if let v = isGenHdThumb             { publicVar.isGenHdThumb = v }
        if let v = isPreferInternalThumb    { publicVar.isPreferInternalThumb = v }
        if let v = isEnableHDR              { publicVar.isEnableHDR = v }
        if let v = isRawUseEmbeddedThumb    { publicVar.isRawUseEmbeddedThumb = v }
        if let v = isRecursiveContainFolder { publicVar.isRecursiveContainFolder = v }
        if let v = autoPlayVisibleVideo     { publicVar.autoPlayVisibleVideo = v }
        if let v = autoPlaySelectedVideo    { publicVar.autoPlaySelectedVideo = v }
        if let v = isRotationLocked         { publicVar.isRotationLocked = v }
        if let v = isZoomLocked             { publicVar.isZoomLocked = v }
        if let v = isMirrorLocked           { publicVar.isMirrorLocked = v }
        if let v = isPanWhenZoomed          { publicVar.isPanWhenZoomed = v }
        if let v = currentTag               { publicVar.currentTag = v }
    }
}

// Singleton cache so ViewController can reuse data already pulled by AppDelegate.
final class StartupDefaultsCache {
    static let shared = StartupDefaultsCache()
    private(set) var loaded: AppStartupDefaults?
    private let lock = NSLock()

    func loadIfNeeded() -> AppStartupDefaults {
        lock.lock()
        defer { lock.unlock() }
        if let l = loaded { return l }
        let d = AppStartupDefaults.load()
        loaded = d
        return d
    }
}
```

Note: `PublicVar` type name must match the actual nested type used inside `ViewController` (verify by grep before editing — adjust the parameter type if it's named differently).

### - [ ] Step 3.2: Verify `PublicVar` type name

Run: `grep -n "class PublicVar\|class publicVar\|var publicVar:" FlowVision/Sources/ViewController.swift | head -5`

If actual name differs, adjust `StartupDefaults.swift` `applyToPublicVar(_:)` parameter type accordingly. Re-run grep before continuing.

### - [ ] Step 3.3: Add `StartupDefaults.swift` to Xcode target

Drag file into FlowVision target (or edit `project.pbxproj`). Build: `xcodebuild -project FlowVision.xcodeproj -scheme FlowVision build`. Expect: BUILD SUCCEEDED.

### - [ ] Step 3.4: Replace defaults block in `applicationWillFinishLaunching`

Modify `FlowVision/Sources/AppDelegate.swift`. Inside the block currently spanned by `spBegin(.appWillFinishDefaultsLoad)` / `spEnd(.appWillFinishDefaultsLoad)`:

Replace the entire region from `let defaults = UserDefaults.standard` (line 96) through the closing `}` of the last `if let collectionViewItemShowTooltip ...` (line 225) — plus the existing `globalVar.fastStartupEnabled` block added in Task 2 — with:

```swift
if globalVar.fastStartupEnabled {
    let d = StartupDefaultsCache.shared.loadIfNeeded()

    if d.appearance == "darkAqua" {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    } else if d.appearance == "aqua" {
        NSApp.appearance = NSAppearance(named: .aqua)
    } else {
        NSApp.appearance = nil
    }

    if let hasNormalExit = d.hasNormalExit, !hasNormalExit {
        UserDefaults.standard.set("file:///", forKey: "lastFolder")
        globalVar.homeFolder = "file:///"
    }
    UserDefaults.standard.set(false, forKey: "hasNormalExit")

    d.applyToGlobalVar()

    if let savedLabels = d.customTagLabels {
        FinderTag.customLabels = savedLabels.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            return (name, dict["colorIndex"] as? Int)
        }
    } else {
        FinderTag.customLabels = FinderTag.systemColorLabels.map { ($0.name, $0.colorIndex) }
    }
} else {
    // legacy path — keep original lines 96–235 unchanged here for rollback
    // (copy original block back inside this else for safety)
}
```

For the `else` branch, paste the original lines 96–235 verbatim (the legacy individual `value(forKey:)` reads + `FinderTag` block) so toggling the flag fully restores old behavior. This is the only place we keep duplication; it's removed in cleanup after one stable release per spec §8.

### - [ ] Step 3.5: Replace defaults block in `ViewController.viewDidLoad`

Modify `FlowVision/Sources/ViewController.swift`. Inside the block spanned by `spBegin(.vcViewDidLoadDefaultsLoad)` / `spEnd(.vcViewDidLoadDefaultsLoad)`:

Replace lines 538–591 (every `if let ... = UserDefaults.standard.value(forKey:) ...` block, up to but not including the `if #available(macOS 14.0, *)` block at line 592) with:

```swift
if globalVar.fastStartupEnabled {
    let d = StartupDefaultsCache.shared.loadIfNeeded()
    d.applyToPublicVar(publicVar)
} else {
    // legacy path — original lines 538–591 verbatim
}
```

Paste the original 60-ish lines into the `else` block for rollback safety.

### - [ ] Step 3.6: Build

`xcodebuild -project FlowVision.xcodeproj -scheme FlowVision build`. Expect BUILD SUCCEEDED.

### - [ ] Step 3.7: Manual test

1. Launch from PNG via Finder. Confirm window opens, large image shows.
2. Open Settings → confirm previously-set preferences (theme, hidden files toggle, video volume) preserved.
3. Toggle in `~/Library/Preferences/<bundle-id>.plist`: `defaults write app.flowvision fastStartupEnabled -bool NO`, relaunch — verify legacy path works (defaults still applied).
4. Reset: `defaults write app.flowvision fastStartupEnabled -bool YES`.

### - [ ] Step 3.8: Re-measure & gate-check

Repeat baseline capture (Step 2.3) for `app.willFinish.defaultsLoad` + `vc.viewDidLoad.defaultsLoad` + `file.openFromFinder.total`. Append numbers to `2026-05-23-startup-perf-baseline.md` under heading `## After T3: batched defaults read`.

If `app.willFinish.defaultsLoad` + `vc.viewDidLoad.defaultsLoad` combined improvement is <5% of its baseline, revert (`git revert HEAD`) and skip remaining fix units that depend on the cache (none do — others are independent).

### - [ ] Step 3.9: Commit

```bash
git add FlowVision/Sources/Common/StartupDefaults.swift \
        FlowVision/Sources/AppDelegate.swift \
        FlowVision/Sources/ViewController.swift \
        FlowVision/FlowVision.xcodeproj/project.pbxproj \
        docs/superpowers/specs/2026-05-23-startup-perf-baseline.md
git commit -m "perf: batch UserDefaults reads at startup"
```

---

## Task 4 — Fix unit 2: AppDelegate slimming + lazy THUMB_SIZES

Move FinderTag labels load, `THUMB_SIZES` generation, and menu delegate hookup off the critical path.

**Files:**
- Create: `FlowVision/Sources/Common/StartupBootstrap.swift`
- Modify: `FlowVision/Sources/Common/GlobalVariable.swift` (line 12-13)
- Modify: `FlowVision/Sources/AppDelegate.swift` (lines 64–252, 254–278)
- Modify: `FlowVision.xcodeproj/project.pbxproj`

### - [ ] Step 4.1: Make `THUMB_SIZES` lazy

Modify `FlowVision/Sources/Common/GlobalVariable.swift` lines 12–13:

```swift
// Lazily computed thumbnail bucket sizes. Pure function of constants — safe to cache.
private let _thumbSizesComputed: [Int] = {
    var result: [Int] = []
    var seen = Set<Int>()
    var x: Double = 192
    while x <= 10000 {
        let rounded = Int(round(x) / 64) * 64
        if seen.insert(rounded).inserted { result.append(rounded) }
        x *= 1.1
    }
    return result
}()
var THUMB_SIZES: [Int] { _thumbSizesComputed }
```

### - [ ] Step 4.2: Remove `generateRoundedArray` from `applicationWillFinishLaunching`

Modify `FlowVision/Sources/AppDelegate.swift` lines 72–89 (the `generateRoundedArray` nested function + `THUMB_SIZES = generateRoundedArray()` call). Delete this whole block.

`THUMB_SIZES` will now compute lazily on first use (no longer mutates a global var; the new top-level `var THUMB_SIZES: [Int]` is read-only).

### - [ ] Step 4.3: Create `StartupBootstrap.swift`

```swift
//
//  StartupBootstrap.swift
//  FlowVision
//

import Foundation

enum StartupBootstrap {
    /// Schedule non-critical bootstrap work off the main launch path.
    /// Called from applicationDidFinishLaunching after the first window is on screen.
    static func scheduleBackground() {
        DispatchQueue.global(qos: .utility).async {
            FFmpegKitWrapper.shared.warmLoadAfterDelay(seconds: 2.0)
        }
    }
}
```

(FinderTag labels load already runs on main during defaults phase — keep it there for now; it's tiny. If T2 baseline shows it's >5 ms, move it here in a follow-up.)

### - [ ] Step 4.4: Add `StartupBootstrap.swift` to target

Drag into Xcode target or edit `project.pbxproj`.

### - [ ] Step 4.5: Defer menu delegates

Modify `FlowVision/Sources/AppDelegate.swift` lines 240–244 (the `favoritesMenu.removeAllItems(); favoritesMenu.delegate = self; historyMenu...` block).

Move these four lines from `applicationWillFinishLaunching` to the top of `applicationDidFinishLaunching` (immediately after `spBegin(.appDidFinish)`), gated on `if globalVar.fastStartupEnabled { ... } else { /* skip — already done in willFinish for legacy path */ }`. For the legacy path, keep the original lines in `applicationWillFinishLaunching` under the `else` branch of the flag check.

To keep the diff manageable: add a helper:

```swift
private func setupMenuDelegates() {
    favoritesMenu.removeAllItems()
    favoritesMenu.delegate = self
    historyMenu.removeAllItems()
    historyMenu.delegate = self
    viewMenu.delegate = self
}
```

Call from `applicationDidFinishLaunching` when flag on, from `applicationWillFinishLaunching` else branch otherwise.

### - [ ] Step 4.6: Call `StartupBootstrap.scheduleBackground()`

Modify `FlowVision/Sources/AppDelegate.swift` `applicationDidFinishLaunching` (line 254). After `setupMenuDelegates()` (Step 4.5), add:

```swift
if globalVar.fastStartupEnabled {
    StartupBootstrap.scheduleBackground()
}
```

### - [ ] Step 4.7: Build & test

`xcodebuild ... build`. Expect BUILD SUCCEEDED.

Manual:
1. Cold-launch from PNG. Verify favorites menu populated when clicked (delegate fired). Verify history menu populated. Verify view menu items present.
2. Open a video file → confirm FFmpeg path still works (warm-load completes off-main, no hang).

### - [ ] Step 4.8: Re-measure

Re-capture `app.willFinish` and `file.openFromFinder.total` medians. Append to baseline doc under `## After T4: AppDelegate slimming`. If `app.willFinish` improvement <5%, revert and skip.

### - [ ] Step 4.9: Commit

```bash
git add FlowVision/Sources/Common/GlobalVariable.swift \
        FlowVision/Sources/Common/StartupBootstrap.swift \
        FlowVision/Sources/AppDelegate.swift \
        FlowVision/FlowVision.xcodeproj/project.pbxproj \
        docs/superpowers/specs/2026-05-23-startup-perf-baseline.md
git commit -m "perf: defer non-critical AppDelegate bootstrap off main launch path"
```

---

## Task 5 — Fix unit 3: viewDidLoad pruning

Move outlineView / collectionView / event monitor setup behind a `setupDeferredUI()` hook called from `viewDidAppear`.

**Files:**
- Modify: `FlowVision/Sources/ViewController.swift` (lines 444–856)

### - [ ] Step 5.1: Identify split point

In `ViewController.swift` `viewDidLoad`:
- **Keep in `viewDidLoad`:** `largeImageView` setup (lines 459–473), `publicVar.isInInitStage = false` (line 477), `drawingView` setup (lines 526–530), defaults batch read (lines 538–597, now `StartupDefaultsCache`), `publicVar.profile` load (line 597), `publicVar.setFileExtensions()` (line 602), theme color block (lines 619–630).
- **Move to `setupDeferredUI()`:** `collectionViewManager` and `collectionView` config (lines 482–494), progress bar setup (line 498), `outlineViewManager` + `outlineView` config (lines 508–518), splitView delegate (line 522), splitView profile-driven position (lines 604–616), `treeViewData.initData(...)` + `outlineView.reloadData()` + `adjustColumnWidth()` (lines 644–648), all event monitors (lines 653–845).

### - [ ] Step 5.2: Add `setupDeferredUI()` and `viewDidAppear` hook

Modify `FlowVision/Sources/ViewController.swift`. After existing `viewDidLoad` closing brace (line 856), insert:

```swift
private var deferredUIInitialized = false

override func viewDidAppear() {
    super.viewDidAppear()
    if !deferredUIInitialized {
        deferredUIInitialized = true
        setupDeferredUI()
    }
}

private func setupDeferredUI() {
    if !globalVar.fastStartupEnabled { return }  // legacy path already did this in viewDidLoad

    // collectionView
    collectionViewManager = CustomCollectionViewManager(fileDB: fileDB)
    collectionView.wantsLayer = true
    collectionView.allowsMultipleSelection = true
    collectionView.isSelectable = true
    collectionView.delegate = collectionViewManager
    collectionView.dataSource = collectionViewManager
    collectionView.register(CustomCollectionViewItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "CustomCollectionViewItem"))
    collectionView.setDraggingSourceOperationMask([.every], forLocal: true)
    collectionView.setDraggingSourceOperationMask([.every], forLocal: false)

    setupProgressBar()

    // outlineView
    outlineViewManager = CustomOutlineViewManager(fileDB: fileDB, treeViewData: treeViewData, outlineView: outlineView)
    outlineView.delegate = outlineViewManager
    outlineView.dataSource = outlineViewManager
    outlineView.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    outlineView.setDraggingSourceOperationMask([.every], forLocal: true)
    outlineView.setDraggingSourceOperationMask([.every], forLocal: false)
    outlineView.columnAutoresizingStyle = .noColumnAutoresizing

    splitView.delegate = self

    // splitView profile-driven position
    if publicVar.profile.isDirTreeHidden { splitView.setPosition(0, ofDividerAt: 0) }

    // layout
    switch publicVar.profile.layoutType {
    case .waterfall:  collectionView.collectionViewLayout = publicVar.waterfallLayout
    case .justified:  collectionView.collectionViewLayout = publicVar.justifiedLayout
    case .grid:       collectionView.collectionViewLayout = publicVar.gridLayout
    default:          collectionView.collectionViewLayout = publicVar.justifiedLayout
    }
    changeWaterfallLayoutNumberOfColumns()

    treeViewData.initData(path: treeRootFolder)
    outlineView.reloadData()
    DispatchQueue.main.async { [weak self] in
        self?.outlineViewManager.adjustColumnWidth()
    }

    // event monitors — copy the block from original viewDidLoad lines 653–845 verbatim.
    setupEventMonitors()
}
```

Then extract the event-monitor block (currently lines 653–845) into:

```swift
private func setupEventMonitors() {
    NSApp.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new, .old], context: nil)
    outlineView.doubleAction = #selector(outlineViewDoubleClicked(_:))

    eventMonitorLeftMouseDown = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
        // ... original closure verbatim from lines 661–684 ...
    }

    eventMonitorLeftMouseUp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
        // ... original closure verbatim from lines 686–709 ...
    }

    eventMonitorScrollWheel = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        // ... original closure verbatim from lines 745–758 ...
    }

    if let scrollView = collectionView.enclosingScrollView {
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll(_:)), name: NSScrollView.didLiveScrollNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewScrollEnd(_:)), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
    }

    eventMonitorKeyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self else { return event }
        return self.KeyShortcutManager(event: event)
    }

    eventMonitorRightMouseUp = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
        // ... original closure verbatim from lines 778–799 ...
    }

    eventMonitorRightMouseDown = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
        // ... original closure verbatim from lines 801–822 ...
    }

    eventMonitorRightMouseDragged = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDragged) { [weak self] event in
        // ... original closure verbatim from lines 824–845 ...
    }
}
```

Copy each `// ...verbatim...` placeholder with the exact closure body from the corresponding existing lines.

### - [ ] Step 5.3: Wrap legacy viewDidLoad branch

In `viewDidLoad`, after the keep-block (theme colors, line 630), add the gate:

```swift
if globalVar.fastStartupEnabled {
    // deferred work runs in setupDeferredUI from viewDidAppear
} else {
    // legacy: do the work inline here — keep lines 482–518, 522, 604–616, 644–648, 653–845 in place
    setupDeferredUI_legacy()
}
```

Define `setupDeferredUI_legacy()` containing exact original code (a copy of the work, no flag check inside). This duplication is removed after T5 ships stable.

### - [ ] Step 5.4: Build & manual test

`xcodebuild ... build`. Expect BUILD SUCCEEDED.

Manual:
1. Cold-launch from PNG. Verify window appears; verify large image renders; sidebar / tree may appear a beat later (acceptable).
2. Click sidebar entry → tree responds.
3. Right-click large image → context menu fires (right-mouse monitor installed).
4. Key shortcuts (→ arrow, space) → work.
5. Scroll wheel zoom (if enabled) → works.
6. Toggle flag off → all UI present at viewDidLoad time as before.

### - [ ] Step 5.5: Re-measure

`vc.viewDidLoad` and `file.openFromFinder.total` medians → baseline doc, `## After T5: viewDidLoad pruning`. If `vc.viewDidLoad` improvement <5%, revert.

### - [ ] Step 5.6: Commit

```bash
git add FlowVision/Sources/ViewController.swift \
        docs/superpowers/specs/2026-05-23-startup-perf-baseline.md
git commit -m "perf: defer non-critical viewDidLoad work to viewDidAppear"
```

---

## Task 6 — Fix unit 4: storyboard split (optional, highest risk)

**Defer this task unless prior fix units leave >150 ms in `window.storyboardInstantiate`.** Storyboard refactoring is fragile and AppKit-version-sensitive.

If skipped, document in baseline doc: `## T6 skipped: insufficient remaining cost in window.storyboardInstantiate`.

### - [ ] Step 6.1: Evaluate skip

Inspect baseline doc. If `window.storyboardInstantiate` median <150 ms after T3+T4+T5, skip. Commit a note:

```bash
echo "## T6: skipped (storyboardInstantiate <150ms after T3-T5)" >> docs/superpowers/specs/2026-05-23-startup-perf-baseline.md
git add docs/superpowers/specs/2026-05-23-startup-perf-baseline.md
git commit -m "docs: skip storyboard split fix unit (insufficient remaining cost)"
```

Proceed to Task 7.

### - [ ] Step 6.2 (only if not skipped): Identify Main.storyboard scenes

Open `FlowVision/Resources/Main.storyboard` in Xcode. List scenes/window controllers present. Identify scenes used during launch-from-file vs settings/secondary panels.

### - [ ] Step 6.3 (only if not skipped): Split into `Secondary.storyboard`

Move secondary-panel scenes to a new `Secondary.storyboard`. Wire any `instantiateController(withIdentifier:)` callers to load from the appropriate storyboard.

### - [ ] Step 6.4 (only if not skipped): Build, test, measure, commit

Full smoke test (Settings, Profiles, Tagging). Measure `window.storyboardInstantiate` decrease. If <10% gain or any crash, revert.

---

## Task 7 — Fix unit 5: launch-from-file fast path

Decode image on background queue, show window, defer folder scan.

**Files:**
- Modify: `FlowVision/Sources/AppDelegate.swift` (lines 424–488, `application(openFiles:)`)
- Modify: `FlowVision/Sources/ViewControllerExtension/LargeImage.swift` (lines 469–488, `OpenLargeImageFromFinder`)

### - [ ] Step 7.1: Reorder `application(openFiles:)`

Modify `FlowVision/Sources/AppDelegate.swift` lines 424–488. Inside the "Open in new window" branch (the existing `if true || windowControllers.count == 0` block, lines 449–467), when `!isDirectory`:

```swift
// fast path: window + image first, folder scan after first frame
globalVar.isLaunchFromFile = true
if windowControllers.count == 0 || globalVar.autoHideToolbar {
    globalVar.useCreateWindowShowDelay = true
}
guard let targetWindowController = createNewWindow(file) else { return }

if globalVar.fastStartupEnabled {
    openImageInTargetWindow_FastPath(file, windowController: targetWindowController)
} else {
    openImageInTargetWindow(file, windowController: targetWindowController)
}
return
```

Then add a new `openImageInTargetWindow_FastPath`:

```swift
func openImageInTargetWindow_FastPath(_ openPath: String, windowController: NSWindowController) {
    guard let viewController = windowController.contentViewController as? ViewController else { return }
    let folderPath = getFileSchemeAbsParentFolderPath(openPath)
    let path = getFileSchemeAbsPath(openPath)

    viewController.publicVar.openFromFinderPath = path
    viewController.OpenLargeImageFromFinder(path: path)

    // Folder enumeration runs after the large image is on screen.
    NotificationCenter.default.addObserver(
        forName: .didShowLargeImageFromLaunch,
        object: viewController,
        queue: .main
    ) { [weak viewController] _ in
        DispatchQueue.global(qos: .utility).async {
            DispatchQueue.main.async {
                viewController?.switchDirByDirection(direction: .zero, dest: folderPath, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
            }
        }
    }
}
```

(`Notification.Name.didShowLargeImageFromLaunch` defined in Step 7.3.)

### - [ ] Step 7.2: Define notification name

Modify `FlowVision/Sources/Common/StartupTiming.swift`. Append at file end:

```swift
extension Notification.Name {
    static let didShowLargeImageFromLaunch = Notification.Name("app.flowvision.didShowLargeImageFromLaunch")
}
```

### - [ ] Step 7.3: Post notification after first frame

Modify `FlowVision/Sources/ViewControllerExtension/LargeImage.swift` `OpenLargeImageFromFinder` (line 469).

After the existing body (after the comment `// setWindowTitleOfLargeImage(file: item.file)` at line 487), add:

```swift
DispatchQueue.main.async { [weak self] in
    guard let self = self else { return }
    NotificationCenter.default.post(name: .didShowLargeImageFromLaunch, object: self)
}
```

(The `spEnd(.fileOpenFromFinderTotal)` added in T1.7 stays here too — it's the same dispatch point, but they're separate `async` blocks for clarity.)

### - [ ] Step 7.4: Build & test

`xcodebuild ... build`. Expect BUILD SUCCEEDED.

Manual:
1. Cold-launch from PNG. Confirm window + large image appear. After ~100 ms folder list populates underneath.
2. Press →: navigates to next sibling (folder enum must have completed).
3. Press → again immediately after launch (within 50 ms of first frame): should still work or no-op gracefully (no crash). If crash, add a guard in arrow-key handler checking that folder enum has run.
4. Launch from folder (not file) → unchanged behavior.
5. Toggle flag off → legacy synchronous path.

### - [ ] Step 7.5: Re-measure

`file.openFromFinder.total` median per file type → baseline doc `## After T7: launch-from-file fast path`. Required: ≥40% reduction vs Stage 1 baseline (this is the acceptance metric per spec §7).

If <40% reduction, investigate top remaining span. Possibly the decode itself dominates and architecture cannot help further — note in baseline doc.

### - [ ] Step 7.6: Commit

```bash
git add FlowVision/Sources/AppDelegate.swift \
        FlowVision/Sources/ViewControllerExtension/LargeImage.swift \
        FlowVision/Sources/Common/StartupTiming.swift \
        docs/superpowers/specs/2026-05-23-startup-perf-baseline.md
git commit -m "perf: launch-from-file shows window before folder scan"
```

---

## Task 8 — Fix unit 6: FFmpeg warm + linker audit

**Files:**
- Modify: `FlowVision/Sources/Common/FFmpegKit.swift`
- Modify: `FlowVision/Sources/Common/StartupBootstrap.swift`
- Modify: `FlowVision.xcodeproj/project.pbxproj` (Release `DEAD_CODE_STRIPPING`)

### - [ ] Step 8.1: Add `warmLoadAfterDelay`

Modify `FlowVision/Sources/Common/FFmpegKit.swift` after the existing `loadFFmpegKitIfNeeded()` (line 53):

```swift
func warmLoadAfterDelay(seconds: Double) {
    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + seconds) { [weak self] in
        self?.loadFFmpegKitIfNeeded()
    }
}
```

### - [ ] Step 8.2: Verify `StartupBootstrap` already calls it

Already done in Task 4.3. Re-confirm:

```swift
static func scheduleBackground() {
    DispatchQueue.global(qos: .utility).async {
        FFmpegKitWrapper.shared.warmLoadAfterDelay(seconds: 2.0)
    }
}
```

### - [ ] Step 8.3: Enable DEAD_CODE_STRIPPING

Verify current value:

```bash
grep -n "DEAD_CODE_STRIPPING" FlowVision.xcodeproj/project.pbxproj
```

If absent or `NO` for Release, edit `project.pbxproj` Release buildSettings block (or open Xcode → FlowVision target → Build Settings → search "Dead Code Stripping") → set `DEAD_CODE_STRIPPING = YES` Release. Debug can stay `NO`.

### - [ ] Step 8.4: Audit `OTHER_LDFLAGS`

```bash
grep -n "OTHER_LDFLAGS" FlowVision.xcodeproj/project.pbxproj
```

Inspect for `-framework <Name>` entries. Compare to actually-imported frameworks (`grep -rn "^import " FlowVision/Sources | sort -u`). **Do not remove anything without verification** — many frameworks are loaded indirectly (e.g., from Storyboard or Objective-C runtime).

If any entry is clearly unused (e.g., a removed dependency), remove and rebuild. If unsure, leave it.

### - [ ] Step 8.5: Build Release & test

`xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`. Expect BUILD SUCCEEDED.

Manual:
1. Cold-launch from PNG → confirm normal behavior.
2. Open a `.mkv` video (non-native, requires FFmpeg) → confirm it plays. (Tests warm path.)
3. Set `doNotUseFFmpeg = true` in defaults, relaunch, open `.mkv` → confirm fallback message (no crash).

### - [ ] Step 8.6: Re-measure

`file.openFromFinder.total` (PNG and video) medians → baseline doc `## After T8: FFmpeg warm + linker`. Pre-main / dyld time isn't captured by our spans — measure full launch by Activity Monitor or instruments if curious.

### - [ ] Step 8.7: Commit

```bash
git add FlowVision/Sources/Common/FFmpegKit.swift \
        FlowVision/FlowVision.xcodeproj/project.pbxproj \
        docs/superpowers/specs/2026-05-23-startup-perf-baseline.md
git commit -m "perf: warm-load FFmpeg off main; enable DEAD_CODE_STRIPPING in Release"
```

---

## Task 9 — Cleanup (after one stable release cycle)

**Defer until at least one full release with all units stable.** Skip if any unit was reverted.

### - [ ] Step 9.1: Remove legacy else branches

Remove every `if globalVar.fastStartupEnabled { ... } else { legacy code }` introduced in T3, T4, T5, T7. Keep the `if`-branch contents only.

### - [ ] Step 9.2: Remove `globalVar.fastStartupEnabled`

Remove the property from `GlobalVariable.swift`, remove the defaults wiring in `AppDelegate.swift`, remove the user-defaults migration (delete the key if set).

### - [ ] Step 9.3: Remove `setupDeferredUI_legacy()`

Delete the legacy helper added in T5.3.

### - [ ] Step 9.4: Build, full smoke test, commit

```bash
git commit -m "refactor: remove fastStartupEnabled flag after stable release"
```

---

## Acceptance Summary

Per spec §7:
- Baseline captured (T2.4).
- `file.openFromFinder.total` median (median of 5 cold runs per file type) ≥40% lower vs baseline after T7. Recorded in `docs/superpowers/specs/2026-05-23-startup-perf-baseline.md`.
- Each fix unit gates on its own ≥5% measured improvement of the span it targets, else reverted.
- Per-unit rollback available via `git revert` and via `defaults write app.flowvision fastStartupEnabled -bool NO`.

---

## Self-Review Notes

Coverage check vs spec:
- §1 Goal — Task 1, 7 — ✓
- §2 Pipeline — Task 1 (instruments observed pipeline) — ✓
- §3 Target pipeline — Task 4, 5, 7 — ✓
- §4 Stage 1 instrumentation — Task 1 — ✓
- §4 Stage 2 units 1–6 — Tasks 3, 4, 5, 6, 7, 8 — ✓
- §5 New files — Tasks 1, 3, 4 — ✓
- §5 Feature flag — Task 2 — ✓
- §6 Error handling — covered in each task's manual test step
- §7 Testing matrix — Task 2.3 + each fix unit's manual test
- §8 Rollout order — task order matches
- §9 Rollback — flag toggle steps included in tests; Task 9 final removal — ✓

No placeholders ("TBD", "implement later") in any step.
Type names verified: `PublicVar` reference flagged in T3.2 for verification before edit. `FFmpegKitWrapper.shared`, `CustomTagView.userDefaultsKey`, `FinderTag.customLabels`, `FinderTag.systemColorLabels` all match existing usage in `AppDelegate.swift`.
