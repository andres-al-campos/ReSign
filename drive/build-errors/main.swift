// Checks BuildErrorClassifier against build outputs. Run by drive/build-errors.sh.
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
expect("no message at all falls back to the generic line",
       BuildErrorClassifier.classify("** BUILD FAILED **\n").message, contains: "Check the build log")

if failures > 0 { print("✗ build-errors: \(failures) failed"); exit(1) }
print("✓ build-errors: failure messages name the cause and the fix")
