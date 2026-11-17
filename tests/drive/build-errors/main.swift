// Checks BuildErrorClassifier against build outputs. Run by tests/drive/build-errors.sh.
import Foundation

var failures = 0
func expect(_ name: String, _ got: String, contains want: String) {
    if got.contains(want) { print("  ✓ \(name)") }
    else { failures += 1; print("  ✗ \(name): expected \"\(want)\", got \"\(got)\"") }
}

let here = URL(filePath: CommandLine.arguments[1])
func fixture(_ name: String) -> String {
    try! String(contentsOf: here.appending(path: "fixtures/\(name)"), encoding: .utf8)
}

// Ansa's build.sh on 2026-10-19: install refused because the phone was locked.
let ansaLocked = fixture("ansa-locked.txt")
expect("script's own die() message is surfaced",
       BuildErrorClassifier.classify(ansaLocked).message, contains: "Install failed: the iPhone is locked.")
expect("…with its fix", BuildErrorClassifier.classify(ansaLocked).message, contains: "Unlock it and keep it unlocked")
expect("ios-template's \"Installing to the phone…\" is the install phase",
       BuildErrorClassifier.phase(of: ansaLocked).rawValue, contains: "Install")
expect("_template's \"→ Installing to device\" is the install phase",
       BuildErrorClassifier.phase(of: "→ Installing to device ABC\nboom").rawValue, contains: "Install")
expect("no install line is the build phase",
       BuildErrorClassifier.phase(of: "** BUILD FAILED **").rawValue, contains: "Build")

// devicectl's own locked error, as a script that echoes it shows it.
let devicectlLocked = fixture("devicectl-locked.txt")
expect("devicectl locked error reads as locked, not as iOS too new",
       BuildErrorClassifier.classify(devicectlLocked).message, contains: "iPhone is locked")

expect("a real disk-image mismatch still reads as iOS too new",
       BuildErrorClassifier.classify("Unable to mount developer disk image").message, contains: "newer than this Xcode")
// Timekeep's build.sh on 2026-10-21: iOS 27.0.1 phone, Xcode 26.3.
expect("devicectl's \"could not be mounted\" (error 12040) reads as iOS too new",
       BuildErrorClassifier.classify(fixture("timekeep-ddi-12040.txt")).message, contains: "newer than this Xcode")
expect("the 12040 message says what to do when the App Store has no update",
       BuildErrorClassifier.classify(fixture("timekeep-ddi-12040.txt")).message, contains: "update macOS first")
// xcodebuild on 2026-10-21, right after updating to macOS 27.
expect("an unaccepted Xcode license says how to accept it",
       BuildErrorClassifier.classify("You have not agreed to the Xcode license agreements. Please run 'sudo xcodebuild -license' from within a Terminal window to review and agree to the Xcode and Apple SDKs license.").message,
       contains: "Open Xcode and agree")
// Timekeep's build.sh on 2026-11-16: devicectl's generic 3002 on every attempt.
let install3002 = BuildErrorClassifier.classify(fixture("timekeep-install-3002.txt")).message
expect("a script's error, not devicectl's bare 3002 line, is surfaced",
       install3002, contains: "couldn't install to the iPhone")
expect("…with the fix from its indented lines", install3002, contains: "Unlock it and keep it awake")
expect("a compiler error leaves out the source lines under it",
       BuildErrorClassifier.classify("/a/B.swift:3:5: error: cannot find 'x' in scope\n    let y = x\n            ^").message,
       contains: "in scope")
if BuildErrorClassifier.classify("/a/B.swift:3:5: error: cannot find 'x' in scope\n    let y = x\n").message.contains("let y") {
    failures += 1; print("  ✗ compiler error swallowed the source line under it")
}
expect("no message at all falls back to the generic line",
       BuildErrorClassifier.classify("** BUILD FAILED **\n").message, contains: "Check the build log")

if failures > 0 { print("✗ build-errors: \(failures) failed"); exit(1) }
print("✓ build-errors: failure messages name the cause and the fix")
