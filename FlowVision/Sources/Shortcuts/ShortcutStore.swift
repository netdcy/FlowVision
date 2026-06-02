//
//  ShortcutStore.swift
//  FlowVision
//
//  Each action holds zero, one, or many KeyChords. Persists to UserDefaults
//  (`shortcutBindings.v2`) and posts `.shortcutsChanged` on every mutation.
//  Main-thread only — no locking.
//

import Cocoa

final class ShortcutStore {
    static let shared = ShortcutStore()
    private init() {}

    /// Active binding map. Missing key + not in `clearedExplicitly` = use defaults.
    /// Empty array = user has explicitly removed all bindings.
    private(set) var bindings: [ShortcutAction: [KeyChord]] = [:]

    /// Lookup index. Multiple actions may share a chord (legal when scopes are
    /// disjoint — enforced by conflict UI in the settings pane, not by the store).
    private(set) var reverseIndex: [KeyChord: [ShortcutAction]] = [:]

    /// Layout-aware fallback index keyed on produced glyph rather than physical keyCode.
    /// Consulted only when `reverseIndex` misses, so it never overrides a physical match
    /// (zero regression for US/ANSI and Dvorak/Colemak). Fixes ISO layouts where +, -, =
    /// move physical position or sit behind Option/AltGr. See issue #16 / ShortcutMatching.
    private(set) var semanticIndex: [ShortcutMatching.SemKey: [ShortcutAction]] = [:]

    /// Actions the user has wiped completely. Distinguishes "user cleared all"
    /// from "never persisted" so defaults don't sneak back after a reset-empty.
    private var clearedExplicitly: Set<ShortcutAction> = []

    private let defaultsKey   = "shortcutBindings.v2"

    // MARK: - Wire format v2

    private struct Wire: Codable {
        let version: Int
        let entries: [Entry]
    }

    private struct Entry: Codable {
        let action: ShortcutAction?
        let chords: [KeyChord]

        init(action: ShortcutAction, chords: [KeyChord]) {
            self.action = action
            self.chords = chords
        }

        enum CodingKeys: String, CodingKey { case action, chords }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try? c.decode(String.self, forKey: .action)
            self.action = raw.flatMap { ShortcutAction(rawValue: $0) }
            self.chords = (try? c.decode([KeyChord].self, forKey: .chords)) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(action?.rawValue, forKey: .action)
            try c.encode(chords, forKey: .chords)
        }
    }

    // MARK: - Public API

    /// Returns the active chord list for an action: stored value if present,
    /// empty if explicitly cleared, defaults otherwise.
    func chords(for action: ShortcutAction) -> [KeyChord] {
        if let stored = bindings[action] { return stored }
        if clearedExplicitly.contains(action) { return [] }
        return action.defaultChords
    }

    func load() {
        clearedExplicitly.removeAll()
        bindings = [:]

        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let wire = try? JSONDecoder().decode(Wire.self, from: data) {
            applyV2(wire)
        }
        rebuildIndex()
    }

    private func applyV2(_ wire: Wire) {
        guard wire.version == 2 else { return }
        for entry in wire.entries {
            guard let a = entry.action else { continue }
            if entry.chords.isEmpty {
                clearedExplicitly.insert(a)
            } else {
                bindings[a] = entry.chords
            }
        }
    }

    /// Replace chord at `index` for `action`. If `chord` is nil, remove that slot.
    /// If `index` equals current count, the chord is appended. Indexes beyond
    /// `count` are rejected to avoid silent phantom appends.
    func setChord(_ chord: KeyChord?, at index: Int, for action: ShortcutAction) {
        var current = chords(for: action)
        if let chord {
            if index < current.count {
                current[index] = chord
            } else if index == current.count {
                current.append(chord)
            } else {
                return
            }
        } else {
            guard index < current.count else { return }
            current.remove(at: index)
        }
        commit(current, for: action)
    }

    /// Append a chord to the end of `action`'s chord list.
    func appendChord(_ chord: KeyChord, for action: ShortcutAction) {
        var current = chords(for: action)
        current.append(chord)
        commit(current, for: action)
    }

    /// Remove the chord at `index` from `action`'s chord list.
    func removeChord(at index: Int, for action: ShortcutAction) {
        var current = chords(for: action)
        guard index < current.count else { return }
        current.remove(at: index)
        commit(current, for: action)
    }

    /// Remove every occurrence of `chord` from `action`'s chord list. No-op if
    /// the chord isn't bound on that action.
    func removeChord(_ chord: KeyChord, from action: ShortcutAction) {
        var current = chords(for: action)
        let filtered = current.filter { $0 != chord }
        guard filtered.count != current.count else { return }
        current = filtered
        commit(current, for: action)
    }

    /// Remove every occurrence of `chord` from each action in `actions` in one
    /// pass. Posts a single `.shortcutsChanged` notification (object: nil) at
    /// the end so the Settings view rebuilds once instead of N times.
    func batchRemove(chord: KeyChord, from actions: [ShortcutAction]) {
        var anyChanged = false
        for action in actions {
            let current = chords(for: action)
            let filtered = current.filter { $0 != chord }
            guard filtered.count != current.count else { continue }
            anyChanged = true
            if filtered.isEmpty {
                bindings.removeValue(forKey: action)
                clearedExplicitly.insert(action)
            } else {
                bindings[action] = filtered
                clearedExplicitly.remove(action)
            }
        }
        guard anyChanged else { return }
        persist()
        rebuildIndex()
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }

    /// Reset `action` to its built-in defaults (or empty if no default).
    func reset(_ action: ShortcutAction) {
        clearedExplicitly.remove(action)
        bindings.removeValue(forKey: action)
        persist()
        rebuildIndex()
        NotificationCenter.default.post(name: .shortcutsChanged, object: action)
    }

    /// Wipe all custom bindings, restore defaults.
    func resetAll() {
        clearedExplicitly.removeAll()
        bindings.removeAll()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        rebuildIndex()
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }

    private func commit(_ chords: [KeyChord], for action: ShortcutAction) {
        if chords.isEmpty {
            bindings.removeValue(forKey: action)
            clearedExplicitly.insert(action)
        } else {
            bindings[action] = chords
            clearedExplicitly.remove(action)
        }
        persist()
        rebuildIndex()
        NotificationCenter.default.post(name: .shortcutsChanged, object: action)
    }

    // MARK: - Internals

    private func rebuildIndex() {
        var idx: [KeyChord: [ShortcutAction]] = [:]
        var sem: [ShortcutMatching.SemKey: [ShortcutAction]] = [:]
        for action in ShortcutAction.allCases {
            // Dedupe within an action so intra-action chord duplicates
            // don't show up twice in reverseIndex[chord].
            var seen: Set<KeyChord> = []
            var seenSem: Set<ShortcutMatching.SemKey> = []
            for chord in chords(for: action) where seen.insert(chord).inserted {
                idx[chord, default: []].append(action)
                // Index the recorded glyph for the semantic fallback. Special keys
                // (arrows, Esc, …) record an empty character and are physical-only.
                guard !chord.character.isEmpty else { continue }
                let key = ShortcutMatching.key(char: chord.character, mods: chord.modifiers)
                if seenSem.insert(key).inserted {
                    sem[key, default: []].append(action)
                }
            }
        }
        reverseIndex = idx
        semanticIndex = sem
    }

    /// Layout-aware fallback lookup. Returns actions whose recorded glyph matches one of
    /// the glyphs this key event produced. Call only after `reverseIndex` misses.
    func semanticCandidates(characters: String?,
                            ignoringModifiers: String?,
                            modifiers: Modifiers) -> [ShortcutAction] {
        let glyphs = ShortcutMatching.producedChars(characters: characters,
                                                    ignoringModifiers: ignoringModifiers)
        guard !glyphs.isEmpty else { return [] }
        var out: [ShortcutAction] = []
        var seen: Set<ShortcutAction> = []
        for glyph in glyphs {
            let key = ShortcutMatching.key(char: glyph, mods: modifiers)
            for action in semanticIndex[key] ?? [] where seen.insert(action).inserted {
                out.append(action)
            }
        }
        return out
    }

    @discardableResult
    private func persist() -> Bool {
        var entries: [Entry] = []
        for a in ShortcutAction.allCases {
            if clearedExplicitly.contains(a) {
                entries.append(Entry(action: a, chords: []))
            } else if let chords = bindings[a] {
                entries.append(Entry(action: a, chords: chords))
            }
        }
        do {
            let data = try JSONEncoder().encode(Wire(version: 2, entries: entries))
            UserDefaults.standard.set(data, forKey: defaultsKey)
            return true
        } catch {
            NSLog("[shortcuts] ShortcutStore.persist failed: \(error)")
            return false
        }
    }
}
