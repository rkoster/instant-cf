#!/usr/bin/env bash
#
# generate-manifests.sh
# Generate instant-cf manifests using a 2-phase approach:
#   Phase 1: Apply upstream ops files using bosh interpolate
#   Phase 2: Apply ytt overlays for instance group transformations
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

# Determine which phase to generate (default: all)
PHASE="${1:-all}"

echo -e "${BLUE}=== Instant CF Manifest Generator ===${NC}"
echo -e "Strategy: 2-phase generation (bosh interpolate → ytt overlays)"
echo ""

#
# Phase 1: Database manifest
#
generate_phase1_database() {
  echo -e "${BLUE}Generating Phase 1 Database manifest...${NC}"
  
  # Phase 1: Apply upstream ops files with bosh interpolate
  echo -e "${YELLOW}  Step 1/2: Applying upstream ops files (bosh interpolate)...${NC}"
  bosh interpolate "${CF_DEPLOYMENT_DIR}/cf-deployment.yml" \
    -o "${CF_DEPLOYMENT_DIR}/operations/use-postgres.yml" \
    -o "${CF_DEPLOYMENT_DIR}/operations/bosh-lite.yml" \
    > "${TMP_DIR}/phase1-database-step1.yml"
  
  # Phase 2: Apply ytt overlays for instance group transformations
  echo -e "${YELLOW}  Step 2/2: Applying ytt overlays for transformations...${NC}"
  ytt \
    -f "${TEMPLATES_DIR}/schema.yml" \
    -f "${TEMPLATES_DIR}/values.yml" \
    -f "${TMP_DIR}/phase1-database-step1.yml" \
    -f "${TEMPLATES_DIR}/base/remove-addons.yml" \
    -f "${TEMPLATES_DIR}/phases/phase1/database.yml" \
    > "${GENERATED_DIR}/instant-cf-phase1-database.yml"
  
  echo -e "${GREEN}✓ Generated: manifests/generated/instant-cf-phase1-database.yml${NC}"
  echo ""
}

#
# Phase 1: Runtime manifest
#
generate_phase1_runtime() {
  echo -e "${BLUE}Generating Phase 1 Runtime manifest...${NC}"
  
  # Phase 1: Apply upstream ops files with bosh interpolate
  echo -e "${YELLOW}  Step 1/2: Applying upstream ops files (bosh interpolate)...${NC}"
  bosh interpolate "${CF_DEPLOYMENT_DIR}/cf-deployment.yml" \
    -o "${CF_DEPLOYMENT_DIR}/operations/use-postgres.yml" \
    -o "${CF_DEPLOYMENT_DIR}/operations/bosh-lite.yml" \
    > "${TMP_DIR}/phase1-runtime-step1.yml"
  
  # Phase 2: Apply ytt overlays for instance group transformations
  echo -e "${YELLOW}  Step 2/2: Applying ytt overlays for transformations...${NC}"
  ytt \
    -f "${TEMPLATES_DIR}/schema.yml" \
    -f "${TEMPLATES_DIR}/values.yml" \
    -f "${TMP_DIR}/phase1-runtime-step1.yml" \
    -f "${TEMPLATES_DIR}/base/remove-addons.yml" \
    -f "${TEMPLATES_DIR}/phases/phase1/runtime.yml" \
    > "${GENERATED_DIR}/instant-cf-phase1-runtime.yml"
  
  echo -e "${GREEN}✓ Generated: manifests/generated/instant-cf-phase1-runtime.yml${NC}"
  echo ""
}

#
# Generate based on requested phase
#
case "${PHASE}" in
  all)
    generate_phase1_database
    generate_phase1_runtime
    ;;
  phase1-database)
    generate_phase1_database
    ;;
  phase1-runtime)
    generate_phase1_runtime
    ;;
  *)
    echo -e "Unknown phase: ${PHASE}"
    echo "Available phases: all, phase1-database, phase1-runtime"
    exit 1
    ;;
esac

#
# Summary
#
echo -e "${GREEN}=== Manifest Generation Complete ===${NC}"
echo "Generated manifests:"
ls -1 "${GENERATED_DIR}"/ | sed 's/^/  - /'
echo ""
echo "Next steps:"
echo "  1. Validate with: bosh interpolate manifests/generated/<manifest-name>.yml"
echo "  2. Review generated manifests in manifests/generated/"
