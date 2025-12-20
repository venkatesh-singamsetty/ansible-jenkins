# jenkins-ansible

Repository folder structure (top-level):

```
ansible-jenkins/
├─ ansible/                    # Ansible project (configs, playbooks, roles, inventories)
│  ├─ ansible.cfg               # Ansible project defaults
│  ├─ inventories/
│  ├─ dev/                     # Development inventory
│  │  └─ hosts.ini
│  ├─ prod/                    # Production inventory
│  │  └─ hosts.ini
│  └─ group_vars/              # Shared variables per group
├─ playbooks/
│  ├─ site.yml                 # Orchestrates controller + agents across inventory
│  ├─ controller.yml           # Applies controller role to controller hosts
│  └─ agents.yml               # Applies agent role to agent hosts
# jenkins-ansible

This repository is an opinionated Ansible scaffold to manage a Jenkins controller and Jenkins agents across `dev` and `prod` inventories. It also includes Terraform examples and helper scripts to provision AWS infrastructure and generate inventories (SSH or SSM).

**Top-level layout**
-- `ansible/ansible.cfg` — Ansible defaults (inventory, roles_path, forks, become).
-- `ansible/inventories/` — `dev/` and `prod/` inventories and `group_vars/` (environment-scoped variables).
-- `ansible/playbooks/` — `controller.yml`, `agents.yml`, `site.yml` orchestration playbooks.
-- `ansible/roles/` — `jenkins_controller/` and `jenkins_agent/` using a standard role layout (`tasks/`, `handlers/`, `defaults/`, `vars/`, `templates/`, `meta/`).
-- `terraform/aws/` — Terraform code to provision VPC, bastion, controller/agent instances, IAM role for SSM, and helper scripts (`generate_inventory.sh`).
-- `ansible/ANSIBLE_INFRA_SETUP.md` — ordered provision → configure walkthrough and troubleshooting guidance.

**Quick Start (two common flows)**n

- Option A — Static inventory (existing hosts):
  1. Edit `ansible/inventories/dev/hosts.ini` or `ansible/inventories/prod/hosts.ini` and `ansible/inventories/group_vars/*`.
  2. (Optional) Create vaulted secrets: `./ansible/scripts/create_vault.sh` or `ansible-vault create inventories/group_vars/vault.yml`.
  3. Run controller: `ansible-playbook -i ansible/inventories/dev ansible/playbooks/controller.yml`.
  4. Run agents: `ansible-playbook -i ansible/inventories/dev ansible/playbooks/agents.yml`.

- Option B — Terraform provisioned (AWS t2.micro recommended for demo):
  1. Change into `terraform/aws/` and update `variables.tf` (region, `admin_cidr`, `key_name`, instance type, agent count).
  2. Run `terraform init && terraform apply` (follow prompts). Wait ~1–2 minutes for cloud-init to finish.
  3. Generate inventory (SSM recommended):

```bash
cd terraform/aws
../../ansible/scripts/generate_inventory.sh ssm      # preferred: uses SSM Session Manager
# or
../../ansible/scripts/generate_inventory.sh ssh      # uses bastion + ProxyJump
```

  4. Run playbooks using the generated inventory, e.g.:

```bash
ansible-playbook -i terraform/aws/inventory ansible/playbooks/controller.yml --ask-vault-pass
ansible-playbook -i terraform/aws/inventory ansible/playbooks/agents.yml --ask-vault-pass
```

**Recommended connection method**
- Use SSM (`../../ansible/scripts/generate_inventory.sh ssm`) when possible — simpler and more secure for private instances. SSH via a bastion is available as a fallback.

**Prerequisites**
- `ansible` (latest stable). Install via `pip install ansible` or your package manager.
- `terraform` for `terraform/aws/` provisioning.
- `aws` CLI configured with credentials for your account (for Terraform/SSM operations).
- Optional for local role testing: `molecule`, `docker`, and `testinfra`.

**Secrets & Vault**
- Do NOT commit plaintext secrets. Use Ansible Vault for sensitive values (`jenkins_admin_password`, `agent_secret`).
- Helper: `scripts/ansible/create_vault.sh` creates `inventories/group_vars/vault.yml` for you.

**CI / Linting**
- A GitHub Actions workflow is included to run `terraform validate` and `ansible-lint` (`.github/workflows/ci.yml`).

**Where to find details**
-- Follow the step-by-step guide in `ansible/ANSIBLE_INFRA_SETUP.md` for a copyable provision → configure sequence, checks, and troubleshooting.
- Inventory generator: `ansible/scripts/generate_inventory.sh` (supports `ssm` and `ssh` modes).

**Security notes (must read before applying infra)**
- Set `admin_cidr` in Terraform variables before `terraform apply` to restrict management access.
- The Terraform code provisions a bastion host and enables an IAM instance profile for SSM (`AmazonSSMManagedInstanceCore`) so controller/agents can be managed privately.

**Recent improvements (implemented)**
- Hardened `user_data` in Terraform: creates a non-root `ansible` user, deploys the generated public key to `/home/ansible/.ssh/authorized_keys`, and performs basic SSH hardening (disables password auth and root login).
- `Makefile` at repo root: convenience targets `plan`, `apply`, `provision`, `generate-inventory`, `configure`, and `destroy` to chain Terraform and Ansible steps.
- Groovy init scripts added (templated): `roles/jenkins_controller/templates/init.groovy.d/01-create-admin.groovy.j2` and `02-install-plugins.groovy.j2` — these bootstrap the admin user and install plugins from `jenkins_plugins`.

If you'd like further automation (Makefile CI integration, hardened image builds, or extended Groovy logic), tell me which item to prioritize next.

**Demo Script**

- **Path:** `scripts/demo_provision_and_configure.sh`
- **Purpose:** Runs an end-to-end demo: Terraform apply → wait for cloud-init/SSM → generate inventory → run Ansible (controller by default).
- **Prereqs:** `terraform`, `ansible-playbook`, (optional) `aws` CLI, AWS credentials configured.
- **Quick run (make executable first):**

```bash
chmod +x scripts/demo_provision_and_configure.sh
./scripts/demo_provision_and_configure.sh --tfvars terraform/aws/terraform.tfvars --auto-approve --mode ssm --playbook controller
```

- **Non-interactive with vault file:**

```bash
./scripts/demo_provision_and_configure.sh --tfvars terraform/aws/terraform.tfvars --auto-approve --mode ssm --playbook controller --vault-pass-file ~/.vault_pass.txt
```

- **Notes:** Defaults to `ssm` mode and the `controller` playbook. Use `--mode ssh` to generate an SSH/bastion-style inventory.