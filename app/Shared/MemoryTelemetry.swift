import Darwin
import Foundation
import Metal
import MLX
import os

/// Read only when an opt-in diagnostic requests it. No model or allocator policy
/// is changed, and Simulator diagnostics never initialize the MLX Metal backend.
struct MemoryTelemetry: Codable, Sendable {
    let physicalFootprintBytes: UInt64?
    let residentBytes: UInt64?
    let processHeadroomBytes: UInt64?
    let physicalMemoryBytes: UInt64
    let mlxActiveBytes: Int?
    let mlxCacheBytes: Int?
    let mlxPeakBytes: Int?
    let mlxMemoryLimitBytes: Int?
    let metalAllocatedBytes: Int?
    let thermalState: Int
    let lowPowerMode: Bool

    static func current(includeGPU: Bool = true) -> Self {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        #if os(iOS) || os(tvOS) || os(visionOS)
        let headroom: UInt64? = UInt64(os_proc_available_memory())
        #else
        let headroom: UInt64? = nil
        #endif
        #if targetEnvironment(simulator)
        let active: Int? = nil
        let cache: Int? = nil
        let peak: Int? = nil
        let limit: Int? = nil
        let metal: Int? = nil
        #else
        let active: Int? = includeGPU ? Memory.activeMemory : nil
        let cache: Int? = includeGPU ? Memory.cacheMemory : nil
        let peak: Int? = includeGPU ? Memory.peakMemory : nil
        let limit: Int? = includeGPU ? Memory.memoryLimit : nil
        let metal: Int? = includeGPU ? MTLCreateSystemDefaultDevice()?.currentAllocatedSize : nil
        #endif
        return .init(
            physicalFootprintBytes: result == KERN_SUCCESS ? info.phys_footprint : nil,
            residentBytes: result == KERN_SUCCESS ? info.resident_size : nil,
            processHeadroomBytes: headroom,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            mlxActiveBytes: active, mlxCacheBytes: cache, mlxPeakBytes: peak,
            mlxMemoryLimitBytes: limit, metalAllocatedBytes: metal,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

/// Numeric warning breadcrumbs survive the teardown that follows a low-memory notification.
enum MemoryWarningRecorder {
    private struct Warning: Codable {
        let timestamp: Date
        let memory: MemoryTelemetry
        let capturing: Bool
        let preparingPhoto: Bool
        let answering: Bool
        let modelReady: Bool
    }
    static func record(capturing: Bool, preparingPhoto: Bool, answering: Bool, modelReady: Bool) {
        let url = URL.documentsDirectory.appending(path: "MemoryWarningCheck.json")
        let decoder = JSONDecoder()
        var history = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([Warning].self, from: $0) } ?? []
        history.append(.init(timestamp: Date(), memory: .current(includeGPU: false), capturing: capturing,
                             preparingPhoto: preparingPhoto, answering: answering, modelReady: modelReady))
        if history.count > 16 { history.removeFirst(history.count - 16) }
        try? JSONEncoder().encode(history).write(to: url, options: .atomic)
    }
}
