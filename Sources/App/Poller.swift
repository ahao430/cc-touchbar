import Foundation

@MainActor
final class Poller {

    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var fds: [URL: Int32] = [:]
    private var timers: [URL: Timer] = [:]
    private var lastSizes: [URL: Int64] = [:]
    private let queue = DispatchQueue(label: "cc-touchbar.poller")

    deinit {
        for (_, fd) in fds { close(fd) }
    }

    /// 监听文件变化：DispatchSource + 定时器双保险
    func watch(_ url: URL, onChange: @escaping @Sendable () -> Void) {
        startWatching(url: url, onChange: onChange)
        startPolling(url: url, onChange: onChange)
    }

    private func startWatching(url: URL, onChange: @escaping @Sendable () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.startWatching(url: url, onChange: onChange)
            }
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: queue)
        fds[url] = fd
        sources[url] = src

        src.setEventHandler { [weak self] in
            onChange()
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            if attrs == nil {
                self?.teardown(url: url)
                self?.startWatching(url: url, onChange: onChange)
            }
        }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
    }

    /// 定时轮询兜底：0.4s 间隔检测文件大小变化
    private func startPolling(url: URL, onChange: @escaping @Sendable () -> Void) {
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
                if size < 0 {
                    // 文件被删，尝试重建
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    self.lastSizes[url] = 0
                    return
                }
                let last = self.lastSizes[url] ?? 0
                if size != last {
                    self.lastSizes[url] = size
                    onChange()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[url] = timer
    }

    private func teardown(url: URL) {
        sources[url]?.cancel()
        sources[url] = nil
        fds[url] = nil
        timers[url]?.invalidate()
        timers[url] = nil
    }
}
