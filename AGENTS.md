# ReSign

Keep your sideloaded iOS apps from expiring, without having to remember them.

Features are mapped in `dev/features/`; read the map before adding one.

## Principles

How ReSign ought to be, so a session can decide a case nobody has met yet.
Rulings on one thing go in that feature's file, under Calls, and name the
principle they apply. The Principles in the `AGENTS.md` files above
this one (walled_garden's and `~/Projects/Code`'s) hold here too, unless this
file refines one or names an exception.

- 2026-10-22 22:08, 1.6. **Unseen until it can't do its job.** ReSign works without being watched.
  It asks for attention only when something stops it keeping an app
  installed, says so once rather than once per project, and stays in front
  of the user until the cause is fixed. (After an iOS 27 update left Xcode 26
  unable to install.)
- 2026-10-22 22:08, 1.6. **Every failure comes with its fix.** A message names what went wrong and
  where to fix it, with a button to that place when there is one. The
  project's own message beats a generic "check the build log".
- 2026-10-22 22:08, 1.6. **It picks up on its own.** When the cause clears, ReSign carries on
  without being asked: nobody should have to come back and press retry.
