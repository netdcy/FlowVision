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

let xxxxxxx = 14.0

class CustomFlowLayout: NSCollectionViewLayout {
    private var cache: [NSCollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var contentWidth: CGFloat {
        guard let collectionView = collectionView else { return 0 }
        return getViewController(collectionView)?.mainScrollView.bounds.width ?? collectionView.bounds.width
    }

    //var cellPadding: CGFloat = 5
    var itemSpacing: CGFloat = 0
    var lineSpacing: CGFloat = 0

    override func prepare() {
        guard let collectionView = collectionView else { return }
        guard let delegate = collectionView.delegate as? NSCollectionViewDelegateFlowLayout else { return }

        cache.removeAll()
        contentHeight = 0

        let cellPadding = getViewController(collectionView)!.publicVar.profile.ThumbnailCellPadding
        let borderThickness = getViewController(collectionView)!.publicVar.profile.ThumbnailBorderThickness
        let lineSpaceAdjust = getViewController(collectionView)!.publicVar.profile.ThumbnailLineSpaceAdjust
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
                yOffset += rowHeight + lineSpacing + lineSpaceAdjust
                rowHeight = 0
            }

            let frame = CGRect(x: xOffset, y: yOffset, width: width, height: height)
            let insetFrame = frame.insetBy(dx: cellPadding, dy: cellPadding)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = insetFrame
            cache.append(attributes)

            contentHeight = max(contentHeight, frame.maxY + cellPadding)
            rowHeight = max(rowHeight, height)
            xOffset += width + itemSpacing
        }
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView else { return NSSize(width: 100, height: 100)}
        let cellPadding = getViewController(collectionView)!.publicVar.profile.ThumbnailCellPadding
        return NSSize(width: contentWidth, height: contentHeight)
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

class CustomGridLayout: NSCollectionViewLayout {
    private var cache: [NSCollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var contentWidth: CGFloat {
        guard let collectionView = collectionView else { return 0 }
        return getViewController(collectionView)?.mainScrollView.bounds.width ?? collectionView.bounds.width
    }

    //var cellPadding: CGFloat = 5
    var itemSpacing: CGFloat = 0
    var lineSpacing: CGFloat = 0

    override func prepare() {
        guard let collectionView = collectionView else { return }
        guard let delegate = collectionView.delegate as? NSCollectionViewDelegateFlowLayout else { return }

        cache.removeAll()
        contentHeight = 0

        let filenamePadding = getViewController(collectionView)!.publicVar.profile.ThumbnailFilenamePadding
        let cellPadding = getViewController(collectionView)!.publicVar.profile.ThumbnailCellPadding
        let borderThickness = getViewController(collectionView)!.publicVar.profile.ThumbnailBorderThickness
        let numberOfColumns = Double(getViewController(collectionView)!.publicVar.waterfallLayout.numberOfColumns)
        let scrollbarWidth = getViewController(collectionView)!.publicVar.profile.ThumbnailScrollbarWidth
        var totalWidth = contentWidth - scrollbarWidth - 2 * cellPadding
        
        var xOffset: CGFloat = cellPadding
        var yOffset: CGFloat = cellPadding
        var rowHeight: CGFloat = 0

        for item in 0 ..< collectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: item, section: 0)
            let itemSize = delegate.collectionView!(collectionView, layout: self, sizeForItemAt: indexPath)
            
            // 使用固定尺寸计算位置
            let positionWidth: CGFloat = floor(totalWidth/CGFloat(numberOfColumns+1))
            let positionHeight: CGFloat = positionWidth + filenamePadding

            if xOffset + positionWidth > contentWidth {
                xOffset = cellPadding
                yOffset += rowHeight + lineSpacing
                rowHeight = 0
            }

            // 计算网格单元格的宽度和实际内容的宽度差
            let itemWidth = itemSize.width
            let itemHeight = itemSize.height
            let horizontalOffset = (positionWidth - itemWidth) / 2
            let verticalOffset = (positionHeight - itemHeight) / 2

            // 创建居中的frame
            let frame = CGRect(x: xOffset + horizontalOffset, y: yOffset + verticalOffset, width: itemWidth, height: itemHeight - filenamePadding)
            let insetFrame = frame.insetBy(dx: 0, dy: 0)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = insetFrame
            cache.append(attributes)

            contentHeight = max(contentHeight, yOffset + positionHeight + cellPadding)
            rowHeight = max(rowHeight, positionHeight)  // 使用固定高度计算行高
            xOffset += positionWidth + itemSpacing      // 使用固定宽度计算下一个位置
        }
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView else { return NSSize(width: 100, height: 100)}
        let cellPadding = getViewController(collectionView)!.publicVar.profile.ThumbnailCellPadding
        return NSSize(width: contentWidth, height: contentHeight)
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
    private var contentWidth: CGFloat {
        guard let collectionView = collectionView else { return 0 }
        return getViewController(collectionView)?.mainScrollView.bounds.width ?? collectionView.bounds.width
    }

    var numberOfColumns = 5
    //var cellPadding: CGFloat = 5

    override func prepare() {
        guard let collectionView = collectionView else { return }
        guard let delegate = collectionView.delegate as? NSCollectionViewDelegateFlowLayout else { return }

        let cellPadding = getViewController(collectionView)!.publicVar.profile.ThumbnailCellPadding
        let borderThickness = getViewController(collectionView)!.publicVar.profile.ThumbnailBorderThickness
        let lineSpaceAdjust = getViewController(collectionView)!.publicVar.profile.ThumbnailLineSpaceAdjust
        let totalWidth = getViewController(collectionView)?.mainScrollView.bounds.width ?? collectionView.bounds.width
        let scrollbarWidth = getViewController(collectionView)!.publicVar.profile.ThumbnailScrollbarWidth
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

            contentHeight = max(contentHeight, frame.maxY + cellPadding)
            yOffset[column] = yOffset[column] + height + lineSpaceAdjust
        }
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView else { return NSSize(width: 100, height: 100)}
        let cellPadding = getViewController(collectionView)!.publicVar.profile.ThumbnailCellPadding
        return NSSize(width: contentWidth, height: contentHeight)
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

