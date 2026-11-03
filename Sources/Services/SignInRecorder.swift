import Foundation

/// Keeps ~/Library/Application Support/ReSign/sign-ins.log: when Xcode's account
/// changed and what ran around it, to find out why Xcode keeps signing out.
enum SignInRecorder {
    private static let idsKey = "lastXcodeAccountIDs"
    private static let recordedAtKey = "lastSignInRecordAt"
    /// `log show` slows with the span it covers, and a day reaches back past a night asleep.
    private static let longestLookBack: TimeInterval = 24 * 3600

    /// Called on each sign-in poll. The last IDs are kept across launches, so a
    /// reinstall or a restart doesn't hide a change.
    static func noticeAccounts(_ ids: [String]?) {
        let defaults = UserDefaults.standard
        guard let ids else { return }
        let change = SignInRecord.change(from: defaults.stringArray(forKey: idsKey), to: ids)
        defaults.set(ids, forKey: idsKey)
        if let change { record("\(change), now \(ids.isEmpty ? "none" : ids.joined(separator: ", "))") }
    }

    /// Appends an entry. Runs off the main thread: `log show` takes seconds.
    static func record(_ event: String) {
        let defaults = UserDefaults.standard
        let now = Date.now
        let earliest = now.addingTimeInterval(-longestLookBack)
        // From the last entry, not the last poll: a credentials error can come
        // minutes before the account list changes.
        let since = max(defaults.object(forKey: recordedAtKey) as? Date ?? earliest, earliest)
        defaults.set(now, forKey: recordedAtKey)

        Task.detached(priority: .utility) {
            let entry = [stamp(now) + "  " + event, "  since " + stamp(since)]
                + ["running:"] + running().map { "    \($0)" }
                + SignInRecord.summarize(logLines: systemLog(since: since))
            append((entry + [""]).joined(separator: "\n") + "\n")
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Build tools alive right now, with what started them.
    private static func running() -> [String] {
        let lines = output("/bin/ps", ["-axo", "pid,ppid,etime,command"])
            .filter { $0.contains("xcodebuild") || $0.contains("build.sh") || $0.contains("Xcode.app/Contents/MacOS/Xcode") }
            .filter { !$0.contains("log stream") }
            .map { String($0.prefix(200)) }
        return lines.isEmpty ? ["none"] : lines
    }

    private static func systemLog(since: Date) -> [String] {
        output("/usr/bin/log", [
            "show", "--style", "compact", "--start", stamp(since),
            "--predicate", "process == \"xcodebuild\"",
        ])
    }

    private static func output(_ path: String, _ arguments: [String]) -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return ["could not run \(path)"] }
        // Read before waiting: a full pipe would block the process forever.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
    }

    private static func append(_ text: String) {
        let url = URL.applicationSupportDirectory.appending(path: "ReSign/sign-ins.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }
}
