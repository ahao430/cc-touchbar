import Foundation

@MainActor
final class PreferenceStore {

    static let shared = PreferenceStore()

    private let defaults = UserDefaults.standard

    enum Key: String {
        case hooksInstalled = "cc.touchbar.hooks.installed"
        case setupCompleted = "cc.touchbar.setup.completed"
        case dispatcherPath = "cc.touchbar.dispatcher.path"
        case theme = "cc.touchbar.theme"
        case claudeBinOverride = "cc.touchbar.claudeBin.override"
        case ccSwitchDBOverride = "cc.touchbar.ccSwitchDB.override"
        case pollIntervalSeconds = "cc.touchbar.pollInterval"
        case balanceIntervalSeconds = "cc.touchbar.balanceInterval"
    }

    var hooksInstalled: Bool {
        get { defaults.bool(forKey: Key.hooksInstalled.rawValue) }
        set { defaults.set(newValue, forKey: Key.hooksInstalled.rawValue) }
    }

    var setupCompleted: Bool {
        get { defaults.bool(forKey: Key.setupCompleted.rawValue) }
        set { defaults.set(newValue, forKey: Key.setupCompleted.rawValue) }
    }

    var dispatcherPath: String? {
        get { defaults.string(forKey: Key.dispatcherPath.rawValue) }
        set { defaults.set(newValue, forKey: Key.dispatcherPath.rawValue) }
    }

    var claudeBinOverride: String? {
        get {
            let v = defaults.string(forKey: Key.claudeBinOverride.rawValue)
            return (v?.isEmpty == false) ? v : nil
        }
        set { defaults.set(newValue, forKey: Key.claudeBinOverride.rawValue) }
    }

    var ccSwitchDBOverride: String? {
        get {
            let v = defaults.string(forKey: Key.ccSwitchDBOverride.rawValue)
            return (v?.isEmpty == false) ? v : nil
        }
        set { defaults.set(newValue, forKey: Key.ccSwitchDBOverride.rawValue) }
    }

    var themeName: String {
        get { defaults.string(forKey: Key.theme.rawValue) ?? "Classic" }
        set { defaults.set(newValue, forKey: Key.theme.rawValue) }
    }

    /// Transcript + git 分支检测的轮询间隔（秒），默认 5s，范围 [0.5, 60]
    var pollIntervalSeconds: Double {
        get {
            let v = defaults.double(forKey: Key.pollIntervalSeconds.rawValue)
            return v > 0 ? min(max(v, 0.5), 60) : 5
        }
        set { defaults.set(min(max(newValue, 0.5), 60), forKey: Key.pollIntervalSeconds.rawValue) }
    }

    /// cc switch 余额刷新间隔（秒），默认 30s，范围 [5, 3600]
    var balanceIntervalSeconds: Double {
        get {
            let v = defaults.double(forKey: Key.balanceIntervalSeconds.rawValue)
            return v > 0 ? min(max(v, 5), 3600) : 30
        }
        set { defaults.set(min(max(newValue, 5), 3600), forKey: Key.balanceIntervalSeconds.rawValue) }
    }

    var dispatcherURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/cc-touchbar-dispatcher.sh")
    }

    var eventsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/cc-touchbar-events.jsonl")
    }
}
