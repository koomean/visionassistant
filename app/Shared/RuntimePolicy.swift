import Foundation
import Metal
import os

/// Budgets use actual process headroom as well as physical RAM, rather than model names.
struct RuntimePolicy: Sendable, Equatable {
    let name: String
    let maxPixels: Int
    let maxTokens: Int
    let maxContextTokens: Int
    let prefillStep: Int
    let cacheBytes: Int
    let memoryBytes: Int

    static let megabyte = 1_024 * 1_024
    static let gigabyte = 1_024 * megabyte

    static func prefersEphemeralModels(physicalBytes: UInt64, availableBytes: Int) -> Bool {
        physicalBytes <= UInt64(6 * gigabyte) || (availableBytes > 0 && availableBytes < gigabyte)
    }

    static var prefersEphemeralModels: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--validate-memory"), args.contains("--memory-keep-weights") { return false }
        return prefersEphemeralModels(physicalBytes: ProcessInfo.processInfo.physicalMemory,
                               availableBytes: processHeadroom)
    }

    static var processHeadroom: Int {
        #if os(iOS) || os(tvOS) || os(visionOS)
        Int(os_proc_available_memory())
        #else
        // macOS has no iOS jetsam headroom API; the smoke tool uses Metal's working set.
        0
        #endif
    }

    static func select(
        physicalBytes: UInt64,
        availableBytes: Int,
        thermal: ProcessInfo.ThermalState,
        lowPower: Bool
    ) -> Self {
        let gb = gigabyte
        let memoryConstrained = availableBytes > 0 && availableBytes < 2 * gb
        let throttled = thermal == .serious || thermal == .critical || lowPower
        if physicalBytes < UInt64(6 * gb) || memoryConstrained || throttled {
            return .init(name: "กระชับ", maxPixels: 256 * 32 * 32, maxTokens: 384,
                         maxContextTokens: 1_536, prefillStep: 64, cacheBytes: 8 * megabyte,
                         memoryBytes: 2_350 * megabyte)
        }
        if physicalBytes >= UInt64(10 * gb) && (availableBytes == 0 || availableBytes >= 4 * gb) {
            return .init(name: "รายละเอียดสูง", maxPixels: 768 * 32 * 32, maxTokens: 1_024,
                         maxContextTokens: 4_096, prefillStep: 256, cacheBytes: 128 * megabyte,
                         memoryBytes: 4_500 * megabyte)
        }
        return .init(name: "สมดุล", maxPixels: 512 * 32 * 32, maxTokens: 768,
                     maxContextTokens: 3_072, prefillStep: 128, cacheBytes: 64 * megabyte,
                     memoryBytes: 3_000 * megabyte)
    }

    static func current(residentBytes: Int = 0) -> Self {
        let available = processHeadroom
        return select(physicalBytes: ProcessInfo.processInfo.physicalMemory,
               availableBytes: available > 0 ? available + residentBytes : 0,
               thermal: ProcessInfo.processInfo.thermalState,
               lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// Headroom is free process budget, not physical RAM. Account for a future
    /// ASR/VLM load only if it is not already resident, plus camera/depth reserve.
    /// Six-GB devices exchange the large models after their kernels are warmed.
    static func canKeepPreparedModels(
        availableBytes: Int,
        physicalBytes: UInt64,
        visionResidentBytes: Int,
        speechPrepared: Bool,
        additionalReservedBytes: Int = 0
    ) -> Bool {
        guard physicalBytes > UInt64(6 * gigabyte),
              availableBytes >= 0, visionResidentBytes >= 0, additionalReservedBytes >= 0 else { return false }
        let visionNeeded = max(0, 2_650 * megabyte - visionResidentBytes)
        let speechNeeded = speechPrepared ? 0 : 1_150 * megabyte
        let reserve = additionalReservedBytes + 384 * megabyte
        // Desktop tools have no jetsam headroom API. Real iPhones always use
        // the measured budget; do not infer their capacity from the model name.
        guard availableBytes > 0 else { return physicalBytes >= UInt64(10 * gigabyte) }
        return availableBytes >= visionNeeded + speechNeeded + reserve
    }

    /// Leave OS and image-processing headroom below both jetsam and the GPU working set.
    func safeMemoryLimit(residentBytes: Int = 0) -> Int {
        let headroom = Self.processHeadroom
        let deviceLimit = MTLCreateSystemDefaultDevice().map { Int($0.recommendedMaxWorkingSetSize) }
            ?? memoryBytes
        return min(memoryBytes, deviceLimit,
                   headroom > 0 ? max(0, headroom + residentBytes - 256 * Self.megabyte) : memoryBytes)
    }
}
