#!/bin/bash

# Docker Build Script
# Measures build times and provides optimization recommendations

set -e

# Configuration (override with IMAGE_NAME / IMAGE_TAG env vars if needed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/VERSION"
METRICS_FILE="${SCRIPT_DIR}/build-metrics.csv"
PUSH_IMAGE=false

usage() {
  cat <<'USAGE'
Usage: ./build.sh [--push]

Options:
  --push    Push the built image (and latest tag) to Docker Hub after build.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH_IMAGE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${IMAGE_TAG:-}" ]]; then
  if [[ -f "${VERSION_FILE}" ]]; then
    IMAGE_TAG="$(<"${VERSION_FILE}")"
  else
    echo "ERROR: IMAGE_TAG not provided and ${VERSION_FILE} is missing" >&2
    exit 1
  fi
fi

IMAGE_NAME="${IMAGE_NAME:-glinsky/devsecops-multilang}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"

if [[ ! -s "${METRICS_FILE}" ]]; then
  echo "timestamp,image_tag,build_duration_seconds,image_size" > "${METRICS_FILE}"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Multi-Language Docker Build ===${NC}"
echo -e "${YELLOW}Building image: ${IMAGE_NAME}:${IMAGE_TAG}${NC}"

# Record start time
START_TIME=$(date +%s)

# Build the image
echo -e "${BLUE}Starting Docker build...${NC}"
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f "${DOCKERFILE}" "${SCRIPT_DIR}"

# Record end time
END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

echo -e "${GREEN} Build completed successfully!${NC}"
echo -e "${YELLOW}Build time: ${BUILD_TIME} seconds ($(($BUILD_TIME / 60))m $(($BUILD_TIME % 60))s)${NC}"

# Get image size
IMAGE_SIZE=$(docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "table {{.Size}}" | tail -n 1)
echo -e "${YELLOW}Image size: ${IMAGE_SIZE}${NC}"

# Tag as latest
docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:latest"

echo -e "${BLUE}=== Build Summary ===${NC}"
echo -e "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo -e "Size: ${IMAGE_SIZE}"
echo -e "Build Time: ${BUILD_TIME} seconds"
echo -e "Layers: $(docker history "${IMAGE_NAME}:${IMAGE_TAG}" --quiet | wc -l)"

if [[ "${PUSH_IMAGE}" == "true" ]]; then
  echo -e "${BLUE}Pushing ${IMAGE_NAME}:${IMAGE_TAG} to Docker Hub...${NC}"
  docker push "${IMAGE_NAME}:${IMAGE_TAG}"
  docker push "${IMAGE_NAME}:latest"
fi

echo -e "${GREEN}=== Next Steps ===${NC}"
echo -e "1. Run security scan: ./scan.sh"
echo -e "2. Test the image: docker run -it ${IMAGE_NAME}:${IMAGE_TAG} /bin/bash"
if [[ "${PUSH_IMAGE}" != "true" ]]; then
  echo -e "3. Push to registry: docker push ${IMAGE_NAME}:${IMAGE_TAG}"
else
  echo -e "3. Image pushed to registry (latest tag included)"
fi

# Save build metrics
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),${IMAGE_TAG},${BUILD_TIME},${IMAGE_SIZE}" >> "${METRICS_FILE}"
