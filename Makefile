# Makefile for provisioning and configuring Jenkins infra + Ansible
# Usage: make plan|apply|provision|generate-inventory|configure|destroy

TF_DIR=infra/aws
INVENTORY_PATH=$(TF_DIR)/inventory
VAULT_PASS_FILE?=
SSM_OR_SSH?=ssm

.PHONY: plan apply provision generate-inventory configure destroy clean

plan:
	@echo "==> Terraform plan (in ${TF_DIR})"
	cd ${TF_DIR} && terraform init -input=false && terraform plan -out=tfplan

apply:
	@echo "==> Terraform apply (in ${TF_DIR})"
	cd ${TF_DIR} && terraform init -input=false && terraform apply -auto-approve

provision: apply
	@echo "Provision complete. You may wait a minute for cloud-init to finish."

generate-inventory:
	@echo "==> Generating inventory (mode=${SSM_OR_SSH})"
	cd ${TF_DIR} && ./generate_inventory.sh ${SSM_OR_SSH}
	@echo "Inventory written to ${INVENTORY_PATH}"

configure: generate-inventory
	@echo "==> Running Ansible playbooks using inventory at ${INVENTORY_PATH}"
	if [ -n "${VAULT_PASS_FILE}" ]; then \
		VAULT_OPT="--vault-password-file=${VAULT_PASS_FILE}"; \
	else \
		VAULT_OPT="--ask-vault-pass"; \
	fi; \
	ansible-playbook -i ${INVENTORY_PATH} playbooks/controller.yml $$VAULT_OPT && \
	ansible-playbook -i ${INVENTORY_PATH} playbooks/agents.yml $$VAULT_OPT

destroy:
	@echo "==> Terraform destroy (in ${TF_DIR})"
	cd ${TF_DIR} && terraform destroy -auto-approve

clean:
	rm -f ${TF_DIR}/tfplan
	rm -f ${TF_DIR}/inventory
