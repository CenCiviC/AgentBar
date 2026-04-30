#!/usr/bin/env bash
# Run SwiftLint on the entire package.
set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"

swift package plugin swiftlint
