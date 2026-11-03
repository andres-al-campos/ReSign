# Rebuild after Xcode sign-in

Updated 2026-11-02 21:40, at 1.6.

When Xcode has signed you out, ReSign says nothing until a build needs the
account. Then it skips the builds that would fail, tells you once, and rebuilds
them on its own after you sign back in.

## Sub-features

- While no build is waiting, a sign-out changes nothing: no notification, no
  banner, no red icon.
- A build that is due while Xcode is signed out fails fast with "Not signed in
  to Xcode" instead of running `xcodebuild`, and is queued.
- One "Not signed in to Xcode" notification is shown, however many projects
  are queued and however many passes retry them. The next one needs a build to
  have got past signing first.
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

`./build.sh drive signed-out-alert` compiles the decision of when to speak
alone and runs it: quiet with no build waiting, one notification per spell. It
doesn't observe the banner or icon, or a real sign-in with an Apple ID and
two-factor, which nothing can perform headless. How often ReSign looks for the
sign-in isn't separated from the scheduler's timers, so it isn't checked.

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
- A project comes due a minute after its profile expires, so by the time a
  sign-out is mentioned that app has already stopped launching.
- Xcode's account list can name an account whose credentials are gone
  (`xcodebuild` logs "Invalid credentials in keychain ... missing
  Xcode-Username"). ReSign reads that as signed in. If `xcodebuild` then says
  "No Accounts", the sign-in poll retries the queue every minute.
- What signs Xcode out is unknown. Seen once in the system log, 2026-11-02, on
  Xcode 27.1, in an `xcodebuild` not started by ReSign; signing back in gave the
  account a new ID.

## Calls

- 2026-11-02 21:40, 1.6. **A sign-out doesn't matter until the next build.** Xcode was signing out
  daily while profiles last days, and the red icon and banner warned about each
  one though nothing was stopped yet. So they wait for a build that's blocked.
  Applies *Unseen until it can't do its job*.
