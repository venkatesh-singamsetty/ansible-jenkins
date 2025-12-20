# jenkins-ansible

Opinionated Ansible + Terraform scaffold to provision and configure a Jenkins controller and agents.

This repository contains:
- `ansible/` — Ansible project (playbooks, roles, inventories, group_vars).
- `terraform/aws/` — Terraform code to provision VPC, bastion, controller/agents, and helper scripts.
- `demo_provision_and_configure.sh` — convenience script to run a typical end-to-end demo (terraform → inventory → ansible).

Which doc to read:
- For the full, canonical provision → configure, troubleshooting, and examples, read: `ansible/ANSIBLE_INFRA_SETUP.md` (includes a quick checklist).

Quick notes for a fresh, free-tier-friendly demo
- Create an IAM user named `devops-user` with Programmatic access and configure it locally with `aws configure`. Do NOT use root account credentials for automation.
- `terraform/aws/terraform.tfvars.example` contains conservative, free-tier-friendly defaults (e.g. `t2.micro`, single agent, NAT gateway disabled). Copy it to `terraform.tfvars` and edit `admin_cidr` before applying.

Repo-local setup (recommended)
- Create a Python venv inside the repo so tools don't install globally:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install ansible ansible-lint yamllint boto3 awscli markdownlint-cli
```
- This keeps `ansible`, `ansible-lint` and other tools isolated to this repo.

Demo networking note
- For a quick free-tier demo the Terraform variable `controller_public` can be set to `true` in `terraform/aws/terraform.tfvars` so the Jenkins controller receives a public IP and can download packages without a NAT Gateway. The repository includes the variable and a free-tier-friendly example in `terraform/aws/terraform.tfvars.example`.

Recommended workflow (quick)
1. Configure `aws` credentials for `devops-user` (do not use root credentials): `aws configure`
2. Copy `terraform/aws/terraform.tfvars.example` → `terraform/aws/terraform.tfvars` and set `admin_cidr` and `controller_public = true` for the demo.
3. Run Terraform (see `ansible/ANSIBLE_INFRA_SETUP.md` for full commands) or use the convenience script `./demo_provision_and_configure.sh`.

Quick start (summary)

1. Prepare environment and secrets (see `ansible/ANSIBLE_INFRA_SETUP.md` Quick Checklist section for commands).
2. Provision infra with Terraform or run the convenience demo script:

```bash
chmod +x ./demo_provision_and_configure.sh
./demo_provision_and_configure.sh --tfvars terraform/aws/terraform.tfvars --auto-approve --mode ssm --playbook controller
```

3. Generate inventory (if you ran Terraform manually): `./terraform/aws/generate_inventory.sh ssm > inventories/generated.ini`
4. Run Ansible playbooks: `ansible-playbook -i inventories/generated.ini ansible/playbooks/controller.yml --vault-password-file ~/.vault_pass.txt`

Notes & links
- Use SSM mode whenever possible (no inbound SSH required).
- Do not commit plaintext secrets; use Ansible Vault.
- See `ansible/ANSIBLE_INFRA_SETUP.md` for full procedure and the Quick Checklist section for a concise checklist.

If you'd like, I can also consolidate docs further (merge checklist into the main doc) or add a GitHub Actions workflow to run `ansible-lint` and `terraform fmt/validate` on PRs. Tell me which you'd prefer.

---

## Destroying the infrastructure

When you need to tear down the demo infrastructure (safe, planned destroy), the following sequence was used in this repository. Run these from `terraform/aws`:

```bash
cd terraform/aws
terraform init -input=false
if [ -f terraform.tfvars ]; then \
  terraform plan -destroy -var-file=terraform.tfvars -out=tfplan.destroy; \
else \
  terraform plan -destroy -out=tfplan.destroy; \
fi
# (optional) inspect the saved plan (first 300 lines):
terraform show -no-color tfplan.destroy | sed -n '1,300p'
# apply the saved destroy plan (auto-approve):
terraform apply -auto-approve tfplan.destroy
```

Notes:
- Terraform will save the plan as `tfplan.destroy` in `terraform/aws` for auditing before apply.
- The apply step in this repo removed all demo resources (VPC, subnets, EC2 instances, SGs, IAM roles, key pair, and the local PEM written by Terraform).
- The local PEM generated earlier (example path: `terraform/aws/ssh/jenkins-ansible-key-default.pem`) was removed by the destroy; if you need to keep private keys, export/store them securely before destroying (vault, encrypted S3, or local secure storage).
- Always verify in the AWS Console that resources are deleted and rotate any secrets if necessary.
