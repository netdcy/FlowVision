//
//  GeneralSettingsViewController.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/22.
//

import Cocoa
import Settings

final class AdvancedSettingsViewController: NSViewController, SettingsPane {
	let paneIdentifier = Settings.PaneIdentifier.advanced
	let paneTitle = NSLocalizedString("Advanced", comment: "高级")
	let toolbarItemIcon = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: "")!

	override var nibName: NSNib.Name? { "AdvancedSettingsViewController" }
    
    @IBOutlet weak var memUseLimitSlider: NSSlider!
    @IBOutlet weak var memUseLimitLabel: NSTextField!
    
    @IBOutlet weak var thumbThreadNumStepper: NSStepper!
    @IBOutlet weak var thumbThreadNumLabel: NSTextField!
    
    @IBOutlet weak var folderSearchDepthStepper: NSStepper!
    @IBOutlet weak var folderSearchDepthLabel: NSTextField!
    
    @IBOutlet weak var thumbThreadNumStepper_External: NSStepper!
    @IBOutlet weak var thumbThreadNumLabel_External: NSTextField!
    
    @IBOutlet weak var folderSearchDepthStepper_External: NSStepper!
    @IBOutlet weak var folderSearchDepthLabel_External: NSTextField!
    
    @IBOutlet weak var useFFmpegRadioButton: NSButton!
    @IBOutlet weak var doNotUseFFmpegRadioButton: NSButton!
    
    @IBOutlet weak var searchDepthWarningText: NSTextField!
    @IBOutlet weak var searchDepthWarningText_External: NSTextField!

	override func viewDidLoad() {
		super.viewDidLoad()

        // 初始化 slider、stepper 和标签
        memUseLimitSlider.integerValue = globalVar.memUseLimit
        updateMemUseLimitLabel(value: Double(globalVar.memUseLimit))
        
        thumbThreadNumStepper.integerValue = globalVar.thumbThreadNum
        updateThumbThreadNumLabel(value: globalVar.thumbThreadNum)
        
        folderSearchDepthStepper.integerValue = globalVar.folderSearchDepth
        updateFolderSearchDepthLabel(value: globalVar.folderSearchDepth)
        
        thumbThreadNumStepper_External.integerValue = globalVar.thumbThreadNum_External
        updateThumbThreadNumLabel_External(value: globalVar.thumbThreadNum_External)
        
        folderSearchDepthStepper_External.integerValue = globalVar.folderSearchDepth_External
        updateFolderSearchDepthLabel_External(value: globalVar.folderSearchDepth_External)
        
        if folderSearchDepthStepper.integerValue == 0 {
            searchDepthWarningText.textColor = .systemRed
        } else {
            searchDepthWarningText.textColor = .systemGray
        }
        
        if folderSearchDepthStepper_External.integerValue == 0 {
            searchDepthWarningText_External.textColor = .systemRed
        } else {
            searchDepthWarningText_External.textColor = .systemGray
        }
        
        // 初始化 Radio Buttons
        updateFFmpegRadioButtons()
	}

    @IBAction func memUseLimitSliderChanged(_ sender: NSSlider) {
        let newValue = sender.integerValue
        globalVar.memUseLimit = newValue
        UserDefaults.standard.set(newValue, forKey: "memUseLimit")
        updateMemUseLimitLabel(value: Double(newValue))
    }
    
    private func updateMemUseLimitLabel(value: Double) {
        // 将 slider 的值转换为合适的显示内容
        let formattedValue: String
        if value < 1000 {
            formattedValue = "\(Int(value)) MB"
        } else {
            formattedValue = String(format: "%.0f GB", value / 1000.0)
        }
        memUseLimitLabel.stringValue = formattedValue
    }
    
    @IBAction func thumbThreadNumStepperChanged(_ sender: NSStepper) {
        let newThumbThreadNum = sender.integerValue
        globalVar.thumbThreadNum = newThumbThreadNum
        UserDefaults.standard.set(newThumbThreadNum, forKey: "thumbThreadNum")
        updateThumbThreadNumLabel(value: newThumbThreadNum)
    }
    
    private func updateThumbThreadNumLabel(value: Int) {
        // 更新 thumbThreadNumLabel 的显示内容
        thumbThreadNumLabel.stringValue = "\(value)"
    }
    
    @IBAction func folderSearchDepthStepperChanged(_ sender: NSStepper) {
        let newFolderSearchDepth = sender.integerValue
        globalVar.folderSearchDepth = newFolderSearchDepth
        UserDefaults.standard.set(newFolderSearchDepth, forKey: "folderSearchDepth")
        updateFolderSearchDepthLabel(value: newFolderSearchDepth)
        
        if folderSearchDepthStepper.integerValue == 0 {
            searchDepthWarningText.textColor = .systemRed
        } else {
            searchDepthWarningText.textColor = .systemGray
        }
    }
    
    private func updateFolderSearchDepthLabel(value: Int) {
        // 更新 folderSearchDepthLabel 的显示内容
        folderSearchDepthLabel.stringValue = "\(value)"
    }
    
    @IBAction func thumbThreadNumStepperChanged_External(_ sender: NSStepper) {
        let newThumbThreadNum_External = sender.integerValue
        globalVar.thumbThreadNum_External = newThumbThreadNum_External
        UserDefaults.standard.set(newThumbThreadNum_External, forKey: "thumbThreadNum_External")
        updateThumbThreadNumLabel_External(value: newThumbThreadNum_External)
    }
    
    private func updateThumbThreadNumLabel_External(value: Int) {
        // 更新 thumbThreadNumLabel 的显示内容
        thumbThreadNumLabel_External.stringValue = "\(value)"
    }
    
    @IBAction func folderSearchDepthStepperChanged_External(_ sender: NSStepper) {
        let newFolderSearchDepth_External = sender.integerValue
        globalVar.folderSearchDepth_External = newFolderSearchDepth_External
        UserDefaults.standard.set(newFolderSearchDepth_External, forKey: "folderSearchDepth_External")
        updateFolderSearchDepthLabel_External(value: newFolderSearchDepth_External)
        
        if folderSearchDepthStepper_External.integerValue == 0 {
            searchDepthWarningText_External.textColor = .systemRed
        } else {
            searchDepthWarningText_External.textColor = .systemGray
        }
    }
    
    private func updateFolderSearchDepthLabel_External(value: Int) {
        // 更新 folderSearchDepthLabel 的显示内容
        folderSearchDepthLabel_External.stringValue = "\(value)"
    }
    
    @IBAction func ffmpegRadioButtonChanged(_ sender: NSButton) {
        if sender == useFFmpegRadioButton {
            globalVar.doNotUseFFmpeg = false
        } else if sender == doNotUseFFmpegRadioButton {
            globalVar.doNotUseFFmpeg = true
        }
        UserDefaults.standard.set(globalVar.doNotUseFFmpeg, forKey: "doNotUseFFmpeg")
        updateFFmpegRadioButtons()
    }
    private func updateFFmpegRadioButtons() {
        // 根据全局变量设置 Radio Buttons 的状态
        useFFmpegRadioButton.state = globalVar.doNotUseFFmpeg ? .off : .on
        doNotUseFFmpegRadioButton.state = globalVar.doNotUseFFmpeg ? .on : .off
    }
    
}
