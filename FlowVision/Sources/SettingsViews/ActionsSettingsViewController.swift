//
//  ActionsSettingsViewController.swift
//  FlowVision
//

import Settings
import Cocoa

final class ActionsSettingsViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.actions
    let paneTitle = NSLocalizedString("Actions", comment: "操作（设置里的面板）")
    let toolbarItemIcon = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "")!

    override var nibName: NSNib.Name? { "ActionsSettingsViewController" }
    
    @IBOutlet weak var radioEnterKeyRename: NSButton!
    @IBOutlet weak var radioEnterKeyOpen: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        radioEnterKeyOpen.state = globalVar.isEnterKeyToOpen ? .on : .off
        radioEnterKeyRename.state = globalVar.isEnterKeyToOpen ? .off : .on

    }

    @IBAction func enterKeyToOpenToggled(_ sender: NSButton) {
        let tag = sender.tag
        if tag == 0 {
            globalVar.isEnterKeyToOpen = false
        } else if tag == 1 {
            globalVar.isEnterKeyToOpen = true
        }
        UserDefaults.standard.set(globalVar.isEnterKeyToOpen, forKey: "isEnterKeyToOpen")
    }
}
