import Foundation

enum ProjectDiscovery {
    /// How far below the scan root we look for projects. Ansa needs depth 2
    /// (Ansa/ios/Ansa.xcodeproj); 3 buys one monorepo level (repo/packages/ios)
    /// without walking deep vendored trees.
    static let maxDepth = 3

    /// Directories that never contain a project we want, but often contain a
    /// nested .xcodeproj that would otherwise be discovered as a phantom
    /// project: build output, dependency checkouts, and package caches.
    static let prunedDirectoryNames: Set<String> = [
        "build", "DerivedData", "Pods", ".build", "SourcePackages", "node_modules", ".git"
    ]

    /// Walks `scanRoot` looking for iOS projects at any depth up to `maxDepth`.
    ///
    /// `excludedPaths` are directories to skip entirely — normally ReSign's own
    /// source directory, so it doesn't manage itself. Matched by resolved path
    /// rather than by name: a bare name would also exclude an unrelated project
    /// that happened to share it.
    static func discoverProjects(in scanRoot: URL, excludedPaths: Set<URL> = []) throws -> [ManagedProject] {
        let excluded = Set(excludedPaths.map { canonicalPath($0) })
        var found: [ManagedProject] = []
        // (directory, depth below scanRoot)
        var stack: [(URL, Int)] = [(scanRoot, 0)]

        while let (dir, depth) = stack.popLast() {
            guard !excluded.contains(canonicalPath(dir)) else { continue }

            // A directory that is itself a project is not descended into, so a
            // project's own SwiftPM packages (Ansa/ios/AnsaCore) never register
            // as separate projects.
            if depth > 0, let project = projectCandidate(in: dir) {
                found.append(project)
                continue
            }

            guard depth < maxDepth else { continue }

            let contents = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents {
                let name = url.lastPathComponent
                // Pruning happens before any marker test because .xcodeproj is
                // itself a directory — an unpruned walk would descend into it.
                guard !prunedDirectoryNames.contains(name), !name.hasPrefix(".") else { continue }
                guard isDirectory(url) else { continue }
                stack.append((url, depth + 1))
            }
        }

        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The project `dir` holds, or nil if it holds none.
    ///
    /// Two markers, checked in order. A real `.xcodeproj` wins; failing that a
    /// `project.yml` counts, because for xcodegen projects the .xcodeproj is
    /// generated output that `build.sh clean` deletes while the yml is the
    /// committed source of truth. Checking .xcodeproj first is also what keeps a
    /// directory holding both markers from yielding two entries.
    static func projectCandidate(in dir: URL) -> ManagedProject? {
        let ymlURL = dir.appendingPathComponent("project.yml")
        let hasYML = FileManager.default.fileExists(atPath: ymlURL.path)

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let xcodeprojs = contents
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if let xcodeprojURL = preferredProject(among: xcodeprojs, ymlURL: hasYML ? ymlURL : nil) {
            guard isIOSCandidate(dir: dir, xcodeprojURL: xcodeprojURL) else { return nil }
            // The name comes from the .xcodeproj, never from the directory: for
            // Ansa the directory is "ios", which would give a project named
            // "ios" and an xcodebuild -scheme of "ios".
            let name = xcodeprojURL.deletingPathExtension().lastPathComponent
            return ManagedProject(id: UUID(), name: name, projectPath: xcodeprojURL)
        }

        guard hasYML, let name = projectNameFromYML(at: ymlURL) else { return nil }
        // No .xcodeproj on disk — a cleaned xcodegen project. Synthesize the
        // path xcodegen will create. Keeping it inside `dir` is what lets
        // BuildRunner.projectBuildScript find the sibling build.sh unchanged.
        let xcodeprojURL = dir.appendingPathComponent("\(name).xcodeproj")
        guard isIOSCandidate(dir: dir, xcodeprojURL: xcodeprojURL) else { return nil }
        return ManagedProject(id: UUID(), name: name, projectPath: xcodeprojURL)
    }

    /// Which .xcodeproj to use when a directory holds more than one. Prefers the
    /// one xcodegen would generate, so the choice matches project.yml rather
    /// than alphabetical luck.
    private static func preferredProject(among xcodeprojs: [URL], ymlURL: URL?) -> URL? {
        guard xcodeprojs.count > 1, let ymlURL, let ymlName = projectNameFromYML(at: ymlURL) else {
            return xcodeprojs.first
        }
        return xcodeprojs.first { $0.deletingPathExtension().lastPathComponent == ymlName } ?? xcodeprojs.first
    }

    /// Whether the project at `dir` targets iOS.
    ///
    /// The pbxproj is authoritative when it exists. When it doesn't — a cleaned
    /// xcodegen project — the yml answers instead.
    static func isIOSCandidate(dir: URL, xcodeprojURL: URL) -> Bool {
        let pbxprojURL = xcodeprojURL.appendingPathComponent("project.pbxproj")
        if FileManager.default.fileExists(atPath: pbxprojURL.path) {
            return isIOSProject(xcodeprojURL: xcodeprojURL)
        }
        return isIOSProjectYML(at: dir.appendingPathComponent("project.yml"))
    }

    /// Inspects `project.pbxproj` to decide whether the project targets iOS.
    /// Returns true if SDKROOT (or, failing that, SUPPORTED_PLATFORMS) names
    /// `iphoneos`. Returns false for macOS-only projects (SDKROOT = macosx).
    /// Returns true as a permissive default if the pbxproj can't be read,
    /// so we don't silently drop valid projects on an unexpected format.
    static func isIOSProject(xcodeprojURL: URL) -> Bool {
        let pbxprojURL = xcodeprojURL.appendingPathComponent("project.pbxproj")
        guard let contents = try? String(contentsOf: pbxprojURL, encoding: .utf8) else {
            return true
        }
        // Match build-setting assignments as real tokens rather than bare
        // substrings, tolerating whitespace and optional quotes:
        //   SDKROOT = iphoneos;   SDKROOT = "iphoneos";   SDKROOT=iphoneos;
        if matches(#"SDKROOT\s*=\s*"?iphoneos"?"#, in: contents) { return true }
        if matches(#"SDKROOT\s*=\s*"?macosx"?"#, in: contents) { return false }
        // No explicit SDKROOT: fall back to SUPPORTED_PLATFORMS containing
        // iphoneos as a whole word (e.g. xcodegen projects like Somnya).
        if matches(#"SUPPORTED_PLATFORMS\s*=[^;]*\biphoneos\b"#, in: contents) { return true }
        return false
    }

    /// Whether an xcodegen `project.yml` declares an iOS target.
    ///
    /// Strict where the pbxproj reader is permissive: an unreadable or
    /// iOS-less yml returns false. The yml is committed source of truth, so a
    /// missing iOS marker is real evidence rather than a parse failure — this
    /// is what keeps macOS-only xcodegen projects (Sundial) off the list.
    static func isIOSProjectYML(at ymlURL: URL) -> Bool {
        guard let contents = try? String(contentsOf: ymlURL, encoding: .utf8) else { return false }
        return matches(#"platform:\s*iOS\b"#, in: contents)
    }

    /// The target name to build from an xcodegen `project.yml`: the first key
    /// under `targets:`. Deliberately not the top-level `name:` — xcodegen lets
    /// them differ, and it's the target name that has to work as an
    /// xcodebuild -scheme.
    static func projectNameFromYML(at ymlURL: URL) -> String? {
        guard let contents = try? String(contentsOf: ymlURL, encoding: .utf8) else { return nil }
        var inTargets = false
        for line in contents.components(separatedBy: .newlines) {
            if line.hasPrefix("targets:") {
                inTargets = true
                continue
            }
            guard inTargets else { continue }
            // A non-indented, non-blank line ends the targets block.
            if let first = line.first, !first.isWhitespace { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed.hasSuffix(":") else { continue }
            // Only the immediate children of targets: are target names; deeper
            // indentation is a target's own settings.
            let indent = line.prefix { $0 == " " }.count
            guard indent <= 2 else { continue }
            return String(trimmed.dropLast())
        }
        return nil
    }

    /// Resolves symlinks and standardizes, so /Users/... and its /private
    /// equivalent compare equal.
    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Whether `pattern` (a regex) matches anywhere in `text`.
    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
