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

tf_vars := HCLOUD_TOKEN=$(HCLOUD_TOKEN) \
	TF_VAR_environment=$(TERRAFORM_ENVIRONMENT) \
	$(call tfvar, PREFIX) \
	$(call tfvar, DOMAIN_NAME) \
	$(call tfvar, HCLOUD_TOKEN) \
	$(call tfvar, CONTAINER_REGISTRY) \
	$(call tfvar, CONTROL_SERVER_CLUSTER_SIZE) \
	$(call tfvar, CONTROL_SERVER_TYPE) \
	$(call tfvar, API_CLUSTER_SIZE) \
	$(call tfvar, API_SERVER_TYPE) \
	$(call tfvar, CLIENT_CLUSTER_SIZE) \
	$(call tfvar, CLIENT_SERVER_TYPE) \
	$(call tfvar, BUILD_CLUSTER_SIZE) \
	$(call tfvar, BUILD_SERVER_TYPE) \
	$(call tfvar, CLICKHOUSE_CLUSTER_SIZE) \
	$(call tfvar, REDIS_MANAGED)

.PHONY: provider-login
provider-login:
	@echo "No provider login required for Hetzner Cloud (token-based auth via HCLOUD_TOKEN env var)"

.PHONY: switch
switch:
	$(tf_vars) $(TF) init -input=false -upgrade -reconfigure \
		-backend-config="bucket=$(S3_BUCKET)" \
		-backend-config="region=$(S3_REGION)" \
		-backend-config="access_key=$(S3_ACCESS_KEY)" \
		-backend-config="secret_key=$(S3_SECRET_KEY)" \
		-backend-config="endpoints={s3=\"$(S3_ENDPOINT)\"}"

.PHONY: init
init:
	$(tf_vars) $(TF) init -upgrade -reconfigure \
		-backend-config="bucket=$(S3_BUCKET)" \
		-backend-config="region=$(S3_REGION)" \
		-backend-config="access_key=$(S3_ACCESS_KEY)" \
		-backend-config="secret_key=$(S3_SECRET_KEY)" \
		-backend-config="endpoints={s3=\"$(S3_ENDPOINT)\"}"
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
