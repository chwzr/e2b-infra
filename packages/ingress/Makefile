ENV := $(shell cat ../../.last_used_env || echo "not-set")
-include ../../.env.${ENV}

PREFIX := $(strip $(subst ",,$(PREFIX)))

ifeq ($(PROVIDER),aws)
	REGISTRY_PREFIX := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(PREFIX)core
else ifneq (,$(filter $(PROVIDER),proxmox hetzner))
	REGISTRY_PREFIX := $(CONTAINER_REGISTRY_URL)/$(PREFIX)core
else
	REGISTRY_PREFIX := $(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/$(PREFIX)core
endif

.PHONY: build-and-upload
build-and-upload:
	docker buildx build --push \
		--platform linux/amd64 \
		-t $(REGISTRY_PREFIX)/ingress:latest \
		.
