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

    var dispatcherURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/cc-touchbar-dispatcher.sh")
    }

    var eventsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/cc-touchbar-events.jsonl")
    }
}
