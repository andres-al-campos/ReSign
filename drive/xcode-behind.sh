#!/bin/bash
# Feature check: ReSign notices an Xcode too old for the phone (features/global-problems.md).
# Compiles XcodeCompatibility alone with swiftc and runs it on saved devicectl output.
set -euo pipefail
cd "$(dirname "$0")/.."
bin=$(mktemp -d)/xcode-behind
trap 'rm -rf "$(dirname "$bin")"' EXIT
swiftc -o "$bin" Sources/Services/XcodeCompatibility.swift drive/xcode-behind/main.swift
"$bin" drive/xcode-behind
