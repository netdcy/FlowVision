//
//  ShortcutRecorderView.swift
//  FlowVision
//
//  NSView subclass that captures a single key chord via first-responder + keyDown,
//  plus a local key monitor while recording so menu-owned Cmd chords get through.
//  Bare Esc (no modifiers) clears the binding; Esc with modifiers records normally.
//

import Cocoa

final class ShortcutRecorderView: NSView {

    var chord: KeyChord? {
        didSet { needsDisplay = true; if !suppressOnChange { onChange?(chord) } }
    }

    /// Called when the user commits a new chord (or clears with Esc).
    var onChange: ((KeyChord?) -> Void)?

    private var suppressOnChange = false

    /// Set chord without firing `onChange`. Use for programmatic updates
    /// (cell configure / reload) so the consumer doesn't see them as user commits.
    func setChordSilent(_ c: KeyChord?) {
        suppressOnChange = true
        chord = c
        suppressOnChange = false
    }

    private var isRecording = false {
        didSet {
            needsDisplay = true
            isRecording ? installKeyMonitor() : removeKeyMonitor()
        }
    }

    private var keyMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

    /// When false, mouseDown is ignored and the recorder draws greyed out.
    /// Used by settings rows where the primary chord is system-locked (e.g. Quit).
    var isEnabled: Bool = true {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled }
    override var isFlipped: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 22) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEnabled }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        // Only flip recording state if responder transition succeeds — otherwise we'd
        // be stuck visually recording without receiving keyDown.
        if window?.makeFirstResponder(self) == true {
            isRecording = true
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        let newChord: KeyChord?
        let bareEsc = event.keyCode == KeyChord.escKeyCode
            && Modifiers(event.modifierFlags).isEmpty
        if bareEsc {
            newChord = nil          // clear
        } else {
            newChord = KeyChord(event: event)
        }

        // Exit recording state BEFORE firing onChange so any modal conflict alert
        // rendered by the consumer doesn't paint over a "recording" highlight.
        endRecording()
        chord = newChord
    }

    override func resignFirstResponder() -> Bool {
        // External take-away (Tab to next view, etc): just exit state, no commit.
        isRecording = false
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Table reloads can pull the cell out of the window without a resign.
        if newWindow == nil { isRecording = false }
        super.viewWillMove(toWindow: newWindow)
    }

    // Cmd chords never reach keyDown when a menu item owns them (⌘W closes the
    // window, ⌘Q quits). A local monitor runs before key-equivalent dispatch,
    // so while recording it routes every keyDown of this window here instead.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, event.window === self.window else { return event }
            self.keyDown(with: event)
            return nil
        }
        // Closing Settings only hides the window and keeps this view as first responder,
        // so without this the first key typed after reopening it would be recorded.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.isRecording = false
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
    }

    private func endRecording() {
        // Explicit-commit path. resignFirstResponder uses its own simpler path to
        // avoid reentrancy — calling makeFirstResponder(nil) from inside resign
        // would re-enter this method.
        guard isRecording else { return }
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        // Disabled recorders (locked primary slots) have no context menu so the
        // user can't bypass the lock by right-clicking → "Clear".
        guard isEnabled else { return nil }
        let menu = NSMenu()
        menu.addItem(withTitle: NSLocalizedString("Clear this shortcut",
                                                   comment: "recorder context menu"),
                     action: #selector(clearRequested),
                     keyEquivalent: "").target = self
        return menu
    }

    @objc private func clearRequested() {
        // Mirror a real recording: fire onChange so the host can drop the slot.
        chord = nil
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                 xRadius: 5, yRadius: 5)
        if !isEnabled {
            NSColor.controlBackgroundColor.withAlphaComponent(0.4).setFill()
        } else if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let text: String
        if isRecording {
            text = NSLocalizedString("shortcut.recorder.prompt",
                                      value: "Press shortcut…", comment: "")
        } else if let chord {
            text = chord.displayString
        } else {
            text = NSLocalizedString("shortcut.recorder.empty",
                                      value: "-", comment: "")
        }

        let textColor: NSColor
        if !isEnabled {
            textColor = .disabledControlTextColor
        } else if isRecording {
            textColor = .controlAccentColor
        } else {
            textColor = .labelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: textColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(x: (bounds.width - size.width) / 2,
                              y: (bounds.height - size.height) / 2)
        str.draw(at: origin)
    }
}
