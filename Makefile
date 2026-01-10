.DEFAULT_GOAL := help

.PHONY: help sync generate generate-database generate-runtime validate-templates build-database build-runtime lint-scripts

# Default target - show help
help: ## Show available commands
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

sync: ## Run vendir sync to update vendored dependencies
	@echo "Syncing vendored dependencies..."
	@devbox run vendir sync
	@echo "Sync complete!"

validate-templates: generate ## Validate generated manifests are up to date
	@echo "Validating generated manifests are up to date..."
	@if ! git diff --exit-code manifests/generated/; then \
		echo "❌ Generated manifests have uncommitted changes. Please commit them."; \
		git diff manifests/generated/; \
		exit 1; \
	fi
	@echo "✅ Generated manifests are up to date"

generate: ## Generate all manifests using generate-manifests.sh
	@echo "Generating manifests..."
	@devbox run -- ./scripts/generate-manifests.sh

generate-database: ## Generate database manifest only
	@echo "Generating Database manifest..."
	@mkdir -p manifests/generated
	@devbox run -- ./scripts/generate-manifests.sh database
	@echo "✅ Generated: manifests/generated/instant-cf-database.yml"

generate-runtime: ## Generate runtime manifest only
	@echo "Generating Runtime manifest..."
	@mkdir -p manifests/generated
	@devbox run -- ./scripts/generate-manifests.sh runtime
	@echo "✅ Generated: manifests/generated/instant-cf-runtime.yml"

build-database: generate-database ## Build database container with bob
	@echo "Building Database container..."
	@devbox run -- ./scripts/build-images.sh database

build-runtime: generate-runtime ## Build runtime container with bob
	@echo "Building Runtime container..."
	@devbox run -- ./scripts/build-images.sh runtime

lint-scripts: ## Run shellcheck on all bash scripts
	@echo "Linting bash scripts..."
	@devbox run -- shellcheck .github/scripts/*.sh scripts/*.sh
	@echo "✅ All scripts passed shellcheck"
