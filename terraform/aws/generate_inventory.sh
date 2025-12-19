#!/usr/bin/env bash
set -euo pipefail

# Wrapper for backward compatibility. Forwards to canonical script under scripts/ansible.
# Resolve repository root from this file's directory (terraform/aws -> ../.. => repo root)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$REPO_ROOT/scripts/ansible/generate_inventory.sh" "$@"
