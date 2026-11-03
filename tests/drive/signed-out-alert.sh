#!/bin/bash
# Feature check: being signed out of Xcode stays quiet until a build is close, and each sign-out is recorded (dev/features/xcode-sign-in.md).
# Compiles the decisions alone with swiftc; the real sign-out can't be driven headless.
set -euo pipefail
cd "$(dirname "$0")/../.."
bin=$(mktemp -d)/signed-out-alert
trap 'rm -rf "$(dirname "$bin")"' EXIT
swiftc -o "$bin" Sources/Models/GlobalProblem.swift Sources/Services/SignInRecord.swift tests/drive/signed-out-alert/main.swift
"$bin"
