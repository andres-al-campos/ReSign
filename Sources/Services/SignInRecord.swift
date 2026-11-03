import Foundation

/// What goes in the sign-in record, apart from reading the system. Kept free of
/// AppKit and timers so tests/drive/signed-out-alert.sh can compile it alone.
enum SignInRecord {
    /// Names a change in Xcode's account list, or nil when there's nothing to
    /// record. An unreadable list isn't a change, and neither is the first look.
    static func change(from old: [String]?, to new: [String]?) -> String? {
        guard let old, let new, old != new else { return nil }
        if new.isEmpty { return "signed out: Xcode's account list emptied" }
        if old.isEmpty { return "signed in" }
        return "account replaced: Xcode gave it a new ID"
    }

    /// Boils `log show --style compact` output down to the account errors and
    /// the real xcodebuild runs. ReSign's license check is one too, on each popup
    /// open, and logs only a few lines, so short runs are left out.
    static func summarize(logLines: [String], limit: Int = 20) -> [String] {
        var runs: [(pid: String, time: String, lines: Int)] = []
        var errors: [String] = []
        for line in logLines {
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5, parts[3].hasPrefix("xcodebuild[") else { continue }
            let time = "\(parts[0]) \(parts[1].prefix(8))"
            let pid = parts[3].dropFirst("xcodebuild[".count).prefix { $0 != ":" }
            if let i = runs.firstIndex(where: { $0.pid == pid }) {
                runs[i].lines += 1
            } else {
                runs.append((String(pid), time, 1))
            }
            if parts[4].contains("DVTDeveloperAccountManager") {
                errors.append("\(time) pid \(pid): \(parts[4].prefix(160))")
            }
        }
        let real = runs.filter { $0.lines > minimumRunLines }
            .map { "\($0.time) pid \($0.pid), \($0.lines) log lines" }
        return ["xcodebuild runs:"] + indented(real.suffix(limit))
            + ["account errors:"] + indented(errors.suffix(limit))
    }

    private static let minimumRunLines = 10

    private static func indented(_ lines: ArraySlice<String>) -> [String] {
        lines.isEmpty ? ["    none"] : lines.map { "    \($0)" }
    }
}
