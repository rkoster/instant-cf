#!/usr/bin/env bash
#
# generate-manifests.sh
# Generate instant-cf manifests for different phases using ytt
#

set -e

# Determine script directory (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Directories
TEMPLATES_DIR="${PROJECT_ROOT}/manifests/templates"
GENERATED_DIR="${PROJECT_ROOT}/manifests/generated"
CF_DEPLOYMENT_DIR="${PROJECT_ROOT}/manifests/cf-deployment"

# Ensure generated directory exists
mkdir -p "${GENERATED_DIR}"

# Color output for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Instant CF Manifest Generator ===${NC}"
echo ""

#
# Phase 1: Database manifest
#
echo -e "${BLUE}Generating Phase 1 Database manifest...${NC}"
ytt \
  -f "${TEMPLATES_DIR}/schema.yml" \
  -f "${TEMPLATES_DIR}/values.yml" \
  -f "${CF_DEPLOYMENT_DIR}/cf-deployment.yml" \
  -f "${TEMPLATES_DIR}/base/apply-use-postgres.yml" \
  -f "${TEMPLATES_DIR}/base/apply-bosh-lite.yml" \
  -f "${TEMPLATES_DIR}/phases/phase1/database.yml" \
  > "${GENERATED_DIR}/instant-cf-phase1-database.yml"

echo -e "${GREEN}✓ Generated: manifests/generated/instant-cf-phase1-database.yml${NC}"
echo ""

#
# Summary
#
echo -e "${GREEN}=== Manifest Generation Complete ===${NC}"
echo "Generated manifests:"
echo "  - instant-cf-phase1-database.yml"
echo ""
echo "Next steps:"
echo "  1. Validate with: bosh interpolate manifests/generated/instant-cf-phase1-database.yml"
echo "  2. Review generated manifests in manifests/generated/"
