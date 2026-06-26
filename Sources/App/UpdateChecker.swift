import Foundation
import AppKit

enum UpdateCheckResult {
    case upToDate(current: String)
    case newVersionAvailable(current: String, latest: String, url: URL)
    case error(String)
}

enum UpdateChecker {
    static let repositoryURL = URL(string: "https://github.com/ahao430/cc-touchbar")!
    static let latestReleaseURL = URL(string: "https://github.com/ahao430/cc-touchbar/releases/latest")!

    private static let apiURL = URL(string: "https://api.github.com/repos/ahao430/cc-touchbar/releases/latest")!

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static func check(completion: @escaping @MainActor (UpdateCheckResult) -> Void) {
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("cc-touchbar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, _, error in
            let result: UpdateCheckResult
            if let error = error {
                result = .error(error.localizedDescription)
            } else if let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String {
                let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                let htmlURLString = (json["html_url"] as? String) ?? latestReleaseURL.absoluteString
                let url = URL(string: htmlURLString) ?? latestReleaseURL
                if isRemoteNewer(remote: latest, local: currentVersion) {
                    result = .newVersionAvailable(current: currentVersion, latest: latest, url: url)
                } else {
                    result = .upToDate(current: currentVersion)
                }
            } else {
                result = .error("无法解析版本信息")
            }
            Task { @MainActor in completion(result) }
        }.resume()
    }

    private static func isRemoteNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let n = Swift.max(r.count, l.count)
        for i in 0..<n {
            let ri = i < r.count ? r[i] : 0
            let li = i < l.count ? l[i] : 0
            if ri != li { return ri > li }
        }
        return false
    }
}
