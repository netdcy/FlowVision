//
//  CoreAreaView.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation
import Cocoa

class CoreAreaView: NSView {
    
    var infoView: InfoView!
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        infoView = InfoView(frame: .zero)
        infoView.setupView(fontSize: 20, fontWeight: .light, cornerRadius: 6.0, edge: (18,8))
        infoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoView)
        NSLayoutConstraint.activate([
            infoView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            infoView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    
    func showInfo(_ info: String, timeOut: Double = 1.0) {
        infoView.showInfo(text: info, timeOut: timeOut)
    }
    
    func hideInfo() {
        infoView.hide()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            handleDraggedFiles(urls)
            return true
        }
        return false
    }
    
    func handleDraggedFiles(_ urls: [URL]) {
        var folderPath="file:///"
        var path="file:///"
        
        guard let viewController=getViewController(self) else {return}
        
        if urls.count == 1 {
            if urls[0].hasDirectoryPath {
                folderPath=""+urls[0].absoluteString
                if viewController.publicVar.isInLargeView {
                    //由于图像关闭有动画，导致大图时瞬间关闭再打开大图会有bug，因此暂时只对目录关闭大图
                    viewController.closeLargeImage(0)
                }
            }else{
                if !HandledImageExtensions.contains(urls[0].pathExtension) {return} //限制文件类型
                folderPath=""+urls[0].deletingLastPathComponent().absoluteString
                path=""+urls[0].absoluteString
                viewController.publicVar.openFromFinderPath=path
                viewController.OpenLargeImageFromFinder(path: path)
                
                NSDocumentController.shared.noteNewRecentDocumentURL(urls[0])
            }
        } else if urls.count >= 2 {
            folderPath=""+urls[0].deletingLastPathComponent().absoluteString
        }
        
        viewController.switchDirByDirection(direction: .zero, dest: folderPath, doCollapse: true, expandLast: true, skip: false, stackDeep: 0)
        
        for url in urls {
            if url.hasDirectoryPath {
                // 处理文件夹
                log("Dragged folder: \(url.path)")
            } else {
                // 处理文件
                log("Dragged file: \(url.path)")
            }
        }
    }
}
