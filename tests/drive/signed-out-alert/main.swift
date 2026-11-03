// Checks when a signed-out Xcode is worth saying. Run by tests/drive/signed-out-alert.sh.
import Foundation

var failures = 0
func expect(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { failures += 1; print("  ✗ \(name)") }
}

expect("signed out with no build waiting shows nothing",
       !SignedOutAlert.showsProblem(signedOut: true, waitingBuilds: 0))
expect("signed out with a build waiting shows the problem",
       SignedOutAlert.showsProblem(signedOut: true, waitingBuilds: 1))
expect("signed in with a build still queued shows nothing",
       !SignedOutAlert.showsProblem(signedOut: false, waitingBuilds: 1))

var alert = SignedOutAlert()
expect("the first blocked build notifies", alert.shouldNotifyForBlockedBuild())
expect("the second blocked build doesn't", !alert.shouldNotifyForBlockedBuild())
expect("a retry on the next pass doesn't", !alert.shouldNotifyForBlockedBuild())

alert.accountWorked()
expect("a build blocked after the account worked notifies again", alert.shouldNotifyForBlockedBuild())

if failures > 0 {
    print("signed-out-alert: \(failures) failed. Fix SignedOutAlert in Sources/Models/GlobalProblem.swift, or the expectation if the rule changed in dev/features/xcode-sign-in.md.")
    exit(1)
}
print("✓ signed-out-alert: a sign-out stays quiet until a build is blocked, then notifies once")
