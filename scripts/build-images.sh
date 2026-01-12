#!/usr/bin/env bash
#
# Build instant-cf container images using bob (BOSH OCI Builder)
#
# Usage:
#   ./scripts/build-images.sh <component>
#
# Examples:
#   ./scripts/build-images.sh database
#   ./scripts/build-images.sh runtime
#   ./scripts/build-images.sh control    # (planned for future milestone, not yet implemented)
#   ./scripts/build-images.sh all
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
    local component=$1
    
    local manifest="${MANIFESTS_DIR}/instant-cf-${component}.yml"
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
    #   --manifest manifests/generated/instant-cf-database.yml \
    #   --output ghcr.io/rkoster/instant-cf-database:latest
    
    if bob build --manifest "${manifest}" --output "${image}"; then
        log_success "Build complete: ${image}"
        
        # Verify image was created
        if docker images "${image}" | grep -F -q "${TAG}"; then
            log_success "Image verified in local registry"
            
            # Show image info
            log_info "Image details:"
            docker images "${image}" | grep -F "${TAG}"
            
            # Show image size
            local size
            size=$(docker images "${image}" --format "{{.Size}}")
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

# Build all images
build_all() {
    log_info "Building all instant-cf containers..."
    local failed=0
    
    # Build database
    if ! build_image "database"; then
        log_error "Database build failed"
        failed=$((failed + 1))
    fi
    
    log_info ""
    log_info "================================"
    log_info ""
    
    # Build runtime
    if ! build_image "runtime"; then
        log_error "Runtime build failed"
        failed=$((failed + 1))
    fi
    
    log_info ""
    log_info "================================"
    log_info ""
    
    # Note: Control build will be added in future milestone
    log_warning "Control container not yet implemented"
    log_info "Future milestone will add:"
    log_info "  - Control container (~35 colocated jobs)"
    
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
    if [[ $# -lt 1 ]]; then
        log_error "Usage: $0 <component>"
        echo ""
        echo "Examples:"
        echo "  $0 database  - Build database container"
        echo "  $0 runtime   - Build runtime container"
        echo "  $0 control   - Build control container (future milestone, not yet implemented)"
        echo "  $0 all       - Build all containers"
        exit 1
    fi
    
    local component=$1
    
    # Change to repository root (robust to symlinks)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    cd "${PROJECT_ROOT}"
    
    log_info "instant-cf Container Build"
    log_info "Registry: ${REGISTRY}"
    log_info "Tag: ${TAG}"
    log_info "Component: ${component}"
    log_info ""
    
    # Build requested component(s)
    case "${component}" in
        database)
            build_image "database"
            ;;
        runtime)
            build_image "runtime"
            ;;
        control)
            log_error "Control container not yet implemented (future milestone)"
            exit 1
            ;;
        all)
            build_all
            ;;
        *)
            log_error "Invalid component: ${component}"
            log_info "Valid components: database, runtime, control, all"
            exit 1
            ;;
    esac
}

main "$@"
