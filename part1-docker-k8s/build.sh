#!/bin/bash

# DevSecOps Evaluation - Docker Build Script
# Measures build times and provides optimization recommendations

set -e

# Configuration
IMAGE_NAME="evgenyglinsky/devsecops-multilang"
TAG="v1.0.0"
DOCKERFILE="Dockerfile"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DevSecOps Multi-Language Docker Build ===${NC}"
echo -e "${YELLOW}Building image: ${IMAGE_NAME}:${TAG}${NC}"

# Record start time
START_TIME=$(date +%s)

# Build the image
echo -e "${BLUE}Starting Docker build...${NC}"
docker build -t ${IMAGE_NAME}:${TAG} -f ${DOCKERFILE} .

# Record end time
END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

echo -e "${GREEN}✅ Build completed successfully!${NC}"
echo -e "${YELLOW}Build time: ${BUILD_TIME} seconds ($(($BUILD_TIME / 60))m $(($BUILD_TIME % 60))s)${NC}"

# Get image size
IMAGE_SIZE=$(docker images ${IMAGE_NAME}:${TAG} --format "table {{.Size}}" | tail -n 1)
echo -e "${YELLOW}Image size: ${IMAGE_SIZE}${NC}"

# Tag as latest
docker tag ${IMAGE_NAME}:${TAG} ${IMAGE_NAME}:latest

echo -e "${BLUE}=== Build Summary ===${NC}"
echo -e "Image: ${IMAGE_NAME}:${TAG}"
echo -e "Size: ${IMAGE_SIZE}"
echo -e "Build Time: ${BUILD_TIME} seconds"
echo -e "Layers: $(docker history ${IMAGE_NAME}:${TAG} --quiet | wc -l)"

echo -e "${GREEN}=== Next Steps ===${NC}"
echo -e "1. Run security scan: ./scan.sh"
echo -e "2. Test the image: docker run -it ${IMAGE_NAME}:${TAG} /bin/bash"
echo -e "3. Push to registry: docker push ${IMAGE_NAME}:${TAG}"

# Save build metrics
echo "$(date),${BUILD_TIME},${IMAGE_SIZE}" >> build-metrics.csv
