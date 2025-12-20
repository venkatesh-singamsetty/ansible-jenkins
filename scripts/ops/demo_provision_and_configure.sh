#!/usr/bin/env bash
set -euo pipefail

# Compatibility wrapper: forwards to canonical demo script at `scripts/demo_provision_and_configure.sh`
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$REPO_ROOT/scripts/demo_provision_and_configure.sh" "$@"
