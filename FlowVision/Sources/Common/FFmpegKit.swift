//
//  FFmpegKit.swift
//  FlowVision
//
//  Created by netdcy on 2024/7/5.
//

import Foundation

class FFmpegKitWrapper {
    static let shared = FFmpegKitWrapper()

    private var isFFmpegKitLoaded = false
    private var handle: UnsafeMutableRawPointer?
    //private let syncQueue = DispatchQueue(label: "com.ffmpegkit.wrapper.syncQueue")
    private let lock = NSLock()
    var countBeforeLoaded = 0
    
    private let LOAD_WHEN_USE=true // 是否使用时立即加载

    private init() {}
    
    func getIfLoaded() -> Bool {
        
        if globalVar.doNotUseFFmpeg {
            return false
        }
        
        if LOAD_WHEN_USE{
            loadFFmpegKitIfNeeded()
        }

        if !isFFmpegKitLoaded{
            countBeforeLoaded += 1
        }
        return isFFmpegKitLoaded
    }

    func loadFFmpegKitIfNeeded() {
        lock.lock()
        defer {lock.unlock()}
        if !isFFmpegKitLoaded {
//            loadFFmpegKit("libavcodec.framework/Versions/A/libavcodec")
//            loadFFmpegKit("libavdevice.framework/Versions/A/libavdevice")
//            loadFFmpegKit("libavfilter.framework/Versions/A/libavfilter")
//            loadFFmpegKit("libavformat.framework/Versions/A/libavformat")
//            loadFFmpegKit("libavutil.framework/Versions/A/libavutil")
//            loadFFmpegKit("libswresample.framework/Versions/A/libswresample")
//            loadFFmpegKit("libswscale.framework/Versions/A/libswscale")
            loadFFmpegKit("ffmpegkit.framework/Versions/A/ffmpegkit")
            isFFmpegKitLoaded = true
        }
    }
    
    private func loadFFmpegKit(_ path: String) {
        let ffmpegKitPath = path
        handle = dlopen(ffmpegKitPath, RTLD_NOW)
        if handle == nil {
            let error = String(cString: dlerror())
            log("Error loading FFmpegKit: \(error)")
        } else {
            log("FFmpegKit loaded successfully")
        }
    }
    
    func executeFFmpegCommand(_ command: [String]) -> Any? {
        loadFFmpegKitIfNeeded()
        lock.lock()

        let className = "FFmpegKit"
        let selectorName = "executeWithArguments:"
        guard let ffmpegKitClass = objc_getClass(className) as? AnyClass else {
            log("Could not find class \(className)")
            return nil
        }
        
        let selector = sel_registerName(selectorName)
        guard ffmpegKitClass.responds(to: selector) else {
            log("Could not find selector \(selectorName)")
            return nil
        }
        
        let methodIMP = ffmpegKitClass.method(for: selector)
        typealias ExecuteFunctionType = @convention(c) (AnyClass, Selector, NSArray) -> Any
        let executeFunction = unsafeBitCast(methodIMP, to: ExecuteFunctionType.self)
        
        let args = NSArray(array: command)
        
        lock.unlock()
        return executeFunction(ffmpegKitClass, selector, args)
    }
    
    func executeFFprobeCommand(_ command: [String]) -> Any? {
        loadFFmpegKitIfNeeded()
        lock.lock()
        
        let className = "FFprobeKit"
        let selectorName = "executeWithArguments:"
        guard let ffprobeKitClass = objc_getClass(className) as? AnyClass else {
            log("Could not find class \(className)")
            return nil
        }
        
        let selector = sel_registerName(selectorName)
        guard ffprobeKitClass.responds(to: selector) else {
            log("Could not find selector \(selectorName)")
            return nil
        }
        
        let methodIMP = ffprobeKitClass.method(for: selector)
        typealias ExecuteFunctionType = @convention(c) (AnyClass, Selector, NSArray) -> Any
        let executeFunction = unsafeBitCast(methodIMP, to: ExecuteFunctionType.self)
        
        let args = NSArray(array: command)
        
        lock.unlock()
        return executeFunction(ffprobeKitClass, selector, args)
    }
    
    func getReturnCode(from session: Any) -> Any? {
        loadFFmpegKitIfNeeded()
        lock.lock()
        
        let selectorName = "getReturnCode"
        let selector = sel_registerName(selectorName)
        guard let sessionClass = object_getClass(session) else {
            log("Could not get class of session object")
            return nil
        }
        
        guard sessionClass.instancesRespond(to: selector) else {
            log("Session class does not respond to selector \(selectorName)")
            return nil
        }
        
        let methodIMP = sessionClass.instanceMethod(for: selector)
        typealias GetReturnCodeFunctionType = @convention(c) (AnyObject, Selector) -> Any?
        let getReturnCodeFunction = unsafeBitCast(methodIMP, to: GetReturnCodeFunctionType.self)
        
        lock.unlock()
        return getReturnCodeFunction(session as AnyObject, selector)
    }
    
    func getOutput(from session: Any) -> String? {
        loadFFmpegKitIfNeeded()
        lock.lock()
        
        let selectorName = "getOutput"
        let selector = sel_registerName(selectorName)
        guard let sessionClass = object_getClass(session) else {
            log("Could not get class of session object")
            return nil
        }
        
        guard sessionClass.instancesRespond(to: selector) else {
            log("Session class does not respond to selector \(selectorName)")
            return nil
        }
        
        let methodIMP = sessionClass.instanceMethod(for: selector)
        typealias GetOutputFunctionType = @convention(c) (AnyObject, Selector) -> String?
        let getOutputFunction = unsafeBitCast(methodIMP, to: GetOutputFunctionType.self)
        
        lock.unlock()
        return getOutputFunction(session as AnyObject, selector)
    }
    
    func isSuccess(_ returnCode: Any?) -> Bool {
        loadFFmpegKitIfNeeded()
        lock.lock()
        
        let className = "ReturnCode"
        let selectorName = "isSuccess:"
        guard let returnCodeClass = objc_getClass(className) as? AnyClass else {
            log("Could not find class \(className)")
            return false
        }
        
        let selector = sel_registerName(selectorName)
        guard returnCodeClass.responds(to: selector) else {
            log("Could not find selector \(selectorName)")
            return false
        }
        
        let methodIMP = returnCodeClass.method(for: selector)
        typealias IsSuccessFunctionType = @convention(c) (AnyClass, Selector, Any) -> Bool
        let isSuccessFunction = unsafeBitCast(methodIMP, to: IsSuccessFunctionType.self)
        
        lock.unlock()
        return isSuccessFunction(returnCodeClass, selector, returnCode as Any)
    }
}
