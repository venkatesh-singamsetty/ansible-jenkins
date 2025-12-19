#!/usr/bin/env bash
set -euo pipefail

# Helper to create an Ansible Vault file with placeholder secrets.
# Usage: ./scripts/create_vault.sh inventories/group_vars/vault.yml

OUT_FILE=${1:-inventories/group_vars/vault.yml}

if [ -f "$OUT_FILE" ]; then
  echo "$OUT_FILE already exists. Use ansible-vault edit to modify it." >&2
  exit 1
fi

cat > /tmp/vault_template.yml <<'EOF'
---
# Vaulted secrets for Jenkins
jenkins_admin_password: "REPLACE_WITH_STRONG_PASSWORD"
agent_secret: "REPLACE_WITH_AGENT_SECRET"
EOF

echo "Creating vault file $OUT_FILE (you will be prompted for a vault password)..."
ansible-vault create "$OUT_FILE" --vault-id @prompt --input /tmp/vault_template.yml || true
rm -f /tmp/vault_template.yml

echo "Vault file created: $OUT_FILE"
