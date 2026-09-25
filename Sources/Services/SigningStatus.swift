import AppKit

/// Checks whether Xcode / the keychain has a usable code-signing identity.
///
/// Xcode has a well-known habit of silently signing the user out (session token
/// expiry, 2FA timeout, keychain conflicts). When that happens, `xcodebuild`
/// wastes ~30s before failing with "No Accounts". This check lets us detect
/// the signed-out state in milliseconds and skip the doomed build.
enum SigningStatus {
    enum State: Equatable {
        case signedIn(identityCount: Int)
        case signedOut
        case unknown(reason: String)
    }

    /// Runs `security find-identity -v -p codesigning` and parses the count of
    /// "Apple Development" identities. Zero → signed out.
    static func current() -> State {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/security")
        process.arguments = ["find-identity", "-v", "-p", "codesigning"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return .unknown(reason: error.localizedDescription)
        }
        process.waitUntilExit()

        guard let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return .unknown(reason: "Could not read output from `security`.")
        }

        // Count lines containing an "Apple Development" or "Apple Distribution"
        // identity. Format per line: `  1) ABC123... "Apple Development: name (TEAM)"`
        let count = output
            .components(separatedBy: "\n")
            .filter { $0.contains("Apple Development") || $0.contains("Apple Distribution") }
            .count

        return count > 0 ? .signedIn(identityCount: count) : .signedOut
    }
}

/// Takes the user straight to Xcode → Settings → Accounts, where "not signed in"
/// gets fixed. Pressing keys in another app needs Accessibility permission;
/// without it this still opens Xcode, and ⌘, lands on Accounts via the preset pane.
@MainActor
enum XcodeAccounts {
    static func open() {
        // Xcode reopens Settings on whichever pane was viewed last.
        UserDefaults(suiteName: "com.apple.dt.Xcode")?
            .set("IDEKit.IDESettingsPane.Accounts", forKey: "IDELastViewedSettingsPane")

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else { return }
        // Shows the system Accessibility prompt the first time.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { app, _ in
            guard trusted, let pid = app?.processIdentifier else { return }
            Task { @MainActor in await openSettings(pid: pid) }
        }
    }

    private static func openSettings(pid: pid_t) async {
        // A cold launch takes several seconds before Xcode's menus accept ⌘,.
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline {
            if let app = NSRunningApplication(processIdentifier: pid), app.isFinishedLaunching, app.isActive { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? await Task.sleep(for: .milliseconds(500))

        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0x2B, keyDown: keyDown) // 0x2B = comma
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        // Backstop for a running Xcode that never re-read the preset pane.
        try? await Task.sleep(for: .seconds(1))
        let axApp = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, let accounts = findElement(titled: "Accounts", in: window as! AXUIElement, depth: 0) else { return }
        AXUIElementPerformAction(accounts, kAXPressAction as CFString)
    }

    private static func findElement(titled title: String, in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 6 else { return nil }
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               value as? String == title { return element }
        }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in (children as? [AXUIElement]) ?? [] {
            if let hit = findElement(titled: title, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }
}
