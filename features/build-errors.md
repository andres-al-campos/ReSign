# Build failure messages

When a rebuild fails, ReSign's message says what went wrong and how to fix it,
and labels the failure Build or Install.

## Sub-features

- Known failures get a written message: signed out of Xcode, missing or expired
  profile, code signing, a phone that left Wi-Fi, a locked phone, iOS newer than
  Xcode, the free-account limit of 3 apps, a missing build tool.
- When nothing matches and a project's build.sh exits with its own message
  (its `die()`), that message is shown, headline and fix, rather than "Check
  the build log".
- A failure after the script prints "Installing to …" is labelled Install.

## How to get to it

Rebuild a project while its build would fail, e.g. with the iPhone locked.
The message shows on the project row and in the notification.

## Driving it

`./build.sh drive build-errors` compiles the classifier alone and runs it on
saved outputs in `drive/build-errors/fixtures/`. It observes the message and
phase for each.

## Gotchas

- devicectl's locked error names a `DeveloperDiskImages` path, so the locked
  check must come before the disk-image one or it reads as "iOS too new".
- The install marker is the shared "Installing to " prefix: `_template` prints
  "→ Installing to device …", ios-template prints "Installing to the phone…".
- `devicectl-locked.txt` is reconstructed from devicectl's error format, not
  captured; `ansa-locked.txt` follows Ansa's build.sh text with the progress
  lines abbreviated.
