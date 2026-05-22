//
//  KeyChord.swift
//  FlowVision
//
//  Layout-independent keyboard chord representation backing ShortcutStore.
//

import Cocoa

/// OptionSet wrapper around the subset of `NSEvent.ModifierFlags` that participates
/// in user-rebindable shortcuts. ⌘ ⌥ ⌃ ⇧ Fn.
struct Modifiers: OptionSet, Hashable, Codable {
    let rawValue: UInt

    static let command  = Modifiers(rawValue: 1 << 0)
    static let option   = Modifiers(rawValue: 1 << 1)
    static let control  = Modifiers(rawValue: 1 << 2)
    static let shift    = Modifiers(rawValue: 1 << 3)
    static let function = Modifiers(rawValue: 1 << 4)

    init(rawValue: UInt) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
        var r: UInt = 0
        if flags.contains(.command)  { r |= 1 << 0 }
        if flags.contains(.option)   { r |= 1 << 1 }
        if flags.contains(.control)  { r |= 1 << 2 }
        if flags.contains(.shift)    { r |= 1 << 3 }
        if flags.contains(.function) { r |= 1 << 4 }
        self.rawValue = r
    }

    /// Inverse mapping for round-tripping to AppKit menu keyEquivalent masks.
    var nsFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if contains(.command)  { f.insert(.command) }
        if contains(.option)   { f.insert(.option) }
        if contains(.control)  { f.insert(.control) }
        if contains(.shift)    { f.insert(.shift) }
        if contains(.function) { f.insert(.function) }
        return f
    }
}

/// A single key chord. Hash/equality intentionally on `(keyCode, modifiers)` only —
/// `character` is display metadata captured at record time so menu glyphs stay stable
/// per recording layout but two recordings of the same physical key on different layouts
/// still match.
struct KeyChord: Codable {
    let keyCode: UInt16
    let character: String
    let modifiers: Modifiers

    init(keyCode: UInt16, character: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.character = character
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        self.keyCode = event.keyCode
        self.character = (event.charactersIgnoringModifiers ?? "").lowercased()
        var m = Modifiers(event.modifierFlags)
        if Self.isImplicitFn(event.keyCode) { m.remove(.function) }
        self.modifiers = m
    }

    /// Keys that macOS auto-flags with `.function` regardless of physical Fn press.
    /// Strip the implicit flag during record so chord storage is clean.
    static func isImplicitFn(_ k: UInt16) -> Bool {
        switch k {
        // Arrows + nav cluster
        case 0x7B, 0x7C, 0x7D, 0x7E: return true     // ← → ↓ ↑
        case 0x73, 0x77, 0x74, 0x79: return true     // home, end, pgup, pgdn
        case 0x75: return true                       // forward delete
        // F1–F20
        case 0x7A, 0x78, 0x63, 0x76, 0x60,
             0x61, 0x62, 0x64, 0x65, 0x6D,
             0x67, 0x6F, 0x69, 0x6B, 0x71,
             0x6A, 0x40, 0x4F, 0x50, 0x5A: return true
        default: return false
        }
    }
}

extension KeyChord: Hashable {
    static func == (l: KeyChord, r: KeyChord) -> Bool {
        l.keyCode == r.keyCode && l.modifiers == r.modifiers
    }

    func hash(into h: inout Hasher) {
        h.combine(keyCode)
        h.combine(modifiers)
    }
}

extension KeyChord {
    /// Virtual keyCode for Escape. Named constant to replace magic 0x35 in call sites.
    static let escKeyCode: UInt16 = 0x35

    /// Apple HIG combos that shouldn't be silently hijacked — triggers warning when
    /// the user binds one to a non-system-conventional action. Computed once.
    private static let systemReservedSet: Set<KeyChord> = {
        let cmd = Modifiers.command
        let opt = Modifiers.option
        return [
            KeyChord(keyCode: 0x0C, character: "q", modifiers: cmd),       // Cmd+Q
            KeyChord(keyCode: 0x0D, character: "w", modifiers: cmd),       // Cmd+W
            KeyChord(keyCode: 0x2D, character: "n", modifiers: cmd),       // Cmd+N
            KeyChord(keyCode: 0x2B, character: ",", modifiers: cmd),       // Cmd+,
            KeyChord(keyCode: 0x04, character: "h", modifiers: cmd),       // Cmd+H
            KeyChord(keyCode: 0x04, character: "h", modifiers: [cmd, opt]),// Cmd+Opt+H
            KeyChord(keyCode: 0x03, character: "f", modifiers: cmd),       // Cmd+F
            KeyChord(keyCode: 0x0F, character: "r", modifiers: cmd),       // Cmd+R
            KeyChord(keyCode: 0x00, character: "a", modifiers: cmd),       // Cmd+A
            KeyChord(keyCode: 0x08, character: "c", modifiers: cmd),       // Cmd+C
            KeyChord(keyCode: 0x09, character: "v", modifiers: cmd),       // Cmd+V
            KeyChord(keyCode: 0x07, character: "x", modifiers: cmd),       // Cmd+X
            KeyChord(keyCode: 0x06, character: "z", modifiers: cmd),       // Cmd+Z
            KeyChord(keyCode: 0x2E, character: "m", modifiers: cmd),       // Cmd+M
        ]
    }()

    var isSystemReserved: Bool { Self.systemReservedSet.contains(self) }
}

extension KeyChord {
    /// Human-readable glyph string. Modifier order matches macOS menu convention: Fn ⌃ ⌥ ⇧ ⌘.
    var displayString: String {
        var s = ""
        if modifiers.contains(.function) && !KeyChord.isImplicitFn(keyCode) { s += "Fn" }
        if modifiers.contains(.control)  { s += "⌃" }
        if modifiers.contains(.option)   { s += "⌥" }
        if modifiers.contains(.shift)    { s += "⇧" }
        if modifiers.contains(.command)  { s += "⌘" }
        s += Self.keyToken(keyCode: keyCode, character: character)
        return s
    }

    static func keyToken(keyCode: UInt16, character: String) -> String {
        switch keyCode {
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        case 0x31: return "␣"
        case 0x24: return "⏎"
        case 0x4C: return "⌤"
        case 0x30: return "⇥"
        case 0x35: return "Esc"
        case 0x33: return "⌫"
        case 0x75: return "⌦"
        case 0x73: return "↖"
        case 0x77: return "↘"
        case 0x74: return "⇞"
        case 0x79: return "⇟"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x69: return "F13"
        case 0x6B: return "F14"
        case 0x71: return "F15"
        case 0x6A: return "F16"
        case 0x40: return "F17"
        case 0x4F: return "F18"
        case 0x50: return "F19"
        case 0x5A: return "F20"
        default:
            return character.isEmpty ? "?" : character.uppercased()
        }
    }
}

/// Context in which an action is allowed to fire.
enum ContextScope: String, Codable {
    case browserOnly
    case viewerOnly
    case both
}

/// Top-level grouping in the Settings → Actions outline view.
enum ShortcutCategory: String, CaseIterable, Codable {
    case navigation
    case viewer
    case video
    case window
    case fileOps
    case viewMode
    case visibility
    case viewerBehavior
    case rating
    case finderTags
    case profiles
    case search
    case quickSearch

    var displayName: String {
        let fallback: String
        switch self {
        case .navigation:     fallback = "Navigation"
        case .viewer:         fallback = "Viewer"
        case .video:          fallback = "Video"
        case .window:         fallback = "Window"
        case .fileOps:        fallback = "File Operations"
        case .viewMode:       fallback = "View Mode"
        case .visibility:     fallback = "Visibility"
        case .viewerBehavior: fallback = "Viewer Behavior"
        case .rating:         fallback = "Rating"
        case .finderTags:     fallback = "Finder Tags"
        case .profiles:       fallback = "Profiles"
        case .search:         fallback = "Search"
        case .quickSearch:    fallback = "Quick Search"
        }
        return NSLocalizedString("shortcut.category.\(rawValue)",
                                 value: fallback,
                                 comment: "shortcut category display name")
    }
}

extension Notification.Name {
    /// Posted when ShortcutStore mutates. `object` is the affected `ShortcutAction`,
    /// or nil if all bindings changed (e.g. resetAll).
    static let shortcutsChanged = Notification.Name("shortcutsChanged")
}
