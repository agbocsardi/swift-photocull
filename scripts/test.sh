#!/usr/bin/env bash
# Run the core test suite. Exits non-zero on failure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec swift run PhotoCullTests
