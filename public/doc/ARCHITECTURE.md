# FlowVision 项目架构文档

## 项目概述

FlowVision 是一款 macOS 瀑布流风格图片查看器，支持图片和视频浏览，具有以下特性：
- 自适应布局模式，支持明暗主题
- 便捷的文件管理（类似 Finder）
- 右键手势快速导航
- 大量图片目录的性能优化
- 高质量缩放
- 视频播放支持
- HDR 显示支持
- 递归浏览模式

## 快速导航

仓库级修改规则和构建命令见 [`AGENTS.md`](../../AGENTS.md)。定位代码时先搜索下列稳定锚点，避免通读大型扩展文件。

| 场景 | 调用入口 / 核心锚点 | 主要文件 |
|---|---|---|
| 批量重命名 | `actBatchRenameSelectedItems` → `handleBatchRenameSelectedItems` | `Views/CustomCollectionViewItem.swift`、`Views/CustomOutlineView.swift`、`ViewControllerExtension/FileOperation.swift` |
| 快捷重命名当前目录 | `handleQuickRenameInCurrentFolder` → `executeFileRenameMappingsAsync` | `ViewControllerExtension/FileOperation.swift` |
| 原位更新名称 | `applyRenameMappingsInPlace` | `ViewControllerExtension/FileOperation.swift` |
| 配置目录异步复制 | `handleCopyToPhotoFolder1` / `handleCopySelectedVideosToPhotoFolder2` → `handleCopyToConfiguredFolder` | `ViewControllerExtension/KeyShortcut.swift`、`ViewControllerExtension/FileOperation.swift` |
| 文件系统刷新与定位 | `scheduledRefresh` → `selectItemsNewChanged` | `ViewController.swift`、`ViewControllerExtension/FileSystem.swift` |
| 播放状态 | `currentPlayingURL`、`restorePlayURL` | `ViewController.swift`、`Views/LargeImageView.swift`、`Views/CustomCollectionViewItem.swift` |
| 邻近媒体预热 | `preloadLargeImage` → `MediaPreheatManager` | `ViewControllerExtension/LargeImage.swift`、`Common/VideoProcess.swift` |
| FFmpeg | `FFmpegKit` | `Common/FFmpegKit.swift` |

常用定位命令：

```bash
rg -n 'handleQuickRenameInCurrentFolder|applyRenameMappingsInPlace' FlowVision/Sources
rg -n 'handleCopyToConfiguredFolder|isInFileOperation' FlowVision/Sources
rg -n 'currentPlayingURL|restorePlayURL' FlowVision/Sources
```

## 系统要求

- macOS 11.0 或更高版本
- Xcode 15.2+

## 目录结构

```
FlowVision/
├── FlowVision.xcodeproj          # Xcode 项目文件
├── FlowVision/
│   ├── Info.plist                # 应用程序配置
│   ├── FlowVision.entitlements   # 应用权限配置
│   ├── Resources/                # 资源文件
│   │   ├── Assets.xcassets/      # 图片资源
│   │   ├── Base.lproj/           # 基础本地化资源
│   │   ├── mul.lproj/            # 多语言本地化资源
│   │   ├── Localizable.xcstrings # 本地化字符串
│   │   └── icon.png              # 应用图标
│   └── Sources/                  # 源代码目录
│       ├── AppDelegate.swift     # 应用程序代理
│       ├── ViewController.swift  # 主视图控制器
│       ├── WindowController.swift # 窗口控制器
│       ├── Common/               # 公共模块
│       ├── Views/                # 视图组件
│       ├── ViewControllerExtension/ # 视图控制器扩展
│       └── SettingsViews/        # 设置界面
├── docs/                         # 文档目录
├── public/                       # 公共资源
├── build_dmg.sh                  # DMG 打包脚本
├── Base.xcconfig                 # 基础配置
└── LocalDev.xcconfig.template    # 本地开发配置模板
```

## 核心模块说明

### 1. 入口文件

| 文件 | 说明 |
|------|------|
| `AppDelegate.swift` | 应用程序入口，处理应用生命周期、全局状态管理、菜单配置等 |
| `ViewController.swift` | 主视图控制器，核心业务逻辑，管理图片展示、用户交互 |
| `WindowController.swift` | 窗口控制器，管理窗口行为、标题栏、工具栏等 |

### 2. Common 模块 (`Sources/Common/`)

公共工具和数据模型，被其他模块共享使用。

| 文件 | 大小 | 说明 |
|------|------|------|
| `Common.swift` | 40KB | 通用工具函数、扩展方法、辅助功能 |
| `DataModel.swift` | 41KB | 数据模型定义，包含排序键、文件项模型等 |
| `ImageProcess.swift` | 106KB | 图片处理核心逻辑，缩略图生成、图片解码等 |
| `VideoProcess.swift` | 3KB | 视频处理相关功能 |
| `FFmpegKit.swift` | 7KB | FFmpeg 集成封装 |
| `FinderTag.swift` | 31KB | macOS Finder 标签功能集成 |
| `Log.swift` | 12KB | 日志系统 |
| `GlobalVariable.swift` | 9KB | 全局变量和配置 |
| `Enum.swift` | 1KB | 枚举定义（文件类型、排序类型、布局类型等） |
| `RefCode.swift` | 1KB | 引用代码 |
| `TempVariable.swift` | 0.1KB | 临时变量 |

#### 关键枚举定义 (`Enum.swift`)

```swift
// 文件类型
enum FileType: Int, Codable {
    case image, video, other, folder, notSet, all
}

// 右键手势方向
enum RightMouseGestureDirection: Int, Codable {
    case right, left, up, down, up_right, up_left, down_left, down_right, zero, forward, back
}

// 布局类型
enum LayoutType: Int, Codable {
    case justified, waterfall, grid, detail
}

// 排序类型
enum SortType: Int, Codable {
    case pathA, pathZ, extA, extZ, sizeA, sizeZ,
         createDateA, createDateZ, modDateA, modDateZ,
         addDateA, addDateZ, random, exifDateA, exifDateZ,
         exifPixelA, exifPixelZ
}
```

### 3. Views 模块 (`Sources/Views/`)

自定义视图组件，负责 UI 渲染。

| 文件 | 大小 | 说明 |
|------|------|------|
| `CustomCollectionView.swift` | 18KB | 自定义集合视图，瀑布流布局核心 |
| `CustomCollectionViewItem.swift` | 76KB | 集合视图单元格，缩略图显示 |
| `CustomOutlineView.swift` | 23KB | 目录树视图 |
| `CustomOutlineViewManager.swift` | 16KB | 目录树管理器 |
| `LargeImageView.swift` | 116KB | 大图查看视图 |
| `ImageEditingView.swift` | 34KB | 图片编辑视图 |
| `CoreAreaView.swift` | 12KB | 核心区域视图 |
| `Layout.swift` | 12KB | 布局管理 |
| `CustomImageView.swift` | 8KB | 自定义图片视图 |
| `CustomProfileView.swift` | 23KB | 配置文件视图 |
| `FavoritesPopoverViewController.swift` | 17KB | 收藏夹弹出视图 |
| `DrawingView.swift` | 5KB | 绘图视图 |
| `CustomSplitView.swift` | 2KB | 自定义分割视图 |
| `CustomPathControl.swift` | 0.2KB | 路径控件 |
| `CustomEffectView.swift` | 2KB | 自定义效果视图 |
| `CustomCollectionViewManager.swift` | 6KB | 集合视图管理器 |
| `CustomCollectionViewItem.xib` | 5KB | 界面布局文件 |

### 4. ViewControllerExtension 模块 (`Sources/ViewControllerExtension/`)

视图控制器功能扩展，按职责分离代码。

| 文件 | 大小 | 说明 |
|------|------|------|
| `FileOperation.swift` | 93KB | 文件操作（复制、移动、删除、重命名等） |
| `KeyShortcut.swift` | 52KB | 键盘快捷键处理 |
| `FileSystem.swift` | 76KB | 文件系统操作、目录遍历 |
| `LargeImage.swift` | 47KB | 大图查看功能 |
| `EventHandler.swift` | 27KB | 事件处理 |
| `Search.swift` | 25KB | 搜索功能 |
| `WindowManagement.swift` | 19KB | 窗口管理 |
| `ArrowKeyLocate.swift` | 13KB | 方向键导航 |
| `DirTree.swift` | 7KB | 目录树操作 |
| `AutoScrollPlay.swift` | 5KB | 自动滚动播放 |
| `RightMouseGesture.swift` | 6KB | 右键手势识别 |
| `ProgressBar.swift` | 9KB | 进度条显示 |
| `MemoryManagement.swift` | 3KB | 内存管理 |
| `LayoutManagement.swift` | 11KB | 布局管理 |
| `LayoutProfileConfig.swift` | 6KB | 布局配置文件管理 |

### 5. SettingsViews 模块 (`Sources/SettingsViews/`)

设置界面相关视图。

| 文件 | 说明 |
|------|------|
| `GeneralSettingsViewController.swift` | 通用设置（启动、外观等） |
| `ActionsSettingsViewController.swift` | 操作设置（快捷键、手势等） |
| `CustomSettingsViewController.swift` | 自定义设置 |
| `AdvancedSettingsViewController.swift` | 高级设置（性能、内存等） |
| `TaggingSettingsViewController.swift` | 标签设置 |
| `DemoSettingsViewController.swift` | 演示设置 |

## 架构设计

### MVC 架构

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                       │
│  ┌─────────────────┐                                        │
│  │  AppDelegate    │ ← 应用入口、全局状态、菜单管理           │
│  └─────────────────┘                                        │
├─────────────────────────────────────────────────────────────┤
│                     Controller Layer                         │
│  ┌─────────────────┐  ┌──────────────────────┐             │
│  │ WindowController│  │   ViewController     │             │
│  │                 │  │   (Main Controller)  │             │
│  └─────────────────┘  └──────────────────────┘             │
│                              │                              │
│              ┌───────────────┼───────────────┐             │
│              ↓               ↓               ↓             │
│  ┌────────────────┐ ┌─────────────┐ ┌──────────────┐      │
│  │ FileOperation  │ │ KeyShortcut │ │ EventHandler │ ...  │
│  └────────────────┘ └─────────────┘ └──────────────┘      │
├─────────────────────────────────────────────────────────────┤
│                        View Layer                            │
│  ┌────────────────────┐  ┌────────────────────┐            │
│  │ CustomCollectionView│  │  CustomOutlineView │            │
│  │ (瀑布流缩略图)       │  │  (目录树)          │            │
│  └────────────────────┘  └────────────────────┘            │
│  ┌────────────────────┐  ┌────────────────────┐            │
│  │   LargeImageView   │  │ ImageEditingView   │            │
│  │   (大图查看)        │  │ (图片编辑)          │            │
│  └────────────────────┘  └────────────────────┘            │
├─────────────────────────────────────────────────────────────┤
│                        Model Layer                           │
│  ┌─────────────────────────────────────────────┐           │
│  │ DataModel.swift (SortKey, FileItem等)       │           │
│  │ GlobalVariable.swift (GlobalVar)            │           │
│  └─────────────────────────────────────────────┘           │
├─────────────────────────────────────────────────────────────┤
│                     Service Layer                            │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────────┐       │
│  │ImageProcess │ │ VideoProcess │ │  FinderTag     │       │
│  └─────────────┘ └──────────────┘ └────────────────┘       │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────────┐       │
│  │ FileSystem  │ │   Log        │ │   FFmpegKit    │       │
│  └─────────────┘ └──────────────┘ └────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### 数据流向

```
用户操作 → EventHandler/KeyShortcut
                ↓
         ViewController
                ↓
    ┌───────────┼───────────┐
    ↓           ↓           ↓
FileOperation  Search    FileSystem
    ↓           ↓           ↓
    └───────────┼───────────┘
                ↓
         DataModel 更新
                ↓
         View 刷新
```

## 文件操作、线程与刷新策略

### 重命名调用链

```text
缩略图/目录树菜单                         当前目录快捷键
        │                                      │
        ▼                                      ▼
handleBatchRenameSelectedItems     handleQuickRenameInCurrentFolder
        │                                      │
预览表格（原名称 / 新名称）             后台生成重命名计划
        └──────────────┬───────────────────────┘
                       ▼
 executeFileRenameMappings / executeFileRenameMappingsAsync
                       │
        冲突预检 → 临时名 → 最终名 → 失败回滚
                       │
             更新 Enhanced Index 与 Undo
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
 applyRenameMappingsInPlace    条件不满足的兜底刷新
 路径/名称/排序原位更新          scheduledRefresh + 恢复滚动
```

批量重命名支持前缀、后缀、查找替换，以及 `{name}`、`{index}`、`{index:03}`、`{folder}`、`{ext}` 等变量。确认前使用两列表格展示原名称和新名称。执行器采用两阶段临时路径，避免交换名称或排序链式重命名互相覆盖。

SMB 重命名前通过 `NetworkIOCoordinator` 前台租约暂停新的可选读取，并清空当前窗口邻项预热；不停止播放器。单项 SMB 改名也走后台执行。`RenameIO` 仅在后台对 `EBUSY/EAGAIN` 最多尝试 3 次，拒绝对权限错误及超时、断连等结果不确定的错误自动重试。错误保留来源/目标路径和底层错误码。最终阶段失败时，先将已完成目标退回各自临时名，再恢复全部源名，避免名称交换时回滚互相占位；恢复失败保留文件并报告路径。

2026-09-06 在 FODE 同一父目录的独立临时目录完成消融：无打开句柄时两阶段改名成功；保持子文件读句柄时返回 Cocoa 513 / POSIX EACCES 13；关闭句柄后成功。本地磁盘保持读句柄仍可改名。这是 SMB 文件占用也会显示“无许可”的实测证据，不代表所有权限错误均来自占用。`script/verify_rename_io.py` 验证有限重试开关、权限/不确定网络错误不重试、交换名称的各阶段回滚及本地打开文件往返；实际应用中的播放和预热释放仍需运行新版验收。


### 复制到配置目录

图片目录 1 与视频目录 2 共用 `handleCopyToConfiguredFolder`：

```text
快捷键/菜单
  → 收集并校验 URL、目标目录、自复制关系（主线程）
  → FileManager.copyItem、重名避让、进度统计（后台队列）
  → 状态复位、错误提示、目标定位与刷新（主线程）
```

该路径不依赖 Finder 剪贴板。调用方包括 `handleCopyToPhotoFolder1`、`handleCopySelectedVideosToPhotoFolder2` 和当前视频复制入口。

### 线程约定

| 工作 | 所在线程 |
|---|---|
| 文件枚举、批量冲突检查、复制、两阶段重命名、Enhanced Index 更新 | 后台队列 |
| NSAlert、进度控件、collection/outline view、窗口标题、UndoManager | 主线程 |
| `publicVar.isInFileOperation` 的生命周期切换 | 主线程统一管理，所有退出路径复位 |

`isInFileOperation` 使文件监听刷新在应用主动操作期间让路，防止中间临时文件被扫描进模型。后台任务不得直接访问或修改 AppKit 对象。

### 刷新决策

| 变更类型 | 默认策略 | 原因 |
|---|---|---|
| 仅重命名 | `applyRenameMappingsInPlace` | 复用 `FileModel` 和现有 cell，不闪烁、不重启播放器 |
| 重命名但模型不完整/目录已切换 | `scheduledRefresh`，随后恢复滚动位置 | 确保磁盘和模型最终一致 |
| 创建、复制、移动到当前视图 | 刷新并使用 `filesForLocateAfterChange` 定位新目标 | 新文件尚未存在于当前 Map |
| 移动到视图外或移动当前目录的祖先 | 刷新并恢复滚动位置；同步改写当前目录路径 | 避免跳回顶部或显示空目录 |
| 删除、目录结构变化 | 文件系统刷新 | 需要重新枚举或更新目录树 |

删除操作按删除前的显示顺序，使用实际成功删除的路径计算最近前项；没有前项时选剩余第一项，全部删空时不选。集合视图通过 `selectionAfterDeletion` 在目标布局就绪后恢复单选与键盘焦点，目录树则导航到对应前项。删除期间用户已导航或改选时，不恢复旧选择。递归浏览与媒体单元删除也必须刷新，不能因文件数较多而保留被删项目。

### 媒体单元模式

“媒体单元模式”把用户开启时的当前目录持久化为媒体根（`isMediaUnitMode`、`mediaUnitRootPath`）。根目录只显示直属子文件夹；这些子文件夹是媒体管理单元，目录树中作为叶节点展示。打开单元时，`FileSystem` 在后台枚举该单元下的所有后代文件，将可显示文件写入该单元的 `DirModel` 并保留每个文件的真实 `file://` 路径；集合视图因此平铺显示，文件夹层级和同名文件仍可通过完整路径区分。扫描以 `fileDB.ver` 校验导航代次，切换目录后旧任务不能回写当前模型。返回上一级回到媒体根；离开根范围恢复普通目录浏览。该模式与递归浏览模式独立，不能用递归模式的刷新阈值抑制媒体单元刷新。

尺寸、缩略图与延迟界面回调使用 `isCurrentDirectoryTask` 同时核对当前路径、导航代次、模型版本及模型对象身份；仅核对旧模型自己的版本无法拦截快速返回同一单元后的旧任务。所有目录切换直接移除旧快照，不再捕获旧目录画面覆盖新列表，并在集合清空后使布局失效。

`NetworkIOCoordinator` 必须在释放内部条件锁后调用 `shouldContinue`：回调可能取得文件列表或预热器的锁，而主线程播放切换也需要协调器锁。集合项的 `configureWithImage` 可以启动／停止播放，不得在持有 `fileDB` 锁时调用，否则会出现反向加锁死锁。

原位重命名会克隆新的 `SortKeyFile` 并重建 `BTree.Map`，但继续复用 `FileModel`。可见 cell 只更新 URL、名称、tooltip 和必要的排序移动，不调用完整配置流程。大图路径、`currentPlayingURL`、`restorePlayURL`、Finder 打开路径和窗口标题同步替换，从而保留视频播放进度。

兜底刷新使用 `collectionScrollRestoreAfterRefresh` 保存当前 clip view 原点，并在 `selectItemsNewChanged(isFinal:)` 完成后恢复。快捷重命名不设置 `filesForLocateAfterChange`，否则会错误滚到第一个改名项目。

重命名引起排序变化时，选中状态按 `FileModel` 身份映射到新索引，不沿用旧索引。移动操作会同步改写当前目录、播放器和大图路径；只有目标位于当前视图时才自动定位目标，移出当前视图则保持原滚动位置。

无目标冲突的移动在后台队列执行，完成后一次性回主线程更新路径、进度和刷新状态；只有需要逐项询问覆盖、合并或自动重命名时才走交互式分支。自身/子目录判断按完整路径组件边界处理，不能用裸字符串前缀比较。

从当前视图移出项目时，刷新前记录鼠标所在拖拽项的布局位置和相邻未移动项目。刷新后以该相邻项目作为视口锚点恢复到原屏幕坐标，避免删除前序项目造成列表跳到顶部；锚点不存在时才退回保存的 clip view 原点。

集合视图开始多选拖拽时一次性缓存所有选中 URL，避免 `pasteboardWriterForItemAt` 对每个视频重复加锁查询。超过 8 个项目时不渲染每个视频缩略图/播放器作为拖拽图，而是使用单个带数量标记的轻量文件堆叠预览；pasteboard 仍保留每个文件 URL。

放下多个项目后的目标重名检查也在后台批量执行。无冲突时直接在同一后台任务完成移动；有冲突时用拖拽 URL 快照回到主线程进入原有覆盖、合并和自动重命名交互，避免对网络盘逐项同步探测。

移动与重命名在执行前统一拒绝重复来源、重复目标以及父子项目同时操作。移动“替换”先把旧目标暂存到同目录，源项目到达最终路径后才清理暂存；源移动失败时恢复旧目标。文件夹合并即使部分成功，也会记录实际完成的路径映射并刷新/更新 Enhanced Index。批量重命名在后台执行，两阶段回滚直接持有原始路径，不再依赖目标路径反查。

### FFmpeg 剪切边界

输入端 `-ss` 配合 `-c copy` 是关键帧级无损剪切，不是帧精确剪切。iPhone MOV 可能同时包含视频、多个音轨和 `mebx` data 流；无差别映射所有流会把各自的原始时间轴带入输出，可能表现为开头黑屏或容器时长异常。

- 只需要画面和声音：使用 `-map 0:v:0 -map 0:a?`，不要默认映射 data 流。
- 需要准确起止：视频重编码，并显式处理时间戳；音频可按兼容性决定复制或重编码。
- 需要无损快速导出：接受切点对齐附近关键帧，并用 `ffprobe` 同时检查 format duration 和各 stream 的 start/duration。

大图视频右键菜单的“无损分段裁剪”使用带预览和缩略图的多段时间轴；首段默认覆盖 `00:00` 到完整视频时长，只有用户移动黄色手柄后才缩小范围。每段分别导出到原片同目录，自动避让重名且不替换原片。执行时只映射首个视频流和可选音频流（`-map 0:v:0 -map 0:a?`），串行调用 FFmpeg，文件 I/O 在后台队列，进度与刷新回到主线程。

工具栏“视频裁剪”复用同一个时间轴窗口，并在预览画面上提供空间裁剪框。实现采用独立的 IINA 式几何原则但不依赖 IINA：播放器、静态预览和裁剪框都是同一个等比例视频画布的子视图；选区以原视频 AppKit 底部原点像素矩形作为唯一真值，窗口缩放只改变画布投影，提交 FFmpeg 时才转换为 `crop` 滤镜使用的顶部原点偶数像素坐标。FFmpeg 首帧若表明视频经过 90°/270° 显示旋转，则交换有效裁剪尺寸并按比例保留选区。空间裁剪会生成原目录中的新文件，视频使用 VideoToolbox 编码且不设置固定 `-r`，从而沿用原始时间戳与帧率；它是快速 GPU 重编码，不应描述为无损剪切。

大文件或 SMB 视频进入剪辑窗口时先同步显示预览骨架和时间轴骨架，首帧使用用户交互优先任务加载；缩略图随后作为独立的低优先级任务逐张填充。FFmpegKit 命令是串行的，因此 `OperationQueue` 只允许一个抽帧任务执行；每张缩略图结束后重新选取优先级，拖动预览可排到其余缩略图之前。连续播放始终由 mpv/AVPlayer 的真实渲染面承担，FFmpeg 画面只覆盖暂停和拖动状态，不能用低频抽帧替代播放。缩略图允许快速关键帧定位；暂停预览从输入端关键帧定位后解码丢弃到目标时间，不扫描完整文件。FFmpeg 不可用或抽帧失败时立即露出真实播放器，骨架不能无限保持“加载中”。

视频控制条默认在鼠标离开后自动淡出。“视频进度条常显”是持久化设置；开启后取消隐藏计时器并保持控制条显示，停止视频时仍立即隐藏，避免空播放器残留控件。

目录树定位只能展开目标路径上的具体节点；禁止调用 `expandItem(nil)`，因为这会展开所有顶层分支，并可能在主线程同步枚举无关或已失效的 SMB 卷。`/Volumes/<share>/...` 历史目录在访问前只对照当前挂载卷列表，不直接探测目标路径；未挂载时启动回退到本地目录，交互跳转则立即提示。打开本地文件不得被历史网络目录拖慢。

## 邻近媒体预热与 SMB 播放

大图浏览每次切换位置后，以当前媒体为中心收集前 5 个和后 5 个可浏览媒体。`ViewController` 持有独立的 `MediaPreheatManager`，因此多窗口之间不会相互取消任务。

```text
changeLargeImage（仅浏览位置变化）
  → preloadLargeImage 收集 [-5 ... 当前 ... +5]
  → beginWindow：取消旧任务、更新 generation
      ├─ 图片队列（并发 2）→ LargeImageProcessor 解码缓存
      └─ 视频队列（并发 1）→ AVAssetReader 读取前 5 秒压缩样本
                              → macOS Unified Buffer Cache
                              → 保留已解析 AVURLAsset
```

视频不生成本地 5 秒临时片段，因为片段切回原片会引入时间轴、音轨和关键帧拼接问题。`AVAssetReader` 的目的不是提前播放或长期持有解码帧，而是将 SMB 上即将访问的文件区间预读进系统文件页缓存。邻项切成当前项后：

- `VolumeManager` 使用 `getmntinfo(MNT_NOWAIT)` 读取非阻塞挂载表，并与 `/Volumes` 中实际可见的入口交叉校验；这样既能识别 SMB 等网络卷，也会排除已失效的幽灵挂载，而不会为了“检测”去读取共享中的文件。`NetworkIOCoordinator` 按挂载根目录协调 I/O：大图播放器和列表自动预览持有播放优先租约；缩略图、图片信息、Finder 标签、子目录计数和邻项预热在同一网络卷上最多两路并发，并在播放期间停止分配新后台读取。已进入不可取消的同步读取允许完成，`AVAssetReader` 等可取消任务则在检测到播放后提前退出。
- libmpv 强制开启有界内存缓存：本地媒体维持 5 秒预读，网络媒体使用 12 秒目标/预读窗口、等待 3 秒初始缓冲并在缓存不足时暂停续缓冲；demuxer 前向上限为 128 MiB，回看上限为 32 MiB，禁用落盘缓存。
- libmpv 运行时按“FlowVision 自带 Frameworks → FlowVision 管理的可选运行时 → Homebrew/系统独立运行时 → IINA”选择；IINA 只作为最后兜底，避免其局部更新后出现 libmpv/libplacebo ABI 混用。使用 IINA 时只预载媒体依赖 dylib，明确排除其私有 `libswift_*`，避免与当前系统 Swift 运行时重复注入。
- 正式版本缺少 libmpv 且 AVPlayer 也无法打开当前视频时，`MPVRuntimeManager` 从 GitHub Release 的 `mpv-runtime-manifest.json` 选择当前进程架构的可选运行时。首次自动检测只提示一次；用户确认后才下载，不安装 Homebrew、不修改 IINA。归档必须通过 HTTPS、SHA-256、路径穿越、体积、CPU 架构和代码签名检查；正式签名 App 只接受相同 Team ID 的 dylib。验证通过后原子安装到 `~/Library/Application Support/FlowVision/Runtime/mpv`，刷新 libmpv 单例并在原视频上自动重试，无需重启 App。失败时保留“下载并修复视频播放”和外部播放器两个入口。
- FlowVision 当前只构建和发布 arm64。发布用运行时由 `script/package_mpv_runtime.sh` 生成；脚本拒绝非 arm64 输入，递归收集 libmpv 的非系统动态库、裁成 arm64 单架构、固定主库名为 `libmpv.2.dylib`、把 Homebrew install name 改写为 `@loader_path`、拒绝未收拢依赖和 `libavdevice`、逐库签名并收集许可文件。脚本输出 ZIP 并更新 manifest 中的 arm64 条目；不要直接发布开发机 Homebrew 目录或 ad-hoc 签名产物。
- AVPlayer 回退路径优先从 `MediaPreheatManager` 取已解析的 `AVURLAsset`；本地媒体使用 5 秒、网络媒体使用 12 秒 `preferredForwardBufferDuration`，并允许播放器等待以减少卡顿。
- 当前视频由播放器读取，预热器只处理邻近视频，避免同一 SMB 文件被两条读取链路竞争。

预热任务带 generation。快速连续翻页时，排队任务会被取消，已经运行的视频读取循环检测 generation 并取消 `AVAssetReader`。图片和视频队列分别限制并发，避免预热吞掉当前播放所需带宽。缩放、旋转等不改变浏览位置的刷新不重建预热窗口。

网络媒体缩略图先查本机持久缓存，键包含路径、文件大小、修改时间和目标尺寸参数；缓存目录为 `~/Library/Caches/FlowVision/ExternalMediaThumbnailCache`，超过 1 GiB 时按最久未使用顺序裁到 768 MiB，并与外部文件夹缩略图共用设置中的开关、容量显示和清理入口。视频首张缩略图只取 1 秒附近的关键帧；FFmpeg 使用输入端 seek，AVFoundation 不再为网络视频先读时长并尝试多个百分比时间点。

普通 SMB 目录首屏不读取 Finder 标签；目录模型和布局完成后再以 16 项为一批受控补齐，并更新可见标签点。启用 Finder 标签过滤时仍同步读取，以保持过滤结果正确。SMB 子文件夹媒体数量也不参与首屏全量扫描，只在对应集合项实际请求显示时按需统计。所有后台任务都核对当前目录和版本，切换目录后放弃旧任务，避免可选元数据造成 N+1 网络枚举。

## 支持的文件格式

### 图片格式
- 常见格式：jpg, jpeg, png, gif, bmp, webp, tiff, ico, svg
- 高质量格式：heif, heic, hif, avif, jxl, jp2
- RAW 格式：crw, cr2, cr3, nef, nrw, arw, srf, sr2, rw2, orf, raf, pef, dng, raw, rwl, x3f, 3fr, fff, iiq, mos, dcr, erf, mrw, gpr, srw
- 设计文件：ai, psd

### 视频格式
- 原生支持：mp4, mov, m2ts, ts, mpeg, mpg, m4v, vob
- 内部 libmpv 直接播放：mkv, mts, avi, flv, f4v, asf, wmv, rmvb, rm, webm, divx, xvid, 3gp, 3g2（缩略图和元数据仍使用 FFmpeg）

## 依赖库

| 库名 | 用途 |
|------|------|
| ffmpeg-kit | 视频解码和处理 |
| BTree | 高效有序数据结构 |
| Settings | 设置界面框架 |

## 全局配置 (`GlobalVar`)

主要配置项包括：
- 窗口限制：`WINDOW_LIMIT = 16`
- 缩略图预加载范围：前 20 张，后 40 张
- 内存使用限制：默认 4000MB
- 缩略图线程数：本地 8，外部 1
- 文件夹搜索深度：本地 4，外部 0
- 滚动灵敏度
- 各种显示和行为选项

## 布局模式

1. **Justified（两端对齐）**：图片行两端对齐，类似 Google Photos
2. **Waterfall（瀑布流）**：传统瀑布流布局
3. **Grid（网格）**：均匀网格布局
4. **Detail（详情）**：详细信息列表视图

## 用户交互

### 右键手势
- 右/左：切换到下一个/上一个含图片的文件夹
- 上：切换到父目录
- 下：返回上一个目录
- 右上：切换到同级下一个文件夹
- 右下：关闭标签/窗口

### 键盘快捷键
- W：等同于右键手势向上
- A/D：等同于右键手势左/右
- S：等同于右键手势向下

### 图片查看操作
- 双击：打开/关闭图片
- 右键/左键 + 滚轮：缩放
- 中键拖动：移动窗口
- 长按左键：100% 缩放
- 长按右键：适应窗口

## 构建说明

1. 克隆项目和依赖库
2. 构建 ffmpeg-kit 或下载预编译版本
3. 按指定目录结构组织依赖
4. 使用 Xcode 构建 Release 版本

---

*最后维护日期：2026-07-12*
