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

## 操作说明

### 图片浏览:
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

## 编译

### 环境

Xcode 15.2+

### 第三方库

 - https://github.com/arthenica/ffmpeg-kit
 - https://github.com/attaswift/BTree
 - https://github.com/sindresorhus/Settings

## 协议

本项目使用GPL许可证。完整的许可证文本请参见 [LICENSE](https://github.com/netdcy/FlowVision/blob/main/LICENSE) 文件。