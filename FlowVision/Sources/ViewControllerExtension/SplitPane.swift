//
//  SplitPane.swift
//  FlowVision
//

import Foundation
import Cocoa

// MARK: - 窗口/窗口控制器的窗格访问器
// MARK: - Pane accessors on windows and window controllers

extension NSWindow {

    var paneContainer: PaneContainerViewController? {
        return contentViewController as? PaneContainerViewController
    }

    // 当前活动窗格的ViewController（未分屏时即为唯一的ViewController）
    // The active pane's ViewController (the only one when not split)
    var flowViewController: ViewController? {
        if let container = paneContainer {
            return container.activePane
        }
        return contentViewController as? ViewController
    }

    // 该窗口中的全部窗格
    // Every pane in this window
    var flowViewControllers: [ViewController] {
        if let container = paneContainer {
            return container.panes
        }
        if let viewController = contentViewController as? ViewController {
            return [viewController]
        }
        return []
    }
}

extension NSWindowController {

    var paneContainer: PaneContainerViewController? {
        return contentViewController as? PaneContainerViewController
    }

    var mainViewController: ViewController? {
        if let container = paneContainer {
            return container.activePane
        }
        return contentViewController as? ViewController
    }

    var paneViewControllers: [ViewController] {
        if let container = paneContainer {
            return container.panes
        }
        if let viewController = contentViewController as? ViewController {
            return [viewController]
        }
        return []
    }
}

// 所有窗口中的所有窗格，用于全局设置变更时统一刷新
// Every pane across every window, used when a global setting changes
func getAllViewControllers() -> [ViewController] {
    var result = [ViewController]()
    for window in NSApplication.shared.windows {
        result += window.flowViewControllers
    }
    return result
}

// MARK: - ViewController的窗格相关能力
// MARK: - Pane related helpers on ViewController

extension ViewController {

    var paneContainer: PaneContainerViewController? {
        return parent as? PaneContainerViewController
    }

    // 所在窗口是否处于分屏状态
    // Whether the containing window is currently split
    var isInSplitLayout: Bool {
        return paneContainer?.isSplit ?? false
    }

    // 是否是当前活动窗格（未分屏时恒为true）
    // Whether this is the active pane (always true when not split)
    var isActivePane: Bool {
        guard let container = paneContainer else { return true }
        return container.activePane === self
    }

    var paneIndex: Int? {
        return paneContainer?.panes.firstIndex(where: { $0 === self })
    }

    func activatePane() {
        paneContainer?.setActivePane(self)
    }

    // 鼠标事件是否发生在本窗格内
    // Whether a mouse event happened inside this pane
    func isEventInThisPane(_ event: NSEvent) -> Bool {
        guard event.window === view.window else { return false }
        guard isInSplitLayout else { return true }
        let point = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(point)
    }

    // 本窗格是否应处理该鼠标事件；落在本窗格内的点击同时会激活本窗格
    // Whether this pane should handle a mouse event; a click inside it also activates it
    func shouldHandleMouseEvent(_ event: NSEvent, activate: Bool = false) -> Bool {
        guard isEventInThisPane(event) else { return false }
        if activate && !isActivePane {
            // 不抢占第一响应者，让这次点击自己去决定焦点落在缩略图还是目录树上
            // Leave the first responder alone so the click itself decides whether focus lands on the thumbnails or the sidebar
            paneContainer?.setActivePane(self, moveFocus: false)
        }
        return true
    }

    // 某个窗口坐标是否落在本窗格的核心区域（缩略图/大图区域）内
    // Whether a window-space point falls inside this pane's core area (thumbnails / large image)
    func isPointInCoreArea(_ locationInWindow: NSPoint) -> Bool {
        let point = coreAreaView.convert(locationInWindow, from: nil)
        return coreAreaView.bounds.contains(point)
    }

    // MARK: - 分屏命令
    // MARK: - Split commands

    // 在当前窗格旁新增一个窗格
    // Add a pane next to the current one
    func splitPane(direction: PaneSplitDirection, folder: String? = nil) {
        guard let container = paneContainer else { return }
        if container.panes.count >= PaneContainerViewController.maxPanes {
            coreAreaView.showInfo(NSLocalizedString("Maximum Number of Panes Reached", comment: "已达到窗格数量上限"), timeOut: 1.5, cannotBeCleard: true)
            return
        }
        container.setActivePane(self, moveFocus: false)
        container.addPane(direction: direction, folder: folder)
    }

    // 关闭当前窗格；如果只剩一个窗格，则关闭整个窗口（标签页）
    // Close the current pane; with only one pane left, close the whole window (tab)
    func closeCurrentPaneOrWindow() {
        guard let container = paneContainer, container.isSplit else {
            view.window?.performClose(nil)
            return
        }
        container.closePane(self)
    }

    // 把当前窗格移出为独立的标签页/窗口
    // Move the current pane out into its own tab / window
    func movePaneToNewTab() {
        guard let container = paneContainer, container.isSplit else { return }
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        guard container.detachPane(self) != nil else { return }
        _ = appDelegate.createWindowAdopting(pane: self)
    }

    // 把同组的其它标签页并入本窗口，作为并排的窗格
    // Merge the other tabs of this group into this window as side by side panes
    func mergeTabsIntoPanes(direction: PaneSplitDirection = .right) {
        guard let window = view.window, let container = paneContainer else { return }

        var sourceWindows: [NSWindow] = []
        if let group = window.tabGroup, group.windows.count > 1 {
            sourceWindows = group.windows.filter { $0 !== window }
        } else {
            sourceWindows = NSApplication.shared.windows.filter { $0 !== window && $0.paneContainer != nil && $0.isVisible }
        }
        guard !sourceWindows.isEmpty else {
            coreAreaView.showInfo(NSLocalizedString("No Other Tabs to Merge", comment: "没有可合并的标签页"), timeOut: 1.5, cannotBeCleard: true)
            return
        }

        container.setSplitDirection(direction)

        for sourceWindow in sourceWindows {
            guard let sourceContainer = sourceWindow.paneContainer else { continue }
            for pane in sourceContainer.panes {
                guard container.panes.count < PaneContainerViewController.maxPanes else { break }
                if sourceContainer.detachPane(pane) != nil {
                    container.adoptPane(pane, makeActive: false)
                }
            }
            sourceWindow.close()
        }

        container.equalizePanes()
        container.setActivePane(self)
    }

    // 均分所有窗格
    // Give every pane the same size
    func equalizePanes() {
        paneContainer?.equalizePanes()
    }
}
