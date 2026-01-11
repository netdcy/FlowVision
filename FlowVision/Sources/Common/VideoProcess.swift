//
//  VideoProcess.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import AVKit

class NoHitAVPlayerView: AVPlayerView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return superview?.hitTest(convert(point, to: superview))
    }
}

class LargeAVPlayerView: AVPlayerView {
//    override func hitTest(_ point: NSPoint) -> NSView? {
//        return nil // superview?.hitTest(convert(point, to: superview))
//    }
    override func scrollWheel(with event: NSEvent) {
        // 不响应滚动事件，直接传递给下一个
        // Don't respond to scroll events, pass directly to next responder
        self.nextResponder?.scrollWheel(with: event)
    }
}


func createLoopingComposition(url: URL) -> AVMutableComposition? {
    let asset = AVAsset(url: url)
    guard let videoTrack = asset.tracks(withMediaType: .video).first,
        let audioTrack = asset.tracks(withMediaType: .audio).first else {
        return nil
    }

    // 打印视频轨道信息
    // Print video track information
    // let asset = AVAsset(url: url)
    // for track in asset.tracks {
    //     print("媒体类型:", track.mediaType)
    //     print("时长范围:", track.timeRange)
    // }

    // 计算音视频轨道的共同时间范围
    // Calculate common time range of audio and video tracks
    let timeRange = CMTimeRangeGetIntersection(videoTrack.timeRange, otherRange: audioTrack.timeRange)

    // 创建一个新的可变组合
    // Create a new mutable composition
    let composition = AVMutableComposition()

    do {
        // 将共同时间范围内的音视频轨道插入到新的组合中
        // Insert audio and video tracks within common time range into new composition
        try composition.insertTimeRange(timeRange, of: asset, at: .zero)
    } catch {
        print("Error inserting time range into composition: \(error)")
        return nil
    }

    // 保持视频轨道的方向
    // Preserve video track orientation
    if let compositionVideoTrack = composition.tracks(withMediaType: .video).first {
        compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
    }

    return composition
}

func getCommonTimeRange(url: URL) -> CMTimeRange? {
    let asset = AVAsset(url: url)
    guard let videoTrack = asset.tracks(withMediaType: .video).first,
          let audioTrack = asset.tracks(withMediaType: .audio).first else {
        return nil
    }

    // 计算音视频轨道的共同时间范围
    // Calculate common time range of audio and video tracks
    return CMTimeRangeGetIntersection(videoTrack.timeRange, otherRange: audioTrack.timeRange)
}

