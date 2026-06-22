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
	$(call tfvar, CONSUL_VERSION) \
	$(call tfvar, NOMAD_VERSION) \
	$(call tfvar, VAULT_VERSION) \
	$(call tfvar, SSH_PRIVATE_KEY) \
	$(call tfvar, SSH_BASTION_HOST) \
	$(call tfvar, SSH_BASTION_USER) \
	$(call tfvar, NOMAD_ADDRESS) \
	$(call tfvar, ACME_EMAIL) \
	$(call tfvar, INGRESS_IMAGE) \
	$(call tfvar, HCLOUD_TOKEN) \
	$(call tfvar, HCLOUD_ZONE) \
	$(call tfvar, HCLOUD_ZONE_ID) \
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
	@echo "No provider login required for baremetal (servers pre-provisioned; SSH key auth)."

.PHONY: switch
switch:
	$(tf_vars) $(TF) init -input=false -upgrade -reconfigure \
		-backend-config="bucket=$(S3_BUCKET)" \
		-backend-config="region=$(S3_REGION)" \
		-backend-config="access_key=$(S3_ACCESS_KEY)" \
		-backend-config="secret_key=$(S3_SECRET_KEY)" \
		-backend-config="endpoint=https://$(S3_ENDPOINT)"

.PHONY: init
init:
	$(tf_vars) $(TF) init -upgrade -reconfigure \
		-backend-config="bucket=$(S3_BUCKET)" \
		-backend-config="region=$(S3_REGION)" \
		-backend-config="access_key=$(S3_ACCESS_KEY)" \
		-backend-config="secret_key=$(S3_SECRET_KEY)" \
		-backend-config="endpoint=https://$(S3_ENDPOINT)"
	$(tf_vars) $(TF) apply $(TF_VAR_FILE_ARG) -target=module.init -input=false -compact-warnings

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
