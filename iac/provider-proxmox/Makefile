ENV := $(shell cat ../../.last_used_env || echo "not-set")
ENV_FILE := ../../.env.${ENV}

-include ${ENV_FILE}

TF := $(shell which terraform)
TF_VAR_FILE := ./.terraform.${ENV}.tfvars
TF_VAR_FILE_ARG := $(if $(wildcard $(TF_VAR_FILE)),-var-file=$(TF_VAR_FILE))

SKIP_FMT ?= false
define tf_fmt
$(if $(filter true,$(SKIP_FMT)),,$(TF) fmt -recursive)
endef

define tfvar
$(if $(value $(strip $(1))), TF_VAR_$(shell echo $(strip $(1)) | tr A-Z a-z)=$($(strip $(1))))
endef

tf_vars := TF_VAR_environment=$(TERRAFORM_ENVIRONMENT) \
	$(call tfvar, PREFIX) \
	$(call tfvar, DOMAIN_NAME) \
	$(call tfvar, CONTAINER_REGISTRY_URL) \
	$(call tfvar, S3_ENDPOINT) \
	$(call tfvar, S3_ACCESS_KEY) \
	$(call tfvar, S3_SECRET_KEY) \
	$(call tfvar, S3_REGION) \
	$(call tfvar, PROXMOX_API_URL) \
	$(call tfvar, PROXMOX_API_TOKEN_ID) \
	$(call tfvar, PROXMOX_API_TOKEN_SECRET) \
	$(call tfvar, PROXMOX_TLS_INSECURE) \
	$(call tfvar, PVE_NODE) \
	$(call tfvar, PVE_STORAGE_POOL) \
	$(call tfvar, BASE_TEMPLATE) \
	$(call tfvar, BASE_TEMPLATE_VM_ID) \
	$(call tfvar, BRIDGE) \
	$(call tfvar, SUBNET_CIDR) \
	$(call tfvar, GATEWAY_IP) \
	$(call tfvar, SSH_PUBLIC_KEY) \
	$(call tfvar, SSH_PRIVATE_KEY) \
	$(call tfvar, SSH_BASTION_HOST) \
	$(call tfvar, SSH_BASTION_USER) \
	$(call tfvar, NOMAD_ADDRESS) \
	$(call tfvar, CONTROL_SERVER_CLUSTER_SIZE) \
	$(call tfvar, CONTROL_SERVER_CPU_CORES) \
	$(call tfvar, CONTROL_SERVER_MEMORY_MB) \
	$(call tfvar, CONTROL_SERVER_DISK_SIZE_GB) \
	$(call tfvar, API_CLUSTER_SIZE) \
	$(call tfvar, API_CPU_CORES) \
	$(call tfvar, API_MEMORY_MB) \
	$(call tfvar, API_DISK_SIZE_GB) \
	$(call tfvar, INGRESS_CPU_CORES) \
	$(call tfvar, INGRESS_MEMORY_MB) \
	$(call tfvar, INGRESS_DISK_SIZE_GB) \
	$(call tfvar, ORCHESTRATOR_CLUSTER_SIZE) \
	$(call tfvar, ORCHESTRATOR_CPU_CORES) \
	$(call tfvar, ORCHESTRATOR_MEMORY_MB) \
	$(call tfvar, ORCHESTRATOR_DISK_SIZE_GB) \
	$(call tfvar, BUILD_CLUSTER_SIZE) \
	$(call tfvar, BUILD_CPU_CORES) \
	$(call tfvar, BUILD_MEMORY_MB) \
	$(call tfvar, BUILD_DISK_SIZE_GB) \
	$(call tfvar, CLICKHOUSE_CLUSTER_SIZE) \
	$(call tfvar, CLICKHOUSE_CPU_CORES) \
	$(call tfvar, CLICKHOUSE_MEMORY_MB) \
	$(call tfvar, CLICKHOUSE_DISK_SIZE_GB) \
	$(call tfvar, CLICKHOUSE_DATA_VOLUME_SIZE_GB) \
	$(call tfvar, REDIS_MANAGED) \
	$(call tfvar, POSTGRES_CONNECTION_STRING) \
	$(call tfvar, SUPABASE_JWT_SECRETS) \
	$(call tfvar, LAUNCH_DARKLY_API_KEY) \
	$(call tfvar, GRAFANA_OTLP_URL) \
	$(call tfvar, GRAFANA_OTEL_COLLECTOR_TOKEN) \
	$(call tfvar, GRAFANA_USERNAME) \
	$(call tfvar, GRAFANA_LOGS_USER) \
	$(call tfvar, GRAFANA_LOGS_URL) \
	$(call tfvar, GRAFANA_LOGS_COLLECTOR_API_TOKEN)

.PHONY: provider-login
provider-login:
	@echo "No provider login required for Proxmox (API token auth via PROXMOX_API_TOKEN_* env vars)"

.PHONY: setup-pve-host
setup-pve-host:
	@test -n "$(PROXMOX_API_URL)" || { echo "PROXMOX_API_URL not set (check your .env)"; exit 1; }
	@ host=$$(echo "$(PROXMOX_API_URL)" | sed -E 's|^https?://([^:/]+).*|\1|'); \
	  ssh_target="$${PVE_SSH_USER:-root}@$${PVE_SSH_HOST:-$$host}"; \
	  echo "==> Copying setup-pve-host.sh to $$ssh_target"; \
	  scp scripts/setup-pve-host.sh "$$ssh_target:/tmp/setup-pve-host.sh"; \
	  echo "==> Running setup-pve-host.sh on $$ssh_target"; \
	  ssh "$$ssh_target" "BRIDGE='$(BRIDGE)' SUBNET_CIDR='$(SUBNET_CIDR)' GATEWAY_IP='$(GATEWAY_IP)' bash /tmp/setup-pve-host.sh"

.PHONY: switch
switch:
	$(tf_vars) $(TF) init -input=false -upgrade -reconfigure \
		-backend-config="bucket=$(S3_BUCKET)" \
		-backend-config="region=$(S3_REGION)" \
		-backend-config="access_key=$(S3_ACCESS_KEY)" \
		-backend-config="secret_key=$(S3_SECRET_KEY)" \
		-backend-config="endpoints={s3=\"https://$(S3_ENDPOINT)\"}"

.PHONY: init
init:
	$(tf_vars) $(TF) init -upgrade -reconfigure \
		-backend-config="bucket=$(S3_BUCKET)" \
		-backend-config="region=$(S3_REGION)" \
		-backend-config="access_key=$(S3_ACCESS_KEY)" \
		-backend-config="secret_key=$(S3_SECRET_KEY)" \
		-backend-config="endpoints={s3=\"https://$(S3_ENDPOINT)\"}"
	$(tf_vars) $(TF) apply -target=module.init -input=false -compact-warnings

.PHONY: plan
plan:
	@ printf "Planning Terraform for env: `tput setaf 2``tput bold`$(ENV)`tput sgr0`\n\n"
	@ $(call tf_fmt)
	@ $(tf_vars) $(TF) plan $(TF_VAR_FILE_ARG) -out=.tfplan.$(ENV) -input=false -compact-warnings -parallelism=20

.PHONY: plan-only-jobs
plan-only-jobs:
	@ printf "Planning Terraform for env: `tput setaf 2``tput bold`$(ENV)`tput sgr0`\n\n"
	$(call tf_fmt)
	@ $(tf_vars) $(TF) plan $(TF_VAR_FILE_ARG) -out=.tfplan.$(ENV) -input=false -compact-warnings -parallelism=20 -target=module.nomad

.PHONY: plan-without-jobs
plan-without-jobs:
	@ printf "Planning Terraform for env: `tput setaf 2``tput bold`$(ENV)`tput sgr0`\n\n"
	$(eval TARGET := $(shell cat main.tf | grep "^module" | awk '{print $$2}' | tr ' ' '\n' | grep -v -e "nomad" | awk '{print "-target=module." $$0 ""}' | xargs))
	@ $(tf_vars) $(TF) plan $(TF_VAR_FILE_ARG) -out=.tfplan.$(ENV) -input=false -compact-warnings -parallelism=20 $(TARGET)

.PHONY: apply
apply:
	@ printf "Applying Terraform for env: `tput setaf 2``tput bold`$(ENV)`tput sgr0`\n\n"
	@ $(tf_vars) $(TF) apply -auto-approve -input=false -compact-warnings -parallelism=20 .tfplan.$(ENV)

.PHONY: apply-init
apply-init:
	@ $(tf_vars) $(TF) apply $(TF_VAR_FILE_ARG) -target=module.init -auto-approve -input=false -compact-warnings

.PHONY: destroy
destroy:
	@ printf "Destroying Terraform for env: `tput setaf 2``tput bold`$(ENV)`tput sgr0`\n\n"
	@ $(tf_vars) $(TF) destroy $(TF_VAR_FILE_ARG)
