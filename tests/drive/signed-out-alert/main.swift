// Checks when a signed-out Xcode is worth saying, and what gets recorded. Run by tests/drive/signed-out-alert.sh.
import Foundation

var failures = 0
func expect(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { failures += 1; print("  ✗ \(name)") }
}

let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
func shows(signedOut: Bool = true, waiting: Int = 0, dueInHours: Double?) -> Bool {
    SignedOutAlert.showsProblem(signedOut: signedOut, waitingBuilds: waiting,
                                nextDue: dueInHours.map { now.addingTimeInterval($0 * 3600) }, now: now)
}

expect("signed out with the next build days away shows nothing", !shows(dueInHours: 72))
expect("signed out with nothing scheduled shows nothing", !shows(dueInHours: nil))
expect("signed out with a build due within a day shows the problem", shows(dueInHours: 20))
expect("signed out with a build waiting shows the problem", shows(waiting: 1, dueInHours: 72))
expect("signed in shows nothing, even close to a build", !shows(signedOut: false, waiting: 1, dueInHours: 1))

var alert = SignedOutAlert()
expect("the first warning notifies", alert.shouldNotify())
expect("a second warning doesn't", !alert.shouldNotify())
expect("a retry on the next pass doesn't", !alert.shouldNotify())

alert.accountWorked()
expect("a warning after the account worked notifies again", alert.shouldNotify())

expect("the first look isn't a change", SignInRecord.change(from: nil, to: ["A"]) == nil)
expect("an unreadable list isn't a change", SignInRecord.change(from: ["A"], to: nil) == nil)
expect("the same account isn't a change", SignInRecord.change(from: ["A"], to: ["A"]) == nil)
expect("an emptied list is a sign-out", SignInRecord.change(from: ["A"], to: [])?.hasPrefix("signed out") == true)
expect("a filled list is a sign-in", SignInRecord.change(from: [], to: ["B"]) == "signed in")
expect("a new ID is a replaced account", SignInRecord.change(from: ["A"], to: ["B"])?.hasPrefix("account replaced") == true)

// Shaped like `log show --style compact` for xcodebuild on Xcode 27.1, with made-up IDs.
var lines = ["Timestamp               Ty Process[PID:TID]"]
lines += (0..<3).map { "2026-11-02 21:15:0\($0).100 Df xcodebuild[100:aa] [com.apple.xpc:connection] activating" }
lines += (0..<12).map { "2026-11-02 21:17:30.\($0)00 Df xcodebuild[200:bb] [com.apple.dt.coredevice:devicemanager] check-in" }
lines.append("2026-11-02 21:17:32.931 E  xcodebuild[200:bb] [DVTDeveloperAccountManager:critical] Failed to load credentials for FAKE-ID: missing Xcode-Username")
let summary = SignInRecord.summarize(logLines: lines)
expect("a real xcodebuild run is listed", summary.contains { $0.contains("2026-11-02 21:17:30 pid 200, 13 log lines") })
expect("a short run like the license check is left out", !summary.contains { $0.contains("pid 100") })
expect("the account error is kept", summary.contains { $0.contains("pid 200") && $0.contains("missing Xcode-Username") })

if failures > 0 {
    print("signed-out-alert: \(failures) failed. Fix SignedOutAlert in Sources/Models/GlobalProblem.swift or Sources/Services/SignInRecord.swift, or the expectation if the rule changed in dev/features/xcode-sign-in.md.")
    exit(1)
}
print("✓ signed-out-alert: a sign-out stays quiet until a build is within a day, notifies once, and is recorded with what ran around it")
