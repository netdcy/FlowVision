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
    
    private var quickRenameRuleField = NSTextField()
    private var photoFolder1PathField = NSTextField()
    private var photoFolder1ShortcutPopup = NSPopUpButton()
    private var photoFolder2PathField = NSTextField()
    private var photoFolder2ShortcutPopup = NSPopUpButton()
    private var shortcutConflictLabel = NSTextField(labelWithString: "")
    private var videoShiftArrowSwitchFileCheckbox = NSButton()
    private var showArchiveFileTypeCheckbox = NSButton()
    private var compressionUseDefaultPasswordCheckbox = NSButton()
    private var compressionDefaultPasswordField = NSSecureTextField()
    private weak var guideGrid: NSGridView?
    private var escMonitor: Any?
    
    private let shortcutCandidates: [String] = {
        let letters = (65...90).compactMap { UnicodeScalar($0).map { String($0) } }
        let digits = (0...9).map(String.init)
        let functionKeys = (1...12).map { "F\($0)" }
        return letters + digits + ["=", "-", ",", ".", "[", "]"] + functionKeys
    }()

    private let reservedShortcutNotes: [(key: String, note: String)] = [
        ("A", "上一项"),
        ("D", "下一项"),
        ("W", "放大或上移"),
        ("S", "缩小或下移"),
        ("Q", "左旋 / 快速搜索"),
        ("E", "右旋"),
        ("R", "重命名"),
        ("F", "显示侧栏 / 镜像翻转"),
        ("T", "窗口置顶"),
        ("Z", "缩放到 100%"),
        ("X", "缩放适合"),
        (",", "视频 A 点"),
        (".", "视频 B 点"),
        ("J", "视频记忆播放位置"),
        ("K", "视频 A-B 循环"),
        ("L", "视频顺序播放"),
        ("M", "移动到下载文件夹"),
        ("U", "显示 / 隐藏界面"),
        ("I", "信息 / EXIF"),
        ("O", "OCR"),
        ("P", "二维码"),
        ("SPACE", "打开 / 播放暂停"),
        ("TAB", "切换焦点"),
        ("DELETE", "移到废纸篓"),
        ("F2", "重命名"),
        ("F3", "搜索"),
        ("F5", "刷新"),
        ("=", "缩略图放大"),
        ("-", "缩略图缩小"),
        ("0", "重置缩略图大小"),
        ("1", "最大化窗口"),
        ("2", "合适窗口大小"),
        ("3", "调整窗口至图片实际大小"),
        ("4", "调整窗口至图片当前大小"),
        ("5", "将窗口居中")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        radioEnterKeyOpen.state = globalVar.isEnterKeyToOpen ? .on : .off
        radioEnterKeyRename.state = globalVar.isEnterKeyToOpen ? .off : .on
        
        collapseGuideSection()
        setupInlineFileActionSettingsPanel()

        // MARK: RTL support
        if let container = radioEnterKeyRename.superview {
            convertToLeadingLayoutForRTL(container)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installEscMonitorIfNeeded()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeEscMonitor()
    }

    deinit {
        removeEscMonitor()
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
    
    private func setupInlineFileActionSettingsPanel() {
        guard let grid = guideGrid ?? view.subviews.compactMap({ $0 as? NSGridView }).first else { return }

        let profileTitle = NSLocalizedString("Profile Switching:", comment: "配置切换：")
        let targetRow = (0..<grid.numberOfRows).first { rowIndex in
            guard let label = grid.cell(atColumnIndex: 0, rowIndex: rowIndex).contentView as? NSTextField else { return false }
            return label.stringValue == profileTitle
        } ?? max(0, grid.numberOfRows - 1)

        if let leftLabel = grid.cell(atColumnIndex: 0, rowIndex: targetRow).contentView as? NSTextField {
            leftLabel.stringValue = "文件操作："
        }

        let panel = NSStackView()
        panel.orientation = .vertical
        panel.spacing = 8
        panel.alignment = .leading
        panel.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.setContentHuggingPriority(.required, for: .vertical)
        panel.setContentCompressionResistancePriority(.required, for: .vertical)
        
        let renameRow = NSStackView()
        renameRow.orientation = .horizontal
        renameRow.spacing = 8
        renameRow.alignment = .centerY
        
        let renameLabel = NSTextField(labelWithString: "快速重命名：")
        renameLabel.setContentHuggingPriority(.required, for: .horizontal)
        quickRenameRuleField = NSTextField()
        quickRenameRuleField.stringValue = globalVar.quickRenameRule
        quickRenameRuleField.translatesAutoresizingMaskIntoConstraints = false
        
        let applyButton = NSButton(title: "应用", target: self, action: #selector(applyInlineFileActionSettings))
        applyButton.bezelStyle = .rounded
        applyButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        
        renameRow.addArrangedSubview(renameLabel)
        renameRow.addArrangedSubview(quickRenameRuleField)
        renameRow.addArrangedSubview(applyButton)
        quickRenameRuleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        
        let folderRow = NSStackView()
        folderRow.orientation = .horizontal
        folderRow.spacing = 8
        folderRow.alignment = .centerY
        
        let folderLabel = NSTextField(labelWithString: "图片文件夹1：")
        folderLabel.setContentHuggingPriority(.required, for: .horizontal)
        photoFolder1PathField = NSTextField()
        photoFolder1PathField.stringValue = globalVar.photoFolder1Path
        photoFolder1PathField.lineBreakMode = .byTruncatingMiddle
        
        let selectFolderButton = NSButton(title: "选择文件夹", target: self, action: #selector(selectPhotoFolder1Inline))
        selectFolderButton.bezelStyle = .rounded
        selectFolderButton.widthAnchor.constraint(equalToConstant: 96).isActive = true
        
        folderRow.addArrangedSubview(folderLabel)
        folderRow.addArrangedSubview(photoFolder1PathField)
        folderRow.addArrangedSubview(selectFolderButton)
        photoFolder1PathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let folder2Row = NSStackView()
        folder2Row.orientation = .horizontal
        folder2Row.spacing = 8
        folder2Row.alignment = .centerY

        let folder2Label = NSTextField(labelWithString: "视频文件夹2：")
        folder2Label.setContentHuggingPriority(.required, for: .horizontal)
        photoFolder2PathField = NSTextField()
        photoFolder2PathField.stringValue = globalVar.photoFolder2Path
        photoFolder2PathField.lineBreakMode = .byTruncatingMiddle

        let selectFolder2Button = NSButton(title: "选择文件夹", target: self, action: #selector(selectPhotoFolder2Inline))
        selectFolder2Button.bezelStyle = .rounded
        selectFolder2Button.widthAnchor.constraint(equalToConstant: 96).isActive = true

        folder2Row.addArrangedSubview(folder2Label)
        folder2Row.addArrangedSubview(photoFolder2PathField)
        folder2Row.addArrangedSubview(selectFolder2Button)
        photoFolder2PathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        
        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 8
        shortcutRow.alignment = .centerY
        
        let shortcutLabel = NSTextField(labelWithString: "复制快捷键：")
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        photoFolder1ShortcutPopup = NSPopUpButton()
        photoFolder1ShortcutPopup.addItems(withTitles: shortcutCandidates)
        let selectedShortcut = globalVar.photoFolder1CopyShortcut.uppercased()
        photoFolder1ShortcutPopup.selectItem(withTitle: shortcutCandidates.contains(selectedShortcut) ? selectedShortcut : "N")
        photoFolder1ShortcutPopup.target = self
        photoFolder1ShortcutPopup.action = #selector(applyInlineFileActionSettings)
        
        videoShiftArrowSwitchFileCheckbox = NSButton(checkboxWithTitle: "视频 Shift+左右 切换上/下文件", target: self, action: #selector(applyInlineFileActionSettings))
        videoShiftArrowSwitchFileCheckbox.state = globalVar.videoShiftArrowSwitchFile ? .on : .off
        
        let videoSwitchRow = NSStackView()
        videoSwitchRow.orientation = .horizontal
        videoSwitchRow.spacing = 8
        videoSwitchRow.alignment = .centerY
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 116).isActive = true
        videoSwitchRow.addArrangedSubview(spacer)
        videoSwitchRow.addArrangedSubview(videoShiftArrowSwitchFileCheckbox)
        
        showArchiveFileTypeCheckbox = NSButton(checkboxWithTitle: "显示压缩文件", target: self, action: #selector(applyInlineFileActionSettings))
        showArchiveFileTypeCheckbox.state = globalVar.showArchiveFileType ? .on : .off

        let archiveSwitchRow = NSStackView()
        archiveSwitchRow.orientation = .horizontal
        archiveSwitchRow.spacing = 8
        archiveSwitchRow.alignment = .centerY
        let archiveSpacer = NSView()
        archiveSpacer.translatesAutoresizingMaskIntoConstraints = false
        archiveSpacer.widthAnchor.constraint(equalToConstant: 116).isActive = true
        archiveSwitchRow.addArrangedSubview(archiveSpacer)
        archiveSwitchRow.addArrangedSubview(showArchiveFileTypeCheckbox)

        let compressPasswordRow = NSStackView()
        compressPasswordRow.orientation = .horizontal
        compressPasswordRow.spacing = 8
        compressPasswordRow.alignment = .centerY
        let compressLabel = NSTextField(labelWithString: "ZIP 默认密码：")
        compressLabel.setContentHuggingPriority(.required, for: .horizontal)
        compressionDefaultPasswordField = NSSecureTextField()
        compressionDefaultPasswordField.stringValue = globalVar.compressionDefaultPassword
        compressionDefaultPasswordField.placeholderString = "可选"
        compressionDefaultPasswordField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        compressPasswordRow.addArrangedSubview(compressLabel)
        compressPasswordRow.addArrangedSubview(compressionDefaultPasswordField)

        let compressDefaultRow = NSStackView()
        compressDefaultRow.orientation = .horizontal
        compressDefaultRow.spacing = 8
        compressDefaultRow.alignment = .centerY
        let compressSpacer = NSView()
        compressSpacer.translatesAutoresizingMaskIntoConstraints = false
        compressSpacer.widthAnchor.constraint(equalToConstant: 116).isActive = true
        compressionUseDefaultPasswordCheckbox = NSButton(checkboxWithTitle: "默认使用上面的密码进行加密压缩", target: self, action: #selector(applyInlineFileActionSettings))
        compressionUseDefaultPasswordCheckbox.state = globalVar.compressionUseDefaultPassword ? .on : .off
        compressDefaultRow.addArrangedSubview(compressSpacer)
        compressDefaultRow.addArrangedSubview(compressionUseDefaultPasswordCheckbox)

        shortcutConflictLabel = NSTextField(wrappingLabelWithString: "")
        shortcutConflictLabel.textColor = .systemOrange
        shortcutConflictLabel.font = NSFont.systemFont(ofSize: 11)
        shortcutConflictLabel.lineBreakMode = .byWordWrapping
        shortcutConflictLabel.maximumNumberOfLines = 0

        shortcutRow.addArrangedSubview(shortcutLabel)
        shortcutRow.addArrangedSubview(photoFolder1ShortcutPopup)

        let shortcut2Row = NSStackView()
        shortcut2Row.orientation = .horizontal
        shortcut2Row.spacing = 8
        shortcut2Row.alignment = .centerY

        let shortcut2Label = NSTextField(labelWithString: "视频复制快捷键：")
        shortcut2Label.setContentHuggingPriority(.required, for: .horizontal)

        photoFolder2ShortcutPopup = NSPopUpButton()
        photoFolder2ShortcutPopup.addItems(withTitles: shortcutCandidates)
        let selectedShortcut2 = globalVar.photoFolder2CopyShortcut.uppercased()
        photoFolder2ShortcutPopup.selectItem(withTitle: shortcutCandidates.contains(selectedShortcut2) ? selectedShortcut2 : "F4")
        photoFolder2ShortcutPopup.target = self
        photoFolder2ShortcutPopup.action = #selector(applyInlineFileActionSettings)

        shortcut2Row.addArrangedSubview(shortcut2Label)
        shortcut2Row.addArrangedSubview(photoFolder2ShortcutPopup)
        
        panel.addArrangedSubview(renameRow)
        panel.addArrangedSubview(folderRow)
        panel.addArrangedSubview(shortcutRow)
        panel.addArrangedSubview(folder2Row)
        panel.addArrangedSubview(shortcut2Row)
        panel.addArrangedSubview(videoSwitchRow)
        panel.addArrangedSubview(archiveSwitchRow)
        panel.addArrangedSubview(compressPasswordRow)
        panel.addArrangedSubview(compressDefaultRow)
        panel.addArrangedSubview(shortcutConflictLabel)

        guard let container = grid.cell(atColumnIndex: 1, rowIndex: targetRow).contentView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        container.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            panel.topAnchor.constraint(equalTo: container.topAnchor),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        let minHeight = max(180, panel.fittingSize.height + 12)
        grid.row(at: targetRow).height = minHeight
        updateShortcutInfoLabels()
    }

    private func collapseGuideSection() {
        guard let grid = view.subviews.compactMap({ $0 as? NSGridView }).first else { return }
        guideGrid = grid

        let guideRowIndex = 2
        let hiddenRows = [3, 4, 5, 6, 7, 8, 9]
        hiddenRows.forEach { rowIndex in
            guard rowIndex < grid.numberOfRows else { return }
            grid.row(at: rowIndex).isHidden = true
        }

        guard guideRowIndex < grid.numberOfRows else { return }
        if let leftLabel = grid.cell(atColumnIndex: 0, rowIndex: guideRowIndex).contentView as? NSTextField {
            leftLabel.stringValue = "操作指引："
        }

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        container.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        if let oldTextView = grid.cell(atColumnIndex: 1, rowIndex: guideRowIndex).contentView as? NSTextField {
            oldTextView.stringValue = ""
            oldTextView.textColor = .clear
            oldTextView.isBordered = false
            oldTextView.drawsBackground = false
        }

        let guideButton = NSButton(title: "操作说明", target: self, action: #selector(showActionGuide))
        guideButton.bezelStyle = .rounded
        guideButton.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let shortcutButton = NSButton(title: "快捷键对照", target: self, action: #selector(showShortcutReference))
        shortcutButton.bezelStyle = .rounded
        shortcutButton.widthAnchor.constraint(equalToConstant: 116).isActive = true

        let hint = NSTextField(labelWithString: "点击按钮后会以弹窗显示说明，按 Esc 可先关闭弹窗，再按 Esc 关闭设置窗口。")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 0

        buttonRow.addArrangedSubview(guideButton)
        buttonRow.addArrangedSubview(shortcutButton)

        container.addArrangedSubview(buttonRow)
        container.addArrangedSubview(hint)

        if let contentView = grid.cell(atColumnIndex: 1, rowIndex: guideRowIndex).contentView {
            contentView.subviews.forEach { $0.removeFromSuperview() }
            contentView.addSubview(container)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                container.topAnchor.constraint(equalTo: contentView.topAnchor),
                container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        grid.row(at: guideRowIndex).height = 50
    }

    @objc private func showActionGuide() {
        let sections: [(String, String)] = [
            (
                "图像浏览：",
                "双击打开或关闭图片。\n按住右键或左键滚动滚轮可以缩放。\n按住中键拖动可以移动窗口。\n长按左键切换 100% 缩放。\n长按右键切换缩放到视图。"
            ),
            (
                "右键手势：",
                "向右 / 左：切换到下一个 / 上一个有图片或视频的文件夹。\n向上：切换到上级目录。\n向下：返回上一次目录。\n右上：切换到与当前文件夹平级的下一个图片文件夹。\n右下：关闭当前标签页或窗口。"
            ),
            (
                "键盘按键：",
                "缩略图视图时：W / S / A / D / E 等同于右键手势上 / 下 / 左 / 右 / 右上。\n图像视图时：W / S 放大 / 缩小，Z 缩放到 100%，X 缩放到适合，A / D 上一张 / 下一张。"
            ),
            (
                "快速搜索：",
                "在缩略图界面按 Q 开启快速搜索，可在短时间内输入关键字定位文件。此状态下数字键、字母键和退格键会作为输入用途。更完整的搜索请使用 Command + F。"
            )
        ]

        let message = sections.map { "**\($0.0)**\n\($0.1)" }.joined(separator: "\n\n")
        showInformationLong(title: "操作说明", message: message, width: 460)
    }

    @objc private func showShortcutReference() {
        showInformationLong(title: "快捷键对照", message: shortcutReferenceText(), width: 460)
    }
    
    @objc private func selectPhotoFolder1Inline() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            photoFolder1PathField.stringValue = url.path
            applyInlineFileActionSettings()
        }
    }

    @objc private func selectPhotoFolder2Inline() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            photoFolder2PathField.stringValue = url.path
            applyInlineFileActionSettings()
        }
    }
    
    @objc private func applyInlineFileActionSettings() {
        let renameRule = quickRenameRuleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        globalVar.quickRenameRule = renameRule.isEmpty ? "{folder}_{index}" : renameRule
        UserDefaults.standard.set(globalVar.quickRenameRule, forKey: "quickRenameRule")
        
        let folderPath = photoFolder1PathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !folderPath.isEmpty {
            globalVar.photoFolder1Path = folderPath
            UserDefaults.standard.set(folderPath, forKey: "photoFolder1Path")
        }
        let folder2Path = photoFolder2PathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !folder2Path.isEmpty {
            globalVar.photoFolder2Path = folder2Path
            UserDefaults.standard.set(folder2Path, forKey: "photoFolder2Path")
        }
        
        if let title = photoFolder1ShortcutPopup.selectedItem?.title, !title.isEmpty {
            globalVar.photoFolder1CopyShortcut = title.uppercased()
            UserDefaults.standard.set(globalVar.photoFolder1CopyShortcut, forKey: "photoFolder1CopyShortcut")
        }
        if let title = photoFolder2ShortcutPopup.selectedItem?.title, !title.isEmpty {
            globalVar.photoFolder2CopyShortcut = title.uppercased()
            UserDefaults.standard.set(globalVar.photoFolder2CopyShortcut, forKey: "photoFolder2CopyShortcut")
        }
        
        globalVar.videoShiftArrowSwitchFile = (videoShiftArrowSwitchFileCheckbox.state == .on)
        UserDefaults.standard.set(globalVar.videoShiftArrowSwitchFile, forKey: "videoShiftArrowSwitchFile")
        
        globalVar.showArchiveFileType = (showArchiveFileTypeCheckbox.state == .on)
        UserDefaults.standard.set(globalVar.showArchiveFileType, forKey: "showArchiveFileType")

        globalVar.compressionDefaultPassword = compressionDefaultPasswordField.stringValue
        UserDefaults.standard.set(globalVar.compressionDefaultPassword, forKey: "compressionDefaultPassword")

        globalVar.compressionUseDefaultPassword = (compressionUseDefaultPasswordCheckbox.state == .on)
        UserDefaults.standard.set(globalVar.compressionUseDefaultPassword, forKey: "compressionUseDefaultPassword")
        updateShortcutInfoLabels()
    }

    private func updateShortcutInfoLabels() {
        let folder1 = (photoFolder1ShortcutPopup.selectedItem?.title ?? globalVar.photoFolder1CopyShortcut).uppercased()
        let folder2 = (photoFolder2ShortcutPopup.selectedItem?.title ?? globalVar.photoFolder2CopyShortcut).uppercased()
        var warnings: [String] = []
        if folder1 == folder2, !folder1.isEmpty {
            warnings.append("图片文件夹1和视频文件夹2使用了同一个快捷键：\(folder1)")
        }
        if let note = reservedShortcutNotes.first(where: { $0.key == folder1 })?.note {
            warnings.append("图片文件夹1快捷键 \(folder1) 会覆盖内置功能：\(note)")
        }
        if let note = reservedShortcutNotes.first(where: { $0.key == folder2 })?.note {
            warnings.append("视频文件夹2快捷键 \(folder2) 会覆盖内置功能：\(note)")
        }
        shortcutConflictLabel.stringValue = warnings.joined(separator: "\n")
        shortcutConflictLabel.isHidden = warnings.isEmpty
    }

    private func shortcutReferenceText() -> String {
        let custom1 = "图片文件夹1：\(globalVar.photoFolder1CopyShortcut)"
        let custom2 = "视频文件夹2：\(globalVar.photoFolder2CopyShortcut)"
        let builtins = reservedShortcutNotes.map { "\($0.key)  \($0.note)" }.joined(separator: "\n")
        return ([custom1, custom2, "内置快捷键：", builtins]).joined(separator: "\n")
    }

    private func installEscMonitorIfNeeded() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53 else { return event }
            guard let window = self.view.window, window.isKeyWindow else { return event }
            guard NSApp.modalWindow == nil else { return event }
            window.performClose(nil)
            return nil
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}
