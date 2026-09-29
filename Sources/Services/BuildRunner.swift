import Foundation

enum BuildRunner {
    static func build(
        project: ManagedProject,
        preferredDeviceID: String? = nil,
        onOutput: @Sendable @escaping (String) -> Void = { _ in }
    ) async -> (result: BuildResult, log: String) {
        let fullLog = OutputAccumulator()

        let append: @Sendable (String) -> Void = { text in
            fullLog.append(text)
            onOutput(text)
        }

        // Phase 1: Find device
        append("=== Device Discovery ===\n")
        let device: DeviceInfo
        do {
            try Task.checkCancellation()
            device = try await DeviceLocator.findDevice(preferredID: preferredDeviceID)
            append("Device: \(device.name) (\(device.id))\n\n")
            // Fail here rather than after a full compile dies at install.
            guard await DeviceLocator.isReachable(device.id) else {
                try Task.checkCancellation()
                return (.failure(phase: .deviceNotFound, message: "\(device.name) isn't reachable. Unlock it and make sure it's on the same Wi-Fi as this Mac. ReSign rebuilds when it's back.", kind: .deviceUnreachable), fullLog.value)
            }
        } catch is CancellationError {
            return (.cancelled, fullLog.value)
        } catch {
            return (.failure(phase: .deviceNotFound, message: error.localizedDescription), fullLog.value)
        }

        // Phase 1.5: If the project root ships a build.sh, prefer it. The script
        // owns build+sign+install (and likely knows project-specific steps like
        // xcodegen). We pass the chosen device so it installs to the right phone,
        // then verify it staged a signed .app we can read expiry from. If the
        // script doesn't produce one (e.g. an old unsigned-IPA script), we fall
        // through to ReSign's own xcodebuild path rather than mis-scheduling.
        if let buildScript = projectBuildScript(for: project) {
            do { try Task.checkCancellation() } catch { return (.cancelled, fullLog.value) }
            if let delegated = await runProjectBuildScript(
                buildScript, project: project, deviceID: device.id, append: append
            ) {
                return (await blamingLostPhone(delegated, deviceID: device.id), fullLog.value)
            }
            append("\n(build.sh did not produce a signed .app — falling back to xcodebuild)\n\n")
        }

        // Phase 2: xcodebuild
        do {
            try Task.checkCancellation()
        } catch {
            return (.cancelled, fullLog.value)
        }

        // Use a per-project derived data dir so we know exactly where the .app lands.
        let derivedDataDir = derivedDataDirectory(for: project)
        do {
            try FileManager.default.createDirectory(at: derivedDataDir, withIntermediateDirectories: true)
        } catch {
            return (.failure(phase: .xcodebuild, message: "Could not create build output directory at \(derivedDataDir.path). Check disk permissions."), fullLog.value)
        }

        append("Builder: xcodebuild (built-in)\n")
        append("=== xcodebuild ===\n")
        let buildResult: (output: String, exitCode: Int32)
        do {
            buildResult = try await run([
                "xcodebuild",
                "-project", project.projectPath.path,
                "-scheme", project.name,
                "-configuration", "Debug",
                "-destination", "generic/platform=iOS",
                "-derivedDataPath", derivedDataDir.path,
                "-allowProvisioningUpdates",
                "clean", "build"
            ], onOutput: append)
        } catch is CancellationError {
            return (.cancelled, fullLog.value)
        } catch {
            return (.failure(phase: .xcodebuild, message: error.localizedDescription), fullLog.value)
        }

        guard buildResult.exitCode == 0 else {
            let classified = classifyBuildError(buildResult.output)
            return (.failure(phase: .xcodebuild, message: classified.message, kind: classified.kind), fullLog.value)
        }

        let productsDir = derivedDataDir
            .appendingPathComponent("Build/Products/Debug-iphoneos", isDirectory: true)
        guard let appPath = findAppBundle(in: productsDir) else {
            return (.failure(phase: .xcodebuild, message: "Build reported success but no .app was produced at \(productsDir.path). Try building the scheme manually in Xcode to see what's happening."), fullLog.value)
        }

        // Phase 3: Install
        do {
            try Task.checkCancellation()
        } catch {
            return (.cancelled, fullLog.value)
        }

        append("=== Install ===\n")
        let installResult: (output: String, exitCode: Int32)
        do {
            installResult = try await run([
                "xcrun", "devicectl", "device", "install", "app",
                "--device", device.id,
                appPath.path
            ], onOutput: append)
        } catch is CancellationError {
            return (.cancelled, fullLog.value)
        } catch {
            return (.failure(phase: .deviceInstall, message: error.localizedDescription), fullLog.value)
        }

        guard installResult.exitCode == 0 else {
            // classifyBuildError also recognises the free-provisioning app limit,
            // which surfaces here rather than during xcodebuild.
            let msg: String
            if installResult.output.contains("MIFreeProfileValidatedAppTracker")
                || installResult.output.contains("free development profiles") {
                // The .app is right here, so confirm the tier from its embedded
                // profile rather than inferring it from the log marker alone.
                msg = isFreeProvisioning(appPath: appPath) == true
                    ? "Free Apple ID limit reached — a free account allows only 3 apps installed per device at a time. Delete another ReSign-installed app from your phone, then rebuild."
                    : classifyBuildError(installResult.output).message
            } else if installResult.output.contains("not found") {
                msg = "Device lost during install. Make sure your phone stays unlocked."
            } else {
                msg = String(installResult.output.suffix(300))
            }
            return (await blamingLostPhone(.failure(phase: .deviceInstall, message: msg), deviceID: device.id), fullLog.value)
        }

        // Read actual profile expiration date
        let profileExpiry = readProfileExpiry(appPath: appPath)

        return (.success(appBundlePath: appPath, profileExpiresAt: profileExpiry), fullLog.value)
    }

    // MARK: - Private

    /// An executable `build.sh` at the project repo root (the .xcodeproj's parent
    /// directory), or nil if absent / not executable.
    private static func projectBuildScript(for project: ManagedProject) -> URL? {
        let script = project.projectPath
            .deletingLastPathComponent()
            .appendingPathComponent("build.sh")
        let fm = FileManager.default
        guard fm.fileExists(atPath: script.path),
              fm.isExecutableFile(atPath: script.path) else { return nil }
        return script
    }

    /// Runs the project's build.sh with the target device, then looks for a
    /// signed `build/<Name>.app` it staged. Returns a `.success`/`.failure`
    /// BuildResult if the delegation is conclusive, or nil to signal "fall back
    /// to ReSign's own xcodebuild" (script ran but staged no signed .app).
    private static func runProjectBuildScript(
        _ script: URL,
        project: ManagedProject,
        deviceID: String,
        append: @Sendable @escaping (String) -> Void
    ) async -> BuildResult? {
        append("Builder: build.sh (\(script.path))\n")
        append("=== build.sh ===\n")
        let repoRoot = script.deletingLastPathComponent()

        let result: (output: String, exitCode: Int32)
        do {
            // Pass the chosen device so the script installs to the right phone.
            // Scripts that don't recognize --device should ignore unknown flags;
            // if one hard-fails on it, the staged-.app check below still gates us.
            result = try await run(
                ["bash", script.path, "--device", deviceID],
                cwd: repoRoot,
                onOutput: append
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            // Couldn't even launch the script — fall back to xcodebuild.
            return nil
        }

        // Verify: a build.sh-built app is staged at build/<Name>.app and carries
        // an embedded provisioning profile (i.e. it was actually signed).
        let stagedApp = repoRoot
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("\(project.name).app", isDirectory: true)
        let profile = stagedApp.appendingPathComponent("embedded.mobileprovision")
        guard FileManager.default.fileExists(atPath: stagedApp.path),
              FileManager.default.fileExists(atPath: profile.path) else {
            // No signed .app to read expiry from — let the caller fall back.
            return nil
        }

        guard result.exitCode == 0 else {
            // Confirm the tier from the staged app's profile before blaming the
            // free-tier cap; the log marker alone only suggests it.
            if (result.output.contains("MIFreeProfileValidatedAppTracker")
                || result.output.contains("free development profiles")),
               isFreeProvisioning(appPath: stagedApp) == true {
                return .failure(
                    phase: .deviceInstall,
                    message: "Free Apple ID limit reached — a free account allows only 3 apps installed per device at a time. Delete another ReSign-installed app from your phone, then rebuild.",
                    kind: .generic
                )
            }
            let classified = classifyBuildError(result.output)
            let phase: BuildPhase = result.output.contains("→ Installing") ? .deviceInstall : .xcodebuild
            return .failure(phase: phase, message: classified.message, kind: classified.kind)
        }

        let expiry = readProfileExpiry(appPath: stagedApp)
        return .success(appBundlePath: stagedApp, profileExpiresAt: expiry)
    }

    /// Whether the app's embedded profile was issued to a free Apple ID.
    ///
    /// Free-tier profiles are valid for 7 days; paid Developer Program profiles
    /// run a year. Nothing in the plist states the tier outright, so the
    /// validity window is the signal — anything under a month is free-tier.
    /// Returns nil when there's no profile to read.
    static func isFreeProvisioning(appPath: URL) -> Bool? {
        guard let plist = readProfilePlist(appPath: appPath),
              let created = plist["CreationDate"] as? Date,
              let expires = plist["ExpirationDate"] as? Date else { return nil }
        return expires.timeIntervalSince(created) < 30 * 24 * 60 * 60
    }

    private static func readProfileExpiry(appPath: URL) -> Date? {
        readProfilePlist(appPath: appPath)?["ExpirationDate"] as? Date
    }

    private static func readProfilePlist(appPath: URL) -> [String: Any]? {
        let profilePath = appPath.appendingPathComponent("embedded.mobileprovision")
        guard FileManager.default.fileExists(atPath: profilePath.path) else { return nil }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/security")
        process.arguments = ["cms", "-D", "-i", profilePath.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Per-project derived data directory. Keyed by project UUID so rebuilds are deterministic
    /// and we don't pollute the user's ~/Library/Developer/Xcode/DerivedData.
    private static func derivedDataDirectory(for project: ManagedProject) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/ReSign/DerivedData", isDirectory: true)
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    /// Deletes ReSign's own DerivedData cache for a project. Only touches the
    /// directory ReSign created under ~/Library/Caches/ReSign — never the
    /// user's Xcode DerivedData. Used by "Clean & Retry" after a stale-cache
    /// failure. Missing directory is a no-op.
    static func purgeDerivedData(for project: ManagedProject) {
        try? FileManager.default.removeItem(at: derivedDataDirectory(for: project))
    }

    /// Finds the built .app inside our controlled products directory.
    /// Picks the most recently modified .app in case multiple targets produced one.
    private static func findAppBundle(in productsDir: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: productsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let apps = entries.filter { $0.pathExtension == "app" }
        return apps.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    private static let lostPhoneMessage = "Lost the connection to your iPhone during install. Unlock it and make sure it's on the same Wi-Fi as this Mac. ReSign rebuilds when it's back."

    /// devicectl reports a phone that vanished mid-install under several
    /// errors, some as generic as "Failed to install the app" (3002). Rather
    /// than chase the wording, ask the phone: if it no longer answers, the
    /// install failed because it left.
    private static func blamingLostPhone(_ result: BuildResult, deviceID: String) async -> BuildResult {
        guard case .failure(.deviceInstall, _, let kind) = result, kind != .deviceUnreachable,
              await !DeviceLocator.isReachable(deviceID) else { return result }
        return .failure(phase: .deviceInstall, message: lostPhoneMessage, kind: .deviceUnreachable)
    }

    private static func classifyBuildError(_ output: String) -> (message: String, kind: BuildErrorKind) {
        if output.contains("No Accounts") {
            return ("Not signed in to Xcode. Open Xcode → Settings → Accounts and sign in with your Apple ID, then try again.", .signedOut)
        }
        // The phone left Wi-Fi (or locked hard) partway through. The build
        // itself is fine; it only needs the phone back.
        if output.contains("unable to locate a device")
            || output.contains("connection to this device could not be established")
            || output.contains("NWError") {
            return (lostPhoneMessage, .deviceUnreachable)
        }
        if output.contains("No profiles for") || output.contains("no provisioning profiles") {
            return ("No provisioning profile found. Open the project in Xcode and build it once manually to create a profile.", .projectSigning)
        }
        if output.contains("provisioning profile") && output.contains("expired") {
            return ("Provisioning profile expired. Open the project in Xcode; Xcode regenerates a free-tier profile on the next build.", .projectSigning)
        }
        if output.contains("SIGNING") || output.contains("code sign") || output.contains("CodeSign") {
            return ("Code signing failed. Open the project in Xcode, select your team under Signing & Capabilities, and verify the bundle ID matches your profile.", .projectSigning)
        }
        if output.contains("Build input file cannot be found") {
            return ("Source file missing. Check the project for broken file references in Xcode.", .generic)
        }
        if output.contains("could not find module") {
            return ("Missing Swift module or dependency. This is often a stale build cache — try Clean & Retry, or resolve packages in Xcode.", .staleCache)
        }
        // xcode-select points at the Command Line Tools instead of full Xcode —
        // common after an OS/Xcode update. Retrying can't fix it; the user has to
        // repoint xcode-select once.
        if output.contains("requires Xcode") || output.contains("active developer directory") {
            return ("xcodebuild can't find Xcode. Run: sudo xcode-select -s /Applications/Xcode.app — then ReSign builds resume automatically.", .generic)
        }
        // A newer iOS than the installed Xcode knows about: devicectl can't
        // find a matching Developer Disk Image to mount, so the install fails
        // before it starts. Common right after an iOS update, and no amount of
        // retrying fixes it — Xcode has to catch up to the phone.
        if output.contains("Unable to mount developer disk image")
            || output.contains("DeveloperDiskImage")
            || output.contains("Failed to mount the developer disk image")
            || output.contains("could not find a developer disk image") {
            return ("Your iPhone's iOS is newer than this Xcode supports, so the debug image won't mount. Update Xcode from the App Store (or install the matching iOS support files), then rebuild.", .generic)
        }
        // MIFreeProfileValidatedAppTracker is the iOS subsystem that tracks apps
        // installed under *free* provisioning profiles, so seeing it in a failed
        // install points at the free-tier cap of 3 apps per device. It's a hint,
        // not a verified account tier — ReSign never inspects the Apple ID — so
        // the message hedges rather than asserting the cause.
        //
        // Worth catching at all because install scripts tend to read the refusal
        // as a flaky device link and retry it, blaming a sleeping phone. Retrying
        // never helps: a slot has to be freed first.
        if output.contains("MIFreeProfileValidatedAppTracker")
            || output.contains("free development profiles") {
            return ("Install refused, most likely the free-provisioning limit of 3 apps per device. Delete another ReSign-installed app from your phone and rebuild. (A paid Apple Developer account has no such limit.)", .generic)
        }
        // A build tool the project's build.sh needs (e.g. xcodegen) isn't
        // installed, or isn't on the login-item PATH. The message already carries
        // the fix ("Install with: brew install …"); surface it verbatim rather
        // than burying it under the generic "check the log".
        if output.contains("not installed. Install with:") {
            let lines = output.components(separatedBy: "\n")
            if let line = lines.last(where: { $0.contains("not installed. Install with:") }) {
                return (String(line.drop(while: { $0 == " " }).prefix(200)), .generic)
            }
        }
        // Extract last error: line
        let lines = output.components(separatedBy: "\n")
        if let errorLine = lines.last(where: { $0.contains("error:") }) {
            return (String(errorLine.prefix(200)), .generic)
        }
        return ("Build failed. Check the build log for details.", .generic)
    }

    private static func run(
        _ arguments: [String],
        cwd: URL? = nil,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = arguments
        process.environment = ProcessEnvironment.childEnvironment()
        if let cwd { process.currentDirectoryURL = cwd }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Accumulate full (filtered) output for return value
        let outputAccumulator = OutputAccumulator()

        // Single shared filter instance; it's stateful across chunks (tracks
        // which step header we're inside of). Wrapped for thread-safety since
        // stdout and stderr handlers may fire on different queues.
        let filter = FilterBox()

        let emit: @Sendable (String) -> Void = { raw in
            let compact = filter.feed(raw)
            guard !compact.isEmpty else { return }
            outputAccumulator.append(compact)
            onOutput(compact)
        }

        // Stream stdout in real-time (filtered)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            emit(text)
        }

        // Stream stderr in real-time (filtered)
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            emit(text)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { p in
                    // Clean up handlers
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    // Read any remaining data (filtered)
                    if let remaining = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), !remaining.isEmpty {
                        emit(remaining)
                    }
                    if let remaining = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), !remaining.isEmpty {
                        emit(remaining)
                    }
                    // Flush any trailing partial line the filter was buffering.
                    let tail = filter.flush()
                    if !tail.isEmpty {
                        outputAccumulator.append(tail)
                        onOutput(tail)
                    }

                    let output = outputAccumulator.value
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: (output: output, exitCode: p.terminationStatus))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}

/// Thread-safe wrapper around BuildOutputFilter. Pipe readability handlers
/// can fire on different queues (stdout vs stderr), so we serialize access.
private final class FilterBox: @unchecked Sendable {
    private let lock = NSLock()
    private let filter = BuildOutputFilter()

    func feed(_ chunk: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return filter.feed(chunk)
    }

    func flush() -> String {
        lock.lock()
        defer { lock.unlock() }
        return filter.flush()
    }
}

/// Thread-safe string accumulator for gathering process output.
private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func append(_ text: String) {
        lock.lock()
        _value += text
        lock.unlock()
    }
}

enum ProcessEnvironment {
    /// Environment for spawned build/device tools. A menu-bar app launched by
    /// launchd inherits a minimal PATH (`/usr/bin:/bin:...`) with no Homebrew, so
    /// a subprocess (or a project's build.sh) can't find `xcodegen` and friends —
    /// the same command works fine from the user's terminal. We prepend the common
    /// Homebrew bin dirs (Apple Silicon + Intel) to whatever PATH we inherited.
    static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let brewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existing = env["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        let merged = brewPaths + existing.filter { !brewPaths.contains($0) }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }
}
