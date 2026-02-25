//
//  FinderTag.swift
//  FlowVision
//

import Foundation
import Cocoa

struct FinderTag {
    let name: String
    let color: NSColor

    static let all: [FinderTag] = [
        FinderTag(name: "Red", color: NSColor(red: 0.94, green: 0.22, blue: 0.22, alpha: 1.0)),
        FinderTag(name: "Orange", color: NSColor(red: 0.96, green: 0.56, blue: 0.12, alpha: 1.0)),
        FinderTag(name: "Yellow", color: NSColor(red: 0.98, green: 0.84, blue: 0.16, alpha: 1.0)),
        FinderTag(name: "Green", color: NSColor(red: 0.30, green: 0.78, blue: 0.30, alpha: 1.0)),
        FinderTag(name: "Blue", color: NSColor(red: 0.22, green: 0.47, blue: 0.94, alpha: 1.0)),
        FinderTag(name: "Purple", color: NSColor(red: 0.62, green: 0.35, blue: 0.87, alpha: 1.0)),
        FinderTag(name: "Gray", color: NSColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1.0)),
    ]

    var dotImage: NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    static func byName(_ name: String) -> FinderTag? {
        all.first { $0.name == name }
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
