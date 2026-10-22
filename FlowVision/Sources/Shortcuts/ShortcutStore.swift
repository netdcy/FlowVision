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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Active binding map. Missing key + not in `clearedExplicitly` = use defaults.
    /// Empty array = user has explicitly removed all bindings.
    private(set) var bindings: [ShortcutAction: [KeyChord]] = [:]

    /// Exact-match index keyed by chord identity (see KeyChord ==). Multiple actions may
    /// share a chord when their scopes are disjoint; the settings pane's conflict UI
    /// enforces that, not the store.
    private(set) var reverseIndex: [KeyChord: [ShortcutAction]] = [:]

    /// Bare-symbol bindings by glyph and ⌘/⌃, for the symbol tier in ShortcutMatching.
    private var symbolIndex: [ShortcutMatching.GlyphKey: [ShortcutAction]] = [:]

    /// Glyph bindings by recorded key position, for the position tier in ShortcutMatching.
    private var positionIndex: [ShortcutMatching.PositionKey: [(glyph: String, action: ShortcutAction)]] = [:]

    /// Actions the user has wiped completely. Distinguishes "user cleared all"
    /// from "never persisted" so defaults don't sneak back after a reset-empty.
    private var clearedExplicitly: Set<ShortcutAction> = []

    // v2 is the first format ever persisted (no build wrote a v1 blob), so there
    // is nothing to migrate from. Bump the suffix only alongside a migration.
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
            // An unreadable chord list would otherwise load as "user cleared every chord".
            // Drop the entry instead so the action keeps its defaults.
            if let chords = try? c.decode([KeyChord].self, forKey: .chords) {
                self.action = raw.flatMap { ShortcutAction(rawValue: $0) }
                self.chords = chords
            } else {
                self.action = nil
                self.chords = []
            }
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

        if let data = defaults.data(forKey: defaultsKey),
           let wire = try? JSONDecoder().decode(Wire.self, from: data) {
            applyV2(wire)
        }
        rebuildIndex()
    }

    private func applyV2(_ wire: Wire) {
        guard wire.version == 2 else { return }
        for entry in wire.entries {
            guard let a = entry.action else { continue }
            assign(entry.chords, to: a)
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
        commit(chords(for: action) + [chord], for: action)
    }

    /// Remove the chord at `index` from `action`'s chord list.
    func removeChord(at index: Int, for action: ShortcutAction) {
        setChord(nil, at: index, for: action)
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
            assign(filtered, to: action)
        }
        guard anyChanged else { return }
        didChange(nil)
    }

    /// Reset `action` to its built-in defaults (or empty if no default).
    func reset(_ action: ShortcutAction) {
        clearedExplicitly.remove(action)
        bindings.removeValue(forKey: action)
        didChange(action)
    }

    /// Wipe all custom bindings, restore defaults.
    func resetAll() {
        clearedExplicitly.removeAll()
        bindings.removeAll()
        defaults.removeObject(forKey: defaultsKey)
        rebuildIndex()
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }

    /// Candidate actions for a key event, grouped into ShortcutMatching's tiers (exact,
    /// symbol, position). A glyph and its zoom-cluster partner get separate tiers so a '+'
    /// binding that declines never hands the key to '='. The dispatcher runs only the
    /// first tier with an eligible action.
    func candidateTiers(for input: ShortcutMatching.Input) -> [[ShortcutAction]] {
        guard !input.baseGlyph.isEmpty else {
            let chord = KeyChord(keyCode: input.keyCode, character: "", modifiers: input.modifiers)
            return [reverseIndex[chord] ?? []]
        }

        var tiers = ShortcutMatching.equivalents(of: input.baseGlyph).map { glyph in
            reverseIndex[KeyChord(keyCode: input.keyCode, character: glyph, modifiers: input.modifiers)] ?? []
        }

        let produced = input.producedGlyph
        if produced != input.baseGlyph && ShortcutMatching.isSymbol(produced) {
            let mods = input.modifiers.intersection(ShortcutMatching.symbolModifiers)
            tiers += ShortcutMatching.equivalents(of: produced).map { glyph in
                symbolIndex[ShortcutMatching.GlyphKey(glyph: glyph, modifiers: mods)] ?? []
            }
        }

        let positionKey = ShortcutMatching.PositionKey(keyCode: input.keyCode, modifiers: input.modifiers)
        tiers.append((positionIndex[positionKey] ?? [])
            .filter { ShortcutMatching.allowsPositionMatch(eventGlyph: input.baseGlyph, boundGlyph: $0.glyph) }
            .map(\.action))

        return tiers.map(Self.removingDuplicates)
    }

    // MARK: - Internals

    private func assign(_ chords: [KeyChord], to action: ShortcutAction) {
        if chords.isEmpty {
            bindings.removeValue(forKey: action)
            clearedExplicitly.insert(action)
        } else {
            bindings[action] = chords
            clearedExplicitly.remove(action)
        }
    }

    private func commit(_ chords: [KeyChord], for action: ShortcutAction) {
        assign(chords, to: action)
        didChange(action)
    }

    private func didChange(_ action: ShortcutAction?) {
        persist()
        rebuildIndex()
        NotificationCenter.default.post(name: .shortcutsChanged, object: action)
    }

    private func rebuildIndex() {
        var exact: [KeyChord: [ShortcutAction]] = [:]
        var symbol: [ShortcutMatching.GlyphKey: [ShortcutAction]] = [:]
        var position: [ShortcutMatching.PositionKey: [(glyph: String, action: ShortcutAction)]] = [:]
        for action in ShortcutAction.allCases {
            // Dedupe within an action so intra-action chord duplicates
            // don't show up twice in reverseIndex[chord].
            var seen: Set<KeyChord> = []
            for chord in chords(for: action) where seen.insert(chord).inserted {
                exact[chord, default: []].append(action)
                guard !KeyChord.isSpecialKey(chord.keyCode), !chord.character.isEmpty else { continue }
                position[ShortcutMatching.PositionKey(keyCode: chord.keyCode, modifiers: chord.modifiers),
                         default: []].append((chord.character, action))
                if ShortcutMatching.isSymbol(chord.character)
                    && chord.modifiers.isSubset(of: ShortcutMatching.symbolModifiers) {
                    symbol[ShortcutMatching.GlyphKey(glyph: chord.character, modifiers: chord.modifiers),
                           default: []].append(action)
                }
            }
        }
        reverseIndex = exact
        symbolIndex = symbol
        positionIndex = position
    }

    private static func removingDuplicates(_ actions: [ShortcutAction]) -> [ShortcutAction] {
        var seen: Set<ShortcutAction> = []
        return actions.filter { seen.insert($0).inserted }
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
            defaults.set(data, forKey: defaultsKey)
            return true
        } catch {
            NSLog("[shortcuts] ShortcutStore.persist failed: \(error)")
            return false
        }
    }
}
