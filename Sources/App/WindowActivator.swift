import AppKit
import Darwin
import Foundation

@MainActor
enum WindowActivator {

    /// 把 hostApp 对应的 GUI app 拉到前台
    /// 优先级：TERM_PROGRAM bundle ID → NSRunningApplication → PID fallback
    static func activate(session: Session) {
        // 1. 直接按 bundleID 激活
        if let bid = bundleID(for: session.hostApp) {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            if let app = apps.first {
                app.activate(options: [.activateAllWindows])
                return
            }
        }

        // 2. 走 PID fallback：从 session.pid 开始向上找 GUI app
        if let pid = session.pid {
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.activate(options: [.activateAllWindows])
                return
            }
            // 向上找父进程，直到找到一个 GUI app
            if let gui = findGUIApp(from: pid) {
                gui.activate(options: [.activateAllWindows])
                return
            }
        }

        // 3. iTerm / Terminal 用 AppleScript 精确切到具体 session（如果已知 TERM_SESSION_ID）
        if let tsid = session.termSessionId {
            tryActivateTerminalSession(hostApp: session.hostApp, termSessionId: tsid)
        }
    }

    /// 已知 hostApp → bundleID 映射
    static func bundleID(for hostApp: String) -> String? {
        switch hostApp {
        case "iTerm.app", "iTerm":       return "com.googlecode.iterm2"
        case "Apple_Terminal":            return "com.apple.Terminal"
        case "vscode":                    return "com.microsoft.VSCode"
        case "Cursor":                    return "com.todesktop.230313mzl4w4u92"
        case "Windsurf":                  return "com.codeium.windsurf"
        case "Ghostty":                   return "com.mitchellh.ghostty"
        case "WezTerm":                   return "com.github.wez.wezterm"
        case "Hyper":                     return "co.zeit.hyper"
        case "Alacritty":                 return "org.alacritty"
        case "kitty":                     return "net.kovidgoyal.kitty"
        default:                          return nil
        }
    }

    /// 通过 ps 拿父进程链，找到第一个有 GUI bundle 的 app
    static func findGUIApp(from pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<16 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentPID(of: current) else { return nil }
            current = parent
            if current <= 1 { return nil }
        }
        return nil
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard result > 0 else { return nil }
        return pid_t(info.pbi_ppid)
    }

    static func tryActivateTerminalSession(hostApp: String, termSessionId: String) {
        if hostApp == "iTerm.app" || hostApp == "iTerm" {
            let script = """
            tell application "iTerm"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (id of s as string) is "\(termSessionId)" then
                                select t
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            runAppleScript(script)
        }
        // Apple_Terminal 没有 stable session id API，跳过精细激活
    }

    @discardableResult
    static func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }
}
