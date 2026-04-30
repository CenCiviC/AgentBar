#!/usr/bin/env bash
# Build debug binary and run directly for fast development iteration.
set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"

pkill -x AgentBar 2>/dev/null || true

swift build
.build/debug/AgentBar
