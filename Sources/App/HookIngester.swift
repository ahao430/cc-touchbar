import Foundation

@MainActor
final class HookIngester {

    private weak var store: SessionStore?
    private var poller = Poller()
    private var lastSize: off_t = 0
    private var fileHandle: FileHandle?

    func attach(to store: SessionStore) {
        self.store = store
        startObserving()
    }

    private func startObserving() {
        let url = PreferenceStore.shared.eventsURL
        ensureFileExists(at: url)
        lastSize = currentSize(at: url) ?? 0
        poller.watch(url) { [weak self] in
            Task { @MainActor [weak self] in
                self?.readNewLines()
            }
        }
    }

    private func ensureFileExists(at url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    private func currentSize(at url: URL) -> off_t? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value
    }

    private func readNewLines() {
        guard let store else { return }
        let url = PreferenceStore.shared.eventsURL
        guard let size = currentSize(at: url) else { return }

        // 文件被截断或轮换：重置起点
        if size < lastSize {
            lastSize = 0
        }
        guard size > lastSize else { return }

        guard let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        try? fh.seek(toOffset: UInt64(lastSize))
        let data = (try? fh.readToEnd()) ?? Data()
        lastSize = size

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(HookEvent.self, from: lineData) else {
                continue
            }
            store.apply(event: event)
        }
    }
}
