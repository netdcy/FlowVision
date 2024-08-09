//
//  Log.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/8.
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

    override func viewDidLoad() {
        super.viewDidLoad()
        // Additional setup if needed
    }

    func addLogMessage(_ message: String, level: LogLevel) {
        logMessages.append((message, level))
        refreshLogView()
    }

    private func refreshLogView() {
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

        logTextView.string = filteredMessages.map { $0.0 }.joined(separator: "\n")
    }

    @IBAction func checkBoxChanged(_ sender: NSButton) {
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
}

class Logger {
    static let shared = Logger()

    private var logFileURL: URL?
    private var logWindowController: LogWindowController?
    private let logQueue = DispatchQueue(label: "com.example.LoggerQueue")
    var logLevel: LogLevel = .debug
    var isFileLoggingEnabled = true

    private init() {
        setupLogFile()
        setupLogWindow()
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
