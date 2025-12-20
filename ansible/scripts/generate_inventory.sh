#!/usr/bin/env bash
set -euo pipefail

# Generates `inventories/dev/hosts.ini` from Terraform outputs.
# This canonical copy lives under `ansible/scripts/` and will look for Terraform
# outputs in `terraform/aws` by default. You can override `TF_DIR` env var.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${TF_DIR:-$REPO_ROOT/terraform/aws}"

if [ ! -f "$TF_DIR/terraform.tfstate" ]; then
  echo "terraform state not found in ${TF_DIR}. Run 'terraform init && terraform apply' first." >&2
  exit 1
fi

MODE="ssh"
if [ "${1:-}" = "ssm" ] || [ "${1:-}" = "--mode=ssm" ]; then
  MODE="ssm"
fi

echo "Generating inventories/dev/hosts.ini from terraform outputs (mode=${MODE})..."

TF_OUTPUT=$(cd "$TF_DIR" && terraform output -json)

BASTION_IP=$(echo "$TF_OUTPUT" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("bastion_public_ip", {}).get("value", ""))')
CONTROLLER_IP=$(echo "$TF_OUTPUT" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("controller_private_ip", {}).get("value", ""))')
AGENT_IPS=$(echo "$TF_OUTPUT" | python3 -c 'import sys, json; print("\n".join(json.load(sys.stdin).get("agent_private_ips", {}).get("value", [])))')
KEY_PATH=$(echo "$TF_OUTPUT" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("ssh_private_key_path", {}).get("value", ""))')

OUT_DIR="${REPO_ROOT}/inventories/dev"
mkdir -p "$OUT_DIR"

if [ "$MODE" = "ssm" ]; then
  cat > "$OUT_DIR/hosts.ini" <<EOF
[jenkins_controller]
controller-dev ansible_host=${CONTROLLER_IP}

[jenkins_agent]
EOF

  INDEX=1
  while read -r ip; do
    if [ -n "$ip" ]; then
      echo "agent-dev-${INDEX} ansible_host=${ip}" >> "$OUT_DIR/hosts.ini"
      INDEX=$((INDEX+1))
    fi
  done <<< "$AGENT_IPS"

  echo "Wrote $OUT_DIR/hosts.ini (SSM mode). Ensure you enable 'inventories/group_vars/ssm.yml' or set ansible_connection: aws_ssm in group_vars."
else
  cat > "$OUT_DIR/hosts.ini" <<EOF
[bastion]
bastion ansible_host=${BASTION_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_PATH}

[jenkins_controller]
controller-dev ansible_host=${CONTROLLER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_PATH} ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q -i ${KEY_PATH} ubuntu@${BASTION_IP}"'

[jenkins_agent]
EOF

  INDEX=1
  while read -r ip; do
    if [ -n "$ip" ]; then
      echo "agent-dev-${INDEX} ansible_host=${ip} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_PATH} ansible_ssh_common_args='-o ProxyCommand=\"ssh -W %h:%p -q -i ${KEY_PATH} ubuntu@${BASTION_IP}\"'" >> "$OUT_DIR/hosts.ini"
      INDEX=$((INDEX+1))
    fi
  done <<< "$AGENT_IPS"

  echo "Wrote $OUT_DIR/hosts.ini (SSH mode with bastion)."
fi

exit 0
