#!/usr/bin/env bash
#
# Build instant-cf container images using bob (BOSH OCI Builder)
#
# Usage:
#   ./scripts/build-images.sh <phase> <component>
#
# Examples:
#   ./scripts/build-images.sh phase1 database
#   ./scripts/build-images.sh phase1 control
#   ./scripts/build-images.sh phase1 runtime
#   ./scripts/build-images.sh phase1 all
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REGISTRY="${REGISTRY:-ghcr.io/rkoster}"
TAG="${TAG:-latest}"
MANIFESTS_DIR="manifests/generated"

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

# Check if bob is available
check_bob() {
    if ! command -v bob &> /dev/null; then
        log_error "bob (BOSH OCI Builder) not found in PATH"
        log_info "bob is expected to be available at: https://github.com/rkoster/bosh-oci-builder"
        log_info ""
        log_info "Installation options:"
        log_info "  1. Install bob manually and add to PATH"
        log_info "  2. Add bob to devbox.json when it becomes available in nixpkgs"
        log_info "  3. Install from source: go install github.com/rkoster/bosh-oci-builder/cmd/bob@latest"
        log_info ""
        return 1
    fi
    return 0
}

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found in PATH"
        log_info "Please install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon not running"
        log_info "Please start Docker daemon"
        return 1
    fi
    
    return 0
}

# Build a single container image
build_image() {
    local phase=$1
    local component=$2
    
    local manifest="${MANIFESTS_DIR}/instant-cf-${phase}-${component}.yml"
    local image="${REGISTRY}/instant-cf-${component}:${TAG}"
    
    log_info "Building ${component} container..."
    log_info "  Manifest: ${manifest}"
    log_info "  Image: ${image}"
    
    # Check if manifest exists
    if [[ ! -f "${manifest}" ]]; then
        log_error "Manifest not found: ${manifest}"
        log_info "Run 'make generate' first to generate manifests"
        return 1
    fi
    
    # Validate manifest with bosh-cli
    log_info "Validating manifest with bosh-cli..."
    if ! bosh interpolate "${manifest}" > /dev/null 2>&1; then
        log_error "Manifest validation failed"
        log_info "Check manifest syntax: bosh interpolate ${manifest}"
        return 1
    fi
    log_success "Manifest validated"
    
    # Check prerequisites
    if ! check_bob; then
        log_error "Cannot build without bob"
        return 1
    fi
    
    if ! check_docker; then
        log_error "Cannot build without Docker"
        return 1
    fi
    
    # Build with bob
    log_info "Running bob build..."
    log_info "Command: bob build --manifest ${manifest} --output ${image}"
    
    # Expected bob command format based on ARCHITECTURE.md:
    # bob build \
    #   --manifest manifests/generated/instant-cf-phase1-database.yml \
    #   --output ghcr.io/rkoster/instant-cf-database:latest
    
    if bob build --manifest "${manifest}" --output "${image}"; then
        log_success "Build complete: ${image}"
        
        # Verify image was created
        if docker images "${image}" | grep -q "${TAG}"; then
            log_success "Image verified in local registry"
            
            # Show image info
            log_info "Image details:"
            docker images "${image}" | grep "${TAG}"
            
            # Show image size
            local size=$(docker images "${image}" --format "{{.Size}}" | head -1)
            log_info "Image size: ${size}"
        else
            log_warning "Image not found in local registry"
        fi
        
        return 0
    else
        log_error "Build failed"
        log_info ""
        log_info "Troubleshooting:"
        log_info "  - Check bob logs for errors"
        log_info "  - Verify manifest is valid: bosh interpolate ${manifest}"
        log_info "  - Check Docker is running: docker info"
        log_info "  - Try building with verbose output: bob build --verbose ..."
        return 1
    fi
}

# Build all Phase 1 images
build_phase1_all() {
    log_info "Building all Phase 1 containers..."
    local failed=0
    
    # Build database first (other components depend on it)
    if ! build_image "phase1" "database"; then
        log_error "Database build failed"
        ((failed++))
    fi
    
    log_info ""
    log_info "================================"
    log_info ""
    
    # Note: Control and runtime builds will be added in future milestones
    log_warning "Control and runtime containers not yet implemented"
    log_info "Current milestone (Milestone 3) focuses on database container only"
    log_info ""
    log_info "Future milestones will add:"
    log_info "  - Milestone 4: runtime container (diego-cell)"
    log_info "  - Milestone 5: control container (~35 colocated jobs)"
    log_info "  - Milestone 6: Complete build infrastructure"
    
    if [[ ${failed} -eq 0 ]]; then
        log_success "All available builds completed successfully"
        return 0
    else
        log_error "${failed} build(s) failed"
        return 1
    fi
}

# Main script
main() {
    if [[ $# -lt 2 ]]; then
        log_error "Usage: $0 <phase> <component>"
        echo ""
        echo "Examples:"
        echo "  $0 phase1 database  - Build database container"
        echo "  $0 phase1 control   - Build control container (future)"
        echo "  $0 phase1 runtime   - Build runtime container (future)"
        echo "  $0 phase1 all       - Build all Phase 1 containers"
        exit 1
    fi
    
    local phase=$1
    local component=$2
    
    # Validate phase
    if [[ "${phase}" != "phase1" ]]; then
        log_error "Invalid phase: ${phase}"
        log_info "Currently only 'phase1' is supported"
        exit 1
    fi
    
    # Change to repository root
    cd "$(dirname "$0")/.."
    
    log_info "instant-cf Container Build"
    log_info "Registry: ${REGISTRY}"
    log_info "Tag: ${TAG}"
    log_info "Phase: ${phase}"
    log_info "Component: ${component}"
    log_info ""
    
    # Build requested component(s)
    case "${component}" in
        database)
            build_image "${phase}" "database"
            ;;
        control)
            log_error "Control container not yet implemented (Milestone 5)"
            exit 1
            ;;
        runtime)
            log_error "Runtime container not yet implemented (Milestone 4)"
            exit 1
            ;;
        all)
            build_phase1_all
            ;;
        *)
            log_error "Invalid component: ${component}"
            log_info "Valid components: database, control, runtime, all"
            exit 1
            ;;
    esac
}

main "$@"
