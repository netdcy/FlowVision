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

## 支持的文件格式

### 图片格式
- 常见格式：jpg, jpeg, png, gif, bmp, webp, tiff, ico, svg
- 高质量格式：heif, heic, hif, avif, jxl, jp2
- RAW 格式：crw, cr2, cr3, nef, nrw, arw, srf, sr2, rw2, orf, raf, pef, dng, raw, rwl, x3f, 3fr, fff, iiq, mos, dcr, erf, mrw, gpr, srw
- 设计文件：ai, psd

### 视频格式
- 原生支持：mp4, mov, m2ts, ts, mpeg, mpg, m4v, vob
- FFmpeg 支持：mkv, mts, avi, flv, f4v, asf, wmv, rmvb, rm, webm, divx, xvid, 3gp, 3g2

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

*文档生成日期：2026-04-20*