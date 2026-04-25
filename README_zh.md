<p align="center">
<h1 align="center">FlowVision</h1>
<h3 align="center">为 macOS 设计的瀑布流式图片浏览器</h3>
</p>

[![](https://img.shields.io/github/release/netdcy/FlowVision.svg)](https://github.com/netdcy/FlowVision/releases/latest?color=blue "GitHub release") ![GitHub License](https://img.shields.io/github/license/netdcy/FlowVision?color=blue)

## 预览

### 浅色模式
![preview](https://netdcy.github.io/FlowVision/docs/preview_2.png)

### 深色模式
![preview](https://netdcy.github.io/FlowVision/docs/preview_1.png)

## 功能特性

### 核心功能
- 多种自适应布局模式（两端对齐、瀑布流、网格、详情列表）
- 浅色/深色模式自动适配
- 便捷的文件管理（操作类似 Finder）
- 右键手势快速文件夹导航
- 大量图片目录的性能优化
- 高质量缩放（减轻摩尔纹等问题）
- HDR 显示支持
- 递归浏览模式

### 图片功能
- 支持 40+ 种图片格式，包括 RAW 文件
- 双击打开/关闭大图查看
- 鼠标手势缩放（按住右键/左键 + 滚轮）
- 长按左键切换 100% 缩放
- 按右键切换适应视图
- 图片旋转和镜像翻转
- OCR 文字识别
- 二维码检测
- EXIF 信息显示
- 图片编辑模式

### 视频功能
- 内置视频播放器（FFmpeg 支持）
- 方向键视频定位
- A-B 循环播放（用 `,` 和 `.` 设置循环点）
- 记忆播放位置
- 顺序播放模式
- 视频截图
- 自动播放可见视频选项

### 文件管理
- 复制/移动/删除/重命名操作
- 快速搜索文件名（支持拼音搜索）
- 自定义规则快速重命名
- 自定义快捷键复制到指定文件夹
- Finder 标签和评分支持
- 压缩包文件支持，可提取内部图片
- 新建文件夹

### 布局与配置
- 多种布局类型可切换
- 9 个可自定义配置槽位
- 缩略图大小调节
- 多种排序方式（名称、日期、大小、EXIF、随机等）

## 安装使用

### 系统需求

- macOS 11.0+

### 隐私与安全性

- 开源软件
- 无网络请求

### Homebrew 方式安装

首次安装
```
brew install flowvision
```
版本升级
```
brew update
brew upgrade flowvision
```

## 键盘快捷键

### 导航
| 按键 | 功能 |
|-----|------|
| `W` | 上级目录（大图模式：放大） |
| `A` | 上一个文件夹/图片（大图模式：缩小） |
| `D` | 下一个文件夹/图片 |
| `S` | 返回上次目录（大图模式：缩小） |
| `Q` | 快速搜索 / 左旋 |
| `E` | 右旋 / 关闭标签页 |
| `Space` | 打开/关闭图片或播放/暂停视频 |
| `Enter` | 打开图片（可在设置中启用）或重命名 |
| `Esc` | 关闭大图 / 取消选择 |
| `Tab` | 在侧栏和缩略图视图间切换焦点 |

### 方向键
| 按键 | 功能 |
|-----|------|
| `←/→/↑/↓` | 导航图片或文件夹 |
| `Cmd+↑` | 进入上级目录 |
| `Cmd+↓` | 进入选中的文件夹 |
| `Cmd+←/→` | 上/下一张图片（视频：逐帧定位） |
| `Shift+←/→` | 上/下一个文件（视频模式） |
| `Opt+↑/↓` | 翻页 |

### 文件操作
| 按键 | 功能 |
|-----|------|
| `R` / `F2` | 重命名 |
| `Delete` | 移到废纸篓 |
| `Cmd+Z` | 撤销 |
| `Cmd+Shift+Z` | 重做 |
| `Cmd+R` / `F5` | 刷新 |
| `Cmd+Shift+N` | 新建文件夹 |
| `Cmd+Shift+V` | 切换自动播放可见视频 |

### 图片/视频专用
| 按键 | 功能 |
|-----|------|
| `Z` | 缩放到 100% |
| `X` | 缩放适合 |
| `I` | 显示 EXIF 信息 |
| `U` | 显示文件信息 |
| `O` | OCR 文字识别 |
| `P` | 二维码检测 |
| `,` | 设置视频 A-B 循环点 A |
| `.` | 设置视频 A-B 循环点 B |
| `J` | 记忆视频播放位置 |
| `K` | 切换 A-B 循环播放 |
| `L` | 切换顺序播放 |
| `Cmd+E` | 视频截图 |
| `Cmd+Shift+E` | 进入编辑模式 |

### 标签和评分
| 按键 | 功能 |
|-----|------|
| `Cmd+1~9` | 切换 Finder 标签 (1-9) |
| `Ctrl+0~5` | 设置评分 (0-5 星) |

### 配置和布局
| 按键 | 功能 |
|-----|------|
| `Opt+1~9` | 切换到配置 1-9 |
| `Cmd+Opt+1~9` | 保存当前设置到配置 1-9 |
| `Cmd+Shift+R` | 切换递归模式 |
| `Cmd+Shift+F` | 切换递归包含文件夹 |
| `Cmd+Shift+T` | 重新打开已关闭的标签页 |
| `F3` | 打开搜索 |

### 窗口控制
| 按键 | 功能 |
|-----|------|
| `1` | 最大化窗口 |
| `2` | 合适窗口大小 |
| `3` | 调整窗口至图片实际大小 |
| `4` | 调整窗口至图片当前大小 |
| `5` | 窗口居中 |
| `=` / `-` | 增大/减小缩略图大小 |
| `0` | 重置缩略图大小 |
| `Opt+Enter` | 切换全屏 |
| `T` | 窗口置顶 |

### 自定义快捷键
- 可配置快捷键将文件复制到指定文件夹
- 快速重命名规则模板（如 `{folder}_{index}`）

## 右键手势

| 手势 | 功能 |
|-----|------|
| 向右 | 下一个有图片/视频的文件夹 |
| 向左 | 上一个有图片/视频的文件夹 |
| 向上 | 上级目录 |
| 向下 | 返回上次目录 |
| 向上右 | 同级下一个有图片的文件夹 |
| 向下右 | 关闭标签页/窗口 |

## 大图查看鼠标操作

| 操作 | 功能 |
|-----|------|
| 双击 | 打开/关闭图片 |
| 按住右键/左键 + 滚轮 | 缩放 |
| 按住中键 + 拖动 | 移动窗口 |
| 长按左键 | 100% 缩放 |
| 按右键 | 适应视图 |

## 支持的格式

### 图片
**常见格式：** jpg, jpeg, png, gif, bmp, webp, tiff, ico, svg, jfif

**高质量格式：** heif, heic, hif, avif, jxl, jp2

**RAW 格式：** crw, cr2, cr3, nef, nrw, arw, srf, sr2, rw2, orf, raf, pef, dng, raw, rwl, x3f, 3fr, fff, iiq, mos, dcr, erf, mrw, gpr, srw

**设计文件：** ai, psd

### 视频
**原生支持：** mp4, mov, m2ts, ts, mpeg, mpg, m4v, vob

**FFmpeg 支持：** mkv, mts, avi, flv, f4v, asf, wmv, rmvb, rm, webm, divx, xvid, 3gp, 3g2

## 编译

### 环境

Xcode 15.2+

### 第三方库

 - https://github.com/arthenica/ffmpeg-kit
 - https://github.com/attaswift/BTree
 - https://github.com/sindresorhus/Settings

### 构建步骤

1. 克隆此项目和依赖库的代码。
2. 对于 ffmpeg-kit，需要预先构建二进制文件。如果想节省时间，可以直接下载已构建好的二进制库，例如 `ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip`（非 LTS 版本）。解压后，在终端执行如下命令以移除 quarantine 属性：

    ```
    sudo xattr -rd com.apple.quarantine ./ffmpeg-kit-full-gpl-6.0-macos-xcframework
    ```

    （由于项目中止和版权原因，预构建的二进制文件已被移除，[这里](https://github.com/netdcy/ffmpeg-kit/releases/download/v6.0/ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip)是原文件的备份。）

3. 按如下所示组织目录结构：

    ```
    ├── FlowVision
    │   ├── FlowVision.xcodeproj
    │   └── FlowVision
    │       └── Sources
    ├── ffmpeg-kit-build
    │   └── bundle-apple-xcframework-macos
    │       ├── ffmpegkit.xcframework
    │       └── ...
    ├── BTree
    │   ├── Package.swift
    │   └── Sources
    └── Settings
        ├── Package.swift
        └── Sources
    ```

4. 用 Xcode 打开 `FlowVision.xcodeproj`，在菜单栏中点击 'Product' -> 'Build For' -> 'Profiling'。
5. 然后 'Product' -> 'Show Build Folder in Finder'，就可以看到构建好的 app 了：`Products/Release/FlowVision.app`。

## 协议

本项目使用 GPL 许可证。完整的许可证文本请参见 [LICENSE](https://github.com/netdcy/FlowVision/blob/main/LICENSE) 文件。