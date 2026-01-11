//
//  Enum.swift
//  FlowVision
//

import Foundation
import Settings

enum FileType: Int, Codable {
    case image,video,other,folder,notSet,all
}

enum RightMouseGestureDirection: Int, Codable {
    case right, left, up, down, up_right, up_left, down_left, down_right, zero, forward, back
}

enum LayoutType: Int, Codable {
    case justified,waterfall,grid,detail
}

enum SortType: Int, Codable {
    case pathA,pathZ,extA,extZ,sizeA,sizeZ,createDateA,createDateZ,modDateA,modDateZ,addDateA,addDateZ,random,exifDateA,exifDateZ,exifPixelA,exifPixelZ
}

extension Settings.PaneIdentifier {
    static let general = Self("general")
    static let custom = Self("custom")
    static let actions = Self("actions")
    static let advanced = Self("advanced")
}
