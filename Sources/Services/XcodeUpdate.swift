import AppKit

enum XcodeUpdate {
    /// Xcode's page in the Mac App Store, where the update is.
    static func openAppStore() {
        NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!)
    }
}
