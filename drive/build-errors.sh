#!/bin/bash
# Feature check: a failed rebuild names its cause and fix (features/build-errors.md).
# Compiles BuildErrorClassifier alone with swiftc and runs it on saved outputs.
set -euo pipefail
cd "$(dirname "$0")/.."
bin=$(mktemp -d)/build-errors
trap 'rm -rf "$(dirname "$bin")"' EXIT
swiftc -o "$bin" Sources/Models/BuildResult.swift Sources/Models/GlobalProblem.swift Sources/Services/BuildErrorClassifier.swift drive/build-errors/main.swift
"$bin" drive/build-errors
