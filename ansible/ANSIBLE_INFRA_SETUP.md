# Jenkins Ansible + AWS (t2.micro) Reference

This document consolidates the repository layout, infrastructure steps (Terraform), inventory-generation, Ansible Vault guidance, and recommended commands to provision AWS t2.micro instances and run the Ansible playbooks provided in this repository.

---
 # Jenkins Ansible + AWS Reference (Provision → Configure)

This document provides a single ordered workflow you can follow to provision AWS infrastructure (enterprise mode) with Terraform and configure Jenkins (controller + agents) using Ansible. It includes all manual steps you must run and where to supply secrets.

## Quick Checklist (short, copy-paste steps)

Follow these quick steps to run the end-to-end demo. For details and troubleshooting see the rest of this document.

1) Prepare local environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install ansible ansible-lint yamllint
# Optional: shellcheck (macOS: brew install shellcheck)
# Optional: terraform (install via package manager)
```

2) Vault and variables

```bash
./ansible/scripts/create_vault.sh inventories/group_vars/vault.yml
ansible-vault edit inventories/group_vars/vault.yml
# set jenkins_admin_password and any agent secrets
```

3) Provision infra (quick demo)

```bash
chmod +x ./demo_provision_and_configure.sh
./demo_provision_and_configure.sh --tfvars terraform/aws/terraform.tfvars --auto-approve --mode ssm --playbook controller
```

4) (If Terraform applied manually) Generate inventory

```bash
./terraform/aws/generate_inventory.sh ssm > inventories/generated.ini
```

5) Configure controller and agents

```bash
ansible-playbook -i inventories/generated.ini ansible/playbooks/controller.yml --vault-password-file ~/.vault_pass.txt
ansible-playbook -i inventories/generated.ini ansible/playbooks/agents.yml --vault-password-file ~/.vault_pass.txt
```

6) Verify and cleanup

```bash
terraform output -raw bastion_public_ip || true
terraform destroy -var-file=terraform.tfvars -auto-approve
```

See the full document below for explanations and troubleshooting.


Target architecture (what this repo creates)
- VPC with a public subnet (bastion) and private subnet (controller + agents)
- Bastion host in public subnet (SSH access) — optional when using SSM
- Controller and agent EC2 instances in private subnet with an IAM instance profile for SSM
- NAT Gateway (optional) for private subnet egress

Prerequisites (local)
- Install Terraform (v1.x) and add to PATH
- Install Ansible 2.9+ and `ansible-lint`
- Install `amazon.aws` collection (for SSM connection):

```bash
pip install ansible
ansible-galaxy collection install amazon.aws
pip install ansible-lint
```

- Ensure `terraform` and `python3` are available on your workstation
- Configure AWS credentials (one of):
  - `export AWS_ACCESS_KEY_ID=...` and `export AWS_SECRET_ACCESS_KEY=...` and optionally `AWS_REGION`
  - or use an AWS profile and set `AWS_PROFILE` environment variable

AWS account & IAM checklist
----------------------------
Before running Terraform you will need an AWS account and a user (or role) with sufficient permissions. For a minimal setup create an IAM user with programmatic access and attach the following managed policies (or equivalent fine-grained policies):

- `AmazonVPCFullAccess` (or necessary VPC permissions: VPC, Subnet, RouteTable, InternetGateway, EIP, NAT Gateway)
- `AmazonEC2FullAccess` (or minimal EC2 permissions: LaunchInstances, AllocateAddress, CreateKeyPair, etc.)
- `IAMFullAccess` (or minimal IAM: CreateRole, PutRolePolicy, CreateInstanceProfile)
- `AmazonSSMFullAccess` (required if you'll use SSM features from the controller; instances use `AmazonSSMManagedInstanceCore` via instance profile)

If you prefer least-privilege, scope policies to the specific actions in `terraform/aws/main.tf`.

Notes:
- Ensure your account has limits for EC2 in the chosen region and that `t2.micro` is available.
- Billing: running these EC2 instances will incur charges. Destroy resources after testing with `make destroy`.

Step 1 — Review and set Terraform variables (enterprise)
1. Open `terraform/aws/variables.tf` and review defaults. Important variables to set before apply:
   - `aws_region` (default `us-east-1`)
   - `instance_type` (default `t2.micro` — change for production)
   - `agent_count` (number of agents)
   - `admin_cidr` **(REQUIRED)**: set this to your office/VPN CIDR to restrict SSH/Jenkins access (do not keep `0.0.0.0/0` for production)
   - `enable_nat_gateway` (true/false) — set `true` if private instances need access to the internet to install packages

Example (override with environment or terraform.tfvars):

```hcl
admin_cidr = "203.0.113.0/24"
agent_count = 2
enable_nat_gateway = true
```

Step 2 — Initialize and apply Terraform (provision infra)
1. Change directory and initialize Terraform:

```bash
cd gitRepos/ansible-jenkins/terraform/aws
terraform init
```

2. (Optional) Review plan:

```bash
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
```

3. Apply (this creates the VPC, subnets, bastion, IAM, keys, controller, agents):

```bash
terraform apply -auto-approve
```

Environment variables examples
--------------------------------
You can provide AWS credentials via environment variables or profiles. Examples:

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1
# or
export AWS_PROFILE=my-org-admin
```

Vault password file
-------------------
To avoid interactive vault prompts, create a local vault password file readable only by you and pass it to the Makefile or Ansible commands:

```bash
echo 'your-vault-password' > ~/.vault_pass.txt
chmod 600 ~/.vault_pass.txt
# then
make configure VAULT_PASS_FILE=~/.vault_pass.txt
```

Manual step: after apply completes, Terraform prints outputs including `bastion_public_ip`, `controller_private_ip`, `agent_private_ips`, and `ssh_private_key_path`. Confirm the `ssh_private_key_path` file exists under `terraform/aws/ssh/` and has `0600` permissions.

Step 3 — Choose connection mode: SSM (recommended) or SSH via Bastion
- Recommended (SSM): safer (no inbound SSH rules required), audit-friendly, uses IAM + SSM.
- SSH via Bastion: legacy option or fallback. If you prefer this, ensure `admin_cidr` is restricted tightly.

Decide now which mode you'll use and follow the corresponding steps below.

Step 4A — Configure SSM mode (recommended)
1. Ensure Terraform applied IAM role `AmazonSSMManagedInstanceCore` to instances (the module attaches it by default).
2. Generate inventory in SSM mode:

```bash
cd gitRepos/ansible-jenkins/terraform/aws
../../ansible/script../../ansible/scripts/generate_inventory.sh ssm
```

3. Activate SSM group_vars (this tells Ansible to use the `aws_ssm` connection plugin):

```bash
mkdir -p ../../inventories/dev/group_vars
cp ../../inventories/group_vars/ssm.yml ../../inventories/dev/group_vars/
cp ../../inventories/group_vars/ssm-jenkins_controller.yml ../../inventories/dev/group_vars/jenkins_controller.yml
cp ../../inventories/group_vars/ssm-jenkins_agent.yml ../../inventories/dev/group_vars/jenkins_agent.yml
```

Manual step: ensure your workstation has AWS credentials able to start SSM sessions (the IAM user/role used locally must have `ssm:StartSession` or you can use AWS CLI SSO).

4. Verify connectivity over SSM (optional quick test):

```bash
# Verify SSM managed instance registration (replace INSTANCE_ID if needed)
aws ssm describe-instance-information --region ${AWS_REGION:-us-east-1}

# Or try Ansible ping using SSM connection plugin
ansible -i ../../inventories/dev -m ping controller-dev
```

Step 4B — Configure SSH via Bastion (fallback)
1. Generate inventory (SSH mode) which will include bastion and ProxyCommand entries:

```bash
cd gitRepos/ansible-jenkins/terraform/aws
../../ansible/script../../ansible/scripts/generate_inventory.sh ssh
```

2. Ensure the private key path printed by Terraform is present and readable, and that your `admin_cidr` allowed your client IP during provisioning.

Manual step: if your corporate network/proxy blocks outbound SSH forwarding, you may need to run Ansible from a network that can reach the bastion, or use session manager/SSM.

Step 5 — Create Vault file for secrets (required)
1. Create a vaulted variables file and set secrets (you will be prompted for a vault password):

```bash
cd gitRepos/ansible-jenkins
./ansible/scripts/create_vault.sh inventories/group_vars/vault.yml
ansible-vault edit inventories/group_vars/vault.yml
# set jenkins_admin_password and agent_secret
```

Manual step: store the vault password securely; you'll need it to run playbooks unless you use a `--vault-password-file` helper.

Step 6 — Install optional Galaxy roles and collections
1. Install roles and collections used by the playbooks/roles:

```bash
ansible-galaxy install -r requirements.yml
ansible-galaxy collection install amazon.aws
```

Makefile (convenience wrapper)
--------------------------------
A top-level `Makefile` is included to chain common workflows. Examples:

```bash
# Plan only
make plan

# Apply resources
make apply

# Provision (apply + wait)
make provision

# Generate inventory (default uses SSM; override with SSM_OR_SSH=ssh)
make generate-inventory

# Configure (runs controller + agents playbooks). Use VAULT_PASS_FILE to avoid prompts.
make configure VAULT_PASS_FILE=~/.vault_pass.txt

# Destroy resources
make destroy
```

User data and SSH hardening
--------------------------------
The Terraform `user_data` for bastion, controller, and agent instances now:

- Creates a non-root `ansible` user and populates `/home/ansible/.ssh/authorized_keys` with the generated public key (the private key is saved under `terraform/aws/ssh/`).
- Adds `ansible` to the `sudo` group so Ansible can `become` for privileged tasks.
- Attempts to install `amazon-ssm-agent` (if available) so SSM mode works on fresh images.
- Disables `PasswordAuthentication` and `PermitRootLogin` in `sshd_config` for basic SSH hardening.

If you rely on SSH via the bastion, ensure `admin_cidr` is set appropriately and you use the generated private key. If you prefer SSM (recommended), run `make generate-inventory` and `make configure`.

Groovy init scripts (Jenkins bootstrap)
--------------------------------
Two Groovy init scripts are provided and will be deployed by the `jenkins_controller` role:

- `roles/jenkins_controller/templates/init.groovy.d/01-create-admin.groovy.j2` — creates an initial admin user using `jenkins_admin_user` and `jenkins_admin_password` (populate via Vault).
- `roles/jenkins_controller/templates/init.groovy.d/02-install-plugins.groovy.j2` — installs a minimal list of plugins controlled by `jenkins_plugins` (set in `group_vars` or role defaults).

Notes:
- These init scripts are templated; set `jenkins_admin_password` via Ansible Vault and `jenkins_plugins` in `inventories/group_vars/*` or role defaults before running the controller playbook.
- The Groovy scripts are idempotent and will only create users or install plugins if they are missing.


Step 7 — Run Ansible playbooks to configure Jenkins
1. Run the controller role (creates Jenkins service, deploys config):

```bash
ansible-playbook -i inventories/dev playbooks/controller.yml --ask-vault-pass
```

2. Run the agent role:

```bash
ansible-playbook -i inventories/dev playbooks/agents.yml --ask-vault-pass
```

Manual step: watch Ansible run for failures (network, package repos). If package installs fail due to NAT missing, set `enable_nat_gateway=true` and re-run Terraform (or temporarily allow egress to apt repositories).

Step 8 — Post-configuration verification (manual checks)
- Controller: visit Jenkins UI at `http://<bastion-ip-or-loadbalancer>:8080` or, if using private VPC and SSM, use port-forwarding or temporary SG rule to access it.
- Agents: check agent service is running on agents. Example via Ansible (SSM or SSH):

```bash
ansible -i inventories/dev -m shell -a 'systemctl status jenkins-agent' jenkins_agent
```

Step 9 — Cleanup when finished (optional)
1. Destroy Terraform-managed resources:

```bash
cd gitRepos/ansible-jenkins/terraform/aws
terraform destroy -auto-approve
```

Manual step: remove any sensitive files created locally (private key under `terraform/aws/ssh/` and any unencrypted files). The repo includes `terraform/aws/ssh/.gitignore` — ensure you do not commit keys.

Troubleshooting notes
- If Ansible cannot connect in SSM mode, verify the instance shows up in SSM (`aws ssm describe-instance-information`) and your local AWS credentials have SSM `StartSession` permissions.
- If package installs fail on private instances, verify NAT Gateway is created and route tables are set correctly.
- If inventory generator fails, run `terraform output -json` and inspect the JSON for expected keys: `bastion_public_ip`, `controller_private_ip`, `agent_private_ips`, `ssh_private_key_path`.

Security reminders
- Do not commit `inventories/dev/group_vars/vault.yml` or the private key files. Use Ansible Vault and restrict access to private keys.
- Limit `admin_cidr` to required IP ranges.

Appendix: quick commands summary

```bash
# Provision infrastructure
cd gitRepos/ansible-jenkins/terraform/aws
terraform init && terraform apply -auto-approve

# Generate inventory (ssm recommended)
../../ansible/script../../ansible/scripts/generate_inventory.sh ssm

# Copy ssm group_vars into the dev inventory group_vars (one-time)
mkdir -p ../../inventories/dev/group_vars
cp ../../inventories/group_vars/ssm.yml ../../inventories/dev/group_vars/
cp ../../inventories/group_vars/ssm-jenkins_controller.yml ../../inventories/dev/group_vars/jenkins_controller.yml
cp ../../inventories/group_vars/ssm-jenkins_agent.yml ../../inventories/dev/group_vars/jenkins_agent.yml

# Create vault and edit secrets
../ansible/scripts/create_vault.sh ../../inventories/group_vars/vault.yml
ansible-vault edit ../../inventories/group_vars/vault.yml

# Run Ansible to configure controller and agents
cd ../..
ansible-playbook -i inventories/dev playbooks/controller.yml --ask-vault-pass
ansible-playbook -i inventories/dev playbooks/agents.yml --ask-vault-pass
```

---

Keep this file as the single, up-to-date reference for provisioning and configuring the Jenkins environment with Ansible on AWS.

## Demo Script (convenience)

A convenience script is provided to run a typical end-to-end demo: provision infra with Terraform, wait for instances/SSM, generate the inventory, and run the Ansible playbook.

Path: `./demo_provision_and_configure.sh`

Quick usage:

```bash
# make executable once
chmod +x ./demo_provision_and_configure.sh

# Run interactive terraform apply, then configure controller via SSM
./demo_provision_and_configure.sh --tfvars terraform/aws/terraform.tfvars --mode ssm --playbook controller

# Non-interactive terraform + vault password file
./demo_provision_and_configure.sh --tfvars terraform/aws/terraform.tfvars --auto-approve --mode ssm --playbook controller --vault-pass-file ~/.vault_pass.txt
```

Notes:
- The script defaults to `ssm` mode and the `controller` playbook.
- Wait time after `terraform apply` defaults to 120 seconds — you can tweak with `--wait-seconds`.
- Ensure AWS credentials are available to Terraform and (if using SSM) to the local `aws` CLI for inventory checks.
