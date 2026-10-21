# Problems that block every project

When something stops every project from installing, ReSign says so once, in a
banner at the top of the popup, and turns the menu bar icon red. The banner
stays until the cause is fixed; it has no close button.

## Sub-features

- **Xcode older than the phone's iOS.** The banner names both versions and has
  an Open App Store button. One notification is sent when the mismatch is
  first noticed; clicking it opens the App Store too.
- **Signed out of Xcode.** The banner has an Open Xcode accounts button, which
  opens Settings → Accounts and starts the close sign-in watch (see
  [xcode-sign-in.md](xcode-sign-in.md)). It shows whenever Xcode is signed
  out, whether or not a build is waiting.
- Both can show at once, one banner each.
- The menu bar icon is red while any banner shows, whatever the projects'
  state.

## How to get to it

Open the popup while the phone runs a newer major iOS than Xcode's iOS SDK
(for example iOS 27 with Xcode 26), or while Xcode is signed out.

## Driving it

`./build.sh drive xcode-behind` compiles the version comparison alone and runs
it on saved `devicectl` output in `drive/xcode-behind/fixtures/`. It observes
whether a phone and SDK version pair counts as behind. The banner, icon and
notification aren't driven; they need the running app.

## Gotchas

- Only major versions are compared. Since iOS 17 a disk image covers a whole
  major version, so iOS 26.4 installs from an Xcode whose SDK is 26.2.
- The Xcode version comes from `xcrun --sdk iphoneos --show-sdk-version`, the
  selected Xcode's SDK. Xcode 26.3 reports 26.2.
- The phone is read at launch, on wake, on each scheduled pass and when it
  announces itself on Wi-Fi. Opening the popup re-reads only Xcode, so the
  banner clears right after an Xcode update without waiting on the phone.
- A freshly updated Xcode still needs opening once to install its device
  support. The banner clears on the SDK version alone, so an install right
  after the update can still fail with the disk-image error.
- A phone that doesn't answer keeps its last reading.
