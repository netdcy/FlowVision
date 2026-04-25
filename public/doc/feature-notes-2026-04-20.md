# FlowVision Feature Notes (2026-04-20)

## Overview

This note summarizes the recent file-action and archive-related features added to FlowVision.

## Custom folder copy shortcuts

- `Photo Folder 1` keeps the existing behavior for quick-copying selected items.
- `Video Folder 2` is added for copying videos to a second configured folder.
- Both folder actions are configured from the `Actions` settings pane.
- `Folder 2` works in two contexts:
  - collection view: copies selected video files
  - large video view: copies the current video file

## Shortcut routing

- Shortcut handling stays inside `KeyShortcut.swift`.
- Folder shortcuts are checked before built-in no-modifier shortcuts.
- This means a custom folder shortcut can intentionally override a built-in key.
- To reduce accidental conflicts:
  - `Video Folder 2` default was moved from `F` to `F4`
  - the settings pane now shows a built-in shortcut reference
  - the settings pane also shows warning text when Folder 1 / Folder 2 use the same key or override a built-in action

## Supported custom shortcut candidates

- Letters: `A-Z`
- Digits: `0-9`
- Punctuation currently exposed in settings: `=`, `-`, `,`, `.`, `[`, `]`
- Function keys: `F1-F12`

## Folder copy implementation details

- Physical files are copied with the existing pasteboard + paste flow to stay aligned with current app behavior.
- Virtual archive entries are copied without extracting the whole archive:
  - parse the virtual archive path
  - stream the selected entry via `bsdtar -xOf`
  - write bytes directly to the destination file
- Copy completion reuses the existing bottom-right toast overlay.

## Archive browsing

- Archive browsing still uses the virtual-folder model:
  - archive file path is converted to a virtual archive root
  - archive entry listing is resolved with `bsdtar -tf`
  - image bytes are streamed per-entry when needed
- This avoids creating a temporary extracted directory for browsing image content.

## Archive extraction actions

- New context-menu actions were added for archive files:
  - `解压到当前目录`
  - `解压并删除压缩包`
- These actions are available in:
  - collection item context menu
  - outline/tree context menu

## Archive extraction behavior

- Extraction is implemented in `FileOperation.swift`.
- Supported archive inputs reuse the existing `isSupportedArchiveURL(...)` check.
- Extraction uses `/usr/bin/bsdtar` with:

```bash
bsdtar -xf <archive> -C <destination-folder>
```

- Each archive is extracted into a unique sibling folder named from the archive base name.
- Multi-part names such as `.tar.gz`, `.tar.bz2`, and `.tar.xz` are stripped correctly when generating the destination folder name.
- When `解压并删除压缩包` is chosen, the source archive is moved to Trash after successful extraction.

## Current tradeoffs

- Custom folder shortcuts can still override built-in keys if the user explicitly chooses them.
- The settings pane warns about those conflicts, but does not hard-block the choice.
- Archive extraction currently runs synchronously and does not yet show a dedicated progress overlay.
