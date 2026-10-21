import Foundation

/// A problem that blocks every project at once, so it's shown once, in the
/// popup's banner, rather than as an error on each project. It stays until the
/// cause is fixed; there's nothing to dismiss.
enum GlobalProblem: Equatable, Identifiable {
    case signedOut
    case xcodeBehind(phoneOS: String, sdk: String)

    var id: String {
        switch self {
        case .signedOut: "signed-out"
        case .xcodeBehind: "xcode-behind"
        }
    }

    var title: String {
        switch self {
        case .signedOut: "Not signed in to Xcode"
        case .xcodeBehind: "Xcode is too old for your iPhone"
        }
    }

    var detail: String {
        switch self {
        case .signedOut:
            "Sign in with your Apple ID in Xcode → Settings → Accounts. ReSign rebuilds as soon as you're signed in."
        case .xcodeBehind(let phoneOS, let sdk):
            "Your iPhone runs iOS \(phoneOS) and this Xcode installs up to iOS \(sdk). Update Xcode, then open it once."
        }
    }

    var actionLabel: String {
        switch self {
        case .signedOut: "Open Xcode accounts"
        case .xcodeBehind: "Open App Store"
        }
    }
}
