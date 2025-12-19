#!/usr/bin/env bash
set -euo pipefail
# Wrapper to preserve backward compatibility
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ops/demo_provision_and_configure.sh" "$@"
