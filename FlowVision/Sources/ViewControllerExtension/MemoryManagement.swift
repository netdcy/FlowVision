//
//  MemoryManagement.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

extension ViewController {
    
    func LRUMemRecord(path: String, count: Int){
        fileDB.lock()
        var index: Int?
        if LRUqueue.count > 0 {
            // 之前队首的最后访问时间记录为当前时间
            // Record previous head's last access time as current time
            LRUqueue[0].1=DispatchTime.now()
            // 查找队列中是否有path
            // Search for path in queue
            for (i,(lruPath,_,_)) in LRUqueue.enumerated() {
                if lruPath == path {
                    index=i
                    break
                }
            }
        }
        
        if let index = index {
            LRUqueue.remove(at: index)
        }
        LRUqueue.insert((path,DispatchTime.now(),count), at: 0)
        fileDB.unlock()
    }
    
    func reportPhyMemoryUsage() -> Double {
        let task = mach_task_self_
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / 1024 / 1024
            return usedMemoryMB
        } else {
            return 0
        }
    }
    
    func reportTotalMemoryUsage() -> Double {
        let task = mach_task_self_
        var info = task_vm_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemoryMB = Double(info.phys_footprint) / 1024 / 1024
            return usedMemoryMB
        } else {
            return 0
        }
    }
    
    func getSystemMemorySize() -> Double {
        var size: UInt64 = 0
        var sizeOfSize = MemoryLayout<UInt64>.size
        
        let result = sysctlbyname("hw.memsize", &size, &sizeOfSize, nil, 0)
        
        if result == 0 {
            return Double(size) / 1024 / 1024 / 1024
        } else {
            return 0
        }
    }
}
