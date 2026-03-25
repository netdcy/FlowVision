//
//  CustomProfileView.swift
//  FlowVision
//
//

import Foundation
import Cocoa

private class CardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        updateLayer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class ProfileOptionsWindow: NSWindow {
    private var initialProfile = CustomProfile()

    private var initialWindowTitleUseFullPath: Bool {
        return initialProfile.getValue(forKey: "isWindowTitleUseFullPath") == "true"
    }
    private var initialWindowTitleShowStatistics: Bool {
        return initialProfile.getValue(forKey: "isWindowTitleShowStatistics") == "true"
    }
    private var initialShowThumbnailBadge: Bool {
        return initialProfile.getValue(forKey: "isShowThumbnailBadge") == "true"
    }
    private var initialShowThumbnailTag: Bool {
        return initialProfile.getValue(forKey: "isShowThumbnailTag") == "true"
    }
    private var initialShowThumbnailFilename: Bool {
        return initialProfile.isShowThumbnailFilename
    }
    private var initialThumbnailFilenameSize: Double {
        return initialProfile.ThumbnailFilenameSize
    }
    private var initialThumbnailCellPadding: Double {
        return initialProfile._thumbnailCellPadding
    }
    private var initialThumbnailBorderRadiusInGrid: Double {
        return initialProfile.ThumbnailBorderRadiusInGrid
    }
    private var initialThumbnailBorderRadius: Double {
        return initialProfile.ThumbnailBorderRadius
    }
    private var initialThumbnailBorderThickness: Double {
        return initialProfile._thumbnailBorderThickness
    }
    private var initialThumbnailLineSpaceAdjust: Double {
        return initialProfile.ThumbnailLineSpaceAdjust
    }
    private var initialThumbnailShowShadow: Bool {
        return initialProfile.ThumbnailShowShadow
    }

    var isWindowTitleUseFullPath: Bool
    var isWindowTitleShowStatistics: Bool
    var isShowThumbnailBadge: Bool
    var isShowThumbnailTag: Bool
    var isShowThumbnailFilename: Bool
    var thumbnailFilenameSize: Double
    var thumbnailCellPadding: Double
    var thumbnailBorderRadiusInGrid: Double
    var thumbnailBorderRadius: Double
    var thumbnailBorderThickness: Double
    var thumbnailLineSpaceAdjust: Double
    var thumbnailShowShadow: Bool

    private var windowTitleFullPathCheckbox: NSButton!
    private var windowTitleStatsCheckbox: NSButton!
    private var showBadgeCheckbox: NSButton!
    private var showTagCheckbox: NSButton!
    private var showFilenameCheckbox: NSButton!
    private var filenameSizeTextField: NSTextField!
    private var cellPaddingTextField: NSTextField!
    private var borderRadiusInGridTextField: NSTextField!
    private var borderRadiusTextField: NSTextField!
    private var borderThicknessTextField: NSTextField!
    private var lineSpaceAdjustTextField: NSTextField!
    private var showShadowCheckbox: NSButton!

    init() {
        let windowSize = NSSize(width: 560, height: 660)
        let windowRect = NSRect(origin: .zero, size: windowSize)

        let profile = getMainViewController()!.publicVar.profile
        isWindowTitleUseFullPath = profile.getValue(forKey: "isWindowTitleUseFullPath") == "true"
        isWindowTitleShowStatistics = profile.getValue(forKey: "isWindowTitleShowStatistics") == "true"
        isShowThumbnailBadge = profile.getValue(forKey: "isShowThumbnailBadge") == "true"
        isShowThumbnailTag = profile.getValue(forKey: "isShowThumbnailTag") == "true"
        isShowThumbnailFilename = profile.isShowThumbnailFilename
        thumbnailFilenameSize = profile.ThumbnailFilenameSize
        thumbnailCellPadding = profile._thumbnailCellPadding
        thumbnailBorderRadiusInGrid = profile.ThumbnailBorderRadiusInGrid
        thumbnailBorderRadius = profile.ThumbnailBorderRadius
        thumbnailBorderThickness = profile._thumbnailBorderThickness
        thumbnailLineSpaceAdjust = profile.ThumbnailLineSpaceAdjust
        thumbnailShowShadow = profile.ThumbnailShowShadow

        super.init(contentRect: windowRect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.title = NSLocalizedString("Thumbnail Options", comment: "缩略图选项")

        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        let backgroundView = NSVisualEffectView(frame: contentView.bounds)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.material = .underWindowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        contentView.addSubview(backgroundView)

        let mainStack = NSStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 16
        contentView.addSubview(mainStack)

        // Header
        let headerView = createHeader()
        mainStack.addArrangedSubview(headerView)

        // Section 1: Window Title
        windowTitleFullPathCheckbox = makeCheckbox(isChecked: isWindowTitleUseFullPath)
        windowTitleStatsCheckbox = makeCheckbox(isChecked: isWindowTitleShowStatistics)

        let windowTitleSection = createSection(
            title: NSLocalizedString("Window Title", comment: "窗口标题"),
            iconName: "macwindow",
            rows: [
                makeCheckboxRow(
                    label: NSLocalizedString("Use Full Path in Window Title", comment: "在窗口标题中使用完整路径"),
                    checkbox: windowTitleFullPathCheckbox),
                makeCheckboxRow(
                    label: NSLocalizedString("Show Statistics in Window Title", comment: "在窗口标题中显示统计信息"),
                    checkbox: windowTitleStatsCheckbox),
            ]
        )
        mainStack.addArrangedSubview(windowTitleSection)

        // Section 2: Thumbnail General
        showBadgeCheckbox = makeCheckbox(isChecked: isShowThumbnailBadge)
        showTagCheckbox = makeCheckbox(isChecked: isShowThumbnailTag)
        showFilenameCheckbox = makeCheckbox(isChecked: isShowThumbnailFilename)
        filenameSizeTextField = makeNumberField(value: thumbnailFilenameSize)
        cellPaddingTextField = makeNumberField(value: thumbnailCellPadding)

        let generalSection = createSection(
            title: NSLocalizedString("Thumbnail General", comment: "缩略图通用"),
            iconName: "photo",
            rows: [
                makeCheckboxRow(
                    label: NSLocalizedString("Show RAW/HDR Badge", comment: "显示RAW/HDR标记"),
                    checkbox: showBadgeCheckbox),
                makeCheckboxRow(
                    label: NSLocalizedString("Show Tags and Ratings", comment: "显示标签和评级"),
                    checkbox: showTagCheckbox),
                makeCheckboxRow(
                    label: NSLocalizedString("Show Filename", comment: "显示文件名"),
                    checkbox: showFilenameCheckbox),
                makeTextFieldRow(
                    label: NSLocalizedString("Filename Font Size", comment: "文件名字体大小"),
                    textField: filenameSizeTextField),
                makeTextFieldRow(
                    label: NSLocalizedString("Cell Padding", comment: "单元格外边距"),
                    textField: cellPaddingTextField),
            ]
        )
        mainStack.addArrangedSubview(generalSection)

        // Section 3: Grid View
        borderRadiusInGridTextField = makeNumberField(value: thumbnailBorderRadiusInGrid)

        let gridSection = createSection(
            title: NSLocalizedString("Grid View", comment: "网格视图"),
            iconName: "square.grid.3x3",
            rows: [
                makeTextFieldRow(
                    label: NSLocalizedString("Corner Radius", comment: "圆角半径"),
                    textField: borderRadiusInGridTextField),
            ]
        )
        mainStack.addArrangedSubview(gridSection)

        // Section 4: Non-Grid View
        borderRadiusTextField = makeNumberField(value: thumbnailBorderRadius)
        borderThicknessTextField = makeNumberField(value: thumbnailBorderThickness)
        lineSpaceAdjustTextField = makeNumberField(value: thumbnailLineSpaceAdjust)
        showShadowCheckbox = makeCheckbox(isChecked: thumbnailShowShadow)

        let nonGridSection = createSection(
            title: NSLocalizedString("Non-Grid View", comment: "非网格视图"),
            iconName: "squares.below.rectangle",
            rows: [
                makeTextFieldRow(
                    label: NSLocalizedString("Corner Radius", comment: "圆角半径"),
                    textField: borderRadiusTextField),
                makeTextFieldRow(
                    label: NSLocalizedString("Border Thickness", comment: "边框厚度"),
                    textField: borderThicknessTextField),
                makeTextFieldRow(
                    label: NSLocalizedString("Line Space Adjustment", comment: "行间距调整"),
                    textField: lineSpaceAdjustTextField),
                makeCheckboxRow(
                    label: NSLocalizedString("Show Shadow", comment: "显示阴影"),
                    checkbox: showShadowCheckbox),
            ]
        )
        mainStack.addArrangedSubview(nonGridSection)

        // Buttons
        let buttonContainer = createButtons()
        mainStack.addArrangedSubview(buttonContainer)

        // Layout
        let contentWidth: CGFloat = 500

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            mainStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            mainStack.widthAnchor.constraint(equalToConstant: contentWidth),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),

            windowTitleSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            generalSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            gridSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            nonGridSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            buttonContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    // MARK: - Header

    private func createHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        icon.contentTintColor = .controlAccentColor

        let label = NSTextField(labelWithString: NSLocalizedString("Custom Layout Style", comment: "自定义布局样式"))
        label.font = NSFont.systemFont(ofSize: 17, weight: .semibold)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        return stack
    }

    // MARK: - Section Builder

    private func createSection(title: String, iconName: String, rows: [NSView]) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6

        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 5
        headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        headerStack.addArrangedSubview(iconView)
        headerStack.addArrangedSubview(titleLabel)
        container.addArrangedSubview(headerStack)

        let card = CardView(frame: .zero)
        card.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = NSStackView()
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.orientation = .vertical
        cardStack.spacing = 0
        cardStack.alignment = .leading

        for (index, row) in rows.enumerated() {
            let rowWrapper = NSView()
            rowWrapper.translatesAutoresizingMaskIntoConstraints = false
            row.translatesAutoresizingMaskIntoConstraints = false
            rowWrapper.addSubview(row)

            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: rowWrapper.topAnchor, constant: 8),
                row.bottomAnchor.constraint(equalTo: rowWrapper.bottomAnchor, constant: -8),
                row.leadingAnchor.constraint(equalTo: rowWrapper.leadingAnchor, constant: 16),
                row.trailingAnchor.constraint(equalTo: rowWrapper.trailingAnchor, constant: -16),
            ])

            cardStack.addArrangedSubview(rowWrapper)
            rowWrapper.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

            if index < rows.count - 1 {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false

                let sepWrapper = NSView()
                sepWrapper.translatesAutoresizingMaskIntoConstraints = false
                sepWrapper.addSubview(sep)

                NSLayoutConstraint.activate([
                    sep.leadingAnchor.constraint(equalTo: sepWrapper.leadingAnchor, constant: 16),
                    sep.trailingAnchor.constraint(equalTo: sepWrapper.trailingAnchor),
                    sep.centerYAnchor.constraint(equalTo: sepWrapper.centerYAnchor),
                    sepWrapper.heightAnchor.constraint(equalToConstant: 1),
                ])

                cardStack.addArrangedSubview(sepWrapper)
                sepWrapper.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
            }
        }

        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])

        container.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        return container
    }

    // MARK: - Row Builders

    private func makeCheckbox(isChecked: Bool) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.state = isChecked ? .on : .off
        return checkbox
    }

    private func makeNumberField(value: Double) -> NSTextField {
        let textField = NSTextField(string: String(value))
        textField.alignment = .right
        textField.bezelStyle = .roundedBezel
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        return textField
    }

    private func makeCheckboxRow(label: String, checkbox: NSButton) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: 13)
        labelView.lineBreakMode = .byTruncatingTail
        labelView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(checkbox)

        return stack
    }

    private func makeTextFieldRow(label: String, textField: NSTextField) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: 13)
        labelView.lineBreakMode = .byTruncatingTail
        labelView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(textField)

        return stack
    }

    // MARK: - Buttons

    private func createButtons() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let resetButton = NSButton(title: NSLocalizedString("Reset", comment: "重置"), target: self, action: #selector(resetButtonPressed))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .regular

        let cancelButton = NSButton(title: NSLocalizedString("Cancel", comment: "取消"), target: self, action: #selector(cancelButtonPressed))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.controlSize = .regular

        let okButton = NSButton(title: NSLocalizedString("OK", comment: "确定"), target: self, action: #selector(okButtonPressed))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.controlSize = .regular

        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(resetButton)
        stack.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(okButton)

        NSLayoutConstraint.activate([
            resetButton.widthAnchor.constraint(equalToConstant: 80),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            okButton.widthAnchor.constraint(equalToConstant: 80),
        ])

        return stack
    }

    // MARK: - Actions

    @objc func okButtonPressed() {
        self.isWindowTitleUseFullPath = windowTitleFullPathCheckbox.state == .on
        self.isWindowTitleShowStatistics = windowTitleStatsCheckbox.state == .on
        self.isShowThumbnailBadge = showBadgeCheckbox.state == .on
        self.isShowThumbnailTag = showTagCheckbox.state == .on
        self.isShowThumbnailFilename = showFilenameCheckbox.state == .on
        self.thumbnailFilenameSize = Double(filenameSizeTextField.stringValue) ?? initialThumbnailFilenameSize
        self.thumbnailCellPadding = Double(cellPaddingTextField.stringValue) ?? initialThumbnailCellPadding
        self.thumbnailBorderRadiusInGrid = Double(borderRadiusInGridTextField.stringValue) ?? initialThumbnailBorderRadiusInGrid
        self.thumbnailBorderRadius = Double(borderRadiusTextField.stringValue) ?? initialThumbnailBorderRadius
        self.thumbnailBorderThickness = Double(borderThicknessTextField.stringValue) ?? initialThumbnailBorderThickness
        self.thumbnailLineSpaceAdjust = Double(lineSpaceAdjustTextField.stringValue) ?? initialThumbnailLineSpaceAdjust
        self.thumbnailShowShadow = showShadowCheckbox.state == .on

        self.sheetParent?.endSheet(self, returnCode: .OK)
    }

    @objc func cancelButtonPressed() {
        self.sheetParent?.endSheet(self, returnCode: .cancel)
    }

    @objc func resetButtonPressed() {
        windowTitleFullPathCheckbox.state = initialWindowTitleUseFullPath ? .on : .off
        windowTitleStatsCheckbox.state = initialWindowTitleShowStatistics ? .on : .off
        showBadgeCheckbox.state = initialShowThumbnailBadge ? .on : .off
        showTagCheckbox.state = initialShowThumbnailTag ? .on : .off
        showFilenameCheckbox.state = initialShowThumbnailFilename ? .on : .off
        filenameSizeTextField.stringValue = String(initialThumbnailFilenameSize)
        cellPaddingTextField.stringValue = String(initialThumbnailCellPadding)
        borderRadiusInGridTextField.stringValue = String(initialThumbnailBorderRadiusInGrid)
        borderRadiusTextField.stringValue = String(initialThumbnailBorderRadius)
        borderThicknessTextField.stringValue = String(initialThumbnailBorderThickness)
        lineSpaceAdjustTextField.stringValue = String(initialThumbnailLineSpaceAdjust)
        showShadowCheckbox.state = initialThumbnailShowShadow ? .on : .off
    }
}


func showProfileOptionsPanel(on parentWindow: NSWindow, completion: @escaping (Bool, Bool, Bool, Bool, Bool, Double, Double, Double, Double, Double, Double, Bool) -> Void) {
    let profileOptionsWindow = ProfileOptionsWindow()
    let StoreIsKeyEventEnabled = getMainViewController()!.publicVar.isKeyEventEnabled
    getMainViewController()!.publicVar.isKeyEventEnabled=false
    parentWindow.beginSheet(profileOptionsWindow) { response in
        getMainViewController()!.publicVar.isKeyEventEnabled=StoreIsKeyEventEnabled
        if response == .OK {
            completion(profileOptionsWindow.isWindowTitleUseFullPath,
                       profileOptionsWindow.isWindowTitleShowStatistics,
                       profileOptionsWindow.isShowThumbnailBadge,
                       profileOptionsWindow.isShowThumbnailTag,
                       profileOptionsWindow.isShowThumbnailFilename,
                       profileOptionsWindow.thumbnailFilenameSize,
                       profileOptionsWindow.thumbnailCellPadding,
                       profileOptionsWindow.thumbnailBorderRadiusInGrid,
                       profileOptionsWindow.thumbnailBorderRadius,
                       profileOptionsWindow.thumbnailBorderThickness,
                       profileOptionsWindow.thumbnailLineSpaceAdjust,
                       profileOptionsWindow.thumbnailShowShadow)
        } else {
            log("User canceled custom style window.")
        }
    }
}
