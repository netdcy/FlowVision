//
//  ShortcutMatching.swift
//  FlowVision
//
//  Layout-aware semantic fallback for keyboard shortcuts.
//
//  The primary dispatch path matches on physical keyCode (see ShortcutStore.reverseIndex),
//  which is correct for US/ANSI and physical-position layouts (Dvorak/Colemak) but wrong for
//  ISO national layouts where +, -, = live on different physical keys or behind AltGr/Option
//  (e.g. Norwegian + sits on the US '-' key; Nordic '=' is Option+0). See issue #16.
//
//  This enum holds the pure matching helpers — no AppKit / NSEvent dependency so the algorithm
//  is unit-testable from raw glyph strings + modifiers.
//

import Foundation

enum ShortcutMatching {

    /// Index/lookup key: a produced glyph plus its semantically-relevant modifiers.
    struct SemKey: Hashable {
        let char: String
        let mods: Modifiers
    }

    /// Reduce modifiers to the set that meaningfully distinguishes a shortcut for `char`.
    ///
    /// For symbol glyphs (anything not a letter/digit), Shift and Option are *consumers* —
    /// they are what produced the glyph (US '+' = Shift+=, Nordic '=' = Option+0), so they
    /// must not be required again at match time. Only ⌘ and ⌃ survive.
    ///
    /// For letters/digits the glyph is the base key, so Shift stays significant (don't
    /// collapse ⌘⇧Z onto ⌘Z); Option/Fn are dropped as they alter the glyph or are implicit.
    static func semMods(_ mods: Modifiers, char: String) -> Modifiers {
        if isSymbol(char) {
            return mods.intersection([.command, .control])
        }
        return mods.intersection([.command, .control, .shift])
    }

    /// Expand produced glyphs with zoom-cluster equivalences so a key that yields '+'
    /// also satisfies the '=' binding, and '_' satisfies '-'.
    static func expand(_ chars: Set<String>) -> Set<String> {
        var out = chars
        for c in chars {
            switch c {
            case "+": out.insert("=")
            case "_": out.insert("-")
            default: break
            }
        }
        return out
    }

    /// Glyphs a key event produced, equivalence-expanded.
    ///
    /// Resolves the glyph with the same rule the recorder uses (`recordedCharacter`) so a
    /// keypress at dispatch produces exactly the glyph its binding was indexed under. That
    /// rule prefers the literal `characters` (carries Option/AltGr and Shift symbols) but
    /// rejects control codes and empties — using the literal unconditionally would both leak
    /// the base-layer digit (Nordic Option+0 reports characters="=" but ignoringModifiers="0",
    /// falsely firing zoom-reset) and emit control codes for Ctrl combos.
    static func producedChars(characters: String?, ignoringModifiers: String?) -> Set<String> {
        let glyph = recordedCharacter(literal: characters, ignoringModifiers: ignoringModifiers)
        guard !glyph.isEmpty else { return [] }
        return expand([glyph])
    }

    /// Glyph to persist when recording a chord, kept symmetric with `producedChars` so a
    /// re-recorded binding matches what dispatch later sees.
    ///
    /// Prefers the literal `characters` when it is a normal printable glyph — this captures
    /// Option/AltGr-produced symbols (Nordic '=' is Option+0, where `charactersIgnoringModifiers`
    /// reports the base-layer '0'). Falls back to the modifier-independent base for control
    /// combos (Ctrl+A reports a control code) and dead keys / empty literals.
    static func recordedCharacter(literal: String?, ignoringModifiers: String?) -> String {
        let lit = literal ?? ""
        if let scalar = lit.unicodeScalars.first, scalar.value >= 0x20 {
            return lit.lowercased()
        }
        return (ignoringModifiers ?? "").lowercased()
    }

    /// Build the canonical SemKey for indexing or lookup of a (glyph, modifiers) pair.
    static func key(char: String, mods: Modifiers) -> SemKey {
        SemKey(char: char.lowercased(), mods: semMods(mods, char: char))
    }

    /// Merge semantic and physical candidates with **semantic first**, deduped (stable).
    ///
    /// Semantic (the glyph the user actually typed) must outrank physical keyCode: on ISO
    /// layouts the physical key under a moved symbol is often bound to the *opposite* action
    /// (Norwegian '+' sits on the US '-' key, whose keyCode is bound to zoom-out). Preferring
    /// the glyph fixes issue #16 while staying a no-op on US/ANSI, where both agree.
    static func order<T: Hashable>(semantic: [T], physical: [T]) -> [T] {
        var out: [T] = []
        var seen: Set<T> = []
        for item in semantic + physical where seen.insert(item).inserted {
            out.append(item)
        }
        return out
    }

    private static func isSymbol(_ char: String) -> Bool {
        guard let c = char.first else { return false }
        return !c.isLetter && !c.isNumber
    }
}
