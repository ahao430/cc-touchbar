import AppKit

/// NSTouchBar 子类：声明 systemModal=true 让 DFRSupport 把它当系统模态 Touch Bar 处理
/// 这是 MTMR / Pock 都用的标准技巧
@MainActor
final class SystemTouchBar: NSTouchBar {

    // DFRSupport 内部会通过 KVC 查询 "systemModal"，
    // 我们 swizzle 返回 1（NSNumber/Int 都行）让它识别为系统级
    override func value(forUndefinedKey key: String) -> Any? {
        if key == "systemModal" {
            return 1
        }
        return super.value(forUndefinedKey: key)
    }

    // 同上，某些路径会走 `value(forKey:)` 而非 forUndefinedKey
    override func value(forKey key: String) -> Any? {
        if key == "systemModal" {
            return 1
        }
        return super.value(forKey: key)
    }
}
