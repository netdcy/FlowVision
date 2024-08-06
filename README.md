# FlowVision

[![](https://img.shields.io/github/release/netdcy/FlowVision.svg)](https://github.com/netdcy/FlowVision/releases/latest "GitHub release")

A waterfall-style image viewer for macOS, offering a smooth and immersive browsing experience.

## Screenshots

![preview](https://github.com/user-attachments/assets/4220453c-050d-4700-860e-bc6a0981a944)

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

Xcode 15.2+, macOS 13.5+

### Libraries

 - https://github.com/arthenica/ffmpeg-kit
 - https://github.com/attaswift/BTree
 - https://github.com/sindresorhus/Settings

## License

This project is licensed under the GPL License. See the [LICENSE](https://github.com/netdcy/FlowVision/blob/main/LICENSE) file for the full license text.
