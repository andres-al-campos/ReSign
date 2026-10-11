# Rebuild after Xcode sign-in

When Xcode has signed you out, ReSign skips the builds that would fail, tells
you once, and rebuilds them on its own after you sign back in.

## Sub-features

- A build that is due while Xcode is signed out fails fast with "Not signed in
  to Xcode" instead of running `xcodebuild`, and is queued.
- One "Not signed in to Xcode" notification is shown, however many projects
  are queued.
- Clicking the notification, or its Open Xcode button, opens Xcode at
  Settings → Accounts.
- After that click, the queued builds start about 2 seconds after the account
  appears in Xcode.
- Without the click, they start within a minute of the sign-in.
- The notification is cleared once the sign-in is detected.
- A project ignored after it was queued is not rebuilt.

## How to get to it

Sign out of Xcode (Settings → Accounts, remove the Apple ID), then click
**Rebuild** on any watched project. The notification appears. Click it and
sign back in.

## Driving it

No check yet. The trigger is a real sign-in to Xcode with an Apple ID and
two-factor, which nothing can perform headless. The decision of how often to
look for the sign-in could be tested alone, but ReSign has no test target and
that decision isn't separated from the scheduler's timers.

Last driven: 2026-10-10, macOS, by hand. Signed out, clicked the notification,
signed in; the rebuild started on its own with no noticeable wait. That run
used a 10-minute watch window, since shortened to 5.

## Gotchas

- Being signed out does not make ReSign look more often. Only the click does,
  for 5 minutes, because a Mac can stay signed out for days. Clicking again
  restarts the 5 minutes.
- The close watch ends when a queued build succeeds. A queued build that fails
  signed-out again inside the 5 minutes goes back to the 2-second look.
- "Signed in" means both an Apple ID in Xcode's account list and a development
  certificate in the keychain. The certificate alone isn't enough: it outlives
  the Xcode session.
- If an Xcode version keeps its account list somewhere ReSign doesn't expect,
  ReSign falls back to the certificate alone and can think it is signed in
  when Xcode isn't. The build then fails with "No Accounts" and is queued
  the same way.
- The queue is held in memory. Quitting or reinstalling ReSign drops it, and
  only projects that are due get rebuilt at the next launch.
