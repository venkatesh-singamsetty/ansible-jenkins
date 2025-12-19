# Scripts

This folder documents the canonical operational scripts provided by this repository and the small backward-compatible wrappers that remain for legacy invocations.

Structure
- `scripts/ansible/` — canonical Ansible helpers
  - `generate_inventory.sh` — Generate an inventory from Terraform outputs (SSM or SSH modes).
  - `create_vault.sh` — Helper to create an ansible-vault file with placeholder secrets.

- `scripts/ops/` — canonical operation helpers
  - `demo_provision_and_configure.sh` — End-to-end demo orchestration (terraform apply -> wait -> generate inventory -> run ansible).

Backward-compatible wrappers
- `scripts/create_vault.sh` — Thin wrapper that execs `scripts/ansible/create_vault.sh`.
- `scripts/demo_provision_and_configure.sh` — Thin wrapper that execs `scripts/ops/demo_provision_and_configure.sh`.
- `terraform/aws/generate_inventory.sh` — Thin wrapper that execs `scripts/ansible/generate_inventory.sh` (kept inside `terraform/aws` for convenience when running from that directory).

Recommended usage
- Prefer calling the canonical scripts under `scripts/ansible/` and `scripts/ops/`.
- Wrappers are kept for backward compatibility and CI pipelines that may reference older locations.

Examples

Run demo (recommended canonical path):

```bash
./scripts/ops/demo_provision_and_configure.sh --tfvars terraform/aws/terraform.tfvars --auto-approve --mode ssm --playbook controller
```

Generate inventory (canonical):

```bash
./scripts/ansible/generate_inventory.sh ssm
```

Create vault (canonical):

```bash
./scripts/ansible/create_vault.sh inventories/group_vars/vault.yml
```

Maintenance notes
- If you intend to remove wrappers, update README and CI first and ensure no external references remain.
- Run `shellcheck` on shell scripts to catch common issues. If `shellcheck` is not installed, use your package manager (`brew install shellcheck` on macOS).
