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

    override func viewDidLoad() {
        super.viewDidLoad()
        
        //self.preferredContentSize = NSSize(width: 600, height: 400)
        
        terminateAfterLastWindowClosedCheckbox.state = globalVar.terminateAfterLastWindowClosed ? .on : .off
        autoHideToolbarCheckbox.state = globalVar.autoHideToolbar ? .on : .off
        
        // 初始化 NSPopUpButton 的选项
        let autoTitle = NSLocalizedString("Auto", comment: "自动")
        languagePopUpButton.removeAllItems()
        languagePopUpButton.addItems(withTitles: [autoTitle, "English", "简体中文"])
        
        // 设置初始选择
        if let languageCodes = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String], let firstLanguage = languageCodes.first {
            switch firstLanguage {
            case let lang where lang.hasPrefix("en"):
                languagePopUpButton.selectItem(withTitle: "English")
            case let lang where lang.hasPrefix("zh-Hans"):
                languagePopUpButton.selectItem(withTitle: "简体中文")
            default:
                languagePopUpButton.selectItem(withTitle: autoTitle)
            }
        } else {
            languagePopUpButton.selectItem(withTitle: autoTitle)
        }
    }
    
    @IBAction func languageSelectionChanged(_ sender: NSPopUpButton) {
        let selectedTitle = sender.selectedItem?.title
        let autoTitle = NSLocalizedString("Auto", comment: "自动")
        
        switch selectedTitle {
        case "English":
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case "简体中文":
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
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
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        NSWorkspace.shared.open(url)
    }
    
    @IBAction func setAsDefaultApp(_ sender: Any) {
//        let fileTypes = ["public.jpeg", "public.png", "public.gif", "com.microsoft.bmp", "public.tiff", "public.heif", "org.webmproject.webp", "public.image", "public.heic"]
        guard let fileTypes = getSupportedFileTypes() else {
            log("获取支持文件类型失败", level: .error)
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
}
