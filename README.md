# jenkins-ansible

Repository folder structure (top-level):

```
ansible-jenkins/
├─ ansible.cfg                 # Ansible project defaults
├─ inventories/
│  ├─ dev/                     # Development inventory
│  │  └─ hosts.ini
│  ├─ prod/                    # Production inventory
│  │  └─ hosts.ini
│  └─ group_vars/              # Shared variables per group
├─ playbooks/
│  ├─ site.yml                 # Orchestrates controller + agents across inventory
│  ├─ controller.yml           # Applies controller role to controller hosts
│  └─ agents.yml               # Applies agent role to agent hosts
├─ roles/
│  ├─ jenkins_controller/
│  │  ├─ tasks/
│  │  ├─ handlers/
│  │  ├─ defaults/
│  │  ├─ vars/
│  │  ├─ templates/
│  │  └─ molecule/             # Molecule test skeletons
│  └─ jenkins_agent/
│     ├─ tasks/
│     ├─ handlers/
│     ├─ defaults/
│     ├─ vars/
│     ├─ templates/
│     └─ molecule/
└─ README.md
```

Short comments and purpose (high-level):

- `ansible.cfg` contains project-wide settings (inventory path, role path, become settings).
- `inventories/` contains separate `dev` and `prod` inventories and `group_vars` for environment-scoped variables.
- `playbooks/` contains orchestration playbooks; run `ansible-playbook -i inventories/dev playbooks/controller.yml` to apply controller role.
- `roles/` contain reusable roles respecting Ansible best practices (tasks, handlers, defaults, vars, templates, meta).

See the sections below for usage, Vault guidance, testing, and next steps.

---

This repository contains an opinionated Ansible scaffold to manage a Jenkins controller and Jenkins agents across `dev` and `prod` inventories. It provides a starting point with recommended best-practices: separated inventories, `group_vars`, reusable roles, templates, handlers and Molecule test skeletons.

**Prerequisites**
- **Ansible:** 2.9+ (recommended latest stable). Install via `pip install ansible` or your platform package manager.
- **For tests (optional):** `pip install molecule docker molecule-docker testinfra` and Docker daemon running locally.
- **Permissions:** You need SSH access to target hosts and sudo privileges (or configure `become` accordingly).

... (rest of README omitted here for brevity; unchanged)
# jenkins-ansible

This repository contains an Ansible scaffold to manage a Jenkins controller and Jenkins agents across `dev` and `prod` inventories.

**Quick Start**
- **Inventory:** `inventories/dev/hosts.ini` and `inventories/prod/hosts.ini` (edit host IPs and users)
- **Playbooks:** `playbooks/controller.yml`, `playbooks/agents.yml`, and `playbooks/site.yml`
- **Roles:** `roles/jenkins_controller` and `roles/jenkins_agent`

**Run (example)**
1. Install dependencies: `pip install ansible molecule docker testinfra` (optional for local tests)
2. Run controller playbook against dev inventory:

```bash
ansible-playbook -i inventories/dev playbooks/controller.yml
```

3. Run agents playbook:

```bash
ansible-playbook -i inventories/dev playbooks/agents.yml
```

**Testing & Linting**
- Lint roles/playbooks: `ansible-lint playbooks/controller.yml` and `ansible-lint roles/jenkins_controller/tasks/main.yml`
- Molecule (local docker) (optional):

```bash
cd roles/jenkins_controller
molecule test

cd ../jenkins_agent
molecule test
```

**Secrets**
- Do NOT store real passwords in `group_vars` committed to the repo. Use Ansible Vault or your secrets manager and override `jenkins_admin_password`, `agent_secret`, and other sensitive values.
molecule test
# jenkins-ansible

This repository contains an opinionated Ansible scaffold to manage a Jenkins controller and Jenkins agents across `dev` and `prod` inventories. It provides a starting point with recommended best-practices: separated inventories, `group_vars`, reusable roles, templates, handlers and Molecule test skeletons.

**Prerequisites**
- **Ansible:** 2.9+ (recommended latest stable). Install via `pip install ansible` or your platform package manager.
- **For tests (optional):** `pip install molecule docker molecule-docker testinfra` and Docker daemon running locally.
- **Permissions:** You need SSH access to target hosts and sudo privileges (or configure `become` accordingly).

**Repository Layout**
- **`ansible.cfg`**: project-wide Ansible defaults.
- **`inventories/`**: `dev/` and `prod/` inventories with `hosts.ini` and `group_vars/`.
- **`playbooks/`**: `controller.yml`, `agents.yml`, `site.yml` orchestration playbooks.
- **`roles/`**: `jenkins_controller/` and `jenkins_agent/` with standard role structure (`tasks/`, `handlers/`, `defaults/`, `vars/`, `templates/`, `meta/`).
- **`roles/*/molecule/`**: Molecule scenario skeletons for local testing.

**Important files created**
- `ansible.cfg` — project defaults (inventory path, roles_path, forks, become settings).
- `inventories/dev/hosts.ini`, `inventories/prod/hosts.ini` — sample host entries (edit to your IPs/usernames).
- `inventories/group_vars/*.yml` — shared variables. **Do not** commit secrets.
- `playbooks/controller.yml`, `playbooks/agents.yml`, `playbooks/site.yml` — orchestration playbooks.
- `roles/jenkins_controller` — installs Jenkins, deploys `config.xml` template and restarts service.
- `roles/jenkins_agent` — installs Java, creates agent user, downloads `agent.jar`, and deploys a systemd unit.

**How to run**
- Run controller playbook against `dev` inventory:

```bash
ansible-playbook -i gitRepos/ansible-jenkins/inventories/dev gitRepos/ansible-jenkins/playbooks/controller.yml
```

- Run agents playbook against `dev` inventory:

```bash
ansible-playbook -i gitRepos/ansible-jenkins/inventories/dev gitRepos/ansible-jenkins/playbooks/agents.yml
```

Replace `gitRepos/ansible-jenkins` with the path relative to where you run the commands if you run them from the repository root.

**Group vars & secrets (recommended)**
- Use `inventories/group_vars/` for non-sensitive, environment-scoped values.
- For secrets (e.g., `jenkins_admin_password`, `agent_secret`) use Ansible Vault. Example:

```bash
ansible-vault create inventories/group_vars/vault.yml
# then edit and add: jenkins_admin_password: 'supersecret'
```

To run a playbook using the vault file:

```bash
ansible-playbook -i inventories/dev playbooks/controller.yml --ask-vault-pass
```

Or use `--vault-password-file` with a credentials helper script.

**Ansible Galaxy / External roles**
- You can add external roles to `requirements.yml` and install them with `ansible-galaxy install -r requirements.yml`.

Example `requirements.yml` snippet:

```yaml
- src: geerlingguy.java
	version: 2.0.0
```

Install:

```bash
ansible-galaxy install -r requirements.yml
```

**Linting & Testing**
- Lint playbooks and roles with `ansible-lint`:

```bash
pip install ansible-lint
ansible-lint playbooks/controller.yml
ansible-lint roles/jenkins_controller/tasks/main.yml
```

- Molecule (optional) — run role scenarios locally (requires Docker):

```bash
cd roles/jenkins_controller
molecule test

cd ../jenkins_agent
molecule test
```

Molecule scenarios included are skeletons. Update `molecule.yml`, `converge.yml` and `tests/` with platform-appropriate images and meaningful Testinfra assertions.

**Templates & Customization**
- `roles/jenkins_controller/templates/jenkins_config.xml.j2` is a minimal skeleton — modify for your security model, admin user hashing, and plugin settings.
- You can programmatically install plugins and create admin user via Groovy init scripts placed in `roles/jenkins_controller/files/` and deployed to `{{ jenkins_home }}/init.groovy.d/`.
- For agent provisioning, adjust `roles/jenkins_agent/templates/agent.service.j2` ExecStart to match your connection method (JNLP, SSH, Kubernetes, etc.).

**Platform considerations**
- The current role implementations assume Debian-based targets (apt). To support RHEL/CentOS, add conditional tasks using `ansible_facts['pkg_mgr']` and a `yum`/`dnf` flow for repositories and package names.

**CI recommendations (GitHub Actions example)**
- Run `ansible-lint` and optionally `molecule` in CI. Example job snippet:

```yaml
jobs:
	lint:
		runs-on: ubuntu-latest
		steps:
			- uses: actions/checkout@v4
			- uses: actions/setup-python@v4
				with:
					python-version: '3.x'
			- run: pip install ansible ansible-lint
			- run: ansible-lint playbooks/controller.yml
```

**Security notes**
- Never commit plaintext credentials. Use Ansible Vault or external secret stores (HashiCorp Vault, AWS Secrets Manager, Azure KeyVault).
- Limit access to the Jenkins controller and agent ports; use firewalls and private networks.

**Next steps (I can implement)**
- add an example `requirements.yml` and wire `ansible-galaxy` installs
- add an Ansible Vault example and helper script to encrypt/decrypt secrets
- implement plugin installation and Groovy init scripts to bootstrap admin user and initial jobs
- extend Molecule tests with real Testinfra checks and add CI integration

If you want me to implement one of the next steps, pick which one and I'll add it to the repo.