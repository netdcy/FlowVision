//
//  Tagging.swift
//  FlowVision
//
//

import Foundation
import Cocoa

extension ViewController {
    func handleToggleFinderTag(_ tagName: String) {
        var urls: [URL] = []
        if publicVar.isCollectionViewFirstResponder {
            urls = publicVar.selectedUrls()
        } else if publicVar.isOutlineViewFirstResponder {
            
        }
        handleToggleFinderTag(tagName, urls: urls)
    }

    func handleToggleFinderTag(_ tagName: String, urls: [URL]) {
        guard !urls.isEmpty else { return }
        let added = FinderTagHelper.toggleTag(tagName, on: urls)
        refreshFinderTagsForVisibleItems(urls: urls)

        if let tag = FinderTag.byName(tagName) {
            let action = added ? NSLocalizedString("Add", comment: "添加") : NSLocalizedString("Remove", comment: "移除")
            coreAreaView.showInfo("\(action) \(tag.name)", timeOut: 0.8, cannotBeCleard: false)
        }
    }

    func handleRemoveAllFinderTags() {
        let urls = publicVar.selectedUrls()
        handleRemoveAllFinderTags(urls: urls)
    }

    func handleRemoveAllFinderTags(urls: [URL]) {
        guard !urls.isEmpty else { return }
        FinderTagHelper.removeAllTags(from: urls)
        refreshFinderTagsForVisibleItems(urls: urls)
    }

    func refreshFinderTagsForVisibleItems(urls: [URL]) {
        let changedPaths = Set(urls.map { $0.absoluteString })
        
        var newTagsMap: [String: [String]] = [:]
        for url in urls {
            newTagsMap[url.absoluteString] = FinderTagHelper.readTags(from: url)
        }
        
        if let collectionView = collectionView {
            for item in collectionView.visibleItems() {
                if let item = item as? CustomCollectionViewItem {
                    if changedPaths.contains(item.file.path) {
                        item.file.finderTags = newTagsMap[item.file.path] ?? []
                        item.refreshFinderTagDots()
                    }
                }
            }
        }
        if publicVar.isInLargeView, changedPaths.contains(largeImageView.file.path) {
            largeImageView.file.finderTags = newTagsMap[largeImageView.file.path] ?? []
            largeImageView.refreshFinderTagDots()
        }
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        if let dirModel = fileDB.db[SortKeyDir(curFolder)] {
            for url in urls {
                let filePath = url.absoluteString
                for ele in dirModel.files {
                    if ele.0.path == filePath {
                        ele.1.finderTags = newTagsMap[filePath] ?? []
                        break
                    }
                }
            }
        }
        fileDB.unlock()
    }

    func handleScanEnhancedIndex(url: URL) {
        coreAreaView.onScanCancel = {
            EnhancedIndex.cancelScan()
        }
        EnhancedIndex.scanFolder(url) { message, isComplete in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                coreAreaView.showScanProgress(message)
                if isComplete {
                    coreAreaView.hideScanProgress(delayed: 1.5)
                }
            }
        }
    }

    func handleClearFinderTagFilter() {
        publicVar.isFinderTagFilterReversed = false
        publicVar.isFinderTagFilterModeAnd = false
        publicVar.finderTagFilters.removeAll()
        toggleFinderTagFilter(nil)
    }

    func toggleFinderTagFilter(_ tagIndex: Int) {
        if tagIndex < 0 || tagIndex >= FinderTag.all.count {
            return
        }
        let tagName = FinderTag.all[tagIndex].name
        toggleFinderTagFilter(tagName)
    }

    func toggleFinderTagFilter(_ tagName: String?) {
        guard let tagName = tagName else {
            publicVar.finderTagFilters.removeAll()
            coreAreaView.showInfo(NSLocalizedString("Show All", comment: "显示全部"), timeOut: 0.8, cannotBeCleard: true)
            refreshCollectionView(needLoadThumbPriority: true)
            return
        }
        if publicVar.finderTagFilters.contains(tagName) {
            publicVar.finderTagFilters.remove(tagName)
        } else {
            publicVar.finderTagFilters.insert(tagName)
        }
        if publicVar.finderTagFilters.isEmpty {
            coreAreaView.showInfo(NSLocalizedString("Show All", comment: "显示全部"), timeOut: 0.8, cannotBeCleard: true)
        } else {
            let names = publicVar.finderTagFilters.compactMap { FinderTag.byName($0)?.name }.joined(separator: ", ")
            coreAreaView.showInfo(NSLocalizedString("Filter", comment: "筛选") + ": \(names)", timeOut: 0.8, cannotBeCleard: true)
        }
        refreshCollectionView(needLoadThumbPriority: true)
    }

    func toggleFinderTagFilterReversed() {
        publicVar.isFinderTagFilterReversed.toggle()
        refreshCollectionView(needLoadThumbPriority: true)
    }

    func handleClearTagsAndRatingFilter() {
        publicVar.isFinderTagFilterReversed = false
        publicVar.isFinderTagFilterModeAnd = false
        publicVar.finderTagFilters.removeAll()

        publicVar.isRatingFilterReversed = false
        publicVar.ratingFilters.removeAll()
        
        coreAreaView.showInfo(NSLocalizedString("Show All", comment: "显示全部"), timeOut: 0.8, cannotBeCleard: true)
        refreshCollectionView(needLoadThumbPriority: true)
    }

    func handleClearRatingFilter() {
        publicVar.isRatingFilterReversed = false
        publicVar.ratingFilters.removeAll()
        toggleRatingFilter(nil)
    }

    func toggleRatingFilter(_ rating: Int?) {
        guard let rating = rating else {
            publicVar.ratingFilters.removeAll()
            coreAreaView.showInfo(NSLocalizedString("Show All", comment: "显示全部"), timeOut: 0.8, cannotBeCleard: true)
            refreshCollectionView(needLoadThumbPriority: true)
            return
        }
        if publicVar.ratingFilters.contains(rating) {
            publicVar.ratingFilters.remove(rating)
        } else {
            publicVar.ratingFilters.insert(rating)
        }
        if publicVar.ratingFilters.isEmpty {
            coreAreaView.showInfo(NSLocalizedString("Show All", comment: "显示全部"), timeOut: 0.8, cannotBeCleard: true)
        } else {
            let stars = publicVar.ratingFilters.sorted().map { $0 == 0 ? NSLocalizedString("No Rating", comment: "无评级") : String(repeating: "★", count: $0) }.joined(separator: ", ")
            coreAreaView.showInfo(NSLocalizedString("Filter", comment: "筛选") + ": \(stars)", timeOut: 0.8, cannotBeCleard: true)
        }
        refreshCollectionView(needLoadThumbPriority: true)
    }

    func toggleRatingFilterReversed() {
        publicVar.isRatingFilterReversed.toggle()
        refreshCollectionView(needLoadThumbPriority: true)
    }

    func handleTagLearnMore() {
        if let url = URL(string: FINDER_TAG_LEARN_MORE_URL) {
            NSWorkspace.shared.open(url)
        }
    }

    func handleRatingReadme() {
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("rating-info", comment: "对于评级的说明..."))
    }

    func handleScanEnhancedIndexReadme() {
        showInformationLong(title: NSLocalizedString("Info", comment: "说明"), message: NSLocalizedString("scan-enhanced-index-info", comment: "扫描并更新增强索引说明..."))
    }

    func handleRating(rating: Int) {
        guard publicVar.isCollectionViewFirstResponder else { return }
        let urls: [URL] = publicVar.selectedUrls()
        var successUrls: [URL] = []
        publicVar.isInFileOperation = true
        for url in urls {
            if writeRating(inputURL: url, outputURL: url, rating: rating) {
                successUrls.append(url)
            }
        }
        publicVar.isInFileOperation = false
        if !successUrls.isEmpty {
            refreshRatingForVisibleItems(urls: successUrls, rating: rating)
        }
    }
    
    func refreshRatingForVisibleItems(urls: [URL], rating: Int) {
        let changedPaths = Set(urls.map { $0.absoluteString })
        
        if let collectionView = collectionView {
            for item in collectionView.visibleItems() {
                if let item = item as? CustomCollectionViewItem {
                    if changedPaths.contains(item.file.path) {
                        if let imageInfo = item.file.imageInfo {
                            imageInfo.rating = rating
                            item.refreshRatingStars()
                        }
                    }
                }
            }
        }
        if publicVar.isInLargeView, changedPaths.contains(largeImageView.file.path) {
            if let imageInfo = largeImageView.file.imageInfo {
                imageInfo.rating = rating
                largeImageView.refreshRatingStars()
            }
        }
        
        fileDB.lock()
        let curFolder = fileDB.curFolder
        if let dirModel = fileDB.db[SortKeyDir(curFolder)] {
            for url in urls {
                let filePath = url.absoluteString
                for ele in dirModel.files {
                    if ele.0.path == filePath {
                        if let imageInfo = ele.1.imageInfo {
                            imageInfo.rating = rating
                        }
                        break
                    }
                }
            }
        }
        fileDB.unlock()
    }

    func toggleLargeImageViewShowTagsAndRating() {
        globalVar.largeImageViewShowTagsAndRating.toggle()
        UserDefaults.standard.set(globalVar.largeImageViewShowTagsAndRating, forKey: "largeImageViewShowTagsAndRating")
        if publicVar.isInLargeView {
            largeImageView.refreshFinderTagDots()
            largeImageView.refreshRatingStars()
        }
    }
    
    
}
