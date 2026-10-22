import Foundation

/// A problem that blocks every project at once, so it's shown once, in the
/// popup's banner, rather than as an error on each project. It stays until the
/// cause is fixed; there's nothing to dismiss.
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
            "ReSign won't rebuild your apps until you sign in with your Apple ID in Xcode → Settings → Accounts."
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
