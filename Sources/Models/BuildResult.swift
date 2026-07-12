import Foundation

enum BuildResult {
    case success(appBundlePath: URL, profileExpiresAt: Date? = nil)
    case failure(phase: BuildPhase, message: String, kind: BuildErrorKind = .generic)
    case cancelled
}

enum BuildPhase: String {
    case xcodebuild = "Build"
    case deviceInstall = "Install"
    case deviceNotFound = "Device Discovery"
}

/// Classifies a build failure so the UI can offer the right recovery action.
enum BuildErrorKind {
    /// Not signed in to Xcode. Global fix in Xcode → Settings → Accounts, no
    /// specific project involved → offer "Open Xcode".
    case signedOut
    /// Signing problem specific to this project — missing/expired profile,
    /// wrong team, bundle-ID mismatch. Fixed in this project's Signing &
    /// Capabilities → offer "Open Project in Xcode".
    case projectSigning
    /// Stale build cache — deleting ReSign's DerivedData for the project and
    /// rebuilding is likely to fix it.
    case staleCache
    /// Anything else; the user should read the log.
    case generic
}
