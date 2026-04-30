#!/usr/bin/env bash
# Run SwiftFormat on the entire package.
set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"

swift package plugin --allow-writing-to-package-directory swiftformat
