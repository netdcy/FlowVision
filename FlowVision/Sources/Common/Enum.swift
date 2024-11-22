//
//  Enum.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation
import Settings

enum FileType: Int, Codable {
    case image,video,other,folder,notSet,all
}

enum GestureDirection: Int, Codable {
    case right, left, up, down, up_right, up_left, down_left, down_right, zero, forward, back
}

enum LayoutType: Int, Codable {
    case justified,waterfall,grid,detail
}

enum SortType: Int, Codable {
    case pathA,pathZ,extA,extZ,sizeA,sizeZ,createDateA,createDateZ,modDateA,modDateZ,addDateA,addDateZ,random
}

extension Settings.PaneIdentifier {
    static let general = Self("general")
    static let actions = Self("actions")
    static let advanced = Self("advanced")
}
