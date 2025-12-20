#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper for compatibility: exec canonical `ansible/scripts/create_vault.sh`
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO_ROOT/ansible/scripts/create_vault.sh" "$@"
