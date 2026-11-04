//
//  main.swift
//  Shortcut matching tests
//
//  Standalone harness: compiled by `make test` together with FlowVision/Sources/Shortcuts.
//  Key events are simulated against real macOS keyboard layouts through UCKeyTranslate, so
//  each case checks what a user on that layout actually triggers.
//

import Carbon
import Foundation

// MARK: - Harness

var failures = 0
var passes = 0

func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(name) \(detail())")
    }
}

func expect(_ got: [ShortcutAction], _ want: [ShortcutAction], _ name: String) {
    check(got == want, name, "got \(got.map(\.rawValue)) want \(want.map(\.rawValue))")
}

/// Simulates key events on one installed keyboard layout.
struct Layout {
    let id: String
    private let data: Data

    init(_ id: String) {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            fatalError("keyboard layout \(id) not installed")
        }
        self.id = id
        self.data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
    }

    private func translate(_ keyCode: UInt16, _ mods: Modifiers, deadKeysProduceNothing: Bool) -> String {
        var state: UInt32 = 0
        if mods.contains(.command) { state |= UInt32(cmdKey >> 8) }
        if mods.contains(.shift)   { state |= UInt32(shiftKey >> 8) }
        if mods.contains(.option)  { state |= UInt32(optionKey >> 8) }
        if mods.contains(.control) { state |= UInt32(controlKey >> 8) }
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let options = deadKeysProduceNothing ? 0 : OptionBits(kUCKeyTranslateNoDeadKeysMask)
        data.withUnsafeBytes { raw in
            let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            _ = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), state, UInt32(LMGetKbdType()),
                               options, &dead, chars.count, &length, &chars)
        }
        // A dead key starts a compose sequence and NSEvent reports no characters for it.
        if dead != 0 { return "" }
        return String(utf16CodeUnits: chars, count: length)
    }

    /// Builds the matcher input the same way `ShortcutMatching.Input(event:)` does from NSEvent.
    func press(_ keyCode: UInt16, _ mods: Modifiers = []) -> ShortcutMatching.Input {
        ShortcutMatching.Input(
            keyCode: keyCode,
            modifiers: mods,
            base: translate(keyCode, [], deadKeysProduceNothing: false),
            produced: translate(keyCode, mods, deadKeysProduceNothing: true),
            ignoringModifiers: translate(keyCode, mods.intersection(.shift), deadKeysProduceNothing: false))
    }
}

enum Scope { case browser, viewer }

let store = ShortcutStore(defaults: UserDefaults(suiteName: "flowvision.shortcut-tests")!)
store.resetAll()

/// Actions the dispatcher would try, in order, for `input` in `scope`.
func resolve(_ input: ShortcutMatching.Input, in scope: Scope) -> [ShortcutAction] {
    ShortcutMatching.firstEligibleTier(store.candidateTiers(for: input)) { action in
        switch action.scope {
        case .both:        return true
        case .browserOnly: return scope == .browser
        case .viewerOnly:  return scope == .viewer
        }
    }
}

let us = Layout("com.apple.keylayout.US")
let french = Layout("com.apple.keylayout.French")
let dvorak = Layout("com.apple.keylayout.Dvorak")
let russian = Layout("com.apple.keylayout.Russian")
let norwegian = Layout("com.apple.keylayout.Norwegian")
let german = Layout("com.apple.keylayout.German")

// Virtual key codes (ANSI positions).
let kA: UInt16 = 0x00, kQ: UInt16 = 0x0C, kW: UInt16 = 0x0D, kE: UInt16 = 0x0E
let kF: UInt16 = 0x03, kN: UInt16 = 0x2D, kL: UInt16 = 0x25, kX: UInt16 = 0x07
let k1: UInt16 = 0x12, k2: UInt16 = 0x13, k3: UInt16 = 0x14, k0: UInt16 = 0x1D
let kEqual: UInt16 = 0x18, kMinus: UInt16 = 0x1B, kComma: UInt16 = 0x2B, kPeriod: UInt16 = 0x2F
let kSlash: UInt16 = 0x2C, k5: UInt16 = 0x17
let kReturn: UInt16 = 0x24, kKeypadEnter: UInt16 = 0x4C, kBackspace: UInt16 = 0x33
let kRight: UInt16 = 0x7C, kUp: UInt16 = 0x7E, kDown: UInt16 = 0x7D, kTab: UInt16 = 0x30, kF2: UInt16 = 0x78
let kF5: UInt16 = 0x60, kF6: UInt16 = 0x61

// MARK: - US: modifiers are exact for letters, digits and special keys

expect(resolve(us.press(k3), in: .browser), [], "US bare 3 in the browser is not profile 3")
expect(resolve(us.press(k3), in: .viewer), [.windowImageActual], "US bare 3 in the viewer is window-to-image")
expect(resolve(us.press(k3, .option), in: .browser), [.profileUse3], "US Opt+3 uses profile 3")
expect(resolve(us.press(k1, .command), in: .browser), [.tag1], "US Cmd+1 toggles tag 1 only")
expect(resolve(us.press(k1, [.command, .option]), in: .browser), [.profileSave1], "US Cmd+Opt+1 saves profile 1")
expect(resolve(us.press(kComma, .command), in: .browser), [], "US Cmd+, is left to the Preferences menu")
expect(resolve(us.press(kComma, [.command, .shift]), in: .browser), [.toggleAllFiles], "US Cmd+Shift+, shows all files")
expect(resolve(us.press(kPeriod, .command), in: .browser), [], "US Cmd+. is not hidden files")
expect(resolve(us.press(kPeriod, [.command, .shift]), in: .browser), [.toggleHiddenFiles], "US Cmd+Shift+. shows hidden files")
expect(resolve(us.press(kReturn, .shift), in: .browser), [], "US Shift+Return is not fullscreen")
expect(resolve(us.press(kReturn), in: .browser), [], "US bare Return is not fullscreen")
expect(resolve(us.press(kReturn, .option), in: .browser), [.windowToggleFullscreen], "US Opt+Return toggles fullscreen")
expect(resolve(us.press(kKeypadEnter, .option), in: .browser), [.windowToggleFullscreen], "US Opt+keypad Enter toggles fullscreen")
expect(resolve(us.press(kE, .option), in: .browser), [], "US Opt+E (dead key) is not a plain E action")
expect(resolve(us.press(kN, .option), in: .browser), [], "US Opt+N (dead key) does not copy to Downloads")
expect(resolve(us.press(kF, .function), in: .browser), [], "US Fn+F does not toggle the sidebar")
expect(resolve(us.press(kF), in: .browser), [.browserToggleSidebar], "US F toggles the sidebar")
expect(resolve(us.press(kQ, .command), in: .browser), [.quitApp], "US Cmd+Q quits")
expect(resolve(us.press(kW, .command), in: .browser), [.windowClose], "US Cmd+W closes the window")
expect(resolve(us.press(kUp, .command), in: .browser), [.browserScrollTop], "US Cmd+Up scrolls the browser to the top")
expect(resolve(us.press(kDown, .command), in: .browser), [.browserScrollBottom], "US Cmd+Down scrolls the browser to the bottom")
expect(resolve(us.press(kUp, .command), in: .viewer), [.viewerLocateFirst], "US Cmd+Up in viewer goes to the first image")
expect(resolve(us.press(kEqual), in: .viewer), [.viewerZoomIn], "US = zooms in")
expect(resolve(us.press(kEqual, .shift), in: .viewer), [.viewerZoomIn], "US Shift+= (+) zooms in")
expect(resolve(us.press(kMinus, .shift), in: .viewer), [.viewerZoomOut], "US Shift+- (_) zooms out")
expect(resolve(us.press(kSlash), in: .viewer), [], "US / triggers nothing")

// MARK: - Tiers: a declining handler never hands over to another chord's action

let bareOne = store.candidateTiers(for: us.press(k1)).flatMap { $0 }
check(!bareOne.contains(.profileUse1), "US bare 1 never reaches profile 1", "\(bareOne)")
let declining: [[ShortcutAction]] = [[.windowMaximize], [.profileUse1]]
expect(ShortcutMatching.firstEligibleTier(declining) { _ in true }, [.windowMaximize],
       "first eligible tier stops after the first tier with eligible actions")
let scoped: [[ShortcutAction]] = [[.viewerZoomIn], [.thumbSizeUp]]
expect(ShortcutMatching.firstEligibleTier(scoped) { $0 == .thumbSizeUp }, [.thumbSizeUp],
       "first eligible tier skips tiers whose actions are all ineligible")

// MARK: - Non-QWERTY layouts: letters match by character, never by US position

expect(resolve(french.press(kQ, .command), in: .browser), [], "AZERTY Cmd+A (US Q position) does not quit")
expect(resolve(french.press(kW, .command), in: .browser), [], "AZERTY Cmd+Z (US W position) does not close the window")
expect(resolve(french.press(kA, .command), in: .browser), [.quitApp], "AZERTY Cmd+Q quits")
expect(resolve(french.press(kQ), in: .browser), [.browserDirLeft], "AZERTY bare A switches directory left")
expect(resolve(french.press(k1, .command), in: .browser), [.tag1], "AZERTY Cmd+& (number row 1) toggles tag 1")
expect(resolve(french.press(k2), in: .browser), [.windowSuitable], "AZERTY bare é (number row 2) is suitable window size")
expect(resolve(dvorak.press(kQ, .command), in: .browser), [], "Dvorak Cmd+' does not quit")
expect(resolve(dvorak.press(kW, .command), in: .browser), [], "Dvorak Cmd+, does not close the window")
expect(resolve(dvorak.press(kX, .command), in: .browser), [.quitApp], "Dvorak Cmd+Q quits")
expect(resolve(russian.press(kA), in: .browser), [.browserDirLeft], "Russian bare Ф (A position) switches directory left")
expect(resolve(russian.press(kQ, .command), in: .browser), [.quitApp], "Russian Cmd+Й (Q position) quits")

// MARK: - Moved symbols (issue #16)

expect(resolve(norwegian.press(kMinus), in: .viewer), [.viewerZoomIn], "Norwegian + (US - position) zooms in")
expect(resolve(norwegian.press(kSlash), in: .viewer), [.viewerZoomOut], "Norwegian - zooms out")
expect(resolve(norwegian.press(k0, .shift), in: .viewer), [.viewerZoomIn], "Norwegian Shift+0 (=) zooms in")
expect(resolve(german.press(k5, [.command, .option]), in: .browser), [.profileSave5],
       "German Cmd+Opt+5 produces [ but its exact binding, save profile 5, wins")
expect(resolve(german.press(k0, .shift), in: .viewer), [.viewerZoomIn], "German Shift+0 (=) zooms in")
expect(resolve(german.press(kSlash, [.command, .shift]), in: .browser), [], "German Cmd+_ is not zoom out")
expect(resolve(german.press(kMinus), in: .viewer), [], "German ß (US - position) does not zoom out")

// MARK: - Recorded special keys keep their modifiers

store.appendChord(KeyChord(input: us.press(kBackspace, .option)), for: .fileDeleteNoPrompt)
expect(resolve(us.press(kBackspace), in: .browser), [.fileDelete], "plain Backspace still prompts after binding Opt+Backspace")
expect(resolve(us.press(kBackspace, .option), in: .browser), [.fileDeleteNoPrompt], "recorded Opt+Backspace fires")
store.appendChord(KeyChord(input: us.press(kRight, .shift)), for: .viewerLocateLast)
expect(resolve(us.press(kRight), in: .viewer), [.videoSeekFwd], "plain Right still seeks after binding Shift+Right")
check(KeyChord(input: us.press(kBackspace, .option)).character.isEmpty, "special keys record no glyph")
store.resetAll()

// MARK: - Recording and identity

let recordedPlus = KeyChord(input: us.press(kEqual, .shift))
check(recordedPlus.character == "=" && recordedPlus.modifiers == .shift, "US Shift+= records as base glyph = with Shift",
      "\(recordedPlus.character) \(recordedPlus.modifiers)")
check(KeyChord(keyCode: kQ, character: "a", modifiers: .command) != KeyChord(keyCode: kQ, character: "q", modifiers: .command),
      "glyph chords on the same key position but different glyphs are distinct")
check(KeyChord(keyCode: kBackspace, character: "\u{7f}", modifiers: []) == KeyChord(keyCode: kBackspace, character: "", modifiers: []),
      "special keys compare by key code")

// Exact glyph wins deterministically over its zoom-cluster partner.
store.appendChord(KeyChord(keyCode: kMinus, character: "+", modifiers: []), for: .thumbSizeReset)
for _ in 0..<20 {
    expect(resolve(norwegian.press(kMinus), in: .browser), [.thumbSizeReset], "exact + binding beats = on every lookup")
}
store.resetAll()

// MARK: - Settings and menu rules

check(KeyChord(input: us.press(kRight)).isReservedForBrowserNavigation, "bare Right is reserved for browser navigation")
check(KeyChord(input: us.press(kRight, .shift)).isReservedForBrowserNavigation, "Shift+Right is reserved for browser navigation")
check(!KeyChord(input: us.press(kRight, .option)).isReservedForBrowserNavigation, "Opt+Right is free")
check(KeyChord(input: us.press(kTab)).isReservedForBrowserNavigation, "Tab is reserved")
check(KeyChord(input: us.press(kF2)).isReservedForBrowserNavigation, "F2 is reserved")
check(KeyChord(input: us.press(kReturn)).isReservedForBrowserNavigation, "Return is reserved")
check(!KeyChord(input: us.press(kReturn, .command)).isReservedForBrowserNavigation, "Cmd+Return is free")

check(!ShortcutAction.windowRefresh.needsSystemOverrideConfirmation(for: KeyChord(input: us.press(kF6))),
      "adding F6 to Refresh needs no system warning")
check(ShortcutAction.viewModeGrid.needsSystemOverrideConfirmation(for: KeyChord(input: us.press(kW, .command))),
      "binding Cmd+W to another action warns")
check(!ShortcutAction.windowClose.needsSystemOverrideConfirmation(for: KeyChord(input: us.press(kW, .command))),
      "re-recording Cmd+W on Close window does not warn")

check(!KeyChord(input: us.press(kL, .shift)).isMenuKeyEquivalentEligible, "Shift+L is not a menu key equivalent")
check(!KeyChord(input: us.press(kL, .option)).isMenuKeyEquivalentEligible, "Opt+L is not a menu key equivalent")
check(!KeyChord(input: us.press(kL, .function)).isMenuKeyEquivalentEligible, "Fn+L is not a menu key equivalent")
check(KeyChord(input: us.press(kL, .command)).isMenuKeyEquivalentEligible, "Cmd+L is a menu key equivalent")
check(KeyChord(input: us.press(kL, .control)).isMenuKeyEquivalentEligible, "Ctrl+L is a menu key equivalent")
check(!KeyChord(input: us.press(kF5)).isMenuKeyEquivalentEligible, "F5 has no menu key equivalent glyph")

// MARK: - Persistence

let suite = UserDefaults(suiteName: "flowvision.shortcut-tests")!
suite.set(#"{"version":2,"entries":[{"action":"windowRefresh","chords":[{"bogus":1}]}]}"#.data(using: .utf8),
          forKey: "shortcutBindings.v2")
store.load()
check(store.chords(for: .windowRefresh) == ShortcutAction.windowRefresh.defaultChords,
      "a malformed stored entry keeps the defaults instead of clearing the action")
store.resetAll()
suite.removePersistentDomain(forName: "flowvision.shortcut-tests")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
