import Foundation

/// A problem that blocks every project at once, so it's shown once, in the
/// popup's banner, rather than as an error on each project. It stays until the
/// cause is fixed; there's nothing to dismiss. Its title and detail are also
/// the wording of the matching notification and per-project error.
enum GlobalProblem: Equatable, Identifiable {
    case signedOut
    /// After a macOS or Xcode update, xcodebuild refuses to run until the new
    /// license is accepted.
    case licenseNotAccepted
    /// `macOSFirst` is set when the Xcode that would fix it needs a newer
    /// macOS than this Mac runs, so the App Store shows no update.
    case xcodeBehind(phoneOS: String, sdk: String, macOSFirst: MacOSFirst? = nil)

    struct MacOSFirst: Equatable {
        let xcode: String
        let minimumMacOS: String
        let macOS: String
    }

    var id: String {
        switch self {
        case .signedOut: "signed-out"
        case .licenseNotAccepted: "license"
        case .xcodeBehind: "xcode-behind"
        }
    }

    var title: String {
        switch self {
        case .signedOut: "Not signed in to Xcode"
        case .licenseNotAccepted: "Xcode's license needs accepting"
        case .xcodeBehind: "Xcode is too old for your iPhone"
        }
    }

    var detail: String {
        switch self {
        case .signedOut:
            "Sign in to Xcode → Settings → Accounts so ReSign can rebuild your apps."
        case .licenseNotAccepted:
            "Xcode updated and won't build until you agree to its new license. Open Xcode and agree, or run sudo xcodebuild -license accept in Terminal."
        case .xcodeBehind(let phoneOS, let sdk, nil):
            "Your iPhone runs iOS \(phoneOS) and this Xcode installs up to iOS \(sdk). Update Xcode, then open it once."
        case .xcodeBehind(let phoneOS, let sdk, let first?):
            "Your iPhone runs iOS \(phoneOS) and this Xcode installs up to iOS \(sdk). Xcode \(first.xcode) needs macOS \(first.minimumMacOS) and this Mac runs \(first.macOS), so update macOS first, then Xcode, then open Xcode once."
        }
    }

    var actionLabel: String {
        switch self {
        case .signedOut: "Open Xcode accounts"
        case .licenseNotAccepted: "Open Xcode"
        case .xcodeBehind(_, _, nil): "Open App Store"
        case .xcodeBehind: "Open Software Update"
        }
    }
}

/// When being signed out of Xcode is worth saying. Xcode can sign out several
/// times between builds and a profile lasts days, so most sign-outs stop
/// nothing. Waiting for the build itself would be too late: a project comes due
/// after its profile expires, when the app has already stopped launching.
struct SignedOutAlert {
    /// Long enough to get to the Mac before an app stops launching.
    static let warningWindow: TimeInterval = 24 * 3600

    private var notified = false

    /// The red icon and notification wait for a blocked build, or one due within
    /// the window. The banner doesn't: it's only seen on opening the popup, which
    /// is when someone about to press Rebuild wants to know.
    static func needsAttention(signedOut: Bool, waitingBuilds: Int, nextDue: Date?, now: Date = .now) -> Bool {
        guard signedOut else { return false }
        if waitingBuilds > 0 { return true }
        guard let nextDue else { return false }
        return nextDue.timeIntervalSince(now) <= warningWindow
    }

    /// True the first time only, so later sign-outs in the window and retries
    /// on wake and on the 2-hour pass don't notify again.
    mutating func shouldNotify() -> Bool {
        defer { notified = true }
        return !notified
    }

    /// Reset by a build getting past signing, not by the account list looking
    /// full: the list can name an account whose credentials are gone, which
    /// would flip between "signed in" and "No Accounts" and notify on each flip.
    mutating func accountWorked() {
        notified = false
    }
}
