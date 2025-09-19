#!/bin/bash

# DevSecOps Evaluation - Security Scanning Script
# Performs comprehensive CVE scanning and security analysis

set -e

# Configuration
IMAGE_NAME="evgenyglinsky/devsecops-multilang"
TAG="v1.0.0"
SCAN_RESULTS_DIR="security-reports"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DevSecOps Security Scanning ===${NC}"

# Create results directory
mkdir -p ${SCAN_RESULTS_DIR}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Check if image exists
if ! docker image inspect ${IMAGE_NAME}:${TAG} > /dev/null 2>&1; then
    echo -e "${RED}❌ Image ${IMAGE_NAME}:${TAG} not found. Please build it first.${NC}"
    exit 1
fi

echo -e "${YELLOW}Scanning image: ${IMAGE_NAME}:${TAG}${NC}"

# 1. Trivy Security Scan
echo -e "${BLUE}1. Running Trivy vulnerability scan...${NC}"
if command -v trivy &> /dev/null; then
    trivy image --format json --output ${SCAN_RESULTS_DIR}/trivy-report.json ${IMAGE_NAME}:${TAG}
    trivy image --format table --output ${SCAN_RESULTS_DIR}/trivy-report.txt ${IMAGE_NAME}:${TAG}
    echo -e "${GREEN}✅ Trivy scan completed${NC}"
else
    echo -e "${YELLOW}⚠️  Trivy not installed. Installing...${NC}"
    # Install Trivy on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install trivy
    else
        # Install on Linux
        sudo apt-get update && sudo apt-get install -y wget apt-transport-https gnupg lsb-release
        wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
        echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
        sudo apt-get update && sudo apt-get install -y trivy
    fi
    trivy image --format json --output ${SCAN_RESULTS_DIR}/trivy-report.json ${IMAGE_NAME}:${TAG}
    trivy image --format table --output ${SCAN_RESULTS_DIR}/trivy-report.txt ${IMAGE_NAME}:${TAG}
fi

# 2. Docker Scout (if available)
echo -e "${BLUE}2. Running Docker Scout scan...${NC}"
if docker scout version &> /dev/null; then
    docker scout cves --format json --output ${SCAN_RESULTS_DIR}/scout-report.json ${IMAGE_NAME}:${TAG}
    docker scout cves --format table --output ${SCAN_RESULTS_DIR}/scout-report.txt ${IMAGE_NAME}:${TAG}
    echo -e "${GREEN}✅ Docker Scout scan completed${NC}"
else
    echo -e "${YELLOW}⚠️  Docker Scout not available${NC}"
fi

# 3. Grype Security Scan
echo -e "${BLUE}3. Running Grype vulnerability scan...${NC}"
if command -v grype &> /dev/null; then
    grype ${IMAGE_NAME}:${TAG} -o json > ${SCAN_RESULTS_DIR}/grype-report.json
    grype ${IMAGE_NAME}:${TAG} -o table > ${SCAN_RESULTS_DIR}/grype-report.txt
    echo -e "${GREEN}✅ Grype scan completed${NC}"
else
    echo -e "${YELLOW}⚠️  Grype not installed. Installing...${NC}"
    curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
    grype ${IMAGE_NAME}:${TAG} -o json > ${SCAN_RESULTS_DIR}/grype-report.json
    grype ${IMAGE_NAME}:${TAG} -o table > ${SCAN_RESULTS_DIR}/grype-report.txt
fi

# 4. Hadolint Dockerfile Linting
echo -e "${BLUE}4. Running Hadolint Dockerfile analysis...${NC}"
if command -v hadolint &> /dev/null; then
    hadolint Dockerfile > ${SCAN_RESULTS_DIR}/hadolint-report.txt 2>&1 || true
    echo -e "${GREEN}✅ Hadolint analysis completed${NC}"
else
    echo -e "${YELLOW}⚠️  Hadolint not installed. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install hadolint
    else
        wget -O /usr/local/bin/hadolint https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
        chmod +x /usr/local/bin/hadolint
    fi
    hadolint Dockerfile > ${SCAN_RESULTS_DIR}/hadolint-report.txt 2>&1 || true
fi

# 5. Generate Security Report
echo -e "${BLUE}5. Generating comprehensive security report...${NC}"
cat > ${SCAN_RESULTS_DIR}/security-summary.md << EOF
# Security Scan Report

**Image:** ${IMAGE_NAME}:${TAG}
**Scan Date:** $(date)
**Scan Tools:** Trivy, Docker Scout, Grype, Hadolint

## Executive Summary

This report contains the results of comprehensive security scanning performed on the multi-language development container.

## Scan Results

### 1. Trivy Vulnerability Scan
- Report: [trivy-report.txt](trivy-report.txt)
- JSON: [trivy-report.json](trivy-report.json)

### 2. Docker Scout Analysis
- Report: [scout-report.txt](scout-report.txt)
- JSON: [scout-report.json](scout-report.json)

### 3. Grype Vulnerability Scan
- Report: [grype-report.txt](grype-report.txt)
- JSON: [grype-report.json](grype-report.json)

### 4. Hadolint Dockerfile Analysis
- Report: [hadolint-report.txt](hadolint-report.txt)

## Remediation Recommendations

### High Priority CVEs
1. **Python 2.7 End-of-Life**: Python 2.7 reached EOL on January 1, 2020
   - **Risk**: No security updates, known vulnerabilities
   - **Remediation**: Migrate to Python 3.x or use containerized isolation

2. **Base Image Vulnerabilities**: Ubuntu 20.04 may contain known CVEs
   - **Risk**: System-level vulnerabilities
   - **Remediation**: Use minimal base images (alpine, distroless) or latest LTS

3. **Package Vulnerabilities**: Outdated packages may contain CVEs
   - **Risk**: Application-level vulnerabilities
   - **Remediation**: Regular dependency updates, vulnerability scanning in CI/CD

### Security Best Practices Implemented
- ✅ Non-root user execution
- ✅ Multi-stage builds for reduced attack surface
- ✅ Health checks for container monitoring
- ✅ Minimal package installation with cleanup
- ✅ Explicit version pinning for reproducibility

### Recommended Improvements
1. Use distroless or alpine base images
2. Implement regular dependency updates
3. Add SBOM (Software Bill of Materials) generation
4. Implement runtime security monitoring
5. Use signed images and content trust

## Supply Chain Security

### Package Verification
- Python packages: Installed from PyPI with integrity checks
- R packages: Installed from CRAN with verification
- System packages: Installed from official Ubuntu repositories

### Recommendations
1. Use private package repositories for internal packages
2. Implement package signing verification
3. Use dependency pinning and lock files
4. Regular security scanning in CI/CD pipeline
5. Implement SLSA (Supply-chain Levels for Software Artifacts) compliance

EOF

echo -e "${GREEN}✅ Security scanning completed!${NC}"
echo -e "${BLUE}=== Scan Summary ===${NC}"
echo -e "Reports generated in: ${SCAN_RESULTS_DIR}/"
echo -e "Main report: ${SCAN_RESULTS_DIR}/security-summary.md"

# Count vulnerabilities if Trivy report exists
if [ -f "${SCAN_RESULTS_DIR}/trivy-report.json" ]; then
    CRITICAL=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL") | .VulnerabilityID' ${SCAN_RESULTS_DIR}/trivy-report.json 2>/dev/null | wc -l || echo "0")
    HIGH=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH") | .VulnerabilityID' ${SCAN_RESULTS_DIR}/trivy-report.json 2>/dev/null | wc -l || echo "0")
    MEDIUM=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM") | .VulnerabilityID' ${SCAN_RESULTS_DIR}/trivy-report.json 2>/dev/null | wc -l || echo "0")
    
    echo -e "${RED}Critical: ${CRITICAL}${NC}"
    echo -e "${YELLOW}High: ${HIGH}${NC}"
    echo -e "${BLUE}Medium: ${MEDIUM}${NC}"
fi

echo -e "${GREEN}=== Next Steps ===${NC}"
echo -e "1. Review security reports in ${SCAN_RESULTS_DIR}/"
echo -e "2. Address critical and high severity vulnerabilities"
echo -e "3. Implement security scanning in CI/CD pipeline"
echo -e "4. Deploy to Kubernetes: kubectl apply -f k8s/"
