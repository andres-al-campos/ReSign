import Foundation

/// Whether this Xcode can install to the phone. Xcode only carries developer
/// disk images up to its own iOS SDK's major version, so a phone a major
/// version ahead can't be installed to until Xcode is updated. Minor versions
/// share a disk image, so only the major numbers are compared.
enum XcodeCompatibility {
    static func isBehind(phoneOS: String, sdk: String) -> Bool {
        guard let phone = major(phoneOS), let xcode = major(sdk) else { return false }
        return phone > xcode
    }

    static func major(_ version: String) -> Int? {
        version.split(separator: ".").first.flatMap { Int($0) }
    }

    /// The App Store's current Xcode and the macOS it needs, from Apple's
    /// public lookup (itunes.apple.com/lookup?id=497799835).
    static func appStoreXcode(fromLookupJSON data: Data) -> (version: String, minimumMacOS: String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let version = result["version"] as? String,
              let minimum = result["minimumOsVersion"] as? String else { return nil }
        return (version, minimum)
    }

    /// Compares dotted versions numerically: "26.10" is newer than "26.6".
    static func isOlder(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    /// `osVersionNumber` from `devicectl device info details --json-output -`.
    static func phoneOSVersion(fromDetailsJSON data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let props = result["deviceProperties"] as? [String: Any] else { return nil }
        return props["osVersionNumber"] as? String
    }
}
