//
//  CustomCollectionViewManager.swift
//  FlowVision
//

import Foundation
import Cocoa

class CustomCollectionViewManager: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {

    var fileDB: DatabaseModel
    var lastSelectedIndexPath: IndexPath?
    private var dragURLsByIndexPath: [IndexPath: URL] = [:]
    private let compactDragPreviewThreshold = 8

    init(fileDB: DatabaseModel) {
        self.fileDB = fileDB
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        fileDB.lock()
        defer{fileDB.unlock()}
        if let db=fileDB.db[SortKeyDir(fileDB.curFolder)] {
            return min(db.layoutCalcPos,db.files.count)
        }
        return 0
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "CustomCollectionViewItem"), for: indexPath) as! CustomCollectionViewItem

        var configuredFile: FileModel?
        fileDB.lock()
        if let file=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1{
            configuredFile = file
        }
        fileDB.unlock()
        if let configuredFile {
            item.configureWithImage(configuredFile)
            getViewController(collectionView)?.scheduleNetworkFolderMediaCountIfNeeded(for: configuredFile)
        }

        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
//        (item as! ImageCollectionViewItem).imageViewObj?.image?.recache()
//        (item as! ImageCollectionViewItem).imageViewObj?.image=nil
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths{
            // 注意：下面这句当item不在视野内时为nil
            // Note: The following statement is nil when item is not in view
            // let item = collectionView.item(at: indexPath) as? ImageCollectionViewItem
//            fileDB.lock()
//            if let file=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1{
//                log("Select:",String(indexPath.item),file.path)
//                getViewController(collectionView)!.publicVar.selectedUrls2.append(URL(string: file.path)!)
//            }
//            fileDB.unlock()
        }
        // log("Selected numbers:"+String(indexPaths.count))
        getViewController(collectionView)?.publicVar.updateToolbar()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths {
            // 注意：下面这句当item不在视野内时为nil
            // Note: The following statement is nil when item is not in view
            // let item = collectionView.item(at: indexPath) as? ImageCollectionViewItem
//            fileDB.lock()
//            if let file=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1{
//                log("Deselect:",String(indexPath.item),file.path)
//                if let index=getViewController(collectionView)!.publicVar.selectedUrls2.firstIndex(of: URL(string: file.path)!){
//                    getViewController(collectionView)!.publicVar.selectedUrls2.remove(at: index)
//                }
//            }
//            fileDB.unlock()
        }
        // log("Deselected numbers:"+String(indexPaths.count))
        getViewController(collectionView)?.publicVar.updateToolbar()
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        fileDB.lock()
        defer{fileDB.unlock()}
        if let thumbSize=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1.thumbSize{
            return thumbSize
        }
        return DEFAULT_SIZE
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        dragURLsByIndexPath.removeAll(keepingCapacity: true)
        fileDB.lock()
        defer { fileDB.unlock() }
        guard let files = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files else { return false }

        for indexPath in indexPaths {
            guard let path = files.elementSafe(atOffset: indexPath.item)?.1.path,
                  let url = URL(string: path) else { continue }
            dragURLsByIndexPath[indexPath] = url
        }
        return !dragURLsByIndexPath.isEmpty
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        if let url = dragURLsByIndexPath[indexPath] {
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
            return pasteboardItem
        }

        // Defensive fallback for AppKit versions that request a writer without
        // first calling canDragItemsAt. Normal multi-selection drags use the cache.
        fileDB.lock()
        defer { fileDB.unlock() }
        guard let path = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1.path,
              let url = URL(string: path) else { return nil }
        pasteboardItem.setString(url.absoluteString, forType: .fileURL)
        return pasteboardItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItemsAt indexPaths: Set<IndexPath>
    ) {
        guard indexPaths.count > compactDragPreviewThreshold else {
            session.draggingFormation = indexPaths.count > 1 ? .stack : .none
            return
        }

        session.draggingFormation = .pile
        session.draggingLeaderIndex = 0
        session.animatesToStartingPositionsOnCancelOrFail = false
        let preview = compactDragPreview(itemCount: indexPaths.count)
        var keptVisibleItem = false
        session.enumerateDraggingItems(
            options: [],
            for: collectionView,
            classes: [NSPasteboardItem.self],
            searchOptions: [:]
        ) { draggingItem, _, _ in
            if !keptVisibleItem {
                keptVisibleItem = true
                let oldFrame = draggingItem.draggingFrame
                let size = preview.size
                draggingItem.setDraggingFrame(
                    NSRect(
                        x: oldFrame.midX - size.width / 2,
                        y: oldFrame.midY - size.height / 2,
                        width: size.width,
                        height: size.height
                    ),
                    contents: preview
                )
            } else {
                draggingItem.setDraggingFrame(draggingItem.draggingFrame, contents: nil)
            }
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        dragOperation operation: NSDragOperation
    ) {
        dragURLsByIndexPath.removeAll(keepingCapacity: true)
    }

    private func compactDragPreview(itemCount: Int) -> NSImage {
        let size = NSSize(width: 76, height: 62)
        let image = NSImage(size: size)
        image.lockFocus()

        let backRect = NSRect(x: 8, y: 7, width: 54, height: 44)
        NSColor.controlBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: backRect, xRadius: 8, yRadius: 8).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: backRect, xRadius: 8, yRadius: 8).stroke()

        if let icon = NSImage(named: NSImage.multipleDocumentsName) {
            icon.draw(in: NSRect(x: 19, y: 15, width: 30, height: 30))
        }

        let badgeText = itemCount > 999 ? "999+" : String(itemCount)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (badgeText as NSString).size(withAttributes: attributes)
        let badgeWidth = max(24, textSize.width + 10)
        let badgeRect = NSRect(x: size.width - badgeWidth, y: size.height - 25, width: badgeWidth, height: 21)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 10.5, yRadius: 10.5).fill()
        (badgeText as NSString).draw(
            at: NSPoint(x: badgeRect.midX - textSize.width / 2, y: badgeRect.midY - textSize.height / 2),
            withAttributes: attributes
        )

        image.unlockFocus()
        return image
    }

    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        guard let indexPath = indexPaths.first else { return [] }

        // Check if the Shift key is pressed or no selection
        if NSEvent.modifierFlags.contains(.shift), let lastIndexPath = lastSelectedIndexPath, collectionView.selectionIndexPaths.count >= 1 {
            // Calculate the range of items to select
            let startIndex = min(lastIndexPath.item, indexPath.item)
            let endIndex = max(lastIndexPath.item, indexPath.item)
            let indexSet = IndexSet(startIndex...endIndex)

            // Create new index paths for the range
            let newSelectedIndexPaths = indexSet.map { IndexPath(item: $0, section: indexPath.section) }
            return Set(newSelectedIndexPaths)
        } else {
            // Update the last selected index path for non-shift selection
            lastSelectedIndexPath = indexPath
            return indexPaths
        }
    }

    func collectionView(_ collectionView: NSCollectionView, shouldDeselectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        guard let indexPath = indexPaths.first else { return [] }

        // TODO

        return indexPaths
    }

}
