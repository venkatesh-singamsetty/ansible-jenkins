#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# demo_provision_and_configure.sh
# Typical end-to-end demo script for this repo:
# 1) terraform apply (terraform/aws)
# 2) wait for instances and SSM
# 3) generate inventory (ssm or ssh)
# 4) run ansible playbook (controller by default)

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --tfvars PATH            Path to terraform tfvars file (default: terraform/aws/terraform.tfvars)
  --auto-approve           Pass -auto-approve to terraform apply (non-interactive)
  --mode MODE              Inventory mode: ssm (default) or ssh
  --inventory-out PATH     Path to write generated inventory (default: inventories/generated.ini)
  --playbook NAME          Playbook to run (controller|agents|site). Default: controller
  --vault-pass-file PATH   Ansible vault password file (optional)
  --wait-seconds N         Seconds to wait after terraform apply for cloud-init/SSM (default: 120)
  -h, --help               Show this help

Example:
  $0 --tfvars terraform/aws/terraform.tfvars --auto-approve --mode ssm --playbook controller

Note: Ensure you have AWS creds in env or configured (~/.aws) and tools installed: terraform, ansible-playbook, aws (optional).
EOF
}

# Defaults
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$REPO_ROOT/terraform/aws"
TF_VARS="$TF_DIR/terraform.tfvars"
AUTO_APPROVE="false"
MODE="ssm"
INVENTORY_OUT="$REPO_ROOT/inventories/generated.ini"
PLAYBOOK="controller"
VAULT_PASS_FILE=""
WAIT_SECONDS=120

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tfvars) TF_VARS="$2"; shift 2;;
    --auto-approve) AUTO_APPROVE="true"; shift 1;;
    --mode) MODE="$2"; shift 2;;
    --inventory-out) INVENTORY_OUT="$2"; shift 2;;
    --playbook) PLAYBOOK="$2"; shift 2;;
    --vault-pass-file) VAULT_PASS_FILE="$2"; shift 2;;
    --wait-seconds) WAIT_SECONDS="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 1;;
  esac
done

# Validate choices
if [[ "$MODE" != "ssm" && "$MODE" != "ssh" ]]; then
  echo "Invalid mode: $MODE. Use 'ssm' or 'ssh'." >&2
  exit 2
fi

case "$PLAYBOOK" in
  controller) PLAYBOOK_PATH="$REPO_ROOT/ansible/playbooks/controller.yml";;
  agents) PLAYBOOK_PATH="$REPO_ROOT/ansible/playbooks/agents.yml";;
  site) PLAYBOOK_PATH="$REPO_ROOT/ansible/playbooks/site.yml";;
  *) echo "Unknown playbook: $PLAYBOOK"; exit 2;;
esac

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 3; }
command -v ansible-playbook >/dev/null 2>&1 || { echo "ansible-playbook not found in PATH" >&2; exit 3; }
if [[ "$MODE" == "ssm" ]]; then
  command -v aws >/dev/null 2>&1 || echo "Warning: AWS CLI not found; SSM instance checks will be skipped"
fi

# Step 1: Terraform init & apply
echo "[1/5] Running terraform in $TF_DIR"
cd "$TF_DIR"
terraform init -input=false
if [[ "$AUTO_APPROVE" == "true" ]]; then
  terraform apply -var-file="$TF_VARS" -auto-approve
else
  terraform apply -var-file="$TF_VARS"
fi

# Step 2: Wait for instances & SSM
echo "[2/5] Waiting ${WAIT_SECONDS}s for cloud-init / SSM agent to register"
sleep "$WAIT_SECONDS"

if [[ "$MODE" == "ssm" && $(command -v aws >/dev/null 2>&1; echo $?) -eq 0 ]]; then
  echo "Checking SSM-managed instances (may be empty until instances register)"
  aws ssm list-instance-information --region "$(terraform output -raw aws_region 2>/dev/null || echo '')" || true
fi

# Step 3: Generate inventory
echo "[3/5] Generating inventory (mode=$MODE) -> $INVENTORY_OUT"
cd "$REPO_ROOT"
mkdir -p "$(dirname "$INVENTORY_OUT")"
if [[ ! -x "$REPO_ROOT/terraform/aws/generate_inventory.sh" ]]; then
  chmod +x "$REPO_ROOT/terraform/aws/generate_inventory.sh" || true
fi
./terraform/aws/generate_inventory.sh "$MODE" > "$INVENTORY_OUT"

# Step 4: Run Ansible playbook
echo "[4/5] Running Ansible playbook: $PLAYBOOK_PATH with inventory $INVENTORY_OUT"
ANSIBLE_CMD=(ansible-playbook -i "$INVENTORY_OUT" "$PLAYBOOK_PATH")
if [[ -n "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_CMD+=(--vault-password-file "$VAULT_PASS_FILE")
fi
# Add verbose output for user; do not set -x for secrets
"${ANSIBLE_CMD[@]}"

# Step 5: Summary
echo "[5/5] Done. Summary:"
echo "  - Terraform directory: $TF_DIR"
echo "  - Terraform vars used: $TF_VARS"
echo "  - Inventory generated: $INVENTORY_OUT"
echo "  - Playbook run: $PLAYBOOK_PATH"

cat <<EOF
Next recommended steps:
  - Verify Jenkins controller web UI (http/https) and initial admin setup.
  - If using SSH mode, configure bastion or SSH keys as needed.
  - Consider running role-specific Molecule tests locally before committing changes.
EOF

exit 0
