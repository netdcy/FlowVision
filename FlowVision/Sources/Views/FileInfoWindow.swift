//
//  FileInfoWindow.swift
//  FlowVision
//

import Cocoa

// MARK: - Data models

struct FileInfoHeader {
    let icon: NSImage
    let title: String
    let subtitle: String
}

struct FileInfoSection {
    enum Kind {
        case keyValue([(String, String)])
        case textBlock(String, monospace: Bool)
    }
    let title: String
    let kind: Kind
    var collapsible: Bool = false
    var initiallyCollapsed: Bool = false
}

// MARK: - Window controller

final class FileInfoWindowController: NSWindowController, NSWindowDelegate {

    private static var openControllers: [FileInfoWindowController] = []
    private var onClose: (() -> Void)?

    @discardableResult
    static func show(
        header: FileInfoHeader,
        sections: [FileInfoSection],
        revealURLs: [URL]? = nil,
        anchorWindow: NSWindow? = nil,
        onClose: (() -> Void)? = nil
    ) -> FileInfoWindowController {
        let vc = FileInfoViewController(header: header, sections: sections, revealURLs: revealURLs)

        let initialSize = NSSize(width: FileInfoLayout.windowWidth, height: 500)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = NSLocalizedString("File Info", comment: "文件信息")
        window.contentViewController = vc
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        // Fit window to content (up to a sensible max), then enable scrolling
        vc.view.layoutSubtreeIfNeeded()
        let desiredContentHeight = vc.preferredContentHeight()
        let maxHeight: CGFloat = 760
        let contentHeight = min(max(desiredContentHeight, 240), maxHeight)
        let contentRect = NSRect(x: 0, y: 0, width: FileInfoLayout.windowWidth, height: contentHeight)
        let frame = window.frameRect(forContentRect: contentRect)
        window.setFrame(frame, display: false)
        window.contentMinSize = contentRect.size
        window.contentMaxSize = contentRect.size

        let controller = FileInfoWindowController(window: window)
        controller.onClose = onClose
        window.delegate = controller

        // Cascade placement based on number of already-open info windows
        if let anchor = anchorWindow {
            let anchorFrame = anchor.frame
            var origin = NSPoint(
                x: anchorFrame.midX - frame.width / 2,
                y: anchorFrame.midY - frame.height / 2
            )
            let offset = CGFloat((openControllers.count % 8) * 22)
            origin.x += offset
            origin.y -= offset
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        openControllers.append(controller)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        return controller
    }

    func updateSections(_ sections: [FileInfoSection]) {
        (window?.contentViewController as? FileInfoViewController)?.updateSections(sections)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
        Self.openControllers.removeAll { $0 === self }
    }
}

// MARK: - Layout constants

enum FileInfoLayout {
    static let windowWidth: CGFloat = 460
    static let horizontalPadding: CGFloat = 18
    static let headerHeight: CGFloat = 92
    static let buttonBarHeight: CGFloat = 48
    static let sectionSpacing: CGFloat = 14
    static let keyColumnWidth: CGFloat = 130
}

// MARK: - View controller

final class FileInfoViewController: NSViewController {

    private let header: FileInfoHeader
    private var sections: [FileInfoSection]
    private let revealURLs: [URL]?

    private var stackView: NSStackView!
    private var scrollView: NSScrollView!

    init(header: FileInfoHeader, sections: [FileInfoSection], revealURLs: [URL]?) {
        self.header = header
        self.sections = sections
        self.revealURLs = revealURLs
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func loadView() {
        let width = FileInfoLayout.windowWidth
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 500))
        container.wantsLayer = true
        //container.translatesAutoresizingMaskIntoConstraints = false
        //container.widthAnchor.constraint(equalToConstant: width).isActive = true

        let headerView = makeHeaderView()
        let headerSeparator = makeSeparator()
        let scroll = makeScrollView()
        let footerSeparator = makeSeparator()
        let buttonBar = makeButtonBar()

        for v in [headerView, headerSeparator, scroll, footerSeparator, buttonBar] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: container.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: FileInfoLayout.headerHeight),

            headerSeparator.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor),

            footerSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footerSeparator.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),
            footerSeparator.heightAnchor.constraint(equalToConstant: 1),

            buttonBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            buttonBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            buttonBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            buttonBar.heightAnchor.constraint(equalToConstant: FileInfoLayout.buttonBarHeight),
        ])

        self.view = container
    }

    func preferredContentHeight() -> CGFloat {
        stackView.layoutSubtreeIfNeeded()
        let stackHeight = stackView.fittingSize.height
        return FileInfoLayout.headerHeight + 1 + stackHeight + 1 + FileInfoLayout.buttonBarHeight
    }

    func updateSections(_ sections: [FileInfoSection]) {
        self.sections = sections
        guard isViewLoaded else { return }
        rebuildSectionViews()
        view.layoutSubtreeIfNeeded()
    }

    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(nil)
    }

    // MARK: Build subviews

    private func makeHeaderView() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let imageView = NSImageView()
        imageView.image = header.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(labelWithString: header.title)
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.maximumNumberOfLines = 1
        titleField.toolTip = header.title
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitleField = NSTextField(labelWithString: header.subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 2
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [titleField, subtitleField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(imageView)
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: FileInfoLayout.horizontalPadding),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 56),
            imageView.heightAnchor.constraint(equalToConstant: 56),

            textStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -FileInfoLayout.horizontalPadding),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = FileInfoLayout.sectionSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: 14,
            left: FileInfoLayout.horizontalPadding,
            bottom: 14,
            right: FileInfoLayout.horizontalPadding
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalToConstant: FileInfoLayout.windowWidth),
        ])

        scroll.documentView = document
        self.stackView = stack
        self.scrollView = scroll
        rebuildSectionViews()
        return scroll
    }

    private func rebuildSectionViews() {
        guard stackView != nil else { return }
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for section in sections {
            let sectionView = FileInfoSectionView(section: section)
            stackView.addArrangedSubview(sectionView)
            NSLayoutConstraint.activate([
                sectionView.widthAnchor.constraint(
                    equalToConstant: FileInfoLayout.windowWidth - FileInfoLayout.horizontalPadding * 2
                )
            ])
        }
    }

    private func makeButtonBar() -> NSView {
        let container = NSView()

        let copyButton = NSButton(
            title: NSLocalizedString("Copy All", comment: "复制全部"),
            target: self,
            action: #selector(actCopyAll)
        )
        copyButton.focusRingType = .none
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        let revealButton = NSButton(
            title: NSLocalizedString("Show in Finder", comment: "在 Finder 中显示"),
            target: self,
            action: #selector(actRevealInFinder)
        )
        revealButton.focusRingType = .none
        revealButton.bezelStyle = .rounded
        revealButton.translatesAutoresizingMaskIntoConstraints = false
        revealButton.isEnabled = (revealURLs?.isEmpty == false)

        let closeButton = NSButton(
            title: NSLocalizedString("Close", comment: "关闭"),
            target: self,
            action: #selector(actClose)
        )
        closeButton.focusRingType = .none
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(copyButton)
        container.addSubview(revealButton)
        container.addSubview(closeButton)

        NSLayoutConstraint.activate([
            copyButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: FileInfoLayout.horizontalPadding),
            copyButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            revealButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 8),
            revealButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -FileInfoLayout.horizontalPadding),
            closeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    // MARK: Actions

    @objc private func actCopyAll() {
        let text = FileInfoTextRenderer.render(header: header, sections: sections)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func actRevealInFinder() {
        guard let urls = revealURLs, !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func actClose() {
        view.window?.performClose(nil)
    }
}

// MARK: - Section view

final class FileInfoSectionView: NSView {

    private var contentContainer: NSView!
    private var disclosure: NSButton?
    private var isCollapsed: Bool

    init(section: FileInfoSection) {
        self.isCollapsed = section.collapsible && section.initiallyCollapsed
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(section: section)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func build(section: FileInfoSection) {
        let titleLabel = NSTextField(labelWithString: section.title.uppercased())
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSView()
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addSubview(titleLabel)

        var leadingAnchorForTitle = titleRow.leadingAnchor

        if section.collapsible {
            let btn = NSButton()
            btn.bezelStyle = .disclosure
            btn.setButtonType(.pushOnPushOff)
            btn.title = ""
            btn.state = isCollapsed ? .off : .on
            btn.target = self
            btn.focusRingType = .none
            btn.action = #selector(toggleCollapse(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            titleRow.addSubview(btn)

            NSLayoutConstraint.activate([
                btn.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
                btn.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            ])
            self.disclosure = btn
            leadingAnchorForTitle = btn.trailingAnchor
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchorForTitle, constant: section.collapsible ? 6 : 0),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleRow.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            titleRow.heightAnchor.constraint(equalToConstant: 18),
        ])

        let content: NSView
        switch section.kind {
        case .keyValue(let pairs):
            content = buildKeyValueGrid(pairs: pairs)
        case .textBlock(let text, let monospace):
            content = buildTextBlock(text: text, monospace: monospace)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        self.contentContainer = content

        let outerStack = NSStackView(views: [titleRow, content])
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 8
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleRow.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            content.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
        ])

        if section.collapsible {
            // Initial collapsed state: hide content
            content.isHidden = isCollapsed
        }

        if section.collapsible {
            // Make title row clickable too
            let click = NSClickGestureRecognizer(target: self, action: #selector(toggleCollapseFromTitle(_:)))
            titleRow.addGestureRecognizer(click)
        }
    }

    @objc private func toggleCollapse(_ sender: NSButton) {
        isCollapsed = (sender.state == .off)
        applyCollapseState(animated: true)
    }

    @objc private func toggleCollapseFromTitle(_ sender: NSClickGestureRecognizer) {
        isCollapsed.toggle()
        disclosure?.state = isCollapsed ? .off : .on
        applyCollapseState(animated: true)
    }

    private func applyCollapseState(animated: Bool) {
        let target = isCollapsed
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                contentContainer.isHidden = target
                window?.layoutIfNeeded()
            }
        } else {
            contentContainer.isHidden = target
        }
    }

    private func buildKeyValueGrid(pairs: [(String, String)]) -> NSView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.columnSpacing = 12
        grid.rowSpacing = 5
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = FileInfoLayout.keyColumnWidth
        grid.column(at: 1).xPlacement = .leading

        for (key, value) in pairs {
            let keyLabel = NSTextField(labelWithString: key)
            keyLabel.font = NSFont.systemFont(ofSize: 11)
            keyLabel.textColor = .secondaryLabelColor
            keyLabel.alignment = .right
            keyLabel.lineBreakMode = .byWordWrapping
            keyLabel.maximumNumberOfLines = 0

            let valueField = NSTextField(wrappingLabelWithString: value)
            valueField.font = NSFont.systemFont(ofSize: 11)
            valueField.textColor = .labelColor
            valueField.isSelectable = true
            valueField.isEditable = false
            valueField.drawsBackground = false
            valueField.isBordered = false
            valueField.maximumNumberOfLines = 0
            valueField.preferredMaxLayoutWidth =
                FileInfoLayout.windowWidth - FileInfoLayout.horizontalPadding * 2 - FileInfoLayout.keyColumnWidth - 16

            grid.addRow(with: [keyLabel, valueField])
        }
        return grid
    }

    private func buildTextBlock(text: String, monospace: Bool) -> NSView {
        let availableWidth =
            FileInfoLayout.windowWidth - FileInfoLayout.horizontalPadding * 2

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.font = monospace
            ? NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
            : NSFont.systemFont(ofSize: 11)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = text
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: availableWidth,
            height: CGFloat.greatestFiniteMagnitude
        )

        // Calculate desired height (clamped) to give a reasonable initial size
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).size ?? .zero
        let desired = min(max(used.height + 16, 160), 420)

        scroll.documentView = textView
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: desired),
        ])
        return scroll
    }
}

// MARK: - Helper views

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Plain-text rendering for "Copy All"

enum FileInfoTextRenderer {

    static func render(header: FileInfoHeader, sections: [FileInfoSection]) -> String {
        var lines: [String] = []
        lines.append(header.title)
        if !header.subtitle.isEmpty {
            lines.append(header.subtitle)
        }
        lines.append("")

        for (idx, section) in sections.enumerated() {
            if idx > 0 { lines.append("") }
            lines.append("[\(section.title)]")
            switch section.kind {
            case .keyValue(let pairs):
                lines.append(renderAlignedPairs(pairs))
            case .textBlock(let text, _):
                lines.append(text)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderAlignedPairs(_ pairs: [(String, String)]) -> String {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let maxKeyLen = pairs.map { $0.0.size(withAttributes: [.font: font]).width }.max() ?? 0
        let spaceWidth = " ".size(withAttributes: [.font: font]).width
        var out: [String] = []
        for (k, v) in pairs {
            let keyLen = k.size(withAttributes: [.font: font]).width
            let padCount = max(0, Int((maxKeyLen - keyLen) / spaceWidth))
            out.append("\(k):\(String(repeating: " ", count: padCount)) \(v)")
        }
        return out.joined(separator: "\n")
    }
}
