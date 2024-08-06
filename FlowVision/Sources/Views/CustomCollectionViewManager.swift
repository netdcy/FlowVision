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

}

