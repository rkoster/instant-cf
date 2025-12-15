.DEFAULT_GOAL := help

.PHONY: help sync generate

# Default target - show help
help: ## Show available commands
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

sync: ## Run vendir sync to update vendored dependencies
	@echo "Syncing vendored dependencies..."
	@devbox run vendir sync
	@echo "Sync complete!"

generate: ## Generate manifests (placeholder for future implementation)
	@echo "Generate target is not yet implemented"
	@echo "This will be used to generate Cloud Foundry deployment manifests"
	@exit 1
