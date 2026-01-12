#!/usr/bin/env bash
# tag-and-push-image.sh
#
# Tags and pushes a Docker image created by bob with multiple metadata tags
#
# Usage:
#   tag-and-push-image.sh <image-name> <metadata-tags>
#
# Arguments:
#   image-name:     Name to search for in docker images (e.g., "instant-cf-database")
#   metadata-tags:  Newline-separated list of tags to apply and push
#
# Environment:
#   - Expects docker CLI to be available in PATH
#   - Expects user to be authenticated to the registry

set -euo pipefail

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <image-name> <metadata-tags>" >&2
    exit 1
fi

IMAGE_NAME="$1"
METADATA_TAGS="$2"

# Find the image that bob created and tag it with all metadata tags
# Bob may create the image with a different name than expected
IMAGE_ID=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "${IMAGE_NAME}" | grep -v 'none' | head -1)

if [ -z "${IMAGE_ID}" ]; then
    echo "Error: Could not find ${IMAGE_NAME} image" >&2
    docker images
    exit 1
fi

echo "Found image: ${IMAGE_ID}"

# Tag and push with all metadata tags
echo "${METADATA_TAGS}" | while read -r tag; do
    if [ -n "${tag}" ]; then
        echo "Tagging ${IMAGE_ID} as ${tag}"
        docker tag "${IMAGE_ID}" "${tag}"
        echo "Pushing ${tag}"
        docker push "${tag}"
    fi
done

echo "✅ Successfully tagged and pushed ${IMAGE_NAME}"
