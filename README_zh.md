<p align="center">
<h1 align="center">FlowVision</h1>
<h3 align="center">为macOS设计的瀑布流式图片浏览器</h3> 
</p>

[![](https://img.shields.io/github/release/netdcy/FlowVision.svg)](https://github.com/netdcy/FlowVision/releases/latest?color=blue "GitHub release") ![GitHub License](https://img.shields.io/github/license/netdcy/FlowVision?color=blue)

## 预览

![preview](https://netdcy.github.io/FlowVision/docs/preview.jpg)

## 应用特点:

 - 自适应布局模式、浅色/深色模式

 - 方便的文件管理（操作类似 Finder）

 - 右键手势、快速查找上一个/下一个有图片/视频的文件夹

 - 针对目录下大量图片情况的性能优化

 - 高质量的缩放（减轻摩尔纹等问题）

 - 支持视频缩略图

## 安装使用

### 系统需求

 - macOS 11.0+

### 隐私与安全性

 - 开源软件
 - 无网络连接
 - 提供无签名的官方构建，可自行编译

### Homebrew 安装

 ```
brew tap netdcy/flowvision
brew install flowvision --no-quarantine
 ```

## 操作说明

### 图片浏览:
 - 双击打开/关闭图片
 - 按住右键/左键滚动滚轮可以缩放
 - 按住中键拖动可以移动窗口
 - 长按左键切换 100%缩放
 - 长按右键切换缩放到视图
### 右键手势:
 - 向右/左：切换到下一个/上一个有图片/视频的文件夹(逻辑上等同于将整个磁盘中的文件夹排序后的下一个)
 - 向上：切换到上级目录
 - 向下：返回到上一次的目录
 - 向下右/下左：切换到与当前文件夹平级的下一个/上一个有图片的文件夹
 - 向上右/上左：切换到上级目录后，再执行向下右/下左的操作
### 键盘按键:
 - W：同右键手势 向上
 - A/D：同右键手势 向左/右
 - S：同右键手势 向下

## 常见问题

**Q1: 为什么我无法打开这个应用？系统提示应用程序不受信任。**

**A1:** 这是因为该应用程序没有经过Apple的公证。要打开它，请按以下步骤操作：
- 在Finder中找到应用程序
- 右键点击应用程序文件
- 从菜单中选择“打开”
- 在出现的对话框中再次点击“打开”

（参考：https://support.apple.com/102445#openanyway）

**Q2: 为什么应用程序没有经过公证？**

**A2:** 公证应用程序需要每年向Apple支付100美元的费用。为了保持软件免费，我们没有对其进行公证。如果你愿意，可以从提供的源代码自行构建应用程序。

**Q3: 为什么程序没有自动升级功能？**

**A3:** 检查更新需要网络连接，而该项目的理念是保证数据隐私完全掌控在用户手中。使用自动升级可能会遇到开发者账号被窃取，通过升级渠道传播恶意代码等意外情况。为了确保用户的数据安全和隐私，我们选择不提供自动升级功能。

## 编译

### 环境

Xcode 15.2+

### 第三方库

 - https://github.com/arthenica/ffmpeg-kit
 - https://github.com/attaswift/BTree
 - https://github.com/sindresorhus/Settings

### 构建步骤

1. 克隆此项目和依赖库的代码
2. 对于ffmpeg-kit，需要预先构建二进制文件。如果你想省时间，可以直接下载它已构建好的二进制库，例如 `ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip` (非LTS版本)。 解压后，在终端执行如下命令以移除quarantine属性：

    ```
    sudo xattr -rd com.apple.quarantine ./ffmpeg-kit-full-gpl-6.0-macos-xcframework
    ```

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

4. 用Xcode打开 `FlowVision.xcodeproj` ，在菜单栏中点击 'Product' -> 'Build For' -> 'Profiling'
5. 然后 'Product' -> 'Show Build Folder in Finder'，就可以看到构建好的app了 `Products/Release/FlowVison.app`

## 协议

本项目使用GPL许可证。完整的许可证文本请参见 [LICENSE](https://github.com/netdcy/FlowVision/blob/main/LICENSE) 文件。