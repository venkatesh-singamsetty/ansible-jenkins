#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# generate_inventory.sh
# Usage: generate_inventory.sh [ssm|ssh]
# Reads `terraform output -json` and writes an Ansible INI-style inventory to stdout.

MODE=${1:-ssm}
# Ensure we run from the script directory (terraform/aws)
SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform CLI not found in PATH" >&2
  exit 1
fi

TF_JSON=$(terraform output -json 2>/dev/null || true)
# If terraform CLI didn't return outputs (e.g. running from elsewhere or no access to backend),
# try to read local terraform.tfstate as a fallback.
if [[ -z "$TF_JSON" ]]; then
  if [[ -f "terraform.tfstate" ]]; then
    TF_JSON=$(python3 - <<'PY'
import json
import sys
try:
    s = json.load(open('terraform.tfstate'))
    outputs = s.get('outputs', {})
    out = {}
    for k, v in outputs.items():
        out[k] = {'value': v.get('value')}
    sys.stdout.write(json.dumps(out))
except Exception as e:
    sys.stderr.write('Failed to parse terraform.tfstate: ' + str(e) + '\n')
    sys.exit(1)
PY
)
  fi
fi

if [[ -z "$TF_JSON" ]]; then
  echo "Could not read Terraform outputs — run 'terraform output -json' in terraform/aws or ensure terraform.tfstate exists" >&2
  exit 1
fi

# Helper to extract an output value using python (avoids jq dependency)
py_extract() {
  local key=$1
  # Use an environment variable to pass TF JSON to python to avoid stdin/heredoc conflicts.
  TF_JSON_env="$TF_JSON" python3 - <<PY
import os, json, sys
key = "$key"
o = json.loads(os.environ.get('TF_JSON_env', '{}'))
v = o.get(key, {})
val = v.get('value') if isinstance(v, dict) else None
if val is None:
    sys.exit(0)
if isinstance(val, list):
    for item in val:
        print(item)
else:
    print(val)
PY
}

# controller ip
controller_ip=$(py_extract controller_private_ip || true)

# agent IPs: older macOS bash lacks readarray, use a loop
agent_ips=()
while IFS= read -r _line; do
  [[ -z "$_line" ]] && continue
  agent_ips+=("$_line")
done < <(py_extract agent_private_ips || true)

bastion_ip=$(py_extract bastion_public_ip || true)
ssh_key_path=$(py_extract ssh_private_key_path || true)

echo "# Inventory generated from terraform outputs (mode=$MODE)"
echo

if [[ "$MODE" == "ssm" ]]; then
  # SSM mode: rely on connection plugin configuration in group_vars
  echo "[jenkins_controller]"
  if [[ -n "$controller_ip" ]]; then
    echo "controller ansible_host=${controller_ip}"
  else
    echo "# controller IP not found in terraform outputs"
  fi
  echo
  echo "[jenkins_agent]"
  if [[ ${#agent_ips[@]} -gt 0 ]]; then
    i=1
    for ip in "${agent_ips[@]}"; do
      echo "agent-${i} ansible_host=${ip}"
      i=$((i+1))
    done
  else
    echo "# no agent IPs found"
  fi
  echo
  echo "[all:vars]"
  echo "# Using SSM connection plugin — ensure group_vars enable SSM settings"
  echo "ansible_user=ansible"
  exit 0
fi

if [[ "$MODE" == "ssh" ]]; then
  echo "[bastion]"
  if [[ -n "$bastion_ip" ]]; then
    echo "bastion ansible_host=${bastion_ip} ansible_user=ubuntu"
  else
    echo "# bastion public IP not found"
  fi
  echo
  echo "[jenkins_controller]"
  if [[ -n "$controller_ip" ]]; then
    echo "controller ansible_host=${controller_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_key_path}"
  else
    echo "# controller IP not found"
  fi
  echo
  echo "[jenkins_agent]"
  if [[ ${#agent_ips[@]} -gt 0 ]]; then
    i=1
    for ip in "${agent_ips[@]}"; do
      echo "agent-${i} ansible_host=${ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_key_path}"
      i=$((i+1))
    done
  else
    echo "# no agent IPs found"
  fi

  echo
  echo "# If you need to route SSH via the bastion, set the following group var in your inventory or ansible.cfg"
  echo "# ansible_ssh_common_args='-o ProxyCommand=\"ssh -i ${ssh_key_path} -W %h:%p -q ubuntu@${bastion_ip}\"'"
  exit 0
fi

echo "Unknown mode: $MODE. Use 'ssm' or 'ssh'" >&2
exit 2
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# generate_inventory.sh
# Usage: generate_inventory.sh [ssm|ssh]
# Reads `terraform output -json` and writes an Ansible INI-style inventory to stdout.

MODE=${1:-ssm}
# Ensure we run from the script directory (terraform/aws)
SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform CLI not found in PATH" >&2
  exit 1
fi

TF_JSON=$(terraform output -json 2>/dev/null || true)
# If terraform CLI didn't return outputs (e.g. running from elsewhere or no access to backend),
# try to read local terraform.tfstate as a fallback.
if [[ -z "$TF_JSON" ]]; then
  if [[ -f "terraform.tfstate" ]]; then
    TF_JSON=$(python3 - <<'PY'
import json
import sys
try:
    s = json.load(open('terraform.tfstate'))
    outputs = s.get('outputs', {})
    out = {}
    for k, v in outputs.items():
        out[k] = {'value': v.get('value')}
    sys.stdout.write(json.dumps(out))
except Exception as e:
    sys.stderr.write('Failed to parse terraform.tfstate: ' + str(e) + '\n')
    sys.exit(1)
PY
)
  fi
fi

if [[ -z "$TF_JSON" ]]; then
  echo "Could not read Terraform outputs — run 'terraform output -json' in terraform/aws or ensure terraform.tfstate exists" >&2
  exit 1
fi

# Helper to extract an output value using python (avoids jq dependency)
py_extract() {
  local key=$1
  python3 - <<PY
import sys, json
try:
    o = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = o.get('$key', {})
val = v.get('value') if isinstance(v, dict) else None
if val is None:
    sys.exit(0)
if isinstance(val, list):
    for item in val:
        print(item)
else:
    print(val)
PY
}

controller_ip=$(printf '%s' "$TF_JSON" | py_extract controller_private_ip || true)
readarray -t agent_ips <<<"$(printf '%s' "$TF_JSON" | py_extract agent_private_ips || true)"
bastion_ip=$(printf '%s' "$TF_JSON" | py_extract bastion_public_ip || true)
ssh_key_path=$(printf '%s' "$TF_JSON" | py_extract ssh_private_key_path || true)

echo "# Inventory generated from terraform outputs (mode=$MODE)"
echo

if [[ "$MODE" == "ssm" ]]; then
  # SSM mode: rely on connection plugin configuration in group_vars
  echo "[jenkins_controller]"
  if [[ -n "$controller_ip" ]]; then
    echo "controller ansible_host=${controller_ip}"
  else
    echo "# controller IP not found in terraform outputs"
  fi
  echo
  echo "[jenkins_agent]"
  if [[ ${#agent_ips[@]} -gt 0 ]]; then
    i=1
    for ip in "${agent_ips[@]}"; do
      echo "agent-${i} ansible_host=${ip}"
      i=$((i+1))
    done
  else
    echo "# no agent IPs found"
  fi
  echo
  echo "[all:vars]"
  echo "# Using SSM connection plugin — ensure group_vars enable SSM settings"
  echo "ansible_user=ansible"
  exit 0
fi

if [[ "$MODE" == "ssh" ]]; then
  echo "[bastion]"
  if [[ -n "$bastion_ip" ]]; then
    echo "bastion ansible_host=${bastion_ip} ansible_user=ubuntu"
  else
    echo "# bastion public IP not found"
  fi
  echo
  echo "[jenkins_controller]"
  if [[ -n "$controller_ip" ]]; then
    echo "controller ansible_host=${controller_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_key_path}"
  else
    echo "# controller IP not found"
  fi
  echo
  echo "[jenkins_agent]"
  if [[ ${#agent_ips[@]} -gt 0 ]]; then
    i=1
    for ip in "${agent_ips[@]}"; do
      echo "agent-${i} ansible_host=${ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_key_path}"
      i=$((i+1))
    done
  else
    echo "# no agent IPs found"
  fi

  echo
  echo "# If you need to route SSH via the bastion, set the following group var in your inventory or ansible.cfg"
  echo "# ansible_ssh_common_args='-o ProxyCommand=\"ssh -i ${ssh_key_path} -W %h:%p -q ubuntu@${bastion_ip}\"'"
  exit 0
fi

echo "Unknown mode: $MODE. Use 'ssm' or 'ssh'" >&2
exit 2
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# generate_inventory.sh
# Usage: generate_inventory.sh [ssm|ssh]
# Reads `terraform output -json` and writes an Ansible INI-style inventory to stdout.

MODE=${1:-ssm}
# Ensure we run from the script directory (terraform/aws)
SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform CLI not found in PATH" >&2
  exit 1
fi

TF_JSON=$(terraform output -json 2>/dev/null || true)
# If terraform CLI didn't return outputs (e.g. running from elsewhere or no access to backend),
# try to read local terraform.tfstate as a fallback.
if [[ -z "$TF_JSON" ]]; then
  if [[ -f "terraform.tfstate" ]]; then
    TF_JSON=$(python3 - <<'PY'
import json
import sys
try:
    s = json.load(open('terraform.tfstate'))
    outputs = s.get('outputs', {})
    # Convert terraform state outputs to a similar shape as `terraform output -json`
    out = {}
    for k,v in outputs.items():
        out[k] = {'value': v.get('value')}
    print(json.dumps(out))
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# generate_inventory.sh
# Usage: generate_inventory.sh [ssm|ssh]
# Reads `terraform output -json` and writes an Ansible INI-style inventory to stdout.

MODE=${1:-ssm}
# Ensure we run from the script directory (terraform/aws)
SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform CLI not found in PATH" >&2
  exit 1
fi

TF_JSON=$(terraform output -json 2>/dev/null || true)
# If terraform CLI didn't return outputs (e.g. running from elsewhere or no access to backend),
# try to read local terraform.tfstate as a fallback.
if [[ -z "$TF_JSON" ]]; then
  if [[ -f "terraform.tfstate" ]]; then
    TF_JSON=$(python3 - <<'PY'
import json
import sys
try:
    s = json.load(open('terraform.tfstate'))
    outputs = s.get('outputs', {})
    # Convert terraform state outputs to a similar shape as `terraform output -json`
    out = {}
    for k, v in outputs.items():
        # Each output in state has a 'value' key already; preserve it
        out[k] = {'value': v.get('value')}
    sys.stdout.write(json.dumps(out))
except Exception as e:
    sys.stderr.write('Failed to parse terraform.tfstate: ' + str(e) + '\n')
    sys.exit(1)
PY
)
  fi
fi

if [[ -z "$TF_JSON" ]]; then
  echo "Could not read Terraform outputs — run 'terraform output -json' in terraform/aws or ensure terraform.tfstate exists" >&2
  exit 1
fi

# Helper to extract an output value using python (avoids jq dependency)
py_extract() {
  local key=$1
  python3 - <<PY
import sys, json
try:
    o = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = o.get('$key', {})
val = v.get('value') if isinstance(v, dict) else None
if val is None:
    sys.exit(0)
if isinstance(val, list):
    for item in val:
        print(item)
else:
    print(val)
PY
}

controller_ip=$(printf '%s' "$TF_JSON" | py_extract controller_private_ip || true)
readarray -t agent_ips <<<"$(printf '%s' "$TF_JSON" | py_extract agent_private_ips || true)"
bastion_ip=$(printf '%s' "$TF_JSON" | py_extract bastion_public_ip || true)
ssh_key_path=$(printf '%s' "$TF_JSON" | py_extract ssh_private_key_path || true)

echo "# Inventory generated from terraform outputs (mode=$MODE)"
echo

if [[ "$MODE" == "ssm" ]]; then
  # SSM mode: rely on connection plugin configuration in group_vars
  echo "[jenkins_controller]"
  if [[ -n "$controller_ip" ]]; then
    echo "controller ansible_host=${controller_ip}"
  else
    echo "# controller IP not found in terraform outputs"
  fi
  echo
  echo "[jenkins_agent]"
  if [[ ${#agent_ips[@]} -gt 0 ]]; then
    i=1
    for ip in "${agent_ips[@]}"; do
      echo "agent-${i} ansible_host=${ip}"
      i=$((i+1))
    done
  else
    echo "# no agent IPs found"
  fi
  echo
  echo "[all:vars]"
  echo "# Using SSM connection plugin — ensure group_vars enable SSM settings"
  echo "ansible_user=ansible"
  exit 0
fi

if [[ "$MODE" == "ssh" ]]; then
  echo "[bastion]"
  if [[ -n "$bastion_ip" ]]; then
    echo "bastion ansible_host=${bastion_ip} ansible_user=ubuntu"
  else
    echo "# bastion public IP not found"
  fi
  echo
  echo "[jenkins_controller]"
  if [[ -n "$controller_ip" ]]; then
    echo "controller ansible_host=${controller_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_key_path}"
  else
    echo "# controller IP not found"
  fi
  echo
  echo "[jenkins_agent]"
  if [[ ${#agent_ips[@]} -gt 0 ]]; then
    i=1
    for ip in "${agent_ips[@]}"; do
      echo "agent-${i} ansible_host=${ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_key_path}"
      i=$((i+1))
    done
  else
    echo "# no agent IPs found"
  fi

  echo
  echo "# If you need to route SSH via the bastion, set the following group var in your inventory or ansible.cfg"
  echo "# ansible_ssh_common_args='-o ProxyCommand=\"ssh -i ${ssh_key_path} -W %h:%p -q ubuntu@${bastion_ip}\"'"
  exit 0
fi

echo "Unknown mode: $MODE. Use 'ssm' or 'ssh'" >&2
exit 2
