//
//  DemoSettingsViewController.swift
//  FlowVision
//

import Settings
import Cocoa

final class DemoSettingsViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.demo
    let paneTitle = NSLocalizedString("Demo", comment: "Demo")
    let toolbarItemIcon = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "")!

    override var nibName: NSNib.Name? { "DemoSettingsViewController" }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

}
