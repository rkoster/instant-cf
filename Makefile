.DEFAULT_GOAL := help

.PHONY: help sync generate validate-templates

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

generate: validate-templates ## Generate manifests (Milestone 1: validates templates only)
	@echo "Note: Phase-specific manifest generation will be implemented in Milestone 2+"
	@echo "Current milestone (1) provides template foundation and validation."
	@echo ""
	@echo "Next steps:"
	@echo "  - Milestone 2: Implement phase1/database.yml template"
	@echo "  - Milestone 3+: Add control and runtime templates"
