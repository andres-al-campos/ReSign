// Checks XcodeCompatibility against devicectl output. Run by tests/drive/xcode-behind.sh.
import Foundation

var failures = 0
func expect(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { failures += 1; print("  ✗ \(name)") }
}

let here = URL(filePath: CommandLine.arguments[1])
// devicectl details for an iPhone 15 on iOS 27.0.1, 2026-10-21, trimmed to the keys read.
let details = try! Data(contentsOf: here.appending(path: "fixtures/iphone-ios27-details.json"))
let phone = XcodeCompatibility.phoneOSVersion(fromDetailsJSON: details)
expect("reads the phone's iOS version from devicectl", phone == "27.0.1")

// Xcode 26.3 reports its iOS SDK as 26.2.
expect("iOS 27 phone with a 26 SDK is behind", XcodeCompatibility.isBehind(phoneOS: "27.0.1", sdk: "26.2"))
expect("a newer minor iOS shares the disk image", !XcodeCompatibility.isBehind(phoneOS: "26.4", sdk: "26.2"))
expect("an older phone is fine", !XcodeCompatibility.isBehind(phoneOS: "25.1", sdk: "26.2"))
expect("an unreadable version never warns", !XcodeCompatibility.isBehind(phoneOS: "", sdk: "26.2"))

// Apple's App Store lookup for Xcode, 2026-10-21, trimmed to the keys read.
let lookup = try! Data(contentsOf: here.appending(path: "fixtures/appstore-xcode-lookup.json"))
let listing = XcodeCompatibility.appStoreXcode(fromLookupJSON: lookup)
expect("reads the App Store's Xcode and the macOS it needs",
       listing?.version == "27.1" && listing?.minimumMacOS == "26.6")
expect("macOS 26.5.1 is too old for an Xcode needing 26.6", XcodeCompatibility.isOlder("26.5.1", than: "26.6"))
expect("macOS 26.7.1 is new enough", !XcodeCompatibility.isOlder("26.7.1", than: "26.6"))
expect("versions compare by number, not text", !XcodeCompatibility.isOlder("26.10", than: "26.6"))
expect("equal versions are new enough", !XcodeCompatibility.isOlder("26.6", than: "26.6.0"))

if failures > 0 { print("✗ xcode-behind: \(failures) failed"); exit(1) }
print("✓ xcode-behind: an Xcode older than the phone's iOS is noticed")
