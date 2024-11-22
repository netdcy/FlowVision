//
//  Layout.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation
import Cocoa

//这个布局有问题，拖动选中触发区域不一致
class LeftAlignedCollectionViewFlowLayout: NSCollectionViewFlowLayout {
    override func prepare() {
        super.prepare()
        
        self.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        self.minimumInteritemSpacing = 10
        self.minimumLineSpacing = 10
    }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        let attributes = super.layoutAttributesForElements(in: rect)
        
        var leftMargin = sectionInset.left
        var maxY: CGFloat = -1.0
        
        for layoutAttribute in attributes {
            if layoutAttribute.frame.origin.y >= maxY {
                leftMargin = sectionInset.left
            }

            layoutAttribute.frame.origin.x = leftMargin
            
            leftMargin += layoutAttribute.frame.width + minimumInteritemSpacing
            maxY = max(layoutAttribute.frame.maxY, maxY)
        }
        
        return attributes
    }
}

class CustomFlowLayout: NSCollectionViewLayout {
    private var cache: [NSCollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var contentWidth: CGFloat {
        guard let collectionView = collectionView else { return 0 }
        return collectionView.bounds.width
    }

    //var cellPadding: CGFloat = 5
    var itemSpacing: CGFloat = 0
    var lineSpacing: CGFloat = 0

    override func prepare() {
        guard let collectionView = collectionView else { return }
        guard let delegate = collectionView.delegate as? NSCollectionViewDelegateFlowLayout else { return }

        cache.removeAll()
        contentHeight = 0

        let cellPadding = getViewController(collectionView)!.publicVar.ThumbnailCellPadding
        var xOffset: CGFloat = cellPadding
        var yOffset: CGFloat = cellPadding
        var rowHeight: CGFloat = 0

        for item in 0 ..< collectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: item, section: 0)
            let itemSize = delegate.collectionView!(collectionView, layout: self, sizeForItemAt: indexPath)
            
            let width = itemSize.width + 2 * cellPadding
            let height = itemSize.height + 2 * cellPadding

            if xOffset + width > contentWidth {
                xOffset = cellPadding
                yOffset += rowHeight + lineSpacing
                rowHeight = 0
            }

            let frame = CGRect(x: xOffset, y: yOffset, width: width, height: height)
            let insetFrame = frame.insetBy(dx: cellPadding, dy: cellPadding)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = insetFrame
            cache.append(attributes)

            contentHeight = max(contentHeight, frame.maxY)
            rowHeight = max(rowHeight, height)
            xOffset += width + itemSpacing
        }
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView else { return NSSize(width: 100, height: 100)}
        let cellPadding = getViewController(collectionView)!.publicVar.ThumbnailCellPadding
        return NSSize(width: contentWidth, height: contentHeight + cellPadding)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        var visibleLayoutAttributes: [NSCollectionViewLayoutAttributes] = []

        for attributes in cache {
            if attributes.frame.intersects(rect) {
                visibleLayoutAttributes.append(attributes)
            }
        }

        return visibleLayoutAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < cache.count else { return nil }
        return cache[indexPath.item]
    }
}

class WaterfallLayout: NSCollectionViewLayout {
    private var cache: [NSCollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    var numberOfColumns = 5
    //var cellPadding: CGFloat = 5

    override func prepare() {
        guard let collectionView = collectionView else { return }
        guard let delegate = collectionView.delegate as? NSCollectionViewDelegateFlowLayout else { return }

        let cellPadding = getViewController(collectionView)!.publicVar.ThumbnailCellPadding
        let totalWidth = getViewController(collectionView)?.mainScrollView.bounds.width ?? collectionView.bounds.width
        let scrollbarWidth = getViewController(collectionView)!.publicVar.ThumbnailScrollbarWidth
        let columnWidth = floor((totalWidth - scrollbarWidth - 2*cellPadding) / CGFloat(numberOfColumns))
        var xOffset: [CGFloat] = []
        for column in 0 ..< numberOfColumns {
            xOffset.append(cellPadding + CGFloat(column) * columnWidth)
        }
        var yOffset: [CGFloat] = .init(repeating: cellPadding, count: numberOfColumns)
        
        cache.removeAll()
        contentHeight = 0
        
        for item in 0 ..< collectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: item, section: 0)
            let itemSize = delegate.collectionView!(collectionView, layout: self, sizeForItemAt: indexPath)
            let width = columnWidth - (cellPadding * 2)
            let height = round(itemSize.height * (width / itemSize.width) + (cellPadding * 2))
            
            // 找到所有列中高度最小的列
            let minYOffset = yOffset.min() ?? 0
            let column = yOffset.firstIndex(of: minYOffset) ?? 0
            
            let frame = CGRect(x: xOffset[column], y: yOffset[column], width: columnWidth, height: height)
            let insetFrame = frame.insetBy(dx: cellPadding, dy: cellPadding)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = insetFrame
            cache.append(attributes)
            
            contentHeight = max(contentHeight, frame.maxY)
            yOffset[column] = yOffset[column] + height
        }
    }

    override var collectionViewContentSize: NSSize {
        return NSSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        var visibleLayoutAttributes: [NSCollectionViewLayoutAttributes] = []
        
        for attributes in cache {
            if attributes.frame.intersects(rect) {
                visibleLayoutAttributes.append(attributes)
            }
        }
        
        return visibleLayoutAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < cache.count else { return nil }
        return cache[indexPath.item]
    }
}

