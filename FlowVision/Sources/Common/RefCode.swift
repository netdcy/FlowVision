//
//  RefCode.swift
//  FlowVision
//

import Foundation

var stream: FSEventStreamRef?

func startListeningForFileSystemEvents(in directoryPath: String) {
    let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
        let paths = eventPaths
        let pathArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray as! [String]
        for path in pathArray {
            log("File system change detected at path: \(path)")
        }
    }

    var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
    let pathsToWatch = [directoryPath] as CFArray
    stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, pathsToWatch, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
    
    // 使用DispatchQueue替代RunLoop
    // Use DispatchQueue instead of RunLoop
    if let stream = stream {
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global())
        FSEventStreamStart(stream)
    }
}

func stopListeningForFileSystemEvents() {
    if let stream = stream {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

