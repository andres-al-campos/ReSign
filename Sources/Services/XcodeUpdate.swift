import AppKit

enum XcodeUpdate {
    /// Xcode's page in the Mac App Store, where the update is.
    static func openAppStore() {
        NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!)
    }

    static func openSoftwareUpdate() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
    }

    /// This Mac's macOS version, e.g. "26.5.1".
    static var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// When the App Store's current Xcode needs a newer macOS than this Mac
    /// runs, that Xcode and the macOS it needs; the App Store then shows no
    /// update. Nil when it doesn't, or when the lookup fails.
    static func blockedByMacOS() async -> (xcode: String, minimumMacOS: String)? {
        let url = URL(string: "https://itunes.apple.com/lookup?id=497799835")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let listing = XcodeCompatibility.appStoreXcode(fromLookupJSON: data),
              XcodeCompatibility.isOlder(macOSVersion, than: listing.minimumMacOS) else { return nil }
        return (listing.version, listing.minimumMacOS)
    }
}
