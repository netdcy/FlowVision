//
//  ArrowKeyLocate.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func centerPoint(of item: NSCollectionViewItem) -> CGPoint {
        let frame = item.view.frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    
    func centerPoint(of layoutAttributes: NSCollectionViewLayoutAttributes) -> CGPoint {
        let frame = layoutAttributes.frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    
    func nearbyIndexPaths(around indexPaths: Set<IndexPath>, range: (Int,Int)) -> Set<IndexPath> {
        guard let dataSource = collectionView.dataSource else { return [] }
        if indexPaths.isEmpty {
            return []
        }
        let sortedIndexPaths = indexPaths.sorted()
        var expandedIndexPaths = Set<IndexPath>()

        let leftRange = max(0, sortedIndexPaths.first!.item + range.0)
        let rightRange = min(sortedIndexPaths.last!.item + range.1, dataSource.collectionView(collectionView, numberOfItemsInSection: sortedIndexPaths.first!.section) - 1)
        if leftRange > rightRange {
            return []
        }
        for i in leftRange...rightRange {
            expandedIndexPaths.insert(IndexPath(item: i, section: sortedIndexPaths.first!.section))
        }

        return expandedIndexPaths
    }
    
    func findClosestItem(currentIndexPath: IndexPath, direction: NSEvent.SpecialKey) -> IndexPath? {
        publicVar.isInFindingClosestState = true
        defer {
            publicVar.isInFindingClosestState = false
        }
        
        guard let dataSource = collectionView.dataSource else { return nil }
        var currentItem = collectionView.item(at: currentIndexPath)
        if currentItem == nil {
            collectionView.scrollToItems(at: [currentIndexPath], scrollPosition: .nearestHorizontalEdge)
            currentItem = collectionView.item(at: currentIndexPath)
        }
        guard let currentItem = currentItem else {return nil}
        
        var noLimit = false
        
        // let indexPaths = nearbyIndexPaths(around: collectionView.indexPathsForVisibleItems(), range: (-20,20))
        var indexPaths: Set<IndexPath> = []
        if publicVar.profile.layoutType == .grid {
            if direction == .leftArrow || direction == .rightArrow {
                noLimit = true
                if direction == .leftArrow {
                    indexPaths.insert(IndexPath(item: currentIndexPath.item - 1, section: currentIndexPath.section))
                } else {
                    indexPaths.insert(IndexPath(item: currentIndexPath.item + 1, section: currentIndexPath.section))
                }
            } else {
                if direction == .upArrow {
                    indexPaths.insert(IndexPath(item: currentIndexPath.item - publicVar.waterfallLayout.numberOfColumns - 1, section: currentIndexPath.section))
                } else {
                    for i in 1...(publicVar.waterfallLayout.numberOfColumns+1) {
                        indexPaths.insert(IndexPath(item: currentIndexPath.item + i, section: currentIndexPath.section))
                    }
                }
            }
        } else if publicVar.profile.layoutType == .waterfall {
            let range = 4 * publicVar.waterfallLayout.numberOfColumns
            indexPaths = nearbyIndexPaths(around: [currentIndexPath], range: (-range,range))
        } else if publicVar.profile.layoutType == .justified {
            if direction == .leftArrow || direction == .rightArrow {
                noLimit = true
                if direction == .leftArrow {
                    indexPaths.insert(IndexPath(item: currentIndexPath.item - 1, section: currentIndexPath.section))
                } else {
                    indexPaths.insert(IndexPath(item: currentIndexPath.item + 1, section: currentIndexPath.section))
                }
            } else {
                fileDB.lock()
                let curFolder = fileDB.curFolder
                if let files = fileDB.db[SortKeyDir(curFolder)]?.files,
                   let curLineNo = files.elementSafe(atOffset: currentIndexPath.item)?.1.lineNo {
                    
                    // 向前查找
                    // Search forward
                    if direction == .upArrow {
                        var prevItem = currentIndexPath.item - 1
                        var preLineNo: Int? = nil
                        
                        // 第一步：把与curLineNo相同的都添加进来
                        // Step 1: Add all items with same curLineNo
                        while prevItem >= 0 {
                            if let file = files.elementSafe(atOffset: prevItem) {
                                let lineNo = file.1.lineNo
                                if lineNo == curLineNo {
                                    indexPaths.insert(IndexPath(item: prevItem, section: currentIndexPath.section))
                                } else {
                                    break
                                }
                            } else {
                                break
                            }
                            prevItem -= 1
                        }
                        
                        // 第二步：找到第一个lineNo和当前curLineNo不一样的preLineNo
                        // Step 2: Find first preLineNo with different lineNo from current curLineNo
                        while prevItem >= 0 {
                            if let file = files.elementSafe(atOffset: prevItem) {
                                let lineNo = file.1.lineNo
                                if lineNo != curLineNo {
                                    preLineNo = lineNo
                                    break
                                }
                            } else {
                                break
                            }
                            prevItem -= 1
                        }
                        
                        // 第三步：一直往前把是preLineNo的都添加进来，直到和它不同了则中断
                        // Step 3: Keep adding items with preLineNo forward until different, then break
                        while prevItem >= 0 {
                            if let file = files.elementSafe(atOffset: prevItem) {
                                let lineNo = file.1.lineNo
                                if lineNo == preLineNo {
                                    indexPaths.insert(IndexPath(item: prevItem, section: currentIndexPath.section))
                                } else {
                                    break
                                }
                            } else {
                                break
                            }
                            prevItem -= 1
                        }
                    }
                    
                    // 向后查找
                    // Search backward
                    if direction == .downArrow {
                        var nextItem = currentIndexPath.item + 1
                        var nextLineNo: Int? = nil
                        
                        // 第一步：把与curLineNo相同的都添加进来
                        // Step 1: Add all items with same curLineNo
                        while nextItem < files.count {
                            if let file = files.elementSafe(atOffset: nextItem) {
                                let lineNo = file.1.lineNo
                                if lineNo == curLineNo {
                                    indexPaths.insert(IndexPath(item: nextItem, section: currentIndexPath.section))
                                } else {
                                    break
                                }
                            } else {
                                break
                            }
                            nextItem += 1
                        }
                        
                        // 第二步：找到第一个lineNo和当前curLineNo不一样的nextLineNo
                        // Step 2: Find first nextLineNo with different lineNo from current curLineNo
                        while nextItem < files.count {
                            if let file = files.elementSafe(atOffset: nextItem) {
                                let lineNo = file.1.lineNo
                                if lineNo != curLineNo {
                                    nextLineNo = lineNo
                                    break
                                }
                            } else {
                                break
                            }
                            nextItem += 1
                        }
                        
                        // 第三步：一直往后把是nextLineNo的都添加进来，直到和它不同了则中断
                        // Step 3: Keep adding items with nextLineNo backward until different, then break
                        while nextItem < files.count {
                            if let file = files.elementSafe(atOffset: nextItem) {
                                let lineNo = file.1.lineNo
                                if lineNo == nextLineNo {
                                    indexPaths.insert(IndexPath(item: nextItem, section: currentIndexPath.section))
                                } else {
                                    break
                                }
                            } else {
                                break
                            }
                            nextItem += 1
                        }
                    }
                }
                fileDB.unlock()
            }
        } else {
            indexPaths = nearbyIndexPaths(around: [currentIndexPath], range: (-20,20))
        }
        
        let currentCenter = centerPoint(of: currentItem)
        var closestIndexPath: IndexPath?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        let maxItemNum = dataSource.collectionView(collectionView, numberOfItemsInSection: currentIndexPath.section)
        
        for indexPath in indexPaths {
            if indexPath.item < 0 {continue}
            if indexPath.item >= maxItemNum {continue}
            
//            if indexPath != currentIndexPath {continue}
//            guard let item = collectionView.item(at: indexPath) else { continue }
//            let itemCenter = centerPoint(of: item)
            
//            if indexPath != currentIndexPath {continue}
//            guard let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
//            let itemCenter = centerPoint(of: layoutAttributes)
            
            if indexPath == currentIndexPath {continue}
            var item = collectionView.item(at: indexPath)
            if item == nil {
                collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                item = collectionView.item(at: indexPath)
                guard item != nil else {continue}
            }
            
            let itemCenter = centerPoint(of: item!)
            
            var valid = noLimit
            var distance = CGFloat.greatestFiniteMagnitude
            
            switch direction {
            case .leftArrow: // Left arrow key
                if itemCenter.x < currentCenter.x && (abs(itemCenter.y - currentCenter.y) <= 1 || publicVar.profile.layoutType == .waterfall) {
                    valid = true
                }
            case .rightArrow: // Right arrow key
                if itemCenter.x > currentCenter.x && (abs(itemCenter.y - currentCenter.y) <= 1 || publicVar.profile.layoutType == .waterfall) {
                    valid = true
                }
            case .downArrow: // Up arrow key (Adjusted to move up)
                if itemCenter.y > currentCenter.y && (abs(itemCenter.x - currentCenter.x) <= 1 || publicVar.profile.layoutType == .justified || publicVar.profile.layoutType == .grid) {
                    valid = true
                }
            case .upArrow: // Down arrow key (Adjusted to move down)
                if itemCenter.y < currentCenter.y && (abs(itemCenter.x - currentCenter.x) <= 1 || publicVar.profile.layoutType == .justified) {
                    valid = true
                }
            default:
                break
            }
            
            if valid {
                distance = hypot(currentCenter.x - itemCenter.x, currentCenter.y - itemCenter.y)
            }
            
            if valid && distance < closestDistance {
                closestDistance = distance
                closestIndexPath = indexPath
            }
        }
        
        return closestIndexPath
    }
    
}
