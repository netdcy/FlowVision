//
//  ImageCollectionViewManager.swift
//  FlowVision
//
//  Created by netdcy on 2024/3/24.
//

import Foundation
import Cocoa

class CustomCollectionViewManager: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    
    var fileDB: DatabaseModel
    var lastSelectedIndexPath: IndexPath?
    
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

        fileDB.lock()
        if let file=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1{
            item.configureWithImage(file)
        }
        fileDB.unlock()
        
        return item
    }
    
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
//        (item as! ImageCollectionViewItem).imageViewObj?.image?.recache()
//        (item as! ImageCollectionViewItem).imageViewObj?.image=nil
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths{
            //注意：下面这句当item不在视野内时为nil
            //let item = collectionView.item(at: indexPath) as? ImageCollectionViewItem
//            fileDB.lock()
//            if let file=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1{
//                log("Select:",String(indexPath.item),file.path)
//                getViewController(collectionView)!.publicVar.selectedUrls2.append(URL(string: file.path)!)
//            }
//            fileDB.unlock()
        }
        //log("Selected numbers:"+String(indexPaths.count))
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths {
            //注意：下面这句当item不在视野内时为nil
            //let item = collectionView.item(at: indexPath) as? ImageCollectionViewItem
//            fileDB.lock()
//            if let file=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1{
//                log("Deselect:",String(indexPath.item),file.path)
//                if let index=getViewController(collectionView)!.publicVar.selectedUrls2.firstIndex(of: URL(string: file.path)!){
//                    getViewController(collectionView)!.publicVar.selectedUrls2.remove(at: index)
//                }
//            }
//            fileDB.unlock()
        }
        //log("Deselected numbers:"+String(indexPaths.count))
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        fileDB.lock()
        defer{fileDB.unlock()}
        if let thumbSize=fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1.thumbSize{
            return thumbSize
        }
        return DEFAULT_SIZE
    }
    
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        fileDB.lock()
        defer{fileDB.unlock()}
        let pasteboardItem = NSPasteboardItem()
        if let path = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.elementSafe(atOffset: indexPath.item)?.1.path,
           let url = URL(string: path){
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
        }
        return pasteboardItem
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

