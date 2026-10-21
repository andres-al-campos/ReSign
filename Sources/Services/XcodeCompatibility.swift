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

    /// `osVersionNumber` from `devicectl device info details --json-output -`.
    static func phoneOSVersion(fromDetailsJSON data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let props = result["deviceProperties"] as? [String: Any] else { return nil }
        return props["osVersionNumber"] as? String
    }
}
