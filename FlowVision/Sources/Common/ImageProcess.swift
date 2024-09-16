//
//  ImageRelated.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation
import Cocoa
import AVFoundation
import Vision

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
//
//extension NSImage {
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
//}
//
//extension NSView { // UIView
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
//}

func getFileSize(atPath path: String) -> UInt64 {
    let fileManager = FileManager.default
    do {
        let attributes = try fileManager.attributesOfItem(atPath: path.removingPercentEncoding!)
        if let size = attributes[.size] as? UInt64 {
            return size
        }
    } catch {
        log("Error fetching file size: \(error)")
    }
    return 0
}

func findImageURLs(in directoryURL: URL, maxDepth: Int, maxImages: Int, timeout: TimeInterval = 1.0) -> [URL] {
    let fileManager = FileManager.default
    //要不扫描子目录在下面添加Option: .skipsSubdirectoryDescendants
    let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
    let validExtensions = globalVar.HandledFolderThumbExtensions  // 支持缩略图的格式
    var imageUrls: [URL] = []
    
    let startTime = Date()

    guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: options) else {
        return imageUrls
    }

    for case let fileURL as URL in enumerator {
        // 检查是否超时
        if Date().timeIntervalSince(startTime) > timeout {
            log("Operation timed out")
            break
        }
        
        // 检查是否已经找到足够多的图片
        if imageUrls.count >= maxImages {
            break
        }

        // 检查是否超过了最大目录层数
        let relativePathComponents = fileURL.pathComponents.dropLast().suffix(from: directoryURL.pathComponents.count)
        if relativePathComponents.count > maxDepth {
            enumerator.skipDescendants()  // 跳过更深层次的目录
            continue
        }

        // 检查文件扩展名是否为可生成缩略图的格式
        if validExtensions.contains(fileURL.pathExtension.lowercased()) {
            // 确认这是一个文件而不是文件夹
            do {
                let fileAttributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if fileAttributes.isRegularFile ?? false {
                    imageUrls.append(fileURL)
                }
            } catch {
                log("Error reading file attributes for \(fileURL): \(error)")
                continue
            }
        }
    }

    return imageUrls
}

func createCompositeImage(background: NSImage, images: [NSImage], isVideos: [Bool], scale: CGFloat, rotationAngles: [CGFloat], borderWidth: CGFloat, borderColor: NSColor, shadowOffset: CGSize, shadowBlurRadius: CGFloat, shadowColor: NSColor, cornerRadius: CGFloat) -> NSImage? {
    // 创建一个新的空白图像，用作最终的合成图像
    let resolution=512.0
    let size = NSSize(width: resolution, height: resolution)
    let resultImage = NSImage(size: size)
    resultImage.lockFocus()
    
    // 设置并填充背景颜色
//    hexToNSColor(hex: "#ECECEC").set()
//    let backgroundRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
//    backgroundRect.fill()

    // 绘制背景图像
    let rect = CGRect(origin: .zero, size: size)
    background.draw(in: rect)

    // 获取图形上下文
    let context = NSGraphicsContext.current!.cgContext

    // 遍历图像数组，应用变换并绘制到背景上
    for (index, image) in images.enumerated() {
        context.saveGState()
        
        // 设置阴影
        context.setShadow(offset: shadowOffset, blur: shadowBlurRadius, color: shadowColor.cgColor)

        // 计算缩放和旋转后的中心位置
        let centerX = size.width / 2
        let centerY = size.height / 2
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: rotationAngles[index] * CGFloat.pi / 180)
        context.translateBy(x: -centerX, y: -centerY)

        // 计算等比缩放因子
        let totalScale = min(resolution / image.size.width, resolution / image.size.height) * scale
        
        // 应用缩放
        let newSize = NSSize(width: image.size.width * totalScale, height: image.size.height * totalScale)
        let imageRect = NSRect(x: centerX - newSize.width / 2, y: centerY - newSize.height / 2, width: newSize.width, height: newSize.height)

        // 绘制不透明背景(针对透明png图像)
        let opaqueBackgroundPath = NSBezierPath(rect: imageRect)
        hexToNSColor(hex: "#CECECE").setFill()
        opaqueBackgroundPath.fill()
        
        // 绘制图像
        image.draw(in: imageRect)
        
        // 取消阴影
        context.setShadow(offset: CGSize(width: 0, height: 0), blur: 0)

        // 添加边框
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

    resultImage.unlockFocus()
    return resultImage
    //return compressImage(resultImage, format: .jpeg, compressionFactor: 0.8)
    //return compressImageToThumbnail(resultImage)
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
    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        log("无法从NSImage创建CGImage")
        return nil
    }

    // 创建CGImage的Bitmap Representation
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = bitmapRep.representation(using: .png, properties: [:]) else {
        log("无法从Bitmap Representation获取数据")
        return nil
    }

    // 使用NSData创建CGImageSource
    let cfData = data as CFData
    let cgImageSource = CGImageSourceCreateWithData(cfData, nil)

    return cgImageSource
}

func compressImage(_ image: NSImage, format: NSBitmapImageRep.FileType, compressionFactor: CGFloat) -> NSImage? {
    // 确保图像有一个有效的表示
    guard let tiffData = image.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData) else {
        return nil
    }
    
    //压缩图像
    guard let imgData = bitmapImage.representation(using: format, properties: [.compressionFactor: compressionFactor]) else {
        return nil
    }
    return NSImage(data: imgData)

}

func getVideoThumbnailFFmpeg(for url: URL, at time: TimeInterval = 10) -> NSImage? {
    let tempDirectory = FileManager.default.temporaryDirectory
    let uniqueFilename = UUID().uuidString + ".jpg"
    let thumbnailPath = tempDirectory.appendingPathComponent(uniqueFilename).path
    
    //let ffmpegCommand = "-i '\(url.path)' -ss \(time) -vf \"select=eq(n\\,100),thumbnail,scale=512:-1\" -qscale:v 2 -frames:v 1 \(thumbnailPath)"
    //let ffmpegCommand = "-i '\(url.path)' -vf \"scale=1280:-1,blackframe=0,metadata=select:key=lavfi.blackframe.pblack:value=50:function=less\" -frames:v 1 \(thumbnailPath)"

    // 构建 ffmpeg 命令的参数数组
    let ffmpegArgs: [String] = [
        "-i", url.path,
        "-vf", "scale=1280:-1,blackframe=0,metadata=select:key=lavfi.blackframe.pblack:value=50:function=less",
        "-frames:v", "1",
        "-threads", "2",
        thumbnailPath
    ]

//    let session = FFmpegKit.execute(withArguments: ffmpegArgs)
//    //let session = FFmpegKit.execute(ffmpegCommand)
//    let returnCode = session?.getReturnCode()
//    let output = session?.getOutput()
//
//    if ReturnCode.isSuccess(returnCode) {
//        if let thumbnail = NSImage(contentsOf: URL(fileURLWithPath: thumbnailPath)) {
//        //if let thumbnail = getImageThumb(url: URL(fileURLWithPath: thumbnailPath)) {
//            // 删除临时文件
//            try? FileManager.default.removeItem(at: URL(fileURLWithPath: thumbnailPath))
//            return thumbnail
//        } else {
//            log("Failed to load thumbnail image from \(thumbnailPath)")
//            return getFileTypeIcon(url: url)
//            //return nil
//        }
//    } else {
//        log("FFmpeg command failed with return code \(String(describing: returnCode))")
//        log(output ?? "")
//        return getFileTypeIcon(url: url)
//        //return nil
//    }
    
    if !FFmpegKitWrapper.shared.getIfLoaded() {
        //return getFileTypeIcon(url: url)
        return nil
    }
    
    if let session = FFmpegKitWrapper.shared.executeFFmpegCommand(ffmpegArgs) {
        if let returnCode = FFmpegKitWrapper.shared.getReturnCode(from: session) {
            let output = FFmpegKitWrapper.shared.getOutput(from: session)
            
            if FFmpegKitWrapper.shared.isSuccess(returnCode) {
                if let thumbnail = NSImage(contentsOf: URL(fileURLWithPath: thumbnailPath)) {
                    // 删除临时文件
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
    //return getFileTypeIcon(url: url)
    return nil
}

func getFileTypeIcon(url: URL) -> NSImage {
    return NSWorkspace.shared.icon(forFile: url.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!)
}

func getImageThumb(url: URL, size: NSSize? = nil, refSize: NSSize? = nil) -> NSImage? {
    
    if(url.hasDirectoryPath){
        
        var urls = [URL]()
        let folderSearchDepth = VolumeManager.shared.isExternalVolume(url) ? globalVar.folderSearchDepth_External : globalVar.folderSearchDepth
        if folderSearchDepth > 0 {
            urls = findImageURLs(in: url, maxDepth: folderSearchDepth-1, maxImages: 3)
        }
        
        if urls.count>0 {
            //TODO: 如果返回nil则不计数
            var imgs=[NSImage]()
            var isVideos=[Bool]()
            for url in urls {
                var img = getImageThumb(url: url)
                if img == nil {
                    img = getFileTypeIcon(url: url)
                }
                imgs.append(img!)
                isVideos.append(globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()))
            }
            if imgs.count>0 {
                let finalImg=createCompositeImage(background: NSImage(named: NSImage.folderName)!, images: imgs, isVideos: isVideos, scale: 0.68, rotationAngles: [15.0, -15.0, 0], borderWidth: 3.0, borderColor: NSColor(white: 1.0, alpha: 1.0), shadowOffset: CGSize(width: 5.0, height: -5.0), shadowBlurRadius: 10.0, shadowColor: NSColor(white: 0.3, alpha: 1.0), cornerRadius: 4.0)
                return finalImg
            }
        }
        return NSImage(named: NSImage.folderName)

    }
    
    //处理不支持的缩略图
    if globalVar.HandledNotNativeSupportedExtensions.contains(url.pathExtension.lowercased()) {
        if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
            return getVideoThumbnailFFmpeg(for: url)
        }
        //return getFileTypeIcon(url: url)
        return nil
    }

    //处理视频缩略图
    if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true  // 保证图像的正确方向

        let durationSeconds = asset.duration.seconds
        
        let time: CMTime
        if durationSeconds < 60 {
            time = CMTime(seconds: 2, preferredTimescale: 600)  // 获取第2秒的帧作为缩略图
        }else{
            time = CMTime(seconds: durationSeconds/2, preferredTimescale: 600)
        }
        
        let cgImage: CGImage
        do {
            cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return thumbnail
        } catch {
            //log(error.localizedDescription)
            return getVideoThumbnailFFmpeg(for: url)
            //return getFileTypeIcon(url: url)
            //return nil
        }
        
    }else if (globalVar.HandledImageExtensions+["pdf"]).contains(url.pathExtension.lowercased()) { //处理其它缩略图
        //gif特殊处理
        if( "gif" == url.pathExtension.lowercased() ){
            return NSImage(contentsOf: url)
        }
        //svg特殊处理
        if( "svg" == url.pathExtension.lowercased() ){
            return NSImage(contentsOf: url)
        }
        //若指定了大小则特殊处理
        if( size != nil ){
            //log(size.width,size.height)
            if let resizedImage=getResizedImage(url: url, size: size!){
                return resizedImage
            }
            //print("resizedImage:",url.absoluteString.removingPercentEncoding!)
        }
        do{
            let myOptions = [kCGImageSourceShouldCache : kCFBooleanFalse] as CFDictionary;
            
            guard let myImageSource = CGImageSourceCreateWithURL(url as NSURL, myOptions) else {
                log(stderr, "Image source is NULL.");
                //return getFileTypeIcon(url: url)
                return nil
            }
            let thumbnailOptions = [kCGImageSourceCreateThumbnailWithTransform : kCFBooleanTrue!,
                                  kCGImageSourceCreateThumbnailFromImageAlways : kCFBooleanTrue!,
                                           kCGImageSourceThumbnailMaxPixelSize : 512,
                                                     kCGImageSourceShouldCache : kCFBooleanFalse!,
                                    
            ] as CFDictionary;

            guard let scaledImage = CGImageSourceCreateThumbnailAtIndex(myImageSource,0,thumbnailOptions)else {
                log(stderr, "Thumbnail not created from image source.");
                //return getFileTypeIcon(url: url)
                return nil
            };

            let img = NSImage(cgImage: scaledImage, size: NSSize(width: scaledImage.width, height: scaledImage.height))
            
            //对于缩略图旋转异常的情况
            if refSize != nil && globalVar.HandledImageExtensions.contains(url.pathExtension.lowercased()) {
                let ratio1 = Double(scaledImage.width) / Double(scaledImage.height) / refSize!.width * refSize!.height
                let ratio2 = Double(scaledImage.height) / Double(scaledImage.width) / refSize!.width * refSize!.height
                if ratio1 > 1.05 || ratio1 < 0.95 {
                    if ratio2 < 1.05 && ratio2 > 0.95 {
                        //return getResizedImage(url: url, size: NSSize(width: scaledImage.self.height, height: scaledImage.self.width))
                        return img.rotated(by: 90)
                    }
                }
            }

            return img
        }
        
    }
    
    //默认情况
    return nil

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
    // 1: 0° (normal) 正常
    // 2: 0° (flipped horizontally)
    // 3: 180° (flipped vertically) 正常
    // 4: 180° (flipped horizontally)
    // 5: 90° (flipped vertically)
    // 6: 90° (normal) 正常
    // 7: 270° (flipped vertically)
    // 8: 270° (normal) 正常

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
func getResizedImage(url: URL, size: NSSize, rotate: Int = 0) -> NSImage? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        print("imageSource:",url.absoluteString.removingPercentEncoding!)
        return nil
    }

    var orientation = 1
    if let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
       let orientationRaw = imageProperties[kCGImagePropertyOrientation as String] as? Int {
        orientation=orientationRaw
    }

    orientation=newOrientation(currentOrientation: orientation, rotate: rotate)
    
    //由于传入的是已经正确旋转过的尺寸，因此要旋转回去
    let pointSize: CGSize
    switch orientation {
    case 5, 6, 7, 8: // 图像旋转90度或270度
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
        colorSpace = CGColorSpace(name: CGColorSpace.sRGB)! //似乎不支持索引色
    }
    let anyNonAlpha = (alphaInfo == CGImageAlphaInfo.none.rawValue ||
                       alphaInfo == CGImageAlphaInfo.noneSkipFirst.rawValue ||
                       alphaInfo == CGImageAlphaInfo.noneSkipLast.rawValue)
    if alphaInfo == CGImageAlphaInfo.none.rawValue && colorSpace.model == CGColorSpaceModel.rgb {
        // 无 Alpha 的 RGB 图像只支持 noneSkipFirst
        // https://developer.apple.com/library/archive/qa/qa1037/_index.html
        // Unset the old alpha info.
        adjustedBitmapInfo &= ~CGBitmapInfo.alphaInfoMask.rawValue
        // Set noneSkipFirst.
        adjustedBitmapInfo |= CGImageAlphaInfo.noneSkipFirst.rawValue
    } else if !anyNonAlpha && colorSpace.model == CGColorSpaceModel.rgb {
        // 有 Alpha 的 RGB 图像只支持 premultipliedLast
        // Unset the old alpha info.
        adjustedBitmapInfo &= ~CGBitmapInfo.alphaInfoMask.rawValue
        // Set premultipliedFirst.
        adjustedBitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue
    }
    //print(image.alphaInfo.rawValue)
    //print(colorSpace.model.rawValue)
    
    // 创建足够大的上下文以适应旋转后的尺寸
    let context = CGContext(data: nil,
                            width: Int(rotatedSize.width),
                            height: Int(rotatedSize.height),
                            bitsPerComponent: image.bitsPerComponent,
                            bytesPerRow: 0,
                            space: colorSpace,
                            bitmapInfo: adjustedBitmapInfo)
    context?.interpolationQuality = .high

    // 调整原点到中心并应用旋转
    context?.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
    context?.concatenate(transform)
    context?.translateBy(x: -pointSize.width / 2, y: -pointSize.height / 2)

    context?.draw(image, in: CGRect(x: 0, y: 0, width: pointSize.width, height: pointSize.height))

    guard let scaledImage = context?.makeImage() else {
        if image.bitsPerComponent <= 8 { // 本来就不支持8bit以上图像
            print("makeImage:",url.absoluteString.removingPercentEncoding!)
        }
        return nil
    }

    let pixelSize = NSSize(width: size.width, height: size.height)
    let img = NSImage(cgImage: scaledImage, size: pixelSize)

    return img
}

func getResizedImage2(url: URL, size: NSSize, rotate: Int = 0) -> NSImage? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        print("imageSource:", url.absoluteString.removingPercentEncoding!)
        return nil
    }

    var orientation = 1
    if let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
       let orientationRaw = imageProperties[kCGImagePropertyOrientation as String] as? Int {
        orientation = orientationRaw
    }

    orientation = newOrientation(currentOrientation: orientation, rotate: rotate)
    let transform = CGAffineTransform(rotationAngle: rotationAngle(for: orientation))

    let ciImage = CIImage(cgImage: image).transformed(by: transform)
    let context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])

    // 缩放图像
    let scaleX = size.width * 2 / ciImage.extent.width
    let scaleY = size.height * 2 / ciImage.extent.height
    let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
    let scaledImage = ciImage.transformed(by: scaleTransform)

    // 创建 CGImage
    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
        print("createCGImage:", url.absoluteString.removingPercentEncoding!)
        return nil
    }

    let pixelSize = NSSize(width: size.width, height: size.height)
    return NSImage(cgImage: cgImage, size: pixelSize)
}

func getVideoResolutionFFmpeg(for url: URL) -> NSSize? {
    // 构建 ffprobe 命令来获取视频流的宽度和高度
    //let ffprobeCommand = "-v error -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1:nokey=1 '\(url.path)'"
    
    // 构建 ffprobe 命令的参数数组
    let ffprobeArgs: [String] = [
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "default=noprint_wrappers=1:nokey=1",
        "-threads", "2",
        url.path
    ]
    
//    let session = FFprobeKit.execute(withArguments: ffprobeArgs)
//    //let session = FFprobeKit.execute(ffprobeCommand)
//    let output = session?.getOutput()
//
//    // 解析 ffprobe 的输出
//    if let output = output {
//        let dimensions = output.split(separator: "\n").compactMap { Int($0) }
//        if dimensions.count % 2 == 0 && dimensions.count != 0 { //个别时候会有多个视频流，输出类似为"1280\n720\n1280\n720\n"
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
            let dimensions = output.split(separator: "\n").compactMap { Int($0) }
            if dimensions.count % 2 == 0 && dimensions.count != 0 {
                // 个别时候会有多个视频流，输出类似为 "1280\n720\n1280\n720\n"
                return NSSize(width: dimensions[0], height: dimensions[1])
            }
        }
    } else {
        log("FFprobe execution failed")
    }
    return nil
}

func getImageSize(url: URL) -> NSSize? {
    //let defaultSize = DEFAULT_SIZE
    if globalVar.HandledVideoExtensions.contains(url.pathExtension.lowercased()) {
        if globalVar.HandledNotNativeSupportedExtensions.contains(url.pathExtension.lowercased()){
            if let sizeUseFFmpeg = getVideoResolutionFFmpeg(for: url){
                return sizeUseFFmpeg
            }else{
                return nil
            }
        }
        let asset = AVAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            let width = abs(size.width)
            let height = abs(size.height)

            //log("Video dimensions: \(width) x \(height)")
            //此处获取的是像素size
            return NSSize(width: width, height: height)
            
        } else {
            //log("No video track available")
            if let sizeUseFFmpeg = getVideoResolutionFFmpeg(for: url){
                return sizeUseFFmpeg
            }else{
                return nil
            }
        }
    }else if "pdf" == url.pathExtension.lowercased() {
        if let thumb = getImageThumb(url: url) {return thumb.size}
        return nil
    }else if globalVar.HandledImageExtensions.contains(url.pathExtension.lowercased()){
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else { return nil }
        guard let width = imageProperties[kCGImagePropertyPixelWidth as String] as? CGFloat,
              let height = imageProperties[kCGImagePropertyPixelHeight as String] as? CGFloat else { return nil }
        //此处获取的是像素size

        let orientation = (imageProperties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1

        switch orientation {
        case 1, 2, 3, 4: // Normal orientations (1 is normal, 2 is flipped horizontally, etc.)
            return NSSize(width: width, height: height)
        case 5, 6, 7, 8: // Rotated orientations (6 is 90 degrees CW, etc.)
            return NSSize(width: height, height: width)
        default:
            return NSSize(width: width, height: height)
        }
    }else{
        return nil
    }
}

func getResizedImageDeprecated1(url: URL, size: NSSize) -> NSImage? {
    guard let imageSource = CGImageSourceCreateWithURL(url as NSURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {return nil}
    
    let pointSize=CGSize(width: size.width*2, height: size.height*2)
    let pixelSize=NSSize(width: size.width, height: size.height)
    
    let context = CGContext(data: nil,
                            width: Int(pointSize.width),
                            height: Int(pointSize.height),
                            bitsPerComponent: image.bitsPerComponent,
                            bytesPerRow: 0,
                            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: image.bitmapInfo.rawValue)
    context?.interpolationQuality = .high
    context?.draw(image, in: CGRect(origin: .zero, size: pointSize))
    
    guard let scaledImage = context?.makeImage() else {return nil}
    
    let img = NSImage(cgImage: scaledImage,size:pixelSize)
    //img.cacheMode=NSImage.CacheMode.never
    
    //        let bitmapRep = NSBitmapImageRep(cgImage: scaledImage)
    //        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return nil }
    //        let finalImage = NSImage(data: jpegData)
    
    return img
}

func getImageSizeDeprecated2(url: URL) -> NSSize {
    let result=DEFAULT_SIZE
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return result }
    guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary? else { return result }
    guard let width = imageProperties[kCGImagePropertyPixelWidth] as? CGFloat,
          let height = imageProperties[kCGImagePropertyPixelHeight] as? CGFloat else { return result }
    
    return NSSize(width: width, height: height)
}
func getImageSizeDeprecated1(url: URL) -> NSSize{
    //居然不会释放内存
    let img = NSImageRep(contentsOf: url)
    let raw_width = Double( img?.pixelsWide ?? 512)
    let raw_height = Double( img?.pixelsHigh ?? 512)
    return NSSize(width: raw_width, height: raw_height)
}

func hexToNSColor(hex: String = "#000000", alpha: Double = 1.0) -> NSColor {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0

    // 尝试转换十六进制字符串
    Scanner(string: hexSanitized).scanHexInt64(&rgb)

    let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let blue = CGFloat(rgb & 0x0000FF) / 255.0

    return NSColor(red: red, green: green, blue: blue, alpha: alpha)
}

func parseExifDateTime(dateTimeString: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    dateFormatter.timeZone = TimeZone.current // 设置为你假设的时区
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

func getExifData(from imageURL: URL) -> [String: Any]? {
    guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
        log("Failed to create image source")
        return nil
    }
    
    guard var imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
        log("Failed to copy image properties")
        return nil
    }
    
    do {
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
        
        if let fileSize = fileAttributes[.size] as? Int {
            imageProperties["FileSize"]=readableFileSize(fileSize)
        }
        
        if let creationDate = fileAttributes[.creationDate] as? Date {
            imageProperties["FileCreatedTime"]=formatDateToCurrentTimeZone(creationDate)
        }
        
        if let modificationDate = fileAttributes[.modificationDate] as? Date {
            imageProperties["FileModifiedTime"]=formatDateToCurrentTimeZone(modificationDate)
        }
    } catch {
        log("Error retrieving file attributes: \(error.localizedDescription)")
    }
    
    if let imageSize=getImageSize(url: imageURL) {
        imageProperties["ImageSize"]=String(format: "%.0f", imageSize.width) + " × " + String(format: "%.0f", imageSize.height)
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

func formatExifData(_ imageProperties: [String: Any]) -> [(String, Any)] {
    var isUseChinese=false
    if Bundle.main.preferredLocalizations.first == "zh-Hans"{
        isUseChinese=true
    }
    
    var translationMap: [(CFString, String)] = [
        ("FileSize" as CFString, "文件大小"),
        ("ImageSize" as CFString, "图像分辨率"),
        ("FileCreatedTime" as CFString, "文件创建时间"),
        ("FileModifiedTime" as CFString, "文件修改时间"),
        
        ("-" as CFString, "-"),
        
        (kCGImagePropertyExifDateTimeOriginal, "拍摄时间"),
        (kCGImagePropertyExifDateTimeDigitized, "数字化时间"),
        (kCGImagePropertyTIFFDateTime, "元数据时间"),
        
        (kCGImagePropertyExifExposureTime, "曝光时间"),
        (kCGImagePropertyExifISOSpeedRatings, "ISO值"),
        (kCGImagePropertyExifFNumber, "光圈值 (FNumber)"),
        (kCGImagePropertyExifApertureValue, "光圈值 (Aperture)"),
        (kCGImagePropertyExifFlash, "闪光灯"),
        (kCGImagePropertyExifFocalLength, "焦距"),
        
        (kCGImagePropertyExifLensModel, "镜头型号"),
        (kCGImagePropertyTIFFModel, "相机型号"),
        (kCGImagePropertyTIFFMake, "制造商"),
        
        (kCGImagePropertyTIFFSoftware, "软件"),
        (kCGImagePropertyTIFFArtist, "作者"),
        
        (kCGImagePropertyColorModel, "色彩空间"),
        (kCGImagePropertyProfileName, "配置文件名称"),
        (kCGImagePropertyDepth, "位深度")
    ]
    
    for i in 0..<translationMap.count {
        if !isUseChinese {
            translationMap[i].1 = translationMap[i].0 as String
        }
    }
    
    var formattedData: [(String, Any)] = []
    
    for (key, translationKey) in translationMap {
        if translationKey == "-" {
            formattedData.append(("-", "-"))
        }else if let value = imageProperties[key as String] {
            formattedData.append((translationKey, value))
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
                    if isUseChinese {
                        formattedData.append((translationKey, flashValue == 0 ? "未使用" : "开启"))
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
                    formattedData.append((translationKey, "\(focalLength) mm"))
                }
            default:
                formattedData.append((translationKey, value))
            }
        } else if let tiffData = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any], let value = tiffData[key as String] {
            if key == kCGImagePropertyTIFFDateTime {
                if let dateTime = value as? String,
                   let timeAsDate = parseExifDateTime(dateTimeString: dateTime) {
                    formattedData.append((isUseChinese ? translationKey : "DateTimeMetadata", formatDateToCurrentTimeZone(timeAsDate)))
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
    guard let imageData = image.tiffRepresentation,
          let ciImage = CIImage(data: imageData) else {
        return nil
    }
    
    // 创建一个 CIDetector 并设置类型为二维码
    let context = CIContext()
    let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
    guard let qrDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options) else {
        return nil
    }
    
    // 使用 CIDetector 进行二维码检测
    let features = qrDetector.features(in: ciImage)
    
    // 提取检测到的二维码信息
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
    
    request.recognitionLanguages = ["zh-Hans", "en-US"] // 你可以根据需要添加更多的语言
    
    do {
        try requestHandler.perform([request])
    } catch {
        completion(.failure(error))
    }
}

class LargeImageProcessor {
    private static let cache: CustomCache<NSString, CacheWrapper> = {
        let cache = CustomCache<NSString, CacheWrapper>()
        cache.countLimit = 16 // 设置缓存容量
        return cache
    }()
    
    private static let lock = NSLock()
    private static var ongoingTasks: [String: (DispatchSemaphore, Int)] = [:]
    
    // 用于包装缓存中的图像，包括nil情况
    private class CacheWrapper {
        let image: NSImage?
        init(image: NSImage?) {
            self.image = image
        }
    }
    
    // 原始的图像处理函数
//    private static func originalGetResizedImage(url: URL, size: NSSize, rotate: Int = 0) -> NSImage? {
//        return getResizedImage(url: url, size: size, rotate: rotate)
//    }
    
    static func getImageCache(url: URL, size: NSSize, rotate: Int = 0, useOriginalImage: Bool, needWaitWhenSame: Bool = true) -> NSImage? {
        let cacheKey = "\(url.absoluteString)_\(size.width)x\(size.height)_\(rotate)" as NSString
        //print(cacheKey)
        
        // 先检查缓存中是否已有图像（包括nil情况）
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image
        }
        
        lock.lock()
        // 检查是否有相同参数的任务正在进行
        if let (semaphore, count) = ongoingTasks[cacheKey as String] {
            if needWaitWhenSame {
                ongoingTasks[cacheKey as String] = (semaphore, count + 1)
                lock.unlock()
                // 等待正在进行的任务完成
                semaphore.wait()
                // 任务完成后再检查缓存
                return cache.object(forKey: cacheKey)?.image
            }else{
                lock.unlock()
                return nil
            }
        } else {
            // 创建新的信号量并标记任务开始
            let semaphore = DispatchSemaphore(value: 0)
            ongoingTasks[cacheKey as String] = (semaphore, 1)
            lock.unlock()
            
            // 生成图像
            var image: NSImage?
            if useOriginalImage {
                image = NSImage(contentsOf: url)?.rotated(by: CGFloat(-90*rotate))
            }else{
                image = getResizedImage(url: url, size: size, rotate: rotate)
                if image == nil {
                    image = NSImage(contentsOf: url)?.rotated(by: CGFloat(-90*rotate))
                }
            }
            
            // 更新缓存（包括nil情况）
            let cacheWrapper = CacheWrapper(image: image)
            cache.setObject(cacheWrapper, forKey: cacheKey)
            
            lock.lock()
            // 任务完成，移除信号量
            let (_, count) = ongoingTasks.removeValue(forKey: cacheKey as String)!
            lock.unlock()
            
            // 释放所有等待的线程
            for _ in 0..<count {
                semaphore.signal()
            }
            
            return image
        }
    }
    
    // 检查缓存中是否有图像（且不是nil）
    static func isImageCached(url: URL, size: NSSize, rotate: Int = 0) -> Bool {
        let cacheKey = "\(url.absoluteString)_\(size.width)x\(size.height)_\(rotate)" as NSString
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image != nil
        }
        return false
    }
    
    // 检查缓存中是否有图像，有的话则返回
    static func isImageCachedAndGet(url: URL, size: NSSize, rotate: Int = 0) -> NSImage? {
        let cacheKey = "\(url.absoluteString)_\(size.width)x\(size.height)_\(rotate)" as NSString
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image
        }
        return nil
    }
    
    // 清空缓存
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
        cache.countLimit = 16 // 设置缓存容量
        return cache
    }()
    
    private static let lock = NSLock()
    private static var ongoingTasks: [String: (DispatchSemaphore, Int)] = [:]
    
    // 用于包装缓存中的图像，包括nil情况
    private class CacheWrapper {
        let image: NSImage?
        init(image: NSImage?) {
            self.image = image
        }
    }
    
    static func getImageCache(url: URL, size: NSSize? = nil, refSize: NSSize? = nil, needWaitWhenSame: Bool = true) -> NSImage? {
        let cacheKey = "\(url.absoluteString)_s\(size?.width ?? 0)x\(size?.height ?? 0)_r\(refSize?.width ?? 0)x\(refSize?.height ?? 0)" as NSString
        //print(cacheKey)
        
        // 先检查缓存中是否已有图像（包括nil情况）
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image
        }
        
        lock.lock()
        // 检查是否有相同参数的任务正在进行
        if let (semaphore, count) = ongoingTasks[cacheKey as String] {
            if needWaitWhenSame {
                ongoingTasks[cacheKey as String] = (semaphore, count + 1)
                lock.unlock()
                // 等待正在进行的任务完成
                semaphore.wait()
                // 任务完成后再检查缓存
                return cache.object(forKey: cacheKey)?.image
            }else{
                lock.unlock()
                return nil
            }
        } else {
            // 创建新的信号量并标记任务开始
            let semaphore = DispatchSemaphore(value: 0)
            ongoingTasks[cacheKey as String] = (semaphore, 1)
            lock.unlock()
            
            // 生成图像
            var image: NSImage?
            image = getImageThumb(url: url, size: size, refSize: refSize)
            
            // 更新缓存（包括nil情况）
            let cacheWrapper = CacheWrapper(image: image)
            cache.setObject(cacheWrapper, forKey: cacheKey)
            
            lock.lock()
            // 任务完成，移除信号量
            let (_, count) = ongoingTasks.removeValue(forKey: cacheKey as String)!
            lock.unlock()
            
            // 释放所有等待的线程
            for _ in 0..<count {
                semaphore.signal()
            }
            
            return image
        }
    }
    
    // 检查缓存中是否有图像（且不是nil）
    static func isImageCached(url: URL, size: NSSize, rotate: Int = 0) -> Bool {
        let cacheKey = "\(url.absoluteString)_\(size.width)x\(size.height)_\(rotate)" as NSString
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image != nil
        }
        return false
    }
    
    // 检查缓存中是否有图像，有的话则返回
    static func isImageCachedAndGet(url: URL, size: NSSize, rotate: Int = 0) -> NSImage? {
        let cacheKey = "\(url.absoluteString)_\(size.width)x\(size.height)_\(rotate)" as NSString
        if let cachedWrapper = cache.object(forKey: cacheKey) {
            return cachedWrapper.image
        }
        return nil
    }
    
    // 清空缓存
    static func clearCache() {
        cache.removeAllObjects()
    }
}
