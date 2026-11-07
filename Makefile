# Infrastructure Automation & CI/CD Platform — local developer entry points.
# Every target here is safe to run locally: nothing in this file runs
# `terraform apply` or `destroy`. Applies happen through GitHub Actions
# (or deliberately, by hand, following docs/setup.md).

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

TERRAFORM ?= terraform
TFLINT    ?= tflint
CHECKOV   ?= checkov
TRIVY     ?= trivy
HADOLINT  ?= hadolint
ACTIONLINT ?= actionlint
PYTHON    ?= python3

ENV       ?= dev
IMAGE     ?= icp-app:local
APP_DIR   := application
TF_ROOTS  := terraform/bootstrap terraform/environments/shared terraform/environments/dev terraform/environments/staging terraform/environments/prod
TF_MODULES := $(wildcard terraform/modules/*)
TF_EXAMPLES := $(wildcard terraform/modules/*/examples/*)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- Terraform
.PHONY: fmt
fmt: ## Format all Terraform files
	$(TERRAFORM) fmt -recursive terraform

.PHONY: fmt-check
fmt-check: ## Fail if any Terraform file is not formatted
	$(TERRAFORM) fmt -check -recursive -diff terraform

.PHONY: validate
validate: ## terraform init -backend=false + validate for every root, module and example
	@for d in $(TF_ROOTS) $(TF_MODULES) $(TF_EXAMPLES); do \
	  echo "==> validate $$d"; \
	  $(TERRAFORM) -chdir=$$d init -backend=false -input=false -no-color >/dev/null; \
	  $(TERRAFORM) -chdir=$$d validate -no-color; \
	done

.PHONY: tflint
tflint: ## Run TFLint (with AWS ruleset) over every root and module
	$(TFLINT) --init --config "$(CURDIR)/.tflint.hcl"
	$(TFLINT) --recursive --config "$(CURDIR)/.tflint.hcl" --chdir terraform

.PHONY: checkov
checkov: ## Run Checkov against all Terraform
	$(CHECKOV) --config-file .checkov.yaml

.PHONY: tf-test
tf-test: ## Run native `terraform test` suites in modules
	@for d in $(TF_MODULES); do \
	  if [ -d "$$d/tests" ]; then echo "==> terraform test $$d"; \
	    $(TERRAFORM) -chdir=$$d init -backend=false -input=false -no-color >/dev/null; \
	    $(TERRAFORM) -chdir=$$d test -no-color; fi; \
	done

.PHONY: plan
plan: ## terraform plan for ENV (needs AWS credentials + backend.hcl). Never applies.
	./scripts/tf.sh plan $(ENV)

# -------------------------------------------------------------- Application
.PHONY: venv
venv: ## Create application virtualenv with dev dependencies
	$(PYTHON) -m venv $(APP_DIR)/.venv
	$(APP_DIR)/.venv/bin/pip install -q --upgrade pip
	$(APP_DIR)/.venv/bin/pip install -q -r $(APP_DIR)/requirements-dev.txt

.PHONY: app-lint
app-lint: ## Ruff lint + format check
	cd $(APP_DIR) && .venv/bin/ruff check . && .venv/bin/ruff format --check .

.PHONY: app-test
app-test: ## Unit tests with coverage
	cd $(APP_DIR) && .venv/bin/pytest tests/unit

.PHONY: app-run
app-run: ## Run the Flask API locally on :8080 (dev server)
	cd $(APP_DIR) && APP_ENV=local LOG_LEVEL=DEBUG PYTHONPATH=src .venv/bin/flask --app app:create_app run --port 8080

# ------------------------------------------------------------------- Docker
.PHONY: hadolint
hadolint: ## Lint the Dockerfile
	$(HADOLINT) $(APP_DIR)/Dockerfile

.PHONY: docker-build
docker-build: ## Build the application image
	docker build --build-arg APP_VERSION=$$(git rev-parse --short HEAD 2>/dev/null || echo dev) -t $(IMAGE) $(APP_DIR)

.PHONY: docker-smoke
docker-smoke: ## Run the image and probe /health, /version, /status
	./scripts/container-smoke-test.sh $(IMAGE)

.PHONY: trivy
trivy: ## Scan the built image (HIGH/CRITICAL, fixed vulns fail)
	$(TRIVY) image --ignorefile .trivyignore --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

# --------------------------------------------------------------- Workflows
.PHONY: actionlint
actionlint: ## Validate GitHub Actions workflows
	$(ACTIONLINT)

.PHONY: shellcheck
shellcheck: ## Lint shell scripts
	shellcheck scripts/*.sh

# ------------------------------------------------------------- Aggregates
.PHONY: ci
ci: fmt-check validate tflint checkov tf-test app-lint app-test actionlint shellcheck ## Everything that runs without AWS or Docker

.PHONY: clean
clean: ## Remove local caches (NOT state; state lives in S3)
	find terraform -type d -name .terraform -prune -exec rm -rf {} +
	rm -rf $(APP_DIR)/.pytest_cache $(APP_DIR)/.ruff_cache $(APP_DIR)/.coverage reports
