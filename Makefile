.DEFAULT_GOAL := help

.PHONY: help sync generate generate-phase1-database validate-templates

# Phase 1 Database template files (order matters for ytt overlays)
PHASE1_DB_YTT_FILES := \
	manifests/templates/schema.yml \
	manifests/templates/values.yml \
	manifests/templates/base/remove-addons.yml \
	manifests/templates/phases/phase1/database.yml

# Default target - show help
help: ## Show available commands
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

sync: ## Run vendir sync to update vendored dependencies
	@echo "Syncing vendored dependencies..."
	@devbox run vendir sync
	@echo "Sync complete!"

validate-templates: ## Validate YTT templates can be loaded
	@echo "Validating YTT templates..."
	@echo "  - Checking schema.yml and values.yml..."
	@devbox run -- ytt -f manifests/templates/schema.yml \
		-f manifests/templates/values.yml \
		--data-values-inspect > /dev/null || { echo "❌ Schema/values validation failed"; exit 1; }
	@echo "✅ Template validation successful"

generate: validate-templates ## Generate all manifests using generate-manifests.sh
	@echo "Generating manifests..."
	@devbox run -- ./scripts/generate-manifests.sh

generate-phase1-database: validate-templates ## Generate Phase 1 database manifest only
	@echo "Generating Phase 1 Database manifest..."
	@mkdir -p manifests/generated
	@devbox run -- ./scripts/generate-manifests.sh phase1-database
	@echo "✅ Generated: manifests/generated/instant-cf-phase1-database.yml"
