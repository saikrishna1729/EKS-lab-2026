# EKS Lab 2026 — daily driver
#   make up LEVEL=200     create / update the lab cluster for a level
#   make verify LEVEL=200 run that level's checks
#   make down             tear everything down (always do this!)

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

ifneq (,$(wildcard ./lab.env))
include lab.env
else
include lab.env.example
endif
export

LEVEL ?= $(shell cat .lab/current-level 2>/dev/null || echo 100)
LEVEL_DIR := $(firstword $(wildcard levels/L$(LEVEL)-*))
TFVARS := $(abspath $(LEVEL_DIR)/lab.tfvars)
# Bootstrap runs as an admin identity: BOOTSTRAP_PROFILE (lab.env) or your default credentials
BOOTSTRAP_ENV := $(if $(BOOTSTRAP_PROFILE),env AWS_PROFILE=$(BOOTSTRAP_PROFILE),env -u AWS_PROFILE)
LAB_TF := terraform -chdir=terraform/envs/lab
DR_TF := terraform -chdir=terraform/envs/dr

export TF_VAR_region := $(AWS_REGION)
export TF_VAR_cluster_name := $(CLUSTER_NAME)
export TF_VAR_domain := $(DOMAIN)

.PHONY: help tools bootstrap images init up kubeconfig addons verify down nuke-check plan cost lint dr-up dr-down

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

tools: ## Install extra CLI tools with Homebrew
	brew install k9s stern argocd kubeconform infracost cosign hey kubent velero eks-node-viewer argoproj/tap/kubectl-argo-rollouts
	@echo "Optional: 'make tflint' (tflint is no longer in Homebrew; installed from its GitHub release)"

tflint: ## Optional: install tflint from its GitHub release into ~/.local/bin
	@V=$$(curl -sL https://api.github.com/repos/terraform-linters/tflint/releases/latest | jq -r .tag_name); \
	  ARCH=$$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'); OS=$$(uname -s | tr A-Z a-z); \
	  TMP=$$(mktemp -d); echo "Downloading tflint $$V ($$OS/$$ARCH)"; \
	  curl -sLo $$TMP/t.zip https://github.com/terraform-linters/tflint/releases/download/$$V/tflint_$${OS}_$${ARCH}.zip && \
	  curl -sLo $$TMP/sums https://github.com/terraform-linters/tflint/releases/download/$$V/checksums.txt && \
	  (cd $$TMP && grep " tflint_$${OS}_$${ARCH}.zip$$" sums | sed "s/tflint_$${OS}_$${ARCH}.zip/t.zip/" | shasum -a 256 -c -) && \
	  unzip -oq $$TMP/t.zip -d $$TMP && mkdir -p $$HOME/.local/bin && install -m 755 $$TMP/tflint $$HOME/.local/bin/tflint && \
	  rm -rf $$TMP && $$HOME/.local/bin/tflint --version && echo "Make sure ~/.local/bin is on your PATH"

bootstrap: ## One-time: state bucket, budget, ECR, IAM role (run as an admin identity)
	$(BOOTSTRAP_ENV) terraform -chdir=bootstrap init
	$(BOOTSTRAP_ENV) terraform -chdir=bootstrap apply \
	  -var region=$(AWS_REGION) -var alert_email=$(ALERT_EMAIL) \
	  -var domain=$(DOMAIN) -var github_repo=$(GITHUB_REPO)
	mkdir -p .lab
	$(BOOTSTRAP_ENV) terraform -chdir=bootstrap output -raw backend_hcl > .lab/backend.hcl
	@echo "Bootstrap done. Now configure the eks-lab profile — see bootstrap/README.md"

images: ## Build & push the sample app images (multi-arch) to ECR
	scripts/build-images.sh

init:
	@test -f .lab/backend.hcl || { echo "Run 'make bootstrap' first"; exit 1; }
	$(LAB_TF) init -upgrade -reconfigure -backend-config=$(abspath .lab/backend.hcl) -backend-config="key=lab/terraform.tfstate" >/dev/null

plan: init ## terraform plan for LEVEL
	$(LAB_TF) plan -var-file=$(TFVARS)

up: init ## Create/update the cluster for LEVEL, then install in-cluster add-ons
	@test -n "$(LEVEL_DIR)" || { echo "Unknown LEVEL=$(LEVEL)"; exit 1; }
	@echo ">>> Level $(LEVEL) using $(TFVARS)"
	$(LAB_TF) apply -auto-approve -var-file=$(TFVARS)
	echo $(LEVEL) > .lab/current-level
	$(MAKE) kubeconfig
	scripts/addons.sh $(LEVEL)

kubeconfig: ## Point kubectl at the lab cluster
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME) --alias $(CLUSTER_NAME)

addons: ## (Re)install in-cluster add-ons for LEVEL
	scripts/addons.sh $(LEVEL)

verify: ## Run the checks for LEVEL
	bash $(LEVEL_DIR)/verify.sh

down: init ## Remove LBs/PVCs/nodes created by K8s, destroy the cluster, then look for leftovers
	scripts/predestroy.sh || true
	$(LAB_TF) destroy -auto-approve -var-file=$(TFVARS)
	rm -f .lab/current-level
	scripts/nuke-check.sh

nuke-check: ## Look for billable leftovers tagged/created by the lab
	scripts/nuke-check.sh

cost: ## Estimate the monthly cost of LEVEL with infracost
	infracost breakdown --path terraform/envs/lab --terraform-var-file $(TFVARS)

lint: ## fmt, validate, tflint, kubeconform
	scripts/lint.sh

dr-up: ## L500: create the DR cluster in DR_REGION
	$(DR_TF) init -reconfigure -backend-config=$(abspath .lab/backend.hcl) -backend-config="key=dr/terraform.tfstate" >/dev/null
	TF_VAR_region=$(DR_REGION) TF_VAR_cluster_name=$(CLUSTER_NAME)-dr $(DR_TF) apply -auto-approve
	aws eks update-kubeconfig --region $(DR_REGION) --name $(CLUSTER_NAME)-dr --alias $(CLUSTER_NAME)-dr

dr-down: ## L500: destroy the DR cluster
	kubectl config use-context $(CLUSTER_NAME)-dr && scripts/predestroy.sh || true
	TF_VAR_region=$(DR_REGION) TF_VAR_cluster_name=$(CLUSTER_NAME)-dr $(DR_TF) destroy -auto-approve
	AWS_REGION=$(DR_REGION) scripts/nuke-check.sh
