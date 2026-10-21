import Foundation

/// Reads a failed build's output and says what went wrong and how to fix it.
enum BuildErrorClassifier {
    static let lostPhoneMessage = "Lost the connection to your iPhone during install. Unlock it and make sure it's on the same Wi-Fi as this Mac. ReSign rebuilds when it's back."

    /// The build.sh scripts print "Installing to …" before the device install:
    /// "→ Installing to device <id>" (_template) or "Installing to the phone…"
    /// (ios-template).
    static func phase(of output: String) -> BuildPhase {
        output.contains("Installing to ") ? .deviceInstall : .xcodebuild
    }

    static func classify(_ output: String) -> (message: String, kind: BuildErrorKind) {
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
        // The phone is locked, so iOS won't mount the developer disk image.
        // Checked before the disk-image pattern below: devicectl's locked error
        // names a DeveloperDiskImages path and would read as "iOS too new".
        if output.contains("DeviceLocked") || output.contains("The device is locked") {
            return ("iPhone is locked. Unlock it, keep it unlocked until the install finishes, and rebuild.", .generic)
        }
        // A newer iOS than the installed Xcode knows about: devicectl can't
        // find a matching Developer Disk Image to mount, so the install fails
        // before it starts. Common right after an iOS update, and no amount of
        // retrying fixes it — Xcode has to catch up to the phone.
        if output.contains("Unable to mount developer disk image")
            || output.contains("DeveloperDiskImage")
            || output.contains("Failed to mount the developer disk image")
            || output.contains("could not find a developer disk image")
            || output.contains("developer disk image could not be mounted") {
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
        // The build script exited non-zero with its own message (a die() in
        // build.sh). It already says what went wrong and how to fix it; a
        // warning further up the log is not the cause.
        if let message = scriptMessage(output) {
            return (message, .generic)
        }
        return ("Build failed. Check the build log for details.", .generic)
    }

    /// The text after the script's last progress line, up to its first two
    /// paragraphs: a die() headline and the fix that follows it.
    static func scriptMessage(_ output: String) -> String? {
        let progress = ["Installing to ", "Built and signed", "** BUILD ", "→ "]
        var lines = output.components(separatedBy: "\n")
        if let last = lines.lastIndex(where: { line in progress.contains { line.contains($0) } }) {
            lines = Array(lines[(last + 1)...])
        }
        let paragraphs = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .split(separator: "", omittingEmptySubsequences: true)
            .map { $0.joined(separator: " ") }
        guard !paragraphs.isEmpty else { return nil }
        return String(paragraphs.prefix(2).joined(separator: " ").prefix(300))
    }
}
