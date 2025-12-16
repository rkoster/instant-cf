.DEFAULT_GOAL := help

.PHONY: help sync generate generate-phase1-database validate-templates

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

generate-phase1-database: ## Generate Phase 1 database manifest only
	@echo "Generating Phase 1 Database manifest..."
	@mkdir -p manifests/generated
	@devbox run -- ./scripts/generate-manifests.sh phase1-database
	@echo "✅ Generated: manifests/generated/instant-cf-phase1-database.yml"
