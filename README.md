# jenkins-ansible

Opinionated Ansible + Terraform scaffold to provision and configure a Jenkins controller and agents.

This repository contains:
- `ansible/` — Ansible project (playbooks, roles, inventories, group_vars).
- `terraform/aws/` — Terraform code to provision VPC, bastion, controller/agents, and helper scripts.
- `demo_provision_and_configure.sh` — convenience script to run a typical end-to-end demo (terraform → inventory → ansible).

Which doc to read:
- For the full, canonical provision → configure walkthrough, troubleshooting, and examples, read: `ansible/ANSIBLE_INFRA_SETUP.md` (includes a quick checklist).

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
-- See `ansible/ANSIBLE_INFRA_SETUP.md` for full procedure and the Quick Checklist section for a concise checklist.

If you'd like, I can also consolidate docs further (merge checklist into the main doc) or add a GitHub Actions workflow to run `ansible-lint` and `terraform fmt/validate` on PRs. Tell me which you'd prefer.