#!/usr/bin/env bash
set -euo pipefail
# Wrapper to preserve backward compatibility; forwards to new canonical location under ansible/scripts
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO_ROOT/ansible/scripts/create_vault.sh" "$@"
