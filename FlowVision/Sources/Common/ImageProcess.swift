//
//  ImageProcess.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import Vision
import SDWebImageWebPCoder

extension NSImage {
    func rotated(by degrees: CGFloat) -> NSImage {
        if degrees == 0 {return self}
        let sinDegrees = abs(sin(degrees * CGFloat.pi / 180.0))
        let cosDegrees = abs(cos(degrees * CGFloat.pi / 180.0))
        let newSize = CGSize(width: size.height * sinDegrees + size.width * cosDegrees,
                             height: size.width * sinDegrees + size.height * cosDegrees)

        let imageBounds = NSRect(x: (newSize.width - size.width) / 2,
                                 y: (newSize.height - size.height) / 2,
                                 width: size.width, height: size.height)

        let otherTransform = NSAffineTransform()
        otherTransform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        otherTransform.rotate(byDegrees: degrees)
        otherTransform.translateX(by: -newSize.width / 2, yBy: -newSize.height / 2)

        let rotatedImage = NSImage(size: newSize)
        rotatedImage.lockFocus()
        otherTransform.concat()
        draw(in: imageBounds, from: CGRect.zero, operation: NSCompositingOperation.copy, fraction: 1.0)
        rotatedImage.unlockFocus()

        return rotatedImage
    }
    func grayScale() -> NSImage? {
        guard let tiffData = self.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }
        
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let outputImage = filter?.outputImage else {
            return nil
        }
        
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: self.size)
    }
}
extension NSImage {
    func deepCopy() -> NSImage? {
        guard let tiffData = self.tiffRepresentation else {
            return nil
        }
        
        guard let bitmapImageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        let newImage = NSImage(size: self.size)
        newImage.addRepresentation(bitmapImageRep)
        
        return newImage
    }
}
extension CGImage {
    func deepCopy() -> CGImage? {
        // 创建用于存储新图像数据的缓冲区
        // Create buffer for storing new image data
        guard let dataProvider = self.dataProvider,
              let data = dataProvider.data else {
            return nil
        }
        
        // 复制原始图像数据
        // Copy original image data
        let length = CFDataGetLength(data)
        guard let copiedData = malloc(length) else {
            return nil
        }
        
        CFDataGetBytes(data, CFRangeMake(0, length), copiedData.bindMemory(to: UInt8.self, capacity: length))
        
        // 创建新的 CGDataProvider
        // Create new CGDataProvider
        guard let copiedDataProvider = CGDataProvider(dataInfo: nil, data: copiedData, size: length, releaseData: { _, data, _ in
            free(UnsafeMutableRawPointer(mutating: data))
        }) else {
            free(copiedData)
            return nil
        }

        // 创建新的 CGImage
        // Create new CGImage
        return CGImage(
            width: self.width,
            height: self.height,
            bitsPerComponent: self.bitsPerComponent,
            bitsPerPixel: self.bitsPerPixel,
            bytesPerRow: self.bytesPerRow,
            space: self.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: self.bitmapInfo,
            provider: copiedDataProvider,
            decode: self.decode,
            shouldInterpolate: self.shouldInterpolate,
            intent: self.renderingIntent
        )
    }
}
//
// extension NSImage {
//    func imageWithWhiteBorder(borderWidth: CGFloat) -> NSImage? {
//        // 新图像的尺寸
//        let newWidth = self.size.width + 2 * borderWidth
//        let newHeight = self.size.height + 2 * borderWidth
//        let newSize = NSSize(width: newWidth, height: newHeight)
//
//        // 创建一个新的图像
//        let newImage = NSImage(size: newSize)
//        newImage.lockFocus()
//
//        // 边框颜色
//        NSColor.white.set()
//
//        // 绘制边框
//        let borderRect = NSRect(x: 0, y: 0, width: newWidth, height: newHeight)
//        borderRect.fill()
//
//        // 绘制原始图像
//        let imageRect = NSRect(x: borderWidth, y: borderWidth, width: self.size.width, height: self.size.height)
//        self.draw(in: imageRect, from: NSRect(origin: .zero, size: self.size), operation: .sourceOver, fraction: 1.0)
//
//        newImage.unlockFocus()
//        return newImage
//    }
// }
//
// extension NSView { // UIView
//    // Set source/destination angle.
//    // Angle is set in radians (0..2π), hence 360* rotation = 2π/-2π
//
//    func spinClockwise(timeToRotate: Double) {
//        startRotation(angle: -1 * CGFloat.pi * 2.0, timeToRotate: timeToRotate)
//    }
//
//    func spinAntiClockwise(timeToRotate: Double) {
//        startRotation(angle: CGFloat.pi * 2.0, timeToRotate: timeToRotate)
//    }
//
//    func startRotation(angle: CGFloat, timeToRotate: Double) {
//        let rotateAnimation = CABasicAnimation(keyPath: "transform.rotation")
//        rotateAnimation.fromValue = 0.0
//        rotateAnimation.toValue = angle
//        rotateAnimation.duration = timeToRotate
//        rotateAnimation.speed = 4
//        rotateAnimation.repeatCount = .infinity
//
//        self.layer?.add(rotateAnimation, forKey: nil)
//
//        Swift.log("Start rotating")
//    }
//
//    func stopAnimations() {
//        self.layer?.removeAllAnimations()
//        Swift.log("Stop rotating")
//    }
// }

func getFileInfo(file: FileModel) {
    let fileManager = FileManager.default
    do {
        let attributes = try fileManager.attributesOfItem(atPath: URL(string: file.path)!.path)
        if let size = attributes[.size] as? Int {
            file.fileSize = size
        }
        
        if let creationDate = attributes[.creationDate] as? Date {
            file.createDate = creationDate
        }
        
        if let modificationDate = attributes[.modificationDate] as? Date {
            file.modDate = modificationDate
        }
        
    } catch {
        log("Error fetching file info (size and date): \(error)")
    }
}

func findImageURLs(in directoryURL: URL, maxDepth: Int, maxImages: Int, preferDifferentDirs: Bool = false, timeout: TimeInterval = 1.0) -> [URL] {
    let fileManager = FileManager.default
    let validExtensions = globalVar.HandledFolderThumbExtensions
    // 包含目录及其深度
    // Contains directory and its depth
    var directoriesToVisit: [(URL, Int)] = [(directoryURL, 0)]

    let startTime = Date()

    if preferDifferentDirs {
        // 优先不同目录模式：
        // 第一阶段：BFS收集，每个含图片的目录最多收集maxImages张，收集满maxImages个目录后停止
        // 第二阶段：从收集到的目录中轮询选取
        // Prefer different dirs mode:
        // Phase 1: BFS collect, each directory keeps at most maxImages images, stop after maxImages directories
        // Phase 2: Round-robin select from collected directories
        var imagesByDir: [[URL]] = []

        while !directoriesToVisit.isEmpty {
            // 广度优先搜索
            // Breadth-first search
            let (currentDirectory, currentDepth) = directoriesToVisit.removeFirst()

            // 检查是否在排除列表中
            // Check if in exclude list
            if globalVar.thumbnailExcludeList.contains(currentDirectory.path) {
                continue
            }

            // 检查是否超时
            // Check if timed out
            if Date().timeIntervalSince(startTime) > timeout {
                break
            }

            do {
                var contents = try fileManager.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

                // 打乱目录内容顺序
                // Shuffle directory contents order
                if globalVar.randomFolderThumb {
                    contents.shuffle()
                }

                var dirImages: [URL] = []

                for fileURL in contents {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])

                    if resourceValues.isDirectory ?? false {
                        // 仅在深度限制内将子目录及其深度放入栈/队列中
                        // Only put subdirectories and their depth into stack/queue within depth limit
                        if currentDepth + 1 < maxDepth {
                            directoriesToVisit.append((fileURL, currentDepth + 1))
                        }
                    } else {
                        // 每个目录最多收集maxImages张，达到后跳过图片但继续遍历以发现子目录
                        // Collect at most maxImages per directory, skip images after that but continue to discover subdirectories
                        if dirImages.count >= maxImages { continue }
                        if validExtensions.contains(fileURL.pathExtension.lowercased()) {
                            dirImages.append(fileURL)
                        }
                    }
                }

                if !dirImages.isEmpty {
                    imagesByDir.append(dirImages)
                }

                // 收集满maxImages个含图片的目录后停止扫描
                // Stop scanning after collecting maxImages directories that contain images
                if imagesByDir.count >= maxImages {
                    break
                }
            } catch {
                log("Error accessing contents of directory \(currentDirectory): \(error)")
            }
        }

        // 轮询选取：依次从每个目录取一张图片，循环直到数量足够或所有目录耗尽
        // Round-robin selection: take one image from each directory in turn, loop until enough or all exhausted
        var result: [URL] = []
        var indices = Array(repeating: 0, count: imagesByDir.count)

        while result.count < maxImages {
            var addedAny = false
            for i in 0..<imagesByDir.count {
                if result.count >= maxImages { break }
                if indices[i] < imagesByDir[i].count {
                    result.append(imagesByDir[i][indices[i]])
                    indices[i] += 1
                    addedAny = true
                }
            }
            // 所有目录的图片都已耗尽
            // All directories' images have been exhausted
            if !addedAny { break }
        }

        return result
    } else {
        // 原始模式：按BFS顺序逐个收集
        // Original mode: collect in BFS order
        var imageUrls: [URL] = []

        while !directoriesToVisit.isEmpty {
            // 广度优先搜索
            // Breadth-first search
            let (currentDirectory, currentDepth) = directoriesToVisit.removeFirst()

            // 检查是否在排除列表中
            // Check if in exclude list
            if globalVar.thumbnailExcludeList.contains(currentDirectory.path) {
                continue
            }

            // 检查是否超时
            // Check if timed out
            if Date().timeIntervalSince(startTime) > timeout {
                break
            }

            do {
                var contents = try fileManager.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

                // 打乱目录内容顺序
                // Shuffle directory contents order
                if globalVar.randomFolderThumb {
                    contents.shuffle()
                }

                for fileURL in contents {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])

                    if resourceValues.isDirectory ?? false {
                        // 仅在深度限制内将子目录及其深度放入栈/队列中
                        // Only put subdirectories and their depth into stack/queue within depth limit
                        if currentDepth + 1 < maxDepth {
                            directoriesToVisit.append((fileURL, currentDepth + 1))
                        }
                    } else {
                        // 检查文件扩展名是否为可生成缩略图的格式
                        // Check if file extension is a format that can generate thumbnails
                        if validExtensions.contains(fileURL.pathExtension.lowercased()) {
                            imageUrls.append(fileURL)

                            // 检查是否已经找到足够多的图片
                            // Check if enough images have been found
                            if imageUrls.count >= maxImages {
                                return imageUrls
                            }
                        }
                    }
                }
            } catch {
                log("Error accessing contents of directory \(currentDirectory): \(error)")
            }
        }

        return imageUrls
    }
}

func createCompositeImage(background: NSImage, images: [NSImage], isVideos: [Bool]) -> NSImage? {
    // 定义通用参数
    // Define common parameters
    let borderColor: NSColor = NSColor(white: 1.0, alpha: 1.0)
    let shadowColor: NSColor = NSColor(white: 0.3, alpha: 1.0)
    let shadowOffset: CGSize = CGSize(width: 5.0, height: -5.0)
    let shadowBlurRadius: CGFloat = 10.0
    
    // 创建一个新的空白图像，用作最终的合成图像
    // Create a new blank image as the final composite image
    let resolution=512.0
    let size = NSSize(width: resolution, height: resolution)
    let resultImage = NSImage(size: size)
    resultImage.lockFocus()
    
    // 设置并填充背景颜色
    // Set and fill background color
//    hexToNSColor(hex: "#ECECEC").set()
//    let backgroundRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
//    backgroundRect.fill()

    // 绘制背景图像
    // Draw background image
    let rect = CGRect(origin: .zero, size: size)
    background.draw(in: rect)

    // 获取图形上下文
    // Get graphics context
    let context = NSGraphicsContext.current!.cgContext

    if globalVar.thumbnailOfFolderUseStacking {
        // 叠放模式：遍历图像数组，应用旋转变换并叠放绘制到背景上
        // Stacking mode: iterate through image array, apply rotation and draw stacked onto background
        
        let cornerRadius: CGFloat = 4.0
        let borderWidth: CGFloat = 3.0
        
        let scale: CGFloat = 0.68
        let rotationAngles: [CGFloat] = [15.0, -15.0, 0]
        
        for (index, image) in images.enumerated() {
            context.saveGState()
            
            // 设置阴影
            // Set shadow
            context.setShadow(offset: shadowOffset, blur: shadowBlurRadius, color: shadowColor.cgColor)

            // 计算缩放和旋转后的中心位置
            // Calculate center position after scaling and rotation
            let centerX = size.width / 2
            let centerY = size.height / 2
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: rotationAngles[index] * CGFloat.pi / 180)
            context.translateBy(x: -centerX, y: -centerY)

            // 计算等比缩放因子
            // Calculate proportional scaling factor
            let totalScale = min(resolution / image.size.width, resolution / image.size.height) * scale
            
            // 应用缩放
            // Apply scaling
            let newSize = NSSize(width: image.size.width * totalScale, height: image.size.height * totalScale)
            let imageRect = NSRect(x: centerX - newSize.width / 2, y: centerY - newSize.height / 2, width: newSize.width, height: newSize.height)

            // 绘制不透明背景(针对透明png图像)
            // Draw opaque background (for transparent PNG images)
            let opaqueBackgroundPath = NSBezierPath(rect: imageRect)
            hexToNSColor(hex: "#CECECE").setFill()
            opaqueBackgroundPath.fill()
            
            // 绘制图像
            // Draw image
            image.draw(in: imageRect)
            
            // 取消阴影
            // Remove shadow
            context.setShadow(offset: CGSize(width: 0, height: 0), blur: 0)

            // 添加边框
            // Add border
            if isVideos[index] {
                hexToNSColor(hex: "#3E3E3E").setStroke()
            }else{
                borderColor.setStroke()
            }
            let borderPath = NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius)
            borderPath.lineWidth = borderWidth
            borderPath.stroke()

            context.restoreGState()
        }
    } else {
        // 平铺模式：根据图像数量并排排列，照片裁切为正方形，略微旋转模拟自然摆放
        // Tiling mode: arrange images in grid, crop to square, slight rotation for natural look
        
        let cornerRadius: CGFloat = 0.0
        let borderWidth: CGFloat = 3.5
        
        let gap: CGFloat = resolution * 0.025
        // 每张照片随机略微旋转角度（度），模拟自然摆放效果
        // Random slight rotation angles (degrees) for each photo, simulating natural placement
        let tileRotations: [CGFloat] = images.indices.map { _ in
            let magnitude = CGFloat.random(in: 2.0...4.0)
            let sign: CGFloat = Bool.random() ? 1 : -1
            return magnitude * sign
        }
        
        // 计算正方形单元格大小和中心位置
        // Calculate square cell size and center positions
        var cellSize: CGFloat = 0
        var cellCenters: [CGPoint] = []
        
        switch images.count {
        case 1:
            // 单张图像：居中，适当大小
            // Single image: centered, moderate size
            cellSize = resolution * 0.62
            cellCenters.append(CGPoint(x: resolution / 2, y: resolution / 2))
        case 2:
            // 两张正方形图像：水平并排
            // Two square images: side by side horizontally
            let gridSize = resolution * 0.84
            cellSize = (gridSize - gap) / 2
            let gridOrigin = (resolution - gridSize) / 2
            cellCenters.append(CGPoint(x: gridOrigin + cellSize / 2, y: resolution / 2.05))
            cellCenters.append(CGPoint(x: gridOrigin + cellSize + gap + cellSize / 2, y: resolution / 2.05))
        case 3:
            // 三张图像：第一行两个，第二行一个居中
            // Three images: two on top row, one centered on bottom row
            let gridSize = resolution * 0.82
            cellSize = (gridSize - gap) / 2
            let gridOrigin = (resolution - gridSize) / 2
            // 第一行（上方）
            // First row (top)
            let topY = gridOrigin + cellSize + gap + cellSize / 2
            cellCenters.append(CGPoint(x: gridOrigin + cellSize / 2, y: topY))
            cellCenters.append(CGPoint(x: gridOrigin + cellSize + gap + cellSize / 2, y: topY))
            // 第二行（下方，居中）
            // Second row (bottom, centered)
            let bottomY = gridOrigin + cellSize / 2
            cellCenters.append(CGPoint(x: resolution / 2, y: bottomY))
        case 4:
            // 四张图像：两行两列
            // Four images: 2x2 grid
            let gridSize = resolution * 0.80
            cellSize = (gridSize - gap) / 2
            let gridOrigin = (resolution - gridSize) / 2
            let topY = gridOrigin + cellSize + gap + cellSize / 2
            let bottomY = gridOrigin + cellSize / 2
            let leftX = gridOrigin + cellSize / 2
            let rightX = gridOrigin + cellSize + gap + cellSize / 2
            cellCenters.append(CGPoint(x: leftX, y: topY))
            cellCenters.append(CGPoint(x: rightX, y: topY))
            cellCenters.append(CGPoint(x: leftX, y: bottomY))
            cellCenters.append(CGPoint(x: rightX, y: bottomY))
        default:
            break
        }
        
        for (index, image) in images.enumerated() {
            guard index < cellCenters.count else { break }
            let center = cellCenters[index]
            let angle = tileRotations[index % tileRotations.count]
            
            context.saveGState()
            
            // 应用略微旋转，模拟照片自然摆放
            // Apply slight rotation, simulating natural photo placement
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angle * CGFloat.pi / 180)
            context.translateBy(x: -center.x, y: -center.y)
            
            // 正方形绘制区域
            // Square drawing area
            let imageRect = NSRect(x: center.x - cellSize / 2, y: center.y - cellSize / 2, width: cellSize, height: cellSize)
            
            // 设置阴影
            // Set shadow
            context.setShadow(offset: shadowOffset, blur: shadowBlurRadius, color: shadowColor.cgColor)
            
            // 绘制不透明背景(针对透明png图像)，同时产生阴影
            // Draw opaque background (for transparent PNG images), also produces shadow
            let opaqueBackgroundPath = NSBezierPath(rect: imageRect)
            hexToNSColor(hex: "#CECECE").setFill()
            opaqueBackgroundPath.fill()
            
            // 取消阴影，避免图像绘制重复产生阴影
            // Remove shadow to avoid duplicate shadow from image drawing
            context.setShadow(offset: CGSize(width: 0, height: 0), blur: 0)
            
            // 裁切为正方形并绘制图像（居中裁切，cover模式）
            // Clip to square and draw image (center crop, cover mode)
            context.saveGState()
            let clipPath = NSBezierPath(rect: imageRect)
            clipPath.addClip()
            
            let scaleToFill = max(cellSize / image.size.width, cellSize / image.size.height)
            let drawWidth = image.size.width * scaleToFill
            let drawHeight = image.size.height * scaleToFill
            let drawRect = NSRect(x: center.x - drawWidth / 2, y: center.y - drawHeight / 2, width: drawWidth, height: drawHeight)
            image.draw(in: drawRect)
            context.restoreGState()
            
            // 添加边框
            // Add border
            if isVideos[index] {
                hexToNSColor(hex: "#3E3E3E").setStroke()
            } else {
                borderColor.setStroke()
            }
            let borderPath = NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius)
            borderPath.lineWidth = borderWidth
            borderPath.stroke()
            
            context.restoreGState()
        }
    }

    resultImage.unlockFocus()
    return resultImage
    // return compressImage(resultImage, format: .jpeg, compressionFactor: 0.8)
    // return compressImageToThumbnail(resultImage)
}

func compressImageToThumbnail(_ image: NSImage) -> NSImage? {

    guard let myImageSource = createCGImageSource(from: image) else {
        log(stderr, "Image source is NULL.");
        return nil
    }
    let thumbnailOptions = [kCGImageSourceCreateThumbnailWithTransform : kCFBooleanTrue!,
                          kCGImageSourceCreateThumbnailFromImageAlways : kCFBooleanTrue!,
                                   kCGImageSourceThumbnailMaxPixelSize : 512,
                                             kCGImageSourceShouldCache : kCFBooleanFalse!,
                            
    ] as CFDictionary;

    guard let scaledImage = CGImageSourceCreateThumbnailAtIndex(myImageSource,0,thumbnailOptions)else {
        log(stderr, "Image not created from image source.");
        return nil
    };

    let result = NSImage(cgImage: scaledImage,size: NSSize(width: scaledImage.self.width, height: scaledImage.self.height))
    
    return result
}

func createCGImageSource(from nsImage: NSImage) -> CGImageSource? {
    // 尝试将NSImage转换为CGImage
    // Try to convert NSImage to CGImage
    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        log("Failed to create CGImage from NSImage")
        // Unable to create CGImage from NSImage
        return nil
    }

    // 创建CGImage的Bitmap Representation
    // Create Bitmap Representation of CGImage
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = bitmapRep.representation(using: .png, properties: [:]) else {
        log("Failed to get data from Bitmap Representation")
        // Unable to get data from Bitmap Representation
        return nil
    }

    // 使用NSData创建CGImageSource
    // Use NSData to create CGImageSource
    let cfData = data as CFData
    let cgImageSource = CGImageSourceCreateWithData(cfData, nil)

    return cgImageSource
}

func compressImage(_ image: NSImage, format: NSBitmapImageRep.FileType, compressionFactor: CGFloat) -> NSImage? {
    // 确保图像有一个有效的表示
    // Ensure image has a valid representation
    guard let tiffData = image.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData) else {
        return nil
    }
    
    // 压缩图像
    // Compress image
    guard let imgData = bitmapImage.representation(using: format, properties: [.compressionFactor: compressionFactor]) else {
        return nil
    }
    return NSImage(data: imgData)

}

func getVideoThumbnailFFmpeg(for url: URL, at time: TimeInterval = 10) -> NSImage? {
    let tempDirectory = FileManager.default.temporaryDirectory
    let uniqueFilename = UUID().uuidString + ".jpg"
    let thumbnailPath = tempDirectory.appendingPathComponent(uniqueFilename).path
    
    // let ffmpegCommand = "-i '\(url.path)' -ss \(time) -vf \"select=eq(n\\,100),thumbnail,scale=512:-1\" -qscale:v 2 -frames:v 1 \(thumbnailPath)"
    // let ffmpegCommand = "-i '\(url.path)' -vf \"scale=1280:-1,blackframe=0,metadata=select:key=lavfi.blackframe.pblack:value=50:function=less\" -frames:v 1 \(thumbnailPath)"

    // 构建 ffmpeg 命令的参数数组
    // Build ffmpeg command argument array
    let ffmpegArgs: [String] = [
        "-i", url.path,
        "-vf", "scale=1280:-1,blackframe=0,metadata=select:key=lavfi.blackframe.pblack:value=50:function=less",
        "-frames:v", "1",
        "-threads", "2",
        thumbnailPath
    ]

//    let session = FFmpegKit.execute(withArguments: ffmpegArgs)
//    // let session = FFmpegKit.execute(ffmpegCommand)
//    let returnCode = session?.getReturnCode()
//    let output = session?.getOutput()
//
//    if ReturnCode.isSuccess(returnCode) {
//        if let thumbnail = NSImage(contentsOf: URL(fileURLWithPath: thumbnailPath)) {
//        // if let thumbnail = getImageThumb(url: URL(fileURLWithPath: thumbnailPath)) {
//            // 删除临时文件
//            try? FileManager.default.removeItem(at: URL(fileURLWithPath: thumbnailPath))
//            return thumbnail
//        } else {
//            log("Failed to load thumbnail image from \(thumbnailPath)")
//            return getFileTypeIcon(url: url)
//            // return nil
//        }
//    } else {
//        log("FFmpeg command failed with return code \(String(describing: returnCode))")
//        log(output ?? "")
//        return getFileTypeIcon(url: url)
//        // return nil
//    }
    
    if !FFmpegKitWrapper.shared.getIfLoaded() {
        // return getFileTypeIcon(url: url)
        return nil
    }
    
    if let session = FFmpegKitWrapper.shared.executeFFmpegCommand(ffmpegArgs) {
        if let returnCode = FFmpegKitWrapper.shared.getReturnCode(from: session) {
            let output = FFmpegKitWrapper.shared.getOutput(from: session)
            
            if FFmpegKitWrapper.shared.isSuccess(returnCode) {
                if let thumbnail = NSImage(contentsOf: URL(fileURLWithPath: thumbnailPath)) {
                    // 删除临时文件
                    // Delete temporary file
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: thumbnailPath))
                    return thumbnail
                } else {
                    log("Failed to load thumbnail image from \(thumbnailPath)")
                }
            } else {
                log("FFmpeg command failed with return code \(String(describing: returnCode))")
                log(output ?? "")
            }
        } else {
            log("Failed to get return code")
        }
    } else {
        log("FFmpeg execution failed")
    }
    // return getFileTypeIcon(url: url)
    return nil
}

func getFileTypeIcon(url: URL) -> NSImage {
    return NSWorkspace.shared.icon(forFile: url.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!)
}

func getImageThumb(url: URL, size oriSize: NSSize? = nil, refSize: NSSize? = nil, isPreferInternalThumb: Bool = false) -> NSImage? {
    
    let size: NSSize? = oriSize != nil ? NSSize(width: round(oriSize!.width), height: round(oriSize!.height)) : nil
    
    if(url.hasDirectoryPath){
        
        var urls = [URL]()
        let folderSearchDepth = VolumeManager.shared.isExternalVolume(url) ? globalVar.folderSearchDepth_External : globalVar.folderSearchDepth
        if folderSearchDepth > 0 {
            let maxImages = globalVar.thumbnailOfFolderUseStacking ? 3 : 4
            urls = findImageURLs(in: url, maxDepth: folderSearchDepth, maxImages: maxImages, preferDifferentDirs: !globalVar.thumbnailOfFolderUseStacking)
        }
        
        if urls.count>0 {
            // TODO: 如果返回nil则不计数
            // TODO: If returns nil then don't count
            var imgs=[NSImage]()
            var isVideos=[Bool]()
            for url in urls.reversed() {
                var img = getImageThumb(url: url, isPreferInternalThumb: isPreferInternalThumb)
                if img == nil {
                    img = getFileTypeIcon(url: url)
                }
                imgs.append(img!)
                isVideos.append(globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()))
            }
            if imgs.count>0 {
                let finalImg=createCompositeImage(background: NSImage(named: NSImage.folderName)!, images: imgs, isVideos: isVideos)
                return finalImg
            }
        }
        return NSImage(named: NSImage.folderName)

    }
    
    // 处理不支持的缩略图
    // Handle unsupported thumbnails
    if globalVar.HandledNotNativeSupportedVideoExtensions.contains(url.pathExtension.lowercased()) {
        if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
            return getVideoThumbnailFFmpeg(for: url)
        }
        // return getFileTypeIcon(url: url)
        return nil
    }

    // 处理视频缩略图
    // Handle video thumbnails
    if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        // 保证图像的正确方向
        // Ensure correct image orientation
        imageGenerator.appliesPreferredTrackTransform = true
        // imageGenerator.requestedTimeToleranceBefore = .zero
        // imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let durationSeconds = asset.duration.seconds
        
        // 尝试多个时间点，直到找到合适的帧
        // Try multiple time points until finding a suitable frame
        let timePoints: [Double]
        if durationSeconds < 60 {
            timePoints = [1, 2, 5, 10]
        } else {
            timePoints = [
                durationSeconds * 0.10,
                durationSeconds * 0.25,
                durationSeconds * 0.50,
                durationSeconds * 0.75
            ]
        }
        
        var bestFrame: (image: CGImage, brightness: Double)? = nil
        
        for seconds in timePoints {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let brightness = getFrameBrightness(cgImage)
                
                // 检查帧是否为黑屏或过暗
                // Check if frame is black screen or too dark
                if brightness >= 0.1 {
                    let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    return thumbnail.deepCopy()
                }
                
                // 更新最佳帧
                // Update best frame
                if bestFrame == nil || brightness > bestFrame!.brightness {
                    bestFrame = (cgImage, brightness)
                }
            } catch {
                continue
            }
        }
        
        // 如果有最佳帧（即使不够亮）也使用它
        // If there's a best frame (even if not bright enough), use it
        if let bestFrame = bestFrame {
            let thumbnail = NSImage(cgImage: bestFrame.image, size: NSSize(width: bestFrame.image.width, height: bestFrame.image.height))
            return thumbnail.deepCopy()
        }
        
        // 如果所有尝试都失败，则使用FFmpeg方案
        // If all attempts fail, use FFmpeg solution
        return getVideoThumbnailFFmpeg(for: url)
    }else if (globalVar.HandledImageAndRawExtensions+["pdf"]).contains(url.pathExtension.lowercased()) {
        // 处理其它缩略图
        // Handle other thumbnails
        // 使用原图的格式
        // Use original image format
        if ["gif", "svg"].contains(url.pathExtension.lowercased()) {
            return NSImage(contentsOf: url)
        }
        // 若指定了大小则特殊处理
        // Special handling if size is specified
        if size != nil && "ai" != url.pathExtension.lowercased() {
            // log(size.width,size.height)
            if let resizedImage=getResizedImage(url: url, size: size!, isRawUseEmbeddedThumb: true){
                return resizedImage
            }
            // print("resizedImage:",url.absoluteString.removingPercentEncoding!)
        }
        // 判断是否是动画并处理
        // Determine if it's an animation and handle it
        if let animateImage = getAnimateImage(url: url, rotate: 0) {
            return animateImage
        }

        let myOptions = [kCGImageSourceShouldCache : kCFBooleanFalse] as CFDictionary;
        
        guard let myImageSource = CGImageSourceCreateWithURL(url as NSURL, myOptions) else {
            log(stderr, "Image source is NULL.");
            // return getFileTypeIcon(url: url)
            return nil
        }
        
        var thumbnailOptions: CFDictionary
        
        let thumbnailOptionsAlways = [kCGImageSourceCreateThumbnailWithTransform : kCFBooleanTrue!,
                                    kCGImageSourceCreateThumbnailFromImageAlways : kCFBooleanTrue!,
                                             kCGImageSourceThumbnailMaxPixelSize : 512,
                                                       kCGImageSourceShouldCache : kCFBooleanFalse!,
        ] as CFDictionary;
        
        let thumbnailOptionsIfAbsent = [kCGImageSourceCreateThumbnailWithTransform : kCFBooleanTrue!,
                                    kCGImageSourceCreateThumbnailFromImageIfAbsent : kCFBooleanTrue!,
                                               kCGImageSourceThumbnailMaxPixelSize : 512,
                                                         kCGImageSourceShouldCache : kCFBooleanFalse!,
        ] as CFDictionary;
        
        if globalVar.HandledRawExtensions.contains(url.pathExtension.lowercased()) || isPreferInternalThumb {
            thumbnailOptions = thumbnailOptionsIfAbsent
        }else{
            thumbnailOptions = thumbnailOptionsAlways
        }
        
        guard let scaledImage = CGImageSourceCreateThumbnailAtIndex(myImageSource,0,thumbnailOptions)else {
            log(stderr, "Thumbnail not created from image source.");
            // return getFileTypeIcon(url: url)
            return nil
        };
        
        let img = NSImage(cgImage: scaledImage, size: NSSize(width: scaledImage.width, height: scaledImage.height))
        
        // 对于缩略图旋转异常的情况
        // For cases where thumbnail rotation is abnormal
        if refSize != nil && globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()) {
            let ratio1 = Double(scaledImage.width) / Double(scaledImage.height) / refSize!.width * refSize!.height
            let ratio2 = Double(scaledImage.height) / Double(scaledImage.width) / refSize!.width * refSize!.height
            if ratio1 > 1.05 || ratio1 < 0.95 {
                if ratio2 < 1.05 && ratio2 > 0.95 {
                    // return getResizedImage(url: url, size: NSSize(width: scaledImage.self.height, height: scaledImage.self.width))
                    return img.rotated(by: 90)
                }
            }
        }
        
        return img
    }
    
    // 默认情况
    // Default case
    return nil

}

func getFullExifThumbnail(url: URL, size oriSize: NSSize? = nil, rotate: Int = 0) -> NSImage? {
    
    var maxSize = 65535
    if let oriSize = oriSize {
        maxSize = 2 * Int(min(round(oriSize.width), round(oriSize.height)))
    }

    let myOptions = [kCGImageSourceShouldCache : kCFBooleanFalse] as CFDictionary;
    
    guard let myImageSource = CGImageSourceCreateWithURL(url as NSURL, myOptions) else {
        log(stderr, "Image source is NULL.");
        // return getFileTypeIcon(url: url)
        return nil
    }
    
    let thumbnailOptions = [kCGImageSourceCreateThumbnailWithTransform : kCFBooleanTrue!,
                          kCGImageSourceCreateThumbnailFromImageAlways : kCFBooleanFalse!,
                        kCGImageSourceCreateThumbnailFromImageIfAbsent : kCFBooleanFalse!,
                                   kCGImageSourceThumbnailMaxPixelSize : maxSize,
                                             kCGImageSourceShouldCache : kCFBooleanFalse!,
    ] as CFDictionary;
    
    guard let scaledImage = CGImageSourceCreateThumbnailAtIndex(myImageSource,0,thumbnailOptions) else {
        log(stderr, "Thumbnail not created from image source.");
        // return getFileTypeIcon(url: url)
        return nil
    };
    
    let img = NSImage(cgImage: scaledImage, size: NSSize(width: scaledImage.width, height: scaledImage.height))
    
    // 根据rotate参数旋转图片
    // Rotate image according to rotate parameter
    if rotate != 0 {
        return img.rotated(by: CGFloat(-90 * rotate))
    }
    
    return img
}

func rotationAngle(for orientation: Int) -> CGFloat {
    switch orientation {
    case 1, 2: // 0 degrees
        return 0
    case 3, 4: // 180 degrees
        return .pi
    case 5, 6: // 90 degrees clockwise
        return -.pi / 2
    case 7, 8: // 270 degrees clockwise
        return .pi / 2
    default:
        return 0
    }
}

extension CGSize {
    static func applyAffineTransform(size: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
}

func newOrientation(currentOrientation: Int, rotate: Int) -> Int {
    // EXIF orientation values
    // 1: 0° (normal) 正常 / Normal
    // 2: 0° (flipped horizontally)
    // 3: 180° (flipped vertically) 正常 / Normal
    // 4: 180° (flipped horizontally)
    // 5: 90° (flipped vertically)
    // 6: 90° (normal) 正常 / Normal
    // 7: 270° (flipped vertically)
    // 8: 270° (normal) 正常 / Normal

    let orientationMap: [Int: [Int: Int]] = [
        1: [0: 1, 1: 6, 2: 3, 3: 8],
        2: [0: 2, 1: 7, 2: 4, 3: 5],
        3: [0: 3, 1: 8, 2: 1, 3: 6],
        4: [0: 4, 1: 5, 2: 2, 3: 7],
        5: [0: 5, 1: 4, 2: 7, 3: 2],
        6: [0: 6, 1: 3, 2: 8, 3: 1],
        7: [0: 7, 1: 2, 2: 5, 3: 4],
        8: [0: 8, 1: 1, 2: 6, 3: 3]
    ]
    
    if let newOrientation = orientationMap[currentOrientation]?[rotate] {
        return newOrientation
    }
    
    return currentOrientation // Return the same orientation if no match found
}

func getAnimateImage(url: URL, size: NSSize? = nil, rotate: Int = 0) -> NSImage? {
    
    if ["webp"].contains(url.pathExtension.lowercased()) && rotate == 0 {
        if let data = try? Data(contentsOf: url),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetCount(source) > 1 {
            var options:[SDImageCoderOption: Any] = [:]
            if size == nil {
                options = [.decodeThumbnailPixelSize: CGSize(width: 512, height: 512)]
            }
            if let image = SDImageWebPCoder.shared.decodedImage(with: data, options: options) {
                return image
            }
        }
    }

    if ["png"].contains(url.pathExtension.lowercased()) && rotate == 0 {
        if let data = try? Data(contentsOf: url),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetCount(source) > 1 {
            return NSImage(contentsOf: url)
        }
    }
    
    return nil
}

func getResizedImage(url: URL, size oriSize: NSSize, rotate: Int = 0, isRawUseEmbeddedThumb: Bool) -> NSImage? {
    
    let size: NSSize = NSSize(width: round(oriSize.width), height: round(oriSize.height))

    // 根据配置优先尝试使用Exif内嵌缩略图
    // Try to use Exif embedded thumbnail first according to configuration
    if globalVar.HandledRawExtensions.contains(url.pathExtension.lowercased()) && isRawUseEmbeddedThumb {
        if let thumbnail = getFullExifThumbnail(url: url, size: size, rotate: rotate) {
            return thumbnail
        }
    }
    
    // 先判断是否是动画并处理
    // First determine if it's an animation and handle it
    if let animateImage = getAnimateImage(url: url, size: size, rotate: rotate) {
        return animateImage
    }
    
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        print("Failed when imageSource:",url.absoluteString.removingPercentEncoding!)
        return nil
    }

    var orientation = 1
    if let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
       let orientationRaw = imageProperties[kCGImagePropertyOrientation as String] as? Int {
        orientation=orientationRaw
    }

    orientation=newOrientation(currentOrientation: orientation, rotate: rotate)
    
    // 由于传入的是已经正确旋转过的尺寸，因此要旋转回去
    // Since the passed size is already correctly rotated, need to rotate back
    let pointSize: CGSize
    switch orientation {
    case 5, 6, 7, 8:
        // 图像旋转90度或270度
        // Image rotated 90 or 270 degrees
        pointSize = CGSize(width: size.height * 2, height: size.width * 2)
    default:
        pointSize = CGSize(width: size.width * 2, height: size.height * 2)
    }
    

    let rotation = rotationAngle(for: orientation)
    var transform = CGAffineTransform.identity
    transform = transform.rotated(by: rotation)
    
    // Handle flipping based on orientation
    switch orientation {
    case 2, 4:
        transform = transform.scaledBy(x: -1, y: 1) // Horizontal flip
    case 5, 7:
        transform = transform.scaledBy(x: 1, y: -1) // Vertical flip
    default:
        break
    }
    
    let rotatedSize = CGSize.applyAffineTransform(size: pointSize, transform: transform)
    
    var adjustedBitmapInfo = image.bitmapInfo.rawValue
    let alphaInfo = adjustedBitmapInfo & CGBitmapInfo.alphaInfoMask.rawValue
    var colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    if colorSpace.model == CGColorSpaceModel.indexed {
        // 似乎不支持索引色
        // Seems indexed color is not supported
        colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    }
    let anyNonAlpha = (alphaInfo == CGImageAlphaInfo.none.rawValue ||
                       alphaInfo == CGImageAlphaInfo.noneSkipFirst.rawValue ||
                       alphaInfo == CGImageAlphaInfo.noneSkipLast.rawValue)
    if alphaInfo == CGImageAlphaInfo.none.rawValue && colorSpace.model == CGColorSpaceModel.rgb {
        // 无 Alpha 的 RGB 图像只支持 noneSkipFirst
        // RGB images without Alpha only support noneSkipFirst
        // https:// developer.apple.com/library/archive/qa/qa1037/_index.html
        // Unset the old alpha info.
        adjustedBitmapInfo &= ~CGBitmapInfo.alphaInfoMask.rawValue
        // Set noneSkipFirst.
        adjustedBitmapInfo |= CGImageAlphaInfo.noneSkipFirst.rawValue
    } else if !anyNonAlpha && colorSpace.model == CGColorSpaceModel.rgb {
        // 有 Alpha 的 RGB 图像只支持 premultipliedLast
        // RGB images with Alpha only support premultipliedLast
        // Unset the old alpha info.
        adjustedBitmapInfo &= ~CGBitmapInfo.alphaInfoMask.rawValue
        // Set premultipliedFirst.
        adjustedBitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue
    }
    // print(image.alphaInfo.rawValue)
    // print(colorSpace.model.rawValue)
    
    // 创建足够大的上下文以适应旋转后的尺寸
    // Create context large enough to accommodate rotated size
    let context = CGContext(data: nil,
                            width: Int(rotatedSize.width),
                            height: Int(rotatedSize.height),
                            bitsPerComponent: image.bitsPerComponent,
                            bytesPerRow: 0,
                            space: colorSpace,
                            bitmapInfo: adjustedBitmapInfo)
    context?.interpolationQuality = .high

    // 调整原点到中心并应用旋转
    // Adjust origin to center and apply rotation
    context?.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
    context?.concatenate(transform)
    context?.translateBy(x: -pointSize.width / 2, y: -pointSize.height / 2)

    context?.draw(image, in: CGRect(x: 0, y: 0, width: pointSize.width, height: pointSize.height))

    guard let scaledImage = context?.makeImage() else {
        // 本来就不支持8bit以上图像
        // Images above 8bit are not supported anyway
        if image.bitsPerComponent <= 8 {
            print("Failed when makeImage:",url.absoluteString.removingPercentEncoding!)
        }
        return getResizedImageUsingCI(url: url, size: size, rotate: rotate)
    }

    let pixelSize = NSSize(width: size.width, height: size.height)
    let img = NSImage(cgImage: scaledImage, size: pixelSize)

    return img
}

func checkIsHDR(imageInfo: ImageInfo?) -> Bool {
    if let ext = imageInfo?.ext,
       globalVar.HandledRawExtensions.contains(ext) {
        return true
    }
    if let properties = imageInfo?.properties,
       let headroom = properties["Headroom"] as? Double,
       headroom > 1.0 {
        return true
    }
    return false
}

func getHDRImage(url: URL, size: NSSize? = nil, rotate: Int = 0) -> NSImage? {
    return getResizedImageUsingCI(url: url, size: size, rotate: rotate, useHDR: true)
}

func getResizedImageUsingCI(url: URL, size: NSSize? = nil, rotate: Int = 0, useHDR: Bool = false) -> NSImage? {
    var ciOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
    var ciFormat: CIFormat = .BGRA8
    
    if #available(macOS 14.0, *) {
        if useHDR {
            ciOptions[.expandToHDR] = true
            ciFormat = .RGB10
        }else{
            ciOptions[.expandToHDR] = false
        }
    }
    
    if var inputImage = CIImage(contentsOf: url, options: ciOptions) {
        // 根据rotate参数旋转图像
        // Rotate image according to rotate parameter
        if rotate != 0 {
            inputImage = inputImage.oriented(.right).transformed(by: CGAffineTransform(rotationAngle: CGFloat(-rotate+1) * .pi / 2))
        }
        
        if let size = size {
            // 分别计算宽度和高度的缩放比例
            // Calculate scaling ratios for width and height separately
            let scaleX = 2 * size.width / inputImage.extent.width
            let scaleY = 2 * size.height / inputImage.extent.height
            // 使用CILanczosScaleTransform进行高质量缩放
            // Use CILanczosScaleTransform for high-quality scaling
            let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
            scaleFilter.setValue(inputImage, forKey: kCIInputImageKey)
            scaleFilter.setValue(scaleY, forKey: kCIInputScaleKey)
            scaleFilter.setValue(scaleX/scaleY, forKey: kCIInputAspectRatioKey)
            if let outputImage = scaleFilter.outputImage{
                inputImage = outputImage
            }
        }

        let context = CIContext(options: [.name: "Renderer"])
        if let cgImage = context.createCGImage(inputImage,
                                               from: inputImage.extent,
                                               format: ciFormat,
                                               colorSpace: inputImage.colorSpace ?? CGColorSpace(name: CGColorSpace.itur_2100_PQ)!,
                                               deferred: false) {
            
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }
    
    return nil
}

func getVideoMetadataFormatedFFmpeg(for url: URL) -> [(String, String)]? {

    // 构建 ffprobe 命令的参数数组
    // Build ffprobe command argument array
    let ffprobeArgsVideo: [String] = [
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=index,codec_name,codec_long_name,profile,level,width,height,r_frame_rate,pix_fmt,color_space",
        "-show_entries", "format=bit_rate,duration,format_name",
        "-show_entries", "format_tags=creation_time,encoder",
        "-of", "default=noprint_wrappers=1:nokey=0",
        // "-pretty",
        url.path
    ] // avg_frame_rate
    
    let ffprobeArgsAudio: [String] = [
        "-v", "error",
        "-select_streams", "a",
        "-show_entries", "stream=index,codec_name,codec_long_name,bit_rate,sample_rate,channels,channel_layout",
        "-show_entries", "stream_tags=language,title",
        "-of", "default=noprint_wrappers=1:nokey=0",
        // "-pretty",
        url.path
    ]
    
    if !FFmpegKitWrapper.shared.getIfLoaded() {
        return nil
    }
    
    var result: [(String, String)] = []
    
    if let session = FFmpegKitWrapper.shared.executeFFprobeCommand(ffprobeArgsVideo),
       let output = FFmpegKitWrapper.shared.getOutput(from: session) {
        for stream in convertFFProbeStringToDictionaries(output) {
            result = result + formatVideoMetadata(stream)
        }
    } else {
        log("FFprobe execution failed")
    }
    
    if let session = FFmpegKitWrapper.shared.executeFFprobeCommand(ffprobeArgsAudio),
       let output = FFmpegKitWrapper.shared.getOutput(from: session) {
        for stream in convertFFProbeStringToDictionaries(output) {
            result = result + [("-","-")] + formatAudioMetadata(stream)
        }
    } else {
        log("FFprobe execution failed")
    }
    
    if result.isEmpty {
        return nil
    } else {
        // print(result)
        return result
    }
}

func convertFFProbeStringToDictionaries(_ input: String) -> [[String: String]] {
    var results = [[String: String]]()
    var currentDictionary = [String: String]()

    // Split the input string into lines
    let lines = input.split(separator: "\n")

    for line in lines {
        // Split each line by the first '=' character
        let components = line.split(separator: "=", maxSplits: 1)
        
        if components.count == 2 {
            let key = String(components[0]).trimmingCharacters(in: .whitespaces)
            let value = String(components[1]).trimmingCharacters(in: .whitespaces)
            
            // Check if we encounter a new index
            if key == "index", !currentDictionary.isEmpty {
                // Save the current dictionary and start a new one
                currentDictionary["-"] = "-"
                results.append(currentDictionary)
                currentDictionary = [String: String]()
            }
            
            currentDictionary[key] = value
        }
    }
    
    // Append the last dictionary if it's not empty
    if !currentDictionary.isEmpty {
        currentDictionary["-"] = "-"
        results.append(currentDictionary)
    }
    
    // 合并具有相同index的字典
    // Merge dictionaries with the same index
    var mergedResults = [[String: String]]()
    // 用于记录index对应的位置
    // Used to record the position corresponding to index
    var indexMap = [String: Int]()
    
    for dict in results {
        if let index = dict["index"] {
            if let existingIndex = indexMap[index] {
                // 合并到已存在的字典
                // Merge into existing dictionary
                mergedResults[existingIndex].merge(dict) { (current, _) in current }
            } else {
                // 添加新字典
                // Add new dictionary
                indexMap[index] = mergedResults.count
                mergedResults.append(dict)
            }
        } else {
            // 没有index的直接添加
            // Add directly if no index
            mergedResults.append(dict)
        }
    }
    
    results = mergedResults
    return results
}

func dictionaryToArray(_ dictionary: [String: String]) -> [(String, String)] {
    return dictionary.map { ($0.key, $0.value) }
}

func formatVideoMetadata(_ videoMetadata: [String: String]) -> [(String, String)] {
    // 定义翻译映射
    // Define translation mapping
    let translationMap: [(String, String)] = [
        ("format_name", NSLocalizedString("VideoMetadata-FormatName", comment: "格式名称")),
        ("TAG:encoder", NSLocalizedString("VideoMetadata-EncoderSoftwareName", comment: "编码工具名称")),
        ("bit_rate", NSLocalizedString("VideoMetadata-BitRate", comment: "比特率")),
        ("duration", NSLocalizedString("VideoMetadata-Duration", comment: "时长")),
        ("TAG:creation_time", NSLocalizedString("VideoMetadata-CreationTime", comment: "创建时间")),
        ("-", "-"),
        ("index", NSLocalizedString("VideoMetadata-Index", comment: "索引")),
        ("codec_name", NSLocalizedString("VideoMetadata-CodecName", comment: "编码器名称")),
        // ("codec_long_name", NSLocalizedString("VideoMetadata-CodecLongName", comment: "编码器全名")),
        // ("profile", NSLocalizedString("VideoMetadata-Profile", comment: "配置文件")),
        // ("level", NSLocalizedString("VideoMetadata-Level", comment: "级别")),
        // ("width", NSLocalizedString("VideoMetadata-Width", comment: "宽度")),
        // ("height", NSLocalizedString("VideoMetadata-Height", comment: "高度")),
        ("pix_fmt", NSLocalizedString("VideoMetadata-PixelFormat", comment: "像素格式")),
        ("color_space", NSLocalizedString("VideoMetadata-ColorSpace", comment: "色彩空间")),
        ("r_frame_rate", NSLocalizedString("VideoMetadata-RFrameRate", comment: "参考帧率")),
        // ("avg_frame_rate", NSLocalizedString("VideoMetadata-AvgFrameRate", comment: "平均帧率")),
    ]

    var formattedData: [(String, String)] = []

    // 根据翻译映射格式化数据
    // Format data according to translation mapping
    for (key, translationKey) in translationMap {
        if let value = videoMetadata[key] {
            var formattedValue = value
            
            if value == "N/A" || value == "und" {continue}

            // 对特定字段进行格式化处理
            // Format specific fields
            switch key {
            case "bit_rate":
                if let bitRate = Int(value) {
                    if bitRate >= 1_000_000 {
                        formattedValue = String(format: "%.2f Mbps", Double(bitRate) / 1_000_000)
                    } else {
                        formattedValue = String(format: "%.2f kbps", Double(bitRate) / 1_000)
                    }
                }
            case "duration":
                if let duration = Double(value) {
                    let hours = Int(duration) / 3600
                    let minutes = (Int(duration) % 3600) / 60
                    let seconds = Int(duration) % 60
                    formattedValue = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                }
            case "TAG:creation_time":
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
                // 解析为UTC时间
                // Parse as UTC time
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = dateFormatter.date(from: value) {
                    let localFormatter = DateFormatter()
                    localFormatter.dateStyle = .medium
                    localFormatter.timeStyle = .medium
                    localFormatter.locale = Locale.current
                    // 转换为本地时间
                    // Convert to local time
                    localFormatter.timeZone = TimeZone.current
                    formattedValue = localFormatter.string(from: date)
                }
            case "r_frame_rate":
                let components = value.split(separator: "/")
                if components.count == 2, let numerator = Double(components[0]), let denominator = Double(components[1]), denominator != 0 {
                    let frameRate = numerator / denominator
                    if frameRate.truncatingRemainder(dividingBy: 1) == 0 {
                        // If the frame rate is an integer
                        formattedValue = "\(Int(frameRate)) fps"
                    } else {
                        // If the frame rate is not an integer
                        formattedValue = String(format: "%.2f fps", frameRate)
                    }
                }
            default:
                break
            }
            
            formattedData.append((translationKey, formattedValue))
        }
    }

    return formattedData
}

func formatAudioMetadata(_ audioMetadata: [String: String]) -> [(String, String)] {
    // 定义翻译映射
    // Define translation mapping
    let translationMap: [(String, String)] = [
        ("index", NSLocalizedString("AudioMetadata-Index", comment: "索引")),
        ("codec_name", NSLocalizedString("AudioMetadata-CodecName", comment: "编码器名称")),
        // ("codec_long_name", NSLocalizedString("AudioMetadata-CodecLongName", comment: "编码器全名")),
        ("channel_layout", NSLocalizedString("AudioMetadata-ChannelLayout", comment: "声道布局")),
        // ("channels", NSLocalizedString("AudioMetadata-Channels", comment: "声道数")),
        ("sample_rate", NSLocalizedString("AudioMetadata-SampleRate", comment: "采样率")),
        ("bit_rate", NSLocalizedString("AudioMetadata-BitRate", comment: "比特率")),
        ("TAG:language", NSLocalizedString("AudioMetadata-Language", comment: "语言")),
        ("TAG:title", NSLocalizedString("AudioMetadata-StreamTitle", comment: "流标题"))
    ]

    var formattedData: [(String, String)] = []

    // 根据翻译映射格式化数据
    // Format data according to translation mapping
    for (key, translationKey) in translationMap {
        if let value = audioMetadata[key] {
            var formattedValue = value
            
            if value == "N/A" || value == "und" {continue}
            
            // 对特定字段进行格式化处理
            // Format specific fields
            switch key {
            case "bit_rate":
                if let bitRate = Int(value) {
                    if bitRate >= 1_000_000 {
                        formattedValue = String(format: "%.2f Mbps", Double(bitRate) / 1_000_000)
                    } else {
                        formattedValue = String(format: "%.2f kbps", Double(bitRate) / 1_000)
                    }
                }
            case "sample_rate":
                if let sampleRate = Int(value) {
                    formattedValue = "\(Double(sampleRate) / 1000) kHz"
                }
            default:
                break
            }
            
            formattedData.append((translationKey, formattedValue))
        }
    }

    return formattedData
}

func getVideoMetadataFFmpeg(for url: URL) -> String? {

    // 构建 ffprobe 命令的参数数组
    // Build ffprobe command argument array
    let ffprobeArgs: [String] = [
        "-v", "error",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        "-pretty",
        url.path
    ]
    
    if !FFmpegKitWrapper.shared.getIfLoaded() {
        return nil
    }
    
    if let session = FFmpegKitWrapper.shared.executeFFprobeCommand(ffprobeArgs) {
        if let output = FFmpegKitWrapper.shared.getOutput(from: session) {
            // 解析 ffprobe 的输出
            // Parse ffprobe output
            return output
        }
    } else {
        log("FFprobe execution failed")
    }
    return nil
}

func getVideoResolutionAndDateFFmpeg(for url: URL) -> (Int,Int,Date?)? {

    // 构建 ffprobe 命令的参数数组
    // Build ffprobe command argument array
    let ffprobeArgs: [String] = [
        "-v", "error",
        "-show_entries", "stream=width,height:format_tags=creation_time",
        "-of", "default=noprint_wrappers=1:nokey=0",
        url.path
    ]
    
    if !FFmpegKitWrapper.shared.getIfLoaded() {
        return nil
    }
    
    if let session = FFmpegKitWrapper.shared.executeFFprobeCommand(ffprobeArgs) {
        if let output = FFmpegKitWrapper.shared.getOutput(from: session) {
            // 解析 ffprobe 的输出
            // Parse ffprobe output
            var width = 0
            var height = 0
            var creationTime: Date?

            let lines = output.split(separator: "\n")
            for line in lines {
                let parts = line.split(separator: "=")
                if parts.count == 2 {
                    let key = parts[0]
                    let value = parts[1]
                    
                    if key == "width", let w = Int(value), w > 0, width == 0 {
                        width = w
                    } else if key == "height", let h = Int(value), h > 0, height == 0 {
                        height = h
                    } else if key == "TAG:creation_time" {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
                        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                        creationTime = dateFormatter.date(from: String(value))
                    }
                    
                    if width > 0 && height > 0 && creationTime != nil {
                        break
                    }
                }
            }
            return (width,height,creationTime)
        }
    } else {
        log("FFprobe execution failed")
    }
    return nil
}

func getVideoResolutionFFmpeg(for url: URL) -> NSSize? {
    // 构建 ffprobe 命令来获取视频流的宽度和高度
    // Build ffprobe command to get video stream width and height
    // let ffprobeCommand = "-v error -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1:nokey=1 '\(url.path)'"
    
    // 构建 ffprobe 命令的参数数组
    // Build ffprobe command argument array
    let ffprobeArgs: [String] = [
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "default=noprint_wrappers=1:nokey=1",
        // "-threads", "2",
        url.path
    ]
    
//    let session = FFprobeKit.execute(withArguments: ffprobeArgs)
//    // let session = FFprobeKit.execute(ffprobeCommand)
//    let output = session?.getOutput()
//
//    // 解析 ffprobe 的输出
//    if let output = output {
//        let dimensions = output.split(separator: "\n").compactMap { Int($0) }
//        // 个别时候会有多个视频流，输出类似为"1280\n720\n1280\n720\n"
//        // Sometimes there are multiple video streams, output like "1280\n720\n1280\n720\n"
//        if dimensions.count % 2 == 0 && dimensions.count != 0 {
//            return NSSize(width: dimensions[0], height: dimensions[1])
//        }
//    }
//
//    return nil
    
    if !FFmpegKitWrapper.shared.getIfLoaded() {
        return nil
    }
    
    if let session = FFmpegKitWrapper.shared.executeFFprobeCommand(ffprobeArgs) {
        if let output = FFmpegKitWrapper.shared.getOutput(from: session) {
            // 解析 ffprobe 的输出
            // Parse ffprobe output
            let dimensions = output.split(separator: "\n").compactMap { Int($0) }
            if dimensions.count % 2 == 0 && dimensions.count != 0 {
                // 个别时候会有多个视频流，输出类似为 "1280\n720\n1280\n720\n"
                // Sometimes there are multiple video streams, output like "1280\n720\n1280\n720\n"
                return NSSize(width: dimensions[0], height: dimensions[1])
            }
        }
    } else {
        log("FFprobe execution failed")
    }
    return nil
}

func getImageInfo(url: URL, needMetadata: Bool) -> ImageInfo? {
    // let defaultSize = DEFAULT_SIZE
    if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
        if globalVar.HandledNotNativeSupportedVideoExtensions.contains(url.pathExtension.lowercased()){
            if let sizeUseFFmpeg = getVideoResolutionFFmpeg(for: url){
                return ImageInfo(sizeUseFFmpeg)
            }else{
                return nil
            }
        }
        let asset = AVAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            let width = abs(size.width)
            let height = abs(size.height)

            // log("Video dimensions: \(width) x \(height)")
            // 此处获取的是像素size
            // Get pixel size here
            return ImageInfo(NSSize(width: width, height: height))
            
        } else {
            // log("No video track available")
            if let sizeUseFFmpeg = getVideoResolutionFFmpeg(for: url){
                return ImageInfo(sizeUseFFmpeg)
            }else{
                return nil
            }
        }
    }else if "pdf" == url.pathExtension.lowercased() {
        if let thumb = getImageThumb(url: url) {return ImageInfo(thumb.size)}
        return nil
    }else if globalVar.HandledImageAndRawExtensions.contains(url.pathExtension.lowercased()){
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else { return nil }
        guard let width = imageProperties[kCGImagePropertyPixelWidth as String] as? CGFloat,
              let height = imageProperties[kCGImagePropertyPixelHeight as String] as? CGFloat else { return nil }
        // 此处获取的是像素size
        // Get pixel size here
        let orientation = (imageProperties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1

        var imageSize: NSSize
        switch orientation {
        case 1, 2, 3, 4: // Normal orientations (1 is normal, 2 is flipped horizontally, etc.)
            imageSize = NSSize(width: width, height: height)
        case 5, 6, 7, 8: // Rotated orientations (6 is 90 degrees CW, etc.)
            imageSize = NSSize(width: height, height: width)
        default:
            imageSize = NSSize(width: width, height: height)
        }
        
        let imageInfo = ImageInfo(imageSize)
        imageInfo.properties = imageProperties
        imageInfo.ext = url.pathExtension.lowercased()
        imageInfo.isHDR = checkIsHDR(imageInfo: imageInfo)
        // print(imageProperties)
        
        if needMetadata {
            let metadata = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil)
            imageInfo.metadata = metadata
            let prefix = "xmp"
            let key = "Rating"
            if let metadata = metadata,
               let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "\(prefix):\(key)" as CFString),
               let value = CGImageMetadataTagCopyValue(tag) as? String {
                imageInfo.rating = Int(value)
            }
        }
        
        return imageInfo
        
    }else{
        return nil
    }
}

func hexToNSColor(hex: String = "#000000", alpha: Double = 1.0) -> NSColor {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0

    // 尝试转换十六进制字符串
    // Try to convert hexadecimal string
    Scanner(string: hexSanitized).scanHexInt64(&rgb)

    let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let blue = CGFloat(rgb & 0x0000FF) / 255.0

    return NSColor(red: red, green: green, blue: blue, alpha: alpha)
}

func parseExifDateTime(dateTimeString: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    // 设置为你假设的时区
    // Set to assumed timezone
    dateFormatter.timeZone = TimeZone.current
    return dateFormatter.date(from: dateTimeString)
}

func formatDateToCurrentTimeZone(_ date: Date) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium
    dateFormatter.timeZone = TimeZone.current
    return dateFormatter.string(from: date)
}

func readableFileSize(_ bytes: Int) -> String {
    let kilobyte = 1024.0
    let megabyte = kilobyte * 1024
    let gigabyte = megabyte * 1024
    let terabyte = gigabyte * 1024

    if bytes < Int(kilobyte) {
        return "\(bytes) B"
    } else if bytes < Int(megabyte) {
        let kbSize = Double(bytes) / kilobyte
        return String(format: "%.1f KB", kbSize)
    } else if bytes < Int(gigabyte) {
        let mbSize = Double(bytes) / megabyte
        return String(format: "%.1f MB", mbSize)
    } else if bytes < Int(terabyte) {
        let gbSize = Double(bytes) / gigabyte
        return String(format: "%.1f GB", gbSize)
    } else {
        let tbSize = Double(bytes) / terabyte
        return String(format: "%.1f TB", tbSize)
    }
}

func convertExifData(file: FileModel) -> [String: Any]? {

    if file.imageInfo == nil {
        file.imageInfo = ImageInfo(nil)
    }
    if file.imageInfo?.properties == nil {
        file.imageInfo?.properties = [:]
    }
    
    guard var imageProperties = file.imageInfo?.properties else {return [:]}
    
    imageProperties["Filename"]=(file.path as NSString).lastPathComponent.removingPercentEncoding!

    if let fileSize = file.fileSize {
        imageProperties["FileSize"]=readableFileSize(fileSize)
    }
    
    if let creationDate = file.createDate {
        imageProperties["FileCreatedTime"]=formatDateToCurrentTimeZone(creationDate)
    }
    
    if let modificationDate = file.modDate {
        imageProperties["FileModifiedTime"]=formatDateToCurrentTimeZone(modificationDate)
    }
    
    if let additionDate = file.addDate {
        imageProperties["FileAddedTime"]=formatDateToCurrentTimeZone(additionDate)
    }

    if let imageSize = file.imageInfo?.size {
        imageProperties["Resolution"]=String(format: "%.0f", imageSize.width) + " × " + String(format: "%.0f", imageSize.height)
    }
    
    if let rating = file.imageInfo?.rating {
        imageProperties["Rating"]=rating
    }
    
    return imageProperties
}

func convertExposureTimeToFraction(_ value: Double) -> String {
    if value <= 0 {
        return "0 s"
    }
    
    let fraction = approximateFraction(value)
    if fraction.denominator == 1 {
        return "\(fraction.numerator) s"
    } else {
        return "\(fraction.numerator)/\(fraction.denominator) s"
    }
}

func approximateFraction(_ value: Double, withPrecision precision: Double = 1.0e-6) -> (numerator: Int, denominator: Int) {
    var x = value
    var a = floor(x)
    var h1 = 1.0
    var k1 = 0.0
    var h = a
    var k = 1.0
    
    while x - a > precision * k * k {
        x = 1.0 / (x - a)
        a = floor(x)
        let h2 = h1
        let k2 = k1
        h1 = h
        k1 = k
        h = h2 + a * h1
        k = k2 + a * k1
    }
    
    return (Int(h), Int(k))
}

func formatExifData(_ imageProperties: [String: Any], isVideo: Bool, needWarp: Bool) -> [(String, Any)] {
    var isUseMultiLang=true
    if Bundle.main.preferredLocalizations.first != "en"{
        isUseMultiLang=true
    }
    
    var translationMap: [(CFString, String)] = [
        ("Filename" as CFString, NSLocalizedString("Filename", comment: "文件名")),
        ("FileSize" as CFString, NSLocalizedString("Exif-FileSize", comment: "文件大小")),
        ("Resolution" as CFString, NSLocalizedString("Exif-Resolution", comment: "分辨率")),
        ("FileCreatedTime" as CFString, NSLocalizedString("Exif-FileCreatedTime", comment: "文件创建时间")),
        ("FileModifiedTime" as CFString, NSLocalizedString("Exif-FileModifiedTime", comment: "文件修改时间")),
        ("FileAddedTime" as CFString, NSLocalizedString("Exif-FileAddedTime", comment: "文件添加时间")),
        ("Rating" as CFString, NSLocalizedString("Exif-Rating", comment: "星级")),
        
        ("-" as CFString, "-"),
        
        (kCGImagePropertyExifDateTimeOriginal, NSLocalizedString("Exif-DateTimeOriginal", comment: "拍摄时间")),
        (kCGImagePropertyExifDateTimeDigitized, NSLocalizedString("Exif-DateTimeDigitized", comment: "数字化时间")),
        (kCGImagePropertyTIFFDateTime, NSLocalizedString("Exif-TIFFDateTime", comment: "元数据时间")),
        
        (kCGImagePropertyExifExposureTime, NSLocalizedString("Exif-ExposureTime", comment: "曝光时间")),
        (kCGImagePropertyExifISOSpeedRatings, NSLocalizedString("Exif-ISOSpeedRatings", comment: "ISO感光度")),
        (kCGImagePropertyExifFNumber, NSLocalizedString("Exif-FNumber", comment: "光圈值 (FNumber)")),
        (kCGImagePropertyExifApertureValue, NSLocalizedString("Exif-ApertureValue", comment: "光圈值 (Aperture)")),
        (kCGImagePropertyExifFlash, NSLocalizedString("Exif-Flash", comment: "闪光灯")),
        (kCGImagePropertyExifFocalLength, NSLocalizedString("Exif-FocalLength", comment: "焦距")),
        
        (kCGImagePropertyExifLensModel, NSLocalizedString("Exif-LensModel", comment: "镜头型号")),
        (kCGImagePropertyTIFFModel, NSLocalizedString("Exif-CameraModel", comment: "相机型号")),
        (kCGImagePropertyTIFFMake, NSLocalizedString("Exif-CameraMaker", comment: "制造商")),
        
        (kCGImagePropertyTIFFSoftware, NSLocalizedString("Exif-Software", comment: "软件")),
        (kCGImagePropertyTIFFArtist, NSLocalizedString("Exif-Artist", comment: "作者")),
        
        (kCGImagePropertyColorModel, NSLocalizedString("Exif-ColorModel", comment: "色彩空间")),
        (kCGImagePropertyProfileName, NSLocalizedString("Exif-ProfileName", comment: "配置文件名称")),
        (kCGImagePropertyDepth, NSLocalizedString("Exif-Depth", comment: "位深度")),
        ("HDR Mode" as CFString, "HDR"),
        
    ]
    
    if !isVideo {
        translationMap += [
            ("-" as CFString, "-"),
            
            (kCGImagePropertyGPSLongitude, NSLocalizedString("Exif-GPSLongitude", comment: "GPS经度")),
            (kCGImagePropertyGPSLatitude, NSLocalizedString("Exif-GPSLatitude", comment: "GPS纬度")),
            (kCGImagePropertyGPSAltitude, NSLocalizedString("Exif-GPSAltitude", comment: "GPS海拔")),
        ]
    }
    
    for i in 0..<translationMap.count {
        if !isUseMultiLang {
            translationMap[i].1 = translationMap[i].0 as String
        }
    }
    
    var formattedData: [(String, Any)] = []
    
    for (key, translationKey) in translationMap {
        if translationKey == "-" {
            formattedData.append(("-", "-"))
        }else if let value = imageProperties[key as String] {
            if key as String == "Filename" && needWarp {
                let str = value as? String ?? ""
                let chunkSize = 30
                var startIndex = str.startIndex
                var isFirst = true
                
                while startIndex < str.endIndex {
                    let endIndex = str.index(startIndex, offsetBy: chunkSize, limitedBy: str.endIndex) ?? str.endIndex
                    let chunk = String(str[startIndex..<endIndex])
                    
                    if isFirst {
                        formattedData.append((translationKey, chunk))
                        isFirst = false
                    } else {
                        formattedData.append(("", chunk))
                    }
                    
                    startIndex = endIndex
                }
            } else {
                formattedData.append((translationKey, value))
            }
        } else if let exifData = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any], let value = exifData[key as String] {
            switch key {
            case kCGImagePropertyExifExposureTime:
                if let exposureTime = value as? Double {
                    formattedData.append((translationKey, convertExposureTimeToFraction(exposureTime)))
                }
            case kCGImagePropertyExifFNumber:
                if let fNumber = value as? Double {
                    formattedData.append((translationKey, String(format: "f/%.1f", fNumber)))
                }
            case kCGImagePropertyExifISOSpeedRatings:
                if let isoValues = value as? [Int], let isoValue = isoValues.first {
                    formattedData.append((translationKey, "\(isoValue)"))
                }
            case kCGImagePropertyExifDateTimeOriginal:
                if let dateTime = value as? String,
                   let timeAsDate = parseExifDateTime(dateTimeString: dateTime) {
                    formattedData.append((translationKey, formatDateToCurrentTimeZone(timeAsDate)))
                }
            case kCGImagePropertyExifDateTimeDigitized:
                if let dateTime = value as? String,
                   let timeAsDate = parseExifDateTime(dateTimeString: dateTime) {
                    formattedData.append((translationKey, formatDateToCurrentTimeZone(timeAsDate)))
                }
            case kCGImagePropertyExifFlash:
                if let flashValue = value as? Int {
                    if isUseMultiLang {
                        formattedData.append((translationKey, flashValue == 0 ? NSLocalizedString("Exif-Flash-Off", comment: "未使用") : NSLocalizedString("Exif-Flash-On", comment: "开启")))
                    }else{
                        formattedData.append((translationKey, flashValue == 0 ? "Off" : "On"))
                    }
                }
            case kCGImagePropertyExifApertureValue:
                if let apertureValue = value as? Double {
                    formattedData.append((translationKey, String(format: "%.2f", apertureValue)))
                }
            case kCGImagePropertyExifFocalLength:
                if let focalLength = value as? Double {
                    formattedData.append((translationKey, String(format: "%.6g", focalLength) + " mm"))
                }
            default:
                formattedData.append((translationKey, value))
            }
        } else if let tiffData = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any], let value = tiffData[key as String] {
            if key == kCGImagePropertyTIFFDateTime {
                if let dateTime = value as? String,
                   let timeAsDate = parseExifDateTime(dateTimeString: dateTime) {
                    formattedData.append((isUseMultiLang ? translationKey : "DateTimeMetadata", formatDateToCurrentTimeZone(timeAsDate)))
                }
            }else if key == kCGImagePropertyTIFFArtist {
                if let artist = value as? String {
                    if artist.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                        formattedData.append((translationKey, value))
                    }
                }
            }else{
                formattedData.append((translationKey, value))
            }
        } else if let gpsData = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if key == kCGImagePropertyGPSLatitude {
                if let latitude = gpsData[kCGImagePropertyGPSLatitude as String] as? Double,
                   let latitudeRef = gpsData[kCGImagePropertyGPSLatitudeRef as String] as? String {
                    let finalLatitude = latitudeRef == "S" ? -latitude : latitude
                    formattedData.append((translationKey, String(format: "%.6f°", finalLatitude)))
                }
            } else if key == kCGImagePropertyGPSLongitude {
                if let longitude = gpsData[kCGImagePropertyGPSLongitude as String] as? Double,
                   let longitudeRef = gpsData[kCGImagePropertyGPSLongitudeRef as String] as? String {
                    let finalLongitude = longitudeRef == "W" ? -longitude : longitude
                    formattedData.append((translationKey, String(format: "%.6f°", finalLongitude)))
                }
            } else if key == kCGImagePropertyGPSAltitude {
                if let altitude = gpsData[kCGImagePropertyGPSAltitude as String] as? Double,
                   let altitudeRef = gpsData[kCGImagePropertyGPSAltitudeRef as String] as? Int {
                    let finalAltitude = altitudeRef == 1 ? -altitude : altitude
                    formattedData.append((translationKey, String(format: "%.2fm", finalAltitude)))
                }
            }
        } else if key == "custom-HDR" as CFString {
            if let _ = imageProperties["Headroom"]{
                if let depth = imageProperties["Depth"] as? Int {
                    if depth == 8 {
                        formattedData.append((translationKey, "Gain Map HDR"))
                    }else if depth > 8 {
                        formattedData.append((translationKey, "\(depth)bit HDR"))
                    }
                }
            }
            
        }
    }
    
    if formattedData.count>0 && formattedData.last!.0 == "-" {
        formattedData.removeLast()
    }
    
    return formattedData
}

func distanceBetweenPoints(_ point1: NSPoint, _ point2: NSPoint) -> CGFloat {
    return hypot(point1.x - point2.x, point1.y - point2.y)
}

func recognizeQRCode(from image: NSImage) -> [String]? {
    // 将 NSImage 转换为 CIImage
    // Convert NSImage to CIImage
    guard let imageData = image.tiffRepresentation,
          let ciImage = CIImage(data: imageData) else {
        return nil
    }
    
    // 创建一个 CIDetector 并设置类型为二维码
    // Create a CIDetector and set type to QR code
    let context = CIContext()
    let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
    guard let qrDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options) else {
        return nil
    }
    
    // 使用 CIDetector 进行二维码检测
    // Use CIDetector to detect QR codes
    let features = qrDetector.features(in: ciImage)
    
    // 提取检测到的二维码信息
    // Extract detected QR code information
    var qrCodeStrings: [String] = []
    for feature in features {
        if let qrFeature = feature as? CIQRCodeFeature, let messageString = qrFeature.messageString {
            qrCodeStrings.append(messageString)
        }
    }
    
    return qrCodeStrings.isEmpty ? nil : qrCodeStrings
}

func performLegacyOCR(on image: NSImage, completion: @escaping (Result<[String], Error>) -> Void) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        completion(.failure(NSError(domain: "OCR", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert NSImage to CGImage"])))
        return
    }
    
    let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    
    let request = VNRecognizeTextRequest { (request, error) in
        if let error = error {
            completion(.failure(error))
            return
        }
        
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            completion(.failure(NSError(domain: "OCR", code: -1, userInfo: [NSLocalizedDescriptionKey: "No text recognized"])))
            return
        }
        
        let recognizedTexts = observations.compactMap { observation -> String? in
            observation.topCandidates(1).first?.string
        }
        
        completion(.success(recognizedTexts))
    }
    
    // 你可以根据需要添加更多的语言
    // You can add more languages as needed
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    
    do {
        try requestHandler.perform([request])
    } catch {
        completion(.failure(error))
    }
}

class LargeImageProcessor {
    private static let cache: CustomCache<NSString, CacheWrapper> = {
        let cache = CustomCache<NSString, CacheWrapper>()
        // 设置缓存容量
        // Set cache capacity
        cache.countLimit = 16
        return cache
    }()
    
    private static let lock = NSLock()
    private static var ongoingTasks: [String: (DispatchSemaphore, Int)] = [:]
    
    // 用于包装缓存中的图像，包括nil情况
    // Wrapper for cached images, including nil cases
    private class CacheWrapper {
        let image: NSImage?
        init(image: NSImage?) {
            self.image = image
        }
    }
    
    // 原始的图像处理函数
    // Original image processing function
//    private static func originalGetResizedImage(url: URL, size: NSSize, rotate: Int = 0) -> NSImage? {
//        return getResizedImage(url: url, size: size, rotate: rotate)
//    }
    
    static func getImageCache(url: URL, size: NSSize, rotate: Int = 0, ver: Int, useOriginalImage: Bool, isHDR: Bool, isRawUseEmbeddedThumb: Bool, needWaitWhenSame: Bool = true) -> NSImage? {
        let cacheKey = "\(url.absoluteString)_\(size.width)x\(size.height)_\(rotate)_v\(ver)_hdr\(isHDR)_embeded\(isRawUseEmbeddedThumb)" as NSString
        // print(cacheKey)
        
        // 先检查缓存中是否已有图像（包括nil情况）
        // Check if image exists in cache first (including nil cases)
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image
        }
        
        lock.lock()
        // 检查是否有相同参数的任务正在进行
        // Check if task with same parameters is in progress
        if let (semaphore, count) = ongoingTasks[cacheKey as String] {
            if needWaitWhenSame {
                ongoingTasks[cacheKey as String] = (semaphore, count + 1)
                lock.unlock()
                // 等待正在进行的任务完成
                // Wait for ongoing task to complete
                semaphore.wait()
                // 任务完成后再检查缓存
                // Check cache again after task completion
                return cache.object(forKey: cacheKey)?.image
            }else{
                lock.unlock()
                return nil
            }
        } else {
            // 创建新的信号量并标记任务开始
            // Create new semaphore and mark task start
            let semaphore = DispatchSemaphore(value: 0)
            ongoingTasks[cacheKey as String] = (semaphore, 1)
            lock.unlock()
            
            // 生成图像
            // Generate image
            var image: NSImage?
            if isHDR {
                image = getHDRImage(url: url, size: useOriginalImage ? nil : size, rotate: rotate)
            }else if useOriginalImage {
                // 先判断是否是动画并处理
                // First determine if it's an animation and handle it
                if let animateImage = getAnimateImage(url: url, rotate: rotate) {
                    image = animateImage
                } else {
                    image = NSImage(contentsOf: url)?.rotated(by: CGFloat(-90*rotate))
                }
            }else{
                image = getResizedImage(url: url, size: size, rotate: rotate, isRawUseEmbeddedThumb: isRawUseEmbeddedThumb)
                if image == nil {
                    image = NSImage(contentsOf: url)?.rotated(by: CGFloat(-90*rotate))
                }
            }
            
            // 更新缓存（包括nil情况）
            // Update cache (including nil cases)
            let cacheWrapper = CacheWrapper(image: image)
            cache.setObject(cacheWrapper, forKey: cacheKey)
            
            lock.lock()
            // 任务完成，移除信号量
            // Task completed, remove semaphore
            let (_, count) = ongoingTasks.removeValue(forKey: cacheKey as String)!
            lock.unlock()
            
            // 释放所有等待的线程
            // Release all waiting threads
            for _ in 0..<count {
                semaphore.signal()
            }
            
            return image
        }
    }
    
    // 检查缓存中是否有图像（且不是nil）
    // Check if image exists in cache (and is not nil)
    static func isImageCached(url: URL, size: NSSize, rotate: Int = 0, ver: Int, isHDR: Bool, isRawUseEmbeddedThumb: Bool) -> Bool {
        let cacheKey = "\(url.absoluteString)_\(size.width)x\(size.height)_\(rotate)_v\(ver)_hdr\(isHDR)_embeded\(isRawUseEmbeddedThumb)" as NSString
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image != nil
        }
        return false
    }
    
    // 检查缓存中是否有图像，有的话则返回
    // Check if image exists in cache, return it if found
    static func isImageCachedAndGet(url: URL, size: NSSize, rotate: Int = 0, ver: Int, isHDR: Bool, isRawUseEmbeddedThumb: Bool) -> NSImage? {
        let cacheKey = "\(url.absoluteString)_\(size.width)x\(size.height)_\(rotate)_v\(ver)_hdr\(isHDR)_embeded\(isRawUseEmbeddedThumb)" as NSString
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image
        }
        return nil
    }
    
    // 清空缓存
    // Clear cache
    static func clearCache() {
        cache.removeAllObjects()
    }
}

class CustomCache<Key: Hashable, Value> {
    private var cache: [Key: Value] = [:]
    private var keys: [Key] = []
    private let lock = NSLock()
    
    var countLimit: Int = 0 {
        didSet {
            lock.lock()
            defer { lock.unlock() }
            trimCache()
        }
    }
    
    func object(forKey key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        
        if let value = cache[key] {
            updateAccessOrder(forKey: key)
            return value
        }
        return nil
    }
    
    func setObject(_ obj: Value, forKey key: Key) {
        lock.lock()
        defer { lock.unlock() }
        
        if cache[key] == nil, keys.count >= countLimit {
            trimCache()
        }
        
        cache[key] = obj
        updateAccessOrder(forKey: key)
    }
    
    func removeAllObjects() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        keys.removeAll()
    }
    
    private func updateAccessOrder(forKey key: Key) {
        if let index = keys.firstIndex(of: key) {
            keys.remove(at: index)
        }
        keys.append(key)
    }
    
    private func trimCache() {
        while keys.count > countLimit {
            if let keyToRemove = keys.first {
                cache.removeValue(forKey: keyToRemove)
                keys.removeFirst()
            }
        }
    }
}

class ThumbImageProcessor {
    private static let cache: CustomCache<NSString, CacheWrapper> = {
        let cache = CustomCache<NSString, CacheWrapper>()
        // 设置缓存容量
        // Set cache capacity
        cache.countLimit = 16
        return cache
    }()
    
    private static let lock = NSLock()
    private static var ongoingTasks: [String: (DispatchSemaphore, Int)] = [:]
    
    // 用于包装缓存中的图像，包括nil情况
    // Wrapper for cached images, including nil cases
    private class CacheWrapper {
        let image: NSImage?
        init(image: NSImage?) {
            self.image = image
        }
    }
    
    static func getImageCache(url: URL, size: NSSize? = nil, refSize: NSSize? = nil, needWaitWhenSame: Bool = true, isPreferInternalThumb: Bool = false, ver: Int) -> NSImage? {
        let cacheKey = "\(url.absoluteString)_s\(size?.width ?? 0)x\(size?.height ?? 0)_r\(refSize?.width ?? 0)x\(refSize?.height ?? 0)_p\(isPreferInternalThumb)_v\(ver)" as NSString
        // print(cacheKey)
        
        // 先检查缓存中是否已有图像（包括nil情况）
        // Check if image exists in cache first (including nil cases)
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image
        }
        
        lock.lock()
        // 检查是否有相同参数的任务正在进行
        // Check if task with same parameters is in progress
        if let (semaphore, count) = ongoingTasks[cacheKey as String] {
            if needWaitWhenSame {
                ongoingTasks[cacheKey as String] = (semaphore, count + 1)
                lock.unlock()
                // 等待正在进行的任务完成
                // Wait for ongoing task to complete
                semaphore.wait()
                // 任务完成后再检查缓存
                // Check cache again after task completion
                return cache.object(forKey: cacheKey)?.image
            }else{
                lock.unlock()
                return nil
            }
        } else {
            // 创建新的信号量并标记任务开始
            // Create new semaphore and mark task start
            let semaphore = DispatchSemaphore(value: 0)
            ongoingTasks[cacheKey as String] = (semaphore, 1)
            lock.unlock()
            
            // 生成图像
            // Generate image
            var image: NSImage?
            image = getImageThumb(url: url, size: size, refSize: refSize, isPreferInternalThumb: isPreferInternalThumb)
            
            // 更新缓存（包括nil情况）
            // Update cache (including nil cases)
            let cacheWrapper = CacheWrapper(image: image)
            cache.setObject(cacheWrapper, forKey: cacheKey)
            
            lock.lock()
            // 任务完成，移除信号量
            // Task completed, remove semaphore
            let (_, count) = ongoingTasks.removeValue(forKey: cacheKey as String)!
            lock.unlock()
            
            // 释放所有等待的线程
            // Release all waiting threads
            for _ in 0..<count {
                semaphore.signal()
            }
            
            return image
        }
    }
    
    // 清空缓存
    // Clear cache
    static func clearCache() {
        cache.removeAllObjects()
    }
}

func getFrameBrightness(_ cgImage: CGImage) -> Double {
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * 4
    let totalBytes = bytesPerRow * height
    
    var rawData = [UInt8](repeating: 0, count: totalBytes)
    let context = CGContext(data: &rawData,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: bytesPerRow,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    
    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    // 计算平均亮度
    // Calculate average brightness
    var totalBrightness: Double = 0
    var samplesCount = 0
    // 采样步长，避免处理所有像素
    // Sampling step size to avoid processing all pixels
    let samplingStep = max(1, (width * height) / 1000)
    
    for i in stride(from: 0, to: totalBytes, by: samplingStep * 4) {
        let r = Double(rawData[i])
        let g = Double(rawData[i + 1])
        let b = Double(rawData[i + 2])
        
        // 计算亮度 (使用人眼感知的权重)
        // Calculate brightness (using human eye perception weights)
        let brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        totalBrightness += brightness
        samplesCount += 1
    }
    
    return totalBrightness / Double(samplesCount)
}
