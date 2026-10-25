# Settings

Updated 2026-10-25 11:38, at 1.6.

The gear in the popup's header opens settings: launch at login, the folder
ReSign scans for projects, and which iPhone to install to.

## Sub-features

- **Launch at login.** A switch; the choice survives reinstalls.
- **Scan path.** Change opens a folder picker; the project list re-scans.
- **Install device.** Automatic, or one of the iPhones devicectl lists. The
  refresh button re-reads the list; a spinner shows in its place meanwhile.

## How to get to it

Click the menu bar icon, then the gear. The arrow goes back to projects.

## Driving it

No check yet. It's all SwiftUI in the popup, and ReSign has no UI test target.

Last seen by hand: 2026-10-21. Opening settings resizes the popup once.

## Gotchas

- The panel opens with the height and device list it had last time. Starting
  from empty resized the popup three times per open: to the 44pt floor, to
  the measured height, then again when devices arrived. The very first open
  after a launch can still resize, since nothing is saved yet.
- The spinner sits in the same 28pt box as the refresh button it replaces;
  a smaller box made the row change height when loading finished.
