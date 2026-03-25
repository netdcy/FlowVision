//
//  Log.swift
//  FlowVision
//

import Foundation
import Cocoa

func log(_ items: Any..., separator: String = " ", terminator: String = "\n", level: LogLevel = .info, function: String = #function) {
    let message = items.map { "\($0)" }.joined(separator: separator)
    Logger.shared.log(message, level: level, function: function)
}

class LogViewController: NSViewController {

    @IBOutlet weak var logTextView: NSTextView!
    @IBOutlet weak var debugCheckBox: NSButton!
    @IBOutlet weak var infoCheckBox: NSButton!
    @IBOutlet weak var warnCheckBox: NSButton!
    @IBOutlet weak var errorCheckBox: NSButton!

    var logMessages: [(String, LogLevel)] = []

    private let logFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let logBoldFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTextView()
        setupFilterBar()
    }

    private func setupTextView() {
        logTextView.font = logFont
        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.textContainerInset = NSSize(width: 5, height: 5)
        logTextView.isAutomaticQuoteSubstitutionEnabled = false
        logTextView.isAutomaticDashSubstitutionEnabled = false
        logTextView.isAutomaticTextReplacementEnabled = false
        logTextView.isAutomaticSpellingCorrectionEnabled = false

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        logTextView.defaultParagraphStyle = paragraphStyle
    }

    private func setupFilterBar() {
        styleCheckBox(debugCheckBox, level: .debug)
        styleCheckBox(infoCheckBox, level: .info)
        styleCheckBox(warnCheckBox, level: .warn)
        styleCheckBox(errorCheckBox, level: .error)

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearLog(_:)))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.font = NSFont.systemFont(ofSize: 11)
        clearButton.sizeToFit()
        clearButton.autoresizingMask = [.minXMargin, .minYMargin]
        let cbFrame = debugCheckBox.frame
        clearButton.frame.origin = NSPoint(
            x: view.frame.width - clearButton.frame.width - 16,
            y: cbFrame.origin.y + (cbFrame.height - clearButton.frame.height) / 2
        )
        view.addSubview(clearButton)

        let separator = NSBox(frame: NSRect(x: 15, y: cbFrame.origin.y - 8, width: view.frame.width - 30, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        view.addSubview(separator)
    }

    private func styleCheckBox(_ button: NSButton, level: LogLevel) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: level.color,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        button.attributedTitle = NSAttributedString(string: button.title, attributes: attrs)
        button.attributedAlternateTitle = NSAttributedString(string: button.title, attributes: attrs)
    }

    func addLogMessage(_ message: String, level: LogLevel) {
        if logMessages.count > 1000 {
            logMessages.removeFirst()
        }
        logMessages.append((message, level))
        if let window = self.view.window, window.isVisible {
            refreshLogView()
        }
    }

    func refreshLogView() {
        var filteredMessages = logMessages

        if debugCheckBox.state == .off {
            filteredMessages = filteredMessages.filter { $0.1 != .debug }
        }
        if infoCheckBox.state == .off {
            filteredMessages = filteredMessages.filter { $0.1 != .info }
        }
        if warnCheckBox.state == .off {
            filteredMessages = filteredMessages.filter { $0.1 != .warn }
        }
        if errorCheckBox.state == .off {
            filteredMessages = filteredMessages.filter { $0.1 != .error }
        }

        let attributedText = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2

        for (index, (message, level)) in filteredMessages.enumerated() {
            if index > 0 {
                attributedText.append(NSAttributedString(string: "\n"))
            }
            attributedText.append(styledLogMessage(message, level: level, paragraphStyle: paragraphStyle))
        }

        logTextView.textStorage?.setAttributedString(attributedText)

        if let layoutManager = logTextView.layoutManager, let textContainer = logTextView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        logTextView.scrollToEndOfDocument(nil)

        updateWindowTitle(total: logMessages.count, filtered: filteredMessages.count)
    }

    private func styledLogMessage(_ message: String, level: LogLevel, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let levelTag = "[\(level.description)]"

        if let tagRange = message.range(of: levelTag) {
            let timestampPart = String(message[message.startIndex..<tagRange.lowerBound])
            let messagePart = String(message[tagRange.upperBound...])

            result.append(NSAttributedString(string: timestampPart, attributes: [
                .font: logFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]))
            result.append(NSAttributedString(string: levelTag, attributes: [
                .font: logBoldFont,
                .foregroundColor: level.color,
                .paragraphStyle: paragraphStyle
            ]))
            result.append(NSAttributedString(string: messagePart, attributes: [
                .font: logFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]))
        } else {
            result.append(NSAttributedString(string: message, attributes: [
                .font: logFont,
                .foregroundColor: level.color,
                .paragraphStyle: paragraphStyle
            ]))
        }

        if level == .error {
            let fullRange = NSRange(location: 0, length: result.length)
            result.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.08), range: fullRange)
        } else if level == .warn {
            let fullRange = NSRange(location: 0, length: result.length)
            result.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.05), range: fullRange)
        }

        return result
    }

    private func updateWindowTitle(total: Int, filtered: Int) {
        if total == filtered {
            view.window?.title = "Log (\(total))"
        } else {
            view.window?.title = "Log (\(filtered)/\(total))"
        }
    }

    @IBAction func checkBoxChanged(_ sender: NSButton) {
        refreshLogView()
    }

    @objc func clearLog(_ sender: Any?) {
        logMessages.removeAll()
        refreshLogView()
    }
}

class LogWindowController: NSWindowController, NSWindowDelegate {

    var logViewController: LogViewController? {
        return contentViewController as? LogViewController
    }

    override var windowNibName: NSNib.Name? {
        return NSNib.Name("LogWindowController")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
        window?.minSize = NSSize(width: 480, height: 300)
    }

    func addLogMessage(_ message: String, level: LogLevel) {
        logViewController?.addLogMessage(message, level: level)
    }
}

enum LogLevel: Int {
    case debug = 0
    case info
    case warn
    case error

    var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }

    var color: NSColor {
        switch self {
        case .debug: return .systemGray
        case .info:  return .systemBlue
        case .warn:  return .systemOrange
        case .error: return .systemRed
        }
    }
}

class Logger {
    static let shared = Logger()

    private var logFileURL: URL?
    private var logWindowController: LogWindowController?
    private let logQueue = DispatchQueue(label: "com.example.LoggerQueue")
    var logLevel: LogLevel = .debug
    var isFileLoggingEnabled = false

    private init() {
        setupLogFile()
        setupLogWindow()
        log("Logger initialized", level: .debug)
    }

    private func setupLogFile() {
        let fileManager = FileManager.default
        do {
            let appSupportDirectory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let appDirectory = appSupportDirectory.appendingPathComponent("FlowVision", isDirectory: true)
            if !fileManager.fileExists(atPath: appDirectory.path) {
                try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
            }

            let logFileName = "FlowVision.log"
            logFileURL = appDirectory.appendingPathComponent(logFileName)
            
        } catch {
            let logFileName = ".FlowVision.log"
            let userDirectory = fileManager.homeDirectoryForCurrentUser
            logFileURL = userDirectory.appendingPathComponent(logFileName)
        }
    }

    private func setupLogWindow() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        logWindowController = storyboard.instantiateController(withIdentifier: "LogWindowController") as? LogWindowController
    }
    
    func showLogWindow() {
        logWindowController?.logViewController?.refreshLogView()
        logWindowController?.showWindow(nil)
    }
    
    func log(_ message: String, level: LogLevel = .info, function: String = #function) {
        guard level.rawValue >= logLevel.rawValue else { return }
        
        let timestamp = Logger.timestamp()
        let logMessage = "\(timestamp) [\(level.description)] [\(function)] \(message)"
        
        logQueue.async(flags: .barrier) { // Use barrier to ensure thread safety
            DispatchQueue.main.async {
                self.logWindowController?.addLogMessage(logMessage, level: level)
            }
            
            if self.isFileLoggingEnabled, let logFileURL = self.logFileURL {
                do {
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    fileHandle.seekToEndOfFile()
                    if let data = (logMessage + "\n").data(using: .utf8) {
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } catch {
                    try? logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
                }
            }
        }
    }
    
    func clearLogFile() {
        logQueue.sync(flags: .barrier) { // Use barrier to ensure thread safety
            if let logFileURL = self.logFileURL {
                do {
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    fileHandle.truncateFile(atOffset: 0) // Clear the file
                    fileHandle.closeFile()
                } catch {
                    print("Failed to clear log file: \(error)")
                }
            }
        }
    }

    private static func timestamp() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        return dateFormatter.string(from: Date())
    }
}
