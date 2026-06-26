import Foundation
import IOKit

enum TouchBarMachineDetector {

    /// Touch Bar 支持的机型白名单（model identifier）
    /// 注意：M1 Pro/Max 之后的机型全部取消了 Touch Bar
    static let supported: Set<String> = [
        // 2016 MacBook Pro (Intel)
        "MacBookPro13,1", "MacBookPro13,2", "MacBookPro13,3",
        // 2017 MacBook Pro (Intel)
        "MacBookPro14,1", "MacBookPro14,2", "MacBookPro14,3",
        // 2018-2019 MacBook Pro (Intel)
        "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
        // 2020 MacBook Pro (M1, 13-inch) - 唯一带 Touch Bar 的 Apple Silicon
        "MacBookPro17,1",
    ]

    static func isTouchBarSupported() -> Bool {
        guard let id = modelIdentifier() else { return false }
        return supported.contains(id)
    }

    static func modelIdentifier() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(service) }

        guard service != 0,
              let modelData = IORegistryEntryCreateCFProperty(
                  service,
                    "model" as CFString,
                  kCFAllocatorDefault,
                  0
              )?.takeRetainedValue() as? Data,
              let id = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        else {
            return nil
        }
        return id
    }
}
