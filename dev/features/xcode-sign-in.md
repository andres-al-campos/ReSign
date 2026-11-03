# Rebuild after Xcode sign-in

Updated 2026-11-02 23:09, at 1.6.

When Xcode has signed you out, the popup says so, and the menu bar icon stays
as it was until a build is within a day. Then ReSign tells you once, skips the
builds that would fail, and rebuilds them on its own after you sign back in.
Every sign-out is recorded with what ran around it.

## Sub-features

- While no build is waiting and none is due within 24 hours, a sign-out shows
  only as the banner in the popup: no notification, no red icon.
- Each change to Xcode's account is appended to
  `~/Library/Application Support/ReSign/sign-ins.log`: signed out, signed in, or
  replaced by a new ID, with the build tools running then, and the `xcodebuild`
  runs and account errors in the system log since the last entry. An
  `xcodebuild` that says "No Accounts" is recorded too.
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

`./build.sh drive signed-out-alert` compiles the decisions alone and runs them:
quiet until a build is within a day, one notification, which account changes
get recorded, and what's kept from a saved shape of `log show`. It doesn't
observe the banner or icon, the log file being written, or a real sign-in with
an Apple ID and two-factor, which nothing can perform headless. How often ReSign looks for the
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
- A project comes due a minute after its profile expires, which is why the
  warning runs ahead of the build instead of waiting for it.
- The notification doesn't repeat for a later sign-out until a build has got
  past signing, but the red icon does come back while a build is close.
- The record sees the account list once a minute, so a run that's already
  finished shows only in the system-log part, without its command line.
- Xcode's account list can name an account whose credentials are gone
  (`xcodebuild` logs "Invalid credentials in keychain ... missing
  Xcode-Username"). ReSign reads that as signed in. If `xcodebuild` then says
  "No Accounts", the sign-in poll retries the queue every minute.
- What signs Xcode out is unknown; `sign-ins.log` is there to find out. Seen
  once in the system log, 2026-11-02, on Xcode 27.1, in an `xcodebuild` not
  started by ReSign; signing back in gave the account a new ID.

## Calls

- 2026-11-02 23:09, 1.6. **A sign-out matters only when a build is close.** Xcode was signing out
  daily while profiles last days, and the red icon warned about each one though
  nothing was stopped yet: "I'd like to find a balance so I'm not getting
  bombarded." Waiting for the build itself would be too late, since the app has
  expired by then, so the icon goes red a day ahead. The 24 hours is a guess.
  The banner shows whenever Xcode is signed out: the popup only gets opened
  when the icon is red or to make a build, and then it's useful to know.
  Applies *Unseen until it can't do its job*.
