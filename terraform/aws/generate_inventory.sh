#!/usr/bin/env bash
set -euo pipefail

# generate_inventory.sh
# Generates `inventories/dev/hosts.ini` from Terraform outputs.
# Usage:
#   ./generate_inventory.sh          # default: ssh mode (bastion ProxyJump)
#   ./generate_inventory.sh ssm      # emit inventory for SSM mode (uses ansible_connection: aws_ssm)
#   ./generate_inventory.sh --mode=ssm

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${MODULE_DIR}/.."

pushd "${MODULE_DIR}" > /dev/null

if [ ! -f terraform.tfstate ]; then
  echo "terraform state not found in ${MODULE_DIR}. Run 'terraform init && terraform apply' first." >&2
  exit 1
fi

MODE="ssh"
if [ "${1:-}" = "ssm" ] || [ "${1:-}" = "--mode=ssm" ]; then
  MODE="ssm"
fi

echo "Generating inventories/dev/hosts.ini from terraform outputs (mode=${MODE})..."

TF_OUTPUT=$(terraform output -json)

BASTION_IP=$(echo "$TF_OUTPUT" | python3 -c 'import sys, json; print(json.load(sys.stdin)["bastion_public_ip"]["value"])')
CONTROLLER_IP=$(echo "$TF_OUTPUT" | python3 -c 'import sys, json; print(json.load(sys.stdin)["controller_private_ip"]["value"])')
AGENT_IPS=$(echo "$TF_OUTPUT" | python3 -c 'import sys, json; print("\n".join(json.load(sys.stdin)["agent_private_ips"]["value"]))')
KEY_PATH=$(echo "$TF_OUTPUT" | python3 -c 'import sys, json; print(json.load(sys.stdin)["ssh_private_key_path"]["value"])')

OUT_DIR="${ROOT_DIR}/inventories/dev"
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

popd > /dev/null
