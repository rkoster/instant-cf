#!/usr/bin/env bash
#
# generate-manifests.sh
# Generate instant-cf manifests using a 2-step approach:
#   Step 1: Apply upstream ops files using bosh interpolate
#   Step 2: Apply ytt overlays for instance group transformations
#

set -e

# Determine script directory (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Directories
TEMPLATES_DIR="${PROJECT_ROOT}/manifests/templates"
GENERATED_DIR="${PROJECT_ROOT}/manifests/generated"
CF_DEPLOYMENT_DIR="${PROJECT_ROOT}/manifests/cf-deployment"
TMP_DIR="${PROJECT_ROOT}/.tmp"

# Ensure directories exist
mkdir -p "${GENERATED_DIR}"
mkdir -p "${TMP_DIR}"

# Color output for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Determine which component to generate (default: all)
COMPONENT="${1:-all}"

echo -e "${BLUE}=== Instant CF Manifest Generator ===${NC}"
echo -e "Strategy: 2-step generation (bosh interpolate → ytt overlays)"
echo ""

#
# Database manifest
#
generate_database() {
  echo -e "${BLUE}Generating Database manifest...${NC}"
  
  # Step 1: Apply upstream ops files with bosh interpolate
  echo -e "${YELLOW}  Step 1/2: Applying upstream ops files (bosh interpolate)...${NC}"
  bosh interpolate "${CF_DEPLOYMENT_DIR}/cf-deployment.yml" \
    -o "${CF_DEPLOYMENT_DIR}/operations/use-postgres.yml" \
    -o "${CF_DEPLOYMENT_DIR}/operations/bosh-lite.yml" \
    > "${TMP_DIR}/database-step1.yml"
  
  # Step 2: Apply ytt overlays for instance group transformations
  echo -e "${YELLOW}  Step 2/2: Applying ytt overlays for transformations...${NC}"
  ytt \
    -f "${TEMPLATES_DIR}/schema.yml" \
    -f "${TEMPLATES_DIR}/values.yml" \
    -f "${TMP_DIR}/database-step1.yml" \
    -f "${TEMPLATES_DIR}/base/remove-addons.yml" \
    -f "${TEMPLATES_DIR}/database/database.yml" \
    > "${GENERATED_DIR}/instant-cf-database.yml"
  
  echo -e "${GREEN}✓ Generated: manifests/generated/instant-cf-database.yml${NC}"
  echo ""
}

#
# Runtime manifest
#
generate_runtime() {
  echo -e "${BLUE}Generating Runtime manifest...${NC}"
  
  # Step 1: Apply upstream ops files with bosh interpolate
  echo -e "${YELLOW}  Step 1/2: Applying upstream ops files (bosh interpolate)...${NC}"
  bosh interpolate "${CF_DEPLOYMENT_DIR}/cf-deployment.yml" \
    -o "${CF_DEPLOYMENT_DIR}/operations/use-postgres.yml" \
    -o "${CF_DEPLOYMENT_DIR}/operations/bosh-lite.yml" \
    > "${TMP_DIR}/runtime-step1.yml"
  
  # Step 2: Apply ytt overlays for instance group transformations
  echo -e "${YELLOW}  Step 2/2: Applying ytt overlays for transformations...${NC}"
  ytt \
    -f "${TEMPLATES_DIR}/schema.yml" \
    -f "${TEMPLATES_DIR}/values.yml" \
    -f "${TMP_DIR}/runtime-step1.yml" \
    -f "${TEMPLATES_DIR}/base/remove-addons.yml" \
    -f "${TEMPLATES_DIR}/runtime/runtime.yml" \
    > "${GENERATED_DIR}/instant-cf-runtime.yml"
  
  echo -e "${GREEN}✓ Generated: manifests/generated/instant-cf-runtime.yml${NC}"
  echo ""
}

#
# Generate based on requested component
#
case "${COMPONENT}" in
  all)
    generate_database
    generate_runtime
    ;;
  database)
    generate_database
    ;;
  runtime)
    generate_runtime
    ;;
  *)
    echo -e "Unknown component: ${COMPONENT}"
    echo "Available components: all, database, runtime"
    exit 1
    ;;
esac

#
# Summary
#
echo -e "${GREEN}=== Manifest Generation Complete ===${NC}"
echo "Generated manifests:"
find "${GENERATED_DIR}" -maxdepth 1 -type f -name "*.yml" -printf "%f\n" | sed 's/^/  - /'
echo ""
echo "Next steps:"
echo "  1. Validate with: bosh interpolate manifests/generated/<manifest-name>.yml"
echo "  2. Review generated manifests in manifests/generated/"
