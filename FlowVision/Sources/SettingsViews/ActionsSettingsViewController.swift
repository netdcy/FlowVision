//
//  ActionsSettingsViewController.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/25.
//

import Settings
import Cocoa

final class ActionsSettingsViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.actions
    let paneTitle = NSLocalizedString("Actions", comment: "操作（设置里的面板）")
    let toolbarItemIcon = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "")!

    override var nibName: NSNib.Name? { "ActionsSettingsViewController" }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup stuff here
    }
}
