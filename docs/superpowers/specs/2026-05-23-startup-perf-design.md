# FlowVision Startup Performance — Design

**Date:** 2026-05-23
**Status:** Approved (pending user spec review)
**Branch (origin):** `feat-shortcuts`

## 1. Goal & Scope

Make **launch-from-file** (Finder "Open With → FlowVision" on a single image) feel ultra-fast: measurable reduction in time from icon click to large image visible on screen. Cold-start optimization first; warm-start improvements should follow for free.

**Out of scope:** launch-into-folder (only touched if a fix obviously helps both), in-app folder switch, thumbnail generation, video player.

**Success criteria:**
- Baseline captured (median of 5 cold runs per file type).
- Post-fix median ≥40% lower on the dominant span (`file.openFromFinder.total`).
- Stretch: large-image visible within ~300 ms of icon click on a recent Mac.

## 2. Current Pipeline (Observed)

Findings from `AppDelegate.swift`, `ViewController.swift`, `LargeImage.swift`, `FFmpegKit.swift`:

- `applicationWillFinishLaunching` runs ~30 synchronous `UserDefaults.standard.value(forKey:)` reads on main (lines 96–225).
- `ViewController.viewDidLoad` runs another ~30 synchronous defaults reads (lines 538+) plus full collection/outline/split/drawing-view setup.
- `Main.storyboard` instantiated synchronously inside `createNewWindow`.
- `EnhancedIndex.initialize()` already dispatched to `.userInitiated` queue — good.
- `FFmpegKitWrapper` already lazy via `dlopen` (`LOAD_WHEN_USE=true`) — good.
- `Settings` window controller already `lazy` — good.
- `application(openFiles:)` calls `createNewWindow(file)` then `openImageInTargetWindow(file, …)` which calls `OpenLargeImageFromFinder` and dispatches `switchDirByDirection` (folder enumeration for sibling nav) on main async.

Critical-path sequence today (all main thread):

```
willFinishLaunching ███
  ├─ ShortcutStore.load
  ├─ THUMB_SIZES generate
  ├─ ~30 UserDefaults reads
  ├─ FinderTag custom labels load
  ├─ menu delegates hooked, EnhancedIndex.initialize (async — OK)

didFinishLaunching ███
  └─ createNewWindow() — empty window
        ├─ storyboard instantiate ███
        ├─ viewDidLoad ███ (~30 more defaults + view setup)

application(openFiles:) ███
  ├─ createNewWindow(file) ███ (second window, same heavy storyboard)
  ├─ OpenLargeImageFromFinder
  └─ switchDirByDirection (folder enum) ███
                                            ▼
                                large image visible
```

## 3. Target Pipeline

```
willFinishLaunching ███ (slim)
  ├─ batched defaults read (one call)
  ├─ ShortcutStore.load
  ├─ EnhancedIndex.initialize (already async)
  │  ┌──────────────────────────────────────────┐
  │  │ background (qos:.utility)                │
  │  │  • FinderTag labels                      │
  │  │  • THUMB_SIZES lazy on first access      │
  │  │  • menu delegates on demand              │
  │  │  • FFmpegKit warm dlopen (.background)   │
  │  └──────────────────────────────────────────┘

didFinishLaunching ███ (slim)
  └─ if openFiles already queued → fast path
        ├─ storyboard instantiate (minimal scene)
        ├─ viewDidLoad_Minimal: largeImageView + window only
        ├─ background: decode image
        ├─ main: assign image → window orderFront
        └─ post-paint async:
              ├─ folder enum
              ├─ tree / outline / collection setup
              ├─ remaining defaults reads
                                            ▼
                                sibling navigation ready
```

Critical-path budget:

| Span | Now (est) | Target |
|---|---|---|
| willFinish | 50–100 ms | <20 ms |
| storyboard + minimal viewDidLoad | 100–200 ms | <60 ms |
| image decode | varies | unchanged (off-main) |
| first frame total | sum above | ≤300 ms |

## 4. Stages

### Stage 1 — Instrumentation (lands first, no flag)

Add timing helper using `OSSignposter` (macOS 12+) plus existing `log()`. Span IDs:

- `app.willFinish`, `app.willFinish.defaultsLoad`, `app.didFinish`
- `window.create`, `window.storyboardInstantiate`
- `vc.viewDidLoad`, `vc.viewDidLoad.defaultsLoad`
- `file.openFromFinder.total` (from `application(openFiles:)` entry to large-image first-frame)
- `file.openLargeImage.decode`
- `file.switchDir.scan`

Capture baseline: 5 cold runs × {PNG, JPG, HEIC, RAW (CR2/NEF), animated GIF, WEBP, video}. Record medians in `docs/superpowers/specs/2026-05-23-startup-perf-baseline.md`.

### Stage 2 — Fix units (ordered, each behind `fastStartupEnabled`)

1. **Defaults batch read** — replace 60+ `value(forKey:)` calls in `AppDelegate.applicationWillFinishLaunching` and `ViewController.viewDidLoad` with a single batched read into a struct.
2. **AppDelegate slimming** — move FinderTag labels load, menu hookups, and other non-critical bootstrap off `applicationWillFinishLaunching`. Make `THUMB_SIZES` a static lazy constant.
3. **viewDidLoad pruning** — move outlineView/collectionView/splitView/drawing-view setup behind `setupDeferredUI()` called from `viewDidAppear`.
4. **Storyboard split** — pull rarely-needed bits out of `Main.storyboard` so launch-from-file loads a minimal scene.
5. **Launch-from-file fast path** — restructure `application(openFiles:)`: decode on background queue → show window with image → folder enum + sibling list async after first frame.
6. **FFmpeg async + linker audit** — `warmLoadAfterDelay`; `DEAD_CODE_STRIPPING = YES` Release; audit `Base.xcconfig` `OTHER_LDFLAGS` for unused `-framework` entries.

Each unit gates on its measured win — revert if <5% of its span.

## 5. Components

### New files

**`Sources/Common/StartupTiming.swift`** (~80 lines)
- `enum StartupSpan: String` — cases match span IDs above.
- `func spBegin(_:)` / `spEnd(_:)` using `OSSignposter` + `log()` bridge.
- `func spMeasure<T>(_:, _: () throws -> T) rethrows -> T` wrapper.

**`Sources/Common/Defaults+Batch.swift`** (~60 lines)
- `struct AppStartupDefaults` — every defaults key + default value.
- `static func loadFromUserDefaults() -> AppStartupDefaults` — one `dictionaryRepresentation()` call.
- `func apply(toGlobalVar:)` — assigns to `globalVar` in one shot on main.

### Modified files

**`Sources/AppDelegate.swift`**
- Slim `applicationWillFinishLaunching`: `ShortcutStore.shared.load()` + `AppStartupDefaults` apply + schedule background bootstrap.
- New `createNewWindow_FastPath(file:)` for finder-launch single-image.
- `THUMB_SIZES` → `ThumbSizes.values` (static lazy).
- Menu delegates hooked from `applicationDidFinishLaunching`.

**`Sources/ViewController.swift`**
- `viewDidLoad`: pull config from `globalVar` only, no inline defaults reads.
- `setupDeferredUI()` called from `viewDidAppear` first-call.
- Launch-from-file path: minimal `viewDidLoad` (only `largeImageView`, `largeImageBgEffectView`, bounds).

**`Sources/ViewControllerExtension/LargeImage.swift`**
- `OpenLargeImageFromFinder(path:)`: decode on `.userInitiated` queue → main thread set image + un-hide → post `didShowLargeImageFromLaunch`.
- Folder enumeration (`switchDirByDirection`) dispatched to `.utility` after that notification.

**`Sources/Common/FFmpegKit.swift`**
- `warmLoadAfterDelay(seconds:)` — dispatch `loadFFmpegKitIfNeeded` on `.background` queue.

**Build settings (`Base.xcconfig` / Release)**
- `DEAD_CODE_STRIPPING = YES` (verify not already set).
- Audit `OTHER_LDFLAGS` for unused `-framework` entries (no removal without verification).

### Feature flag

- `globalVar.fastStartupEnabled` (default `true`, hidden Advanced Settings toggle).
- All Stage 2 changes branch on it.
- Removed once stable for one release cycle.

## 6. Error Handling

- Defaults batch read: malformed key falls back to default value (same semantics as today's `if let ... as? Type`). No throws.
- Background image decode: existing decode error paths preserved; on failure window still shows (current behavior).
- Background bootstrap tasks (FFmpeg warm, FinderTag labels, deferred UI): each in its own `DispatchWorkItem`; failures logged via `log()`, not surfaced.
- Fast-path window keeps current `fatalError` on missing `WindowController` identifier — same as today.
- Feature flag off → entire pre-existing code path runs unchanged.

## 7. Testing

No automated UI tests today; matching that.

Manual matrix per fix unit:

1. Cold launch (`killall FlowVision`, wait 30 s) via Finder "Open With" for PNG, JPG, HEIC, RAW (CR2/NEF), animated GIF, WEBP, video file (internal player on).
2. Cold launch via app icon (no file).
3. Warm launch variants of (1).
4. Multi-tab: open second file with one window already up.
5. CLI: `open ./img.jpg`, `open .`.
6. Toggle `fastStartupEnabled` off → confirm old behavior intact.
7. Sibling navigation (→/←) after fast path.
8. Settings window opens, no missing IBOutlet crash.
9. `Instruments → Allocations` 30 s after launch — compare to baseline.

**Acceptance:** `file.openFromFinder.total` median (5 runs) ≥40% lower than baseline per file type. Numbers recorded in `2026-05-23-startup-perf-baseline.md`.

## 8. Rollout

1. Stage 1 (instrumentation) lands first in `main`. No flag.
2. Capture baseline; commit to spec dir.
3. Stage 2 units land one per commit/PR, behind `fastStartupEnabled`:
   1. Defaults batch
   2. AppDelegate slimming
   3. viewDidLoad pruning
   4. Storyboard split (may be deferred — highest risk)
   5. Launch-from-file fast path
   6. FFmpeg async + linker audit
4. Re-measure after each unit. Revert if <5% gain on its span.
5. After one stable release cycle: delete flag, delete legacy code paths.

## 9. Rollback

- Per-unit: revert one commit.
- User-facing: hidden Advanced Settings toggle disables fast path without reinstall.
