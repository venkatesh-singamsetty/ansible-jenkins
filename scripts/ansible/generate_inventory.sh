#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper left for compatibility: forwards to canonical script under ansible/scripts
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO_ROOT/ansible/scripts/generate_inventory.sh" "$@"
