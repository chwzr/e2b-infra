ENV := $(shell cat ../../.last_used_env || echo "not-set")
-include ../../.env.${ENV}

AWS_BUCKET_PREFIX ?= $(PREFIX)$(AWS_ACCOUNT_ID)-
GCP_BUCKET_PREFIX ?= $(GCP_PROJECT_ID)-
S3_BUCKET_PREFIX ?= $(PREFIX)$(S3_REGION)-

PLUGIN_NAME := nomad-nodepool-apm
BIN_DIR := bin
BINARY := $(BIN_DIR)/$(PLUGIN_NAME)

.PHONY: build
build:
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o $(BINARY) .

.PHONY: clean
clean:
	rm -rf $(BIN_DIR)

.PHONY: test
test:
	go test -v ./...

.PHONY: upload
upload:
	chmod +x $(BINARY)
ifeq ($(PROVIDER),aws)
	aws s3 cp $(BINARY) "s3://${AWS_BUCKET_PREFIX}fc-env-pipeline/nomad-nodepool-apm" --profile ${AWS_PROFILE} --cache-control "no-cache, max-age=0"
else ifneq (,$(filter $(PROVIDER),proxmox hetzner))
	AWS_ACCESS_KEY_ID=$(S3_ACCESS_KEY) AWS_SECRET_ACCESS_KEY=$(S3_SECRET_KEY) \
		aws s3 cp $(BINARY) "s3://$(S3_BUCKET_PREFIX)fc-env-pipeline/nomad-nodepool-apm" --endpoint-url "https://$(S3_ENDPOINT)" --cache-control "no-cache, max-age=0"
else
	gsutil -h "Cache-Control:no-cache, max-age=0" cp $(BINARY) "gs://${GCP_BUCKET_PREFIX}fc-env-pipeline/nomad-nodepool-apm"
endif

.PHONY: build-and-upload
build-and-upload: build upload
