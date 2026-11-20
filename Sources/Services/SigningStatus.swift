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
        // A valid certificate outlives the Xcode session, so check the account
        // list first — it empties when Xcode signs out, which is what makes
        // xcodebuild fail with "No Accounts".
        if xcodeAccountCount() == 0 { return .signedOut }

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

    /// Apple IDs in Xcode → Settings → Accounts, or nil if Xcode doesn't store the
    /// list where we expect (older or newer Xcode) — callers must not treat nil as
    /// signed out, or every build would be blocked.
    private static func xcodeAccountCount() -> Int? {
        xcodeAccounts()?.count
    }

    /// The IDs Xcode gave its accounts. Signing back in gets a new ID, so a
    /// change shows a sign-out even when it was undone between two looks.
    static func xcodeAccountIDs() -> [String]? {
        xcodeAccounts()?.compactMap { ($0 as? [String: Any])?["identifier"] as? String }
    }

    private static func xcodeAccounts() -> [Any]? {
        let domain = "com.apple.dt.Xcode" as CFString
        // Pick up Xcode's writes made since ReSign launched.
        CFPreferencesAppSynchronize(domain)
        guard let lists = CFPreferencesCopyAppValue("DVTDeveloperAccountManagerAppleIDLists" as CFString, domain) as? [String: Any] else { return nil }
        return lists["IDE.Identifiers.Prod"] as? [Any]
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

    /// Keeps at it until Accounts has been pressed in a Settings window, since a
    /// fresh Xcode comes to the front before its menus take ⌘, (seen on 27.1,
    /// where a single ⌘, half a second after activation left the welcome window).
    private static func openSettings(pid: pid_t) async {
        let axApp = AXUIElementCreateApplication(pid)
        let deadline = Date.now.addingTimeInterval(30)
        var lastCommaAt = Date.distantPast
        while Date.now < deadline {
            let windows = windows(of: axApp)
            // Settings is the only Xcode window with an Accounts button in reach.
            for window in windows {
                if let accounts = findElement(titled: "Accounts", in: window, depth: 0),
                   AXUIElementPerformAction(accounts, kAXPressAction as CFString) == .success { return }
            }
            // ⌘, goes to the frontmost app, so it waits for Xcode to be in front
            // with a window up, and for Xcode to answer the last one.
            if !windows.isEmpty, NSRunningApplication(processIdentifier: pid)?.isActive == true,
               Date.now.timeIntervalSince(lastCommaAt) > 0.5 {
                pressCommandComma()
                lastCommaAt = .now
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let titles = windows(of: axApp).map { title(of: $0) ?? "untitled" }
        NSLog("ReSign: Xcode Settings → Accounts didn't open in 30 s; Xcode windows: %@", titles.joined(separator: ", "))
    }

    private static func pressCommandComma() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0x2B, keyDown: keyDown) // 0x2B = comma
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return value as? String
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
