import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ShellError: Error, CustomStringConvertible {
    case timeout
    case launchFailed(String)
    case nonZeroExit(ShellResult)

    var description: String {
        switch self {
        case .timeout: return "command timed out"
        case .launchFailed(let s): return "launch failed: \(s)"
        case .nonZeroExit(let r): return "exit \(r.exitCode): \(r.stderr)"
        }
    }
}

enum ShellRunner {

    /// 在登录 shell 下执行命令（兼容 nvm / fish / 自定义 PATH）
    static func run(command: String, timeout: TimeInterval = 5) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-li", "-c", command]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw ShellError.timeout
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        let result = ShellResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )

        if result.exitCode != 0 {
            throw ShellError.nonZeroExit(result)
        }
        return result
    }

    /// 直接 exec 一个 binary（不经过 zsh），返回 stdout 字符串
    static func runCapture(command: String, arguments: [String], timeout: TimeInterval = 5) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw ShellError.timeout
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
