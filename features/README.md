# ReSign features

What a user can do with ReSign, how to reach it, and how to drive it. Read
this before adding anything: if it's already here, extend it instead of
building it again.

This map is partial. It grows one feature at a time, as each is changed.

| Feature | File | Platforms | Driveable headless? |
|---|---|---|---|
| Rebuild after Xcode sign-in | [xcode-sign-in.md](xcode-sign-in.md) | macOS | No check yet |

## What counts as a feature

Something a user sets out to do, with its own way in. What you only reach
inside a feature is a sub-feature and lives in that feature's file.

## Each file has

- **Sub-features**: what a user can do inside it, including limits.
- **How to get to it**: the user's path.
- **Driving it**: preconditions, the command that checks it, and what it
  observes. With no check, "No check yet" and why.
- **Gotchas**: what has bitten us or will.

Claims describe observable behavior, not code locations.

## Keeping it current

Update a feature's file in the same commit that changes the feature. A
feature touched for the first time gets a file and a row here.

## Driving conventions

`./build.sh check` runs every law in `laws/`, including the one that keeps
this map and its files in step, then every drive.

A feature's check is `drive/<name>.sh`. `./build.sh drive` runs them all and
`./build.sh drive <name>` runs one; a name with no script is an error. There
are none yet, and no test target.

ReSign's features depend on Xcode's sign-in state, a paired iPhone and real
`xcodebuild` runs, so most of them can't be driven headless as they stand.
