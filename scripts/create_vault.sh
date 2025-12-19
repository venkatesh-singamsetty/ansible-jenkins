#!/usr/bin/env bash
set -euo pipefail
# Wrapper to preserve backward compatibility
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ansible/create_vault.sh" "$@"
