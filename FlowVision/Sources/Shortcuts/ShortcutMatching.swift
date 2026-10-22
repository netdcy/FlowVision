//
//  ShortcutMatching.swift
//  FlowVision
//
//  Layout-aware matching rules for keyboard shortcuts.
//
//  A chord names either a glyph (letter, digit, symbol) or a special key (arrows, Esc,
//  Return, F-keys, ...). Glyph chords match the character the active layout puts on the
//  pressed key, like menus do, so AZERTY Cmd+A is never read as the US Cmd+Q position.
//  Special keys match by key code. Candidates come in tiers, most specific first:
//
//  1. exact:    the key's base glyph (or special key code) with exactly the same modifiers.
//  2. symbol:   the glyph the modifiers produced, for bindings to a bare symbol. Shift and
//               Option are what produced it (US '+' = Shift+=, Nordic '=' = Option+0), so
//               only ⌘ and ⌃ must match. Covers symbols that move between layouts (#16).
//  3. position: the US key position, only when the key has no ASCII letter or digit to
//               match by name. Non-Latin and accented letters (Russian, Czech number row)
//               reach letter and digit bindings; number-row symbols (AZERTY &é"') reach
//               digit bindings.
//
//  The dispatcher runs the first tier that has an eligible action and never moves on to a
//  later tier, so a handler that declines can't hand the key to an unrelated binding.
//

import Foundation

enum ShortcutMatching {

    /// The parts of a key event the matcher needs. Built from NSEvent via `init(event:)`.
    struct Input {
        let keyCode: UInt16
        let modifiers: Modifiers
        /// The layout's unmodified character for the key, lowercased. Empty for special keys.
        let baseGlyph: String
        /// The character the held modifiers produced. Empty for special keys, dead keys
        /// and control codes.
        let producedGlyph: String

        /// - Parameters:
        ///   - base: characters with no modifiers applied (`characters(byApplyingModifiers: [])`).
        ///   - produced: characters with the held modifiers (`characters`).
        ///   - ignoringModifiers: `charactersIgnoringModifiers`, used when `base` is empty.
        init(keyCode: UInt16, modifiers: Modifiers,
             base: String?, produced: String?, ignoringModifiers: String?) {
            self.keyCode = keyCode
            var mods = modifiers
            if KeyChord.isImplicitFn(keyCode) { mods.remove(.function) }
            self.modifiers = mods
            if KeyChord.isSpecialKey(keyCode) {
                baseGlyph = ""
                producedGlyph = ""
            } else {
                baseGlyph = ShortcutMatching.printable(base)
                    ?? ShortcutMatching.printable(ignoringModifiers) ?? ""
                producedGlyph = ShortcutMatching.printable(produced) ?? ""
            }
        }
    }

    struct GlyphKey: Hashable {
        let glyph: String
        let modifiers: Modifiers
    }

    struct PositionKey: Hashable {
        let keyCode: UInt16
        let modifiers: Modifiers
    }

    /// Modifiers that must still match for a symbol binding once Shift / Option produced it.
    static let symbolModifiers: Modifiers = [.command, .control]

    /// The glyph followed by its zoom-cluster partner: a key yielding '+' also satisfies
    /// '=' bindings and '_' satisfies '-'. The exact glyph always comes first.
    static func equivalents(of glyph: String) -> [String] {
        switch glyph {
        case "+": return ["+", "="]
        case "_": return ["_", "-"]
        default:  return [glyph]
        }
    }

    /// Whether a key whose base glyph is `eventGlyph` may trigger the binding recorded at
    /// the same US key position with glyph `boundGlyph`. See tier 3 in the file header.
    static func allowsPositionMatch(eventGlyph: String, boundGlyph: String) -> Bool {
        guard let c = eventGlyph.first, !isASCIIAlphanumeric(c) else { return false }
        guard let bound = boundGlyph.first else { return false }
        if c.isLetter { return isASCIIAlphanumeric(bound) }
        return bound.isASCII && bound.isNumber
    }

    /// The actions of the first tier holding at least one eligible action.
    static func firstEligibleTier<T>(_ tiers: [[T]], where isEligible: (T) -> Bool) -> [T] {
        for tier in tiers {
            let eligible = tier.filter(isEligible)
            if !eligible.isEmpty { return eligible }
        }
        return []
    }

    static func isSymbol(_ glyph: String) -> Bool {
        guard let c = glyph.first else { return false }
        return !c.isLetter && !c.isNumber
    }

    private static func isASCIIAlphanumeric(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }

    /// Lowercased `s` if it is a visible character, nil for empty strings, control codes,
    /// DEL and the private-use range AppKit reports for function keys.
    private static func printable(_ s: String?) -> String? {
        guard let s, let scalar = s.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F,
              !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        return s.lowercased()
    }
}
