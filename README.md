
<p align="center">
<h1 align="center">FlowVision</h1>
<h3 align="center">Waterfall-style Image Viewer for macOS<br><br><a href="./README_zh.md">[中文说明]</a></h3> 
</p>

[![](https://img.shields.io/github/release/netdcy/FlowVision.svg)](https://github.com/netdcy/FlowVision/releases/latest?color=blue "GitHub release") ![GitHub License](https://img.shields.io/github/license/netdcy/FlowVision?color=blue)


## Screenshots

![preview](https://netdcy.github.io/FlowVision/docs/preview.jpg)

## Features:
 - Adaptive layout mode, light/dark mode
 - Convenient file management (similar to Finder)
 - Right-click gestures, quickly find the previous/next folder with images/videos
 - Performance optimizations for directories with a large number of images
 - High-quality scaling (reduces moiré and other issues)
 - Support for video thumbnails

## Installation and Usage

### System Requirements

 - macOS 11.0 and Later

### Privacy and Security

 - Open source
 - No Internet connection
 - Provide unsigned official builds

### Homebrew Install

 ```
brew tap netdcy/flowvision
brew install flowvision --no-quarantine
 ```

## Instructions:
### In Image View:
 - Hold down the right/left mouse button and scroll the wheel to zoom
 - Hold down the middle mouse button and drag to move the window
 - Long press the left mouse button to switch to 100% zoom
 - Long press the right mouse button to fit the image to the view
### Right-Click Gestures:
 - Right/Left: Switch to the next/previous folder with images/videos (logically equivalent to the next folder when sorting all folders on the disk)
 - Up: Switch to the parent directory
 - Down: Return to the previous directory
 - Down-Right/Down-Left: Switch to the next/previous folder with images at the same level as the current folder
 - Up-Right/Up-Left: Switch to the parent directory, then perform the Down-Right/Down-Left action
### Keyboard Shortcuts:
 - W: Same as the right-click gesture Up
 - A/D: Same as the right-click gesture Left/Right
 - S: Same as the right-click gesture Down

## Build

### Environment

Xcode 15.2+

### Libraries

 - https://github.com/arthenica/ffmpeg-kit
 - https://github.com/attaswift/BTree
 - https://github.com/sindresorhus/Settings

## License

This project is licensed under the GPL License. See the [LICENSE](https://github.com/netdcy/FlowVision/blob/main/LICENSE) file for the full license text.
