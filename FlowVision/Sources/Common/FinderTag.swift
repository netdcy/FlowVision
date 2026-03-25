//
//  FinderTag.swift
//  FlowVision
//

import Foundation
import Cocoa

struct FinderTag {
    let name: String
    let color: NSColor?
    let colorIndex: Int?
    let dotImage: NSImage?
    
    static let all: [FinderTag] = {
        let customLabels = [
            FinderTag(name: "个人", color: customLabelColor, colorIndex: nil, dotImage: customLabelDotImage)
        ]
        return defaultColorLabels + customLabels
    }()
    
    static let customLabelColor: NSColor = NSColor.white
    static let customLabelDotImage: NSImage = makeDotImage(for: customLabelColor)
    
    static let defaultColorLabels: [FinderTag] = {
        let labels = NSWorkspace.shared.fileLabels
        let colors = NSWorkspace.shared.fileLabelColors
        guard labels.count >= 8, colors.count >= 8 else { return [] }
        // 0=None, 1=Gray, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Red, 7=Orange
        let order: [Int] = [6, 7, 5, 2, 4, 3, 1]  // 红橙黄绿蓝紫灰
        return order.compactMap { i in
            let color = colors[i]
            return FinderTag(name: labels[i], color: color, colorIndex: i, dotImage: makeDotImage(for: color))
        }
    }()

    static func byName(_ name: String) -> FinderTag? {
        all.first { $0.name == name } ?? FinderTag(name: name, color: customLabelColor, colorIndex: nil, dotImage: nil)
    }
    
    static func makeDotImage(for color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    static func makeDotImageWithBorder(for color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let r = rect.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(ovalIn: r)
            color.setFill()
            path.fill()
            let strokeColor: NSColor = color.usingColorSpace(.genericGray)?.whiteComponent ?? 0 > 0.9 ? .black : .white
            strokeColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}

enum FinderTagHelper {
    static func readTags(from url: URL) -> [String] {
        guard let values = try? url.resourceValues(forKeys: [.tagNamesKey]) else { return [] }
        return values.tagNames ?? []
    }

    static func writeTags(_ tags: [String], to url: URL) {
        try? (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    /// returns `true` if the tag was added, `false` if removed
    @discardableResult
    static func toggleTag(_ tagName: String, on urls: [URL]) -> Bool {
        let allHaveTag = urls.allSatisfy { readTags(from: $0).contains(tagName) }
        let adding = !allHaveTag
        for url in urls {
            var tags = readTags(from: url)
            if adding {
                if !tags.contains(tagName) { tags.append(tagName) }
            } else {
                tags.removeAll { $0 == tagName }
            }
            writeTags(tags, to: url)
        }
        return adding
    }

    static func removeAllTags(from urls: [URL]) {
        for url in urls {
            writeTags([], to: url)
        }
    }
}
