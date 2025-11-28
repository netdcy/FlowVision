//
//  GeneralSettingsViewController.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/22.
//

import Cocoa
import Settings

final class GeneralSettingsViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.general
    let paneTitle = NSLocalizedString("General", comment: "通用")
    let toolbarItemIcon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "")!

    override var nibName: NSNib.Name? { "GeneralSettingsViewController" }
    
    @IBOutlet weak var terminateAfterLastWindowClosedCheckbox: NSButton!
    @IBOutlet weak var autoHideToolbarCheckbox: NSButton!
    @IBOutlet weak var languagePopUpButton: NSPopUpButton!

    @IBOutlet weak var radioHomeFolder: NSButton!
    @IBOutlet weak var radioLastFolder: NSButton!

    @IBOutlet weak var labelHomeFolder: NSTextField!
    @IBOutlet weak var buttonSelectHomeFolder: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        //self.preferredContentSize = NSSize(width: 600, height: 400)
        
        terminateAfterLastWindowClosedCheckbox.state = globalVar.terminateAfterLastWindowClosed ? .on : .off
        autoHideToolbarCheckbox.state = globalVar.autoHideToolbar ? .on : .off
        
        // 初始化 NSPopUpButton 的选项
        let autoTitle = NSLocalizedString("Auto", comment: "自动")
        languagePopUpButton.removeAllItems()
        languagePopUpButton.addItems(withTitles: [autoTitle, "Arabic(العربية)", "Chinese Simplified(简体中文)", "Chinese Traditional(繁體中文)", "Dutch(Nederlands)", "English(English)", "French(Français)", "German(Deutsch)", "Italian(Italiano)", "Japanese(日本語)", "Korean(한국어)", "Portuguese Brazil(Português)", "Portuguese Portugal(Português)", "Russian(Русский)", "Spanish(Español)", "Swedish(Svenska)"])
        // 设置初始选择
        if let languageCodes = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String], let firstLanguage = languageCodes.first {
            switch firstLanguage {
            case let lang where lang.hasPrefix("en"):
                languagePopUpButton.selectItem(withTitle: "English(English)")
            case let lang where lang.hasPrefix("zh-Hans"):
                languagePopUpButton.selectItem(withTitle: "Chinese Simplified(简体中文)")
            case let lang where lang.hasPrefix("zh-Hant"):
                languagePopUpButton.selectItem(withTitle: "Chinese Traditional(繁體中文)")
            case let lang where lang.hasPrefix("es"):
                languagePopUpButton.selectItem(withTitle: "Spanish(Español)")
            case let lang where lang.hasPrefix("fr"):
                languagePopUpButton.selectItem(withTitle: "French(Français)")
            case let lang where lang.hasPrefix("de"):
                languagePopUpButton.selectItem(withTitle: "German(Deutsch)")
            case let lang where lang.hasPrefix("ja"):
                languagePopUpButton.selectItem(withTitle: "Japanese(日本語)")
            case let lang where lang.hasPrefix("pt-BR"):
                languagePopUpButton.selectItem(withTitle: "Portuguese Brazil(Português)")
            case let lang where lang.hasPrefix("pt-PT"):
                languagePopUpButton.selectItem(withTitle: "Portuguese Portugal(Português)")
            case let lang where lang.hasPrefix("ru"):
                languagePopUpButton.selectItem(withTitle: "Russian(Русский)")
            case let lang where lang.hasPrefix("ko"):
                languagePopUpButton.selectItem(withTitle: "Korean(한국어)")
            case let lang where lang.hasPrefix("it"):
                languagePopUpButton.selectItem(withTitle: "Italian(Italiano)")
            case let lang where lang.hasPrefix("ar"):
                languagePopUpButton.selectItem(withTitle: "Arabic(العربية)")
            case let lang where lang.hasPrefix("nl"):
                languagePopUpButton.selectItem(withTitle: "Dutch(Nederlands)")
            case let lang where lang.hasPrefix("sv"):
                languagePopUpButton.selectItem(withTitle: "Swedish(Svenska)")
            default:
                languagePopUpButton.selectItem(withTitle: autoTitle)
            }
        } else {
            languagePopUpButton.selectItem(withTitle: autoTitle)
        }

        radioLastFolder.state = globalVar.openLastFolder ? .on : .off
        radioHomeFolder.state = !globalVar.openLastFolder ? .on : .off
        labelHomeFolder.stringValue = globalVar.homeFolder.removingPercentEncoding!.replacingOccurrences(of: "file://", with: "")
        labelHomeFolder.textColor = globalVar.openLastFolder ? .disabledControlTextColor : .controlTextColor
        buttonSelectHomeFolder.isEnabled = !globalVar.openLastFolder
    }
    
    @IBAction func languageSelectionChanged(_ sender: NSPopUpButton) {
        let selectedTitle = sender.selectedItem?.title
        let autoTitle = NSLocalizedString("Auto", comment: "自动")
        
        switch selectedTitle {
        case "English(English)":
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case "Chinese Simplified(简体中文)":
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case "Chinese Traditional(繁體中文)":
            UserDefaults.standard.set(["zh-Hant"], forKey: "AppleLanguages")
        case "Spanish(Español)":
            UserDefaults.standard.set(["es"], forKey: "AppleLanguages")
        case "French(Français)":
            UserDefaults.standard.set(["fr"], forKey: "AppleLanguages")
        case "German(Deutsch)":
            UserDefaults.standard.set(["de"], forKey: "AppleLanguages")
        case "Japanese(日本語)":
            UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
        case "Portuguese Brazil(Português)":
            UserDefaults.standard.set(["pt-BR"], forKey: "AppleLanguages")
        case "Portuguese Portugal(Português)":
            UserDefaults.standard.set(["pt-PT"], forKey: "AppleLanguages")
        case "Russian(Русский)":
            UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
        case "Korean(한국어)":
            UserDefaults.standard.set(["ko"], forKey: "AppleLanguages")
        case "Italian(Italiano)":
            UserDefaults.standard.set(["it"], forKey: "AppleLanguages")
        case "Arabic(العربية)":
            UserDefaults.standard.set(["ar"], forKey: "AppleLanguages")
        case "Dutch(Nederlands)":
            UserDefaults.standard.set(["nl"], forKey: "AppleLanguages")
        case "Swedish(Svenska)":
            UserDefaults.standard.set(["sv"], forKey: "AppleLanguages")
        case autoTitle:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        default:
            break
        }
    }
    
    @IBAction func terminateAfterLastWindowClosedToggled(_ sender: NSButton) {
        globalVar.terminateAfterLastWindowClosed = (sender.state == .on)
        UserDefaults.standard.set(globalVar.terminateAfterLastWindowClosed, forKey: "terminateAfterLastWindowClosed")
    }
    
    @IBAction func autoHideToolbarToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state, forKey: "autoHideToolbar")
    }
    
    @IBAction func openSystemPreferences(_ sender: Any) {
        _ = requestAppleEventsPermission()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        NSWorkspace.shared.open(url)
    }
    
    @IBAction func setAsDefaultApp(_ sender: Any) {
//        let fileTypes = ["public.jpeg", "public.png", "public.gif", "com.microsoft.bmp", "public.tiff", "public.heif", "org.webmproject.webp", "public.image", "public.heic"]
        guard let fileTypes = getSupportedFileTypes() else {
            log("获取支持文件类型失败 / Failed to get supported file types", level: .error)
            return
        }
        let appBundleID = Bundle.main.bundleIdentifier!
        
        var allSuccess = true
        var errorMessages = [String]()
        
        let roleMask: LSRolesMask = [.all]
        
        for fileType in fileTypes {
            if fileType == "public.folder" {continue}
            let status = LSSetDefaultRoleHandlerForContentType(fileType as CFString, roleMask, appBundleID as CFString)
            
            if status != noErr {
                allSuccess = false
                errorMessages.append("Failed for \(fileType): Error code: \(status)")
            }
        }
        
        let alert = NSAlert()
        if allSuccess {
            alert.messageText = NSLocalizedString("Success", comment: "成功")
            alert.informativeText = NSLocalizedString("This app is now the default for all specified file types.", comment: "此应用现在是所有指定文件类型的默认应用程序。")
            alert.alertStyle = .informational
        } else {
            alert.messageText = NSLocalizedString("Error", comment: "错误")
            alert.informativeText = NSLocalizedString("Failed to set this app as the default for some file types:\n", comment: "未能将此应用设置为某些文件类型的默认应用程序：\n") + errorMessages.joined(separator: "\n")
            alert.alertStyle = .critical
        }
        alert.runModal()
    }
    
    private func getSupportedFileTypes() -> [String]? {
        guard let infoPlist = Bundle.main.infoDictionary,
              let documentTypes = infoPlist["CFBundleDocumentTypes"] as? [[String: Any]] else {
            return nil
        }
        
        var fileTypes = [String]()
        for documentType in documentTypes {
            if let contentTypes = documentType["LSItemContentTypes"] as? [String] {
                fileTypes.append(contentsOf: contentTypes)
            }
        }
        return fileTypes
    }

    @IBAction func openBehaviorToggled(_ sender: NSButton) {
        let tag = sender.tag
        if tag == 0 {
            globalVar.openLastFolder = false
        } else if tag == 1 {
            globalVar.openLastFolder = true
        }
        UserDefaults.standard.set(globalVar.openLastFolder, forKey: "openLastFolder")
        if globalVar.openLastFolder {
            labelHomeFolder.textColor = .disabledControlTextColor
            buttonSelectHomeFolder.isEnabled = false
        } else {
            labelHomeFolder.textColor = .controlTextColor
            buttonSelectHomeFolder.isEnabled = true
        }
    }

    @IBAction func selectHomeFolder(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(string: globalVar.homeFolder)
        panel.runModal()
        if let url = panel.url {
            globalVar.homeFolder = url.absoluteString
            labelHomeFolder.stringValue = globalVar.homeFolder.removingPercentEncoding!.replacingOccurrences(of: "file://", with: "")
            UserDefaults.standard.set(globalVar.homeFolder, forKey: "homeFolder")
        }
    }
}
