#!/bin/bash

# Security Scanning Script
# Performs CVE and configuration checks against the built image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/VERSION"
SCAN_RESULTS_DIR="security-reports"

usage() {
  cat <<'USAGE'
Usage: ./scan.sh [--tag TAG|DIGEST] [--output DIR]

Options:
  --tag TAG       Image tag or digest to scan (defaults to value in VERSION).
  --output DIR    Directory for generated reports (default: security-reports).
  -h, --help      Display this help text.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --output)
      SCAN_RESULTS_DIR="$2"
      shift 2
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
if [[ "${IMAGE_TAG}" == sha256:* ]]; then
  IMAGE_REF="${IMAGE_NAME}@${IMAGE_TAG}"
else
  IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "${SCAN_RESULTS_DIR}"

if ! docker info > /dev/null 2>&1; then
  echo -e "${RED} Docker is not running. Please start Docker first.${NC}"
  exit 1
fi

if ! docker image inspect "${IMAGE_REF}" > /dev/null 2>&1; then
  echo -e "${RED} Image ${IMAGE_REF} not found. Please build it first.${NC}"
  exit 1
fi

echo -e "${BLUE}=== DevSecOps Security Scanning ===${NC}"
echo -e "${YELLOW}Scanning image: ${IMAGE_REF}${NC}"

TRIVY_STATUS="Skipped (trivy not installed)"
SCOUT_STATUS="Skipped (docker scout unavailable)"
GRYPE_STATUS="Skipped (grype not installed)"
HADOLINT_STATUS="Skipped (hadolint not installed)"

# Trivy scan
if command -v trivy &> /dev/null; then
  echo -e "${BLUE}1. Running Trivy vulnerability scan...${NC}"
  trivy image --format json --output "${SCAN_RESULTS_DIR}/trivy-report.json" "${IMAGE_REF}"
  trivy image --format table --output "${SCAN_RESULTS_DIR}/trivy-report.txt" "${IMAGE_REF}"
  TRIVY_STATUS="Reports generated"
  echo -e "${GREEN} Trivy scan completed${NC}"
else
  echo -e "${YELLOW} Trivy not installed. Install from https://aquasecurity.github.io/trivy and re-run the scan.${NC}"
fi

echo -e "${BLUE}2. Running Docker Scout scan...${NC}"
if command -v docker &> /dev/null && docker scout --help > /dev/null 2>&1; then
  if docker scout cves "${IMAGE_REF}" --format sarif --output "${SCAN_RESULTS_DIR}/docker-scout-results.sarif"; then
    SCOUT_STATUS="docker-scout-results.sarif"
    echo -e "${GREEN} Docker Scout scan completed${NC}"
  else
    SCOUT_STATUS="Failed (see console output)"
    echo -e "${YELLOW} Docker Scout scan failed or returned non-zero. Continuing.${NC}"
  fi
else
  echo -e "${YELLOW} Docker Scout not available. Skipping...${NC}"
fi

echo -e "${BLUE}3. Running Grype vulnerability scan...${NC}"
if command -v grype &> /dev/null; then
  grype "${IMAGE_REF}" -o json > "${SCAN_RESULTS_DIR}/grype-report.json"
  grype "${IMAGE_REF}" -o table > "${SCAN_RESULTS_DIR}/grype-report.txt"
  GRYPE_STATUS="Reports generated"
  echo -e "${GREEN} Grype scan completed${NC}"
else
  echo -e "${YELLOW} Grype not installed. Install it from https://github.com/anchore/grype and re-run the scan.${NC}"
fi

echo -e "${BLUE}4. Running Hadolint Dockerfile analysis...${NC}"
if command -v hadolint &> /dev/null; then
  hadolint Dockerfile > "${SCAN_RESULTS_DIR}/hadolint-report.txt" 2>&1 || true
  HADOLINT_STATUS="hadolint-report.txt"
  echo -e "${GREEN} Hadolint analysis completed${NC}"
else
  echo -e "${YELLOW} Hadolint not installed. Install it from https://github.com/hadolint/hadolint and re-run the scan.${NC}"
fi

# Security summary
echo -e "${BLUE}5. Generating security summary...${NC}"
cat > "${SCAN_RESULTS_DIR}/security-summary.md" << EOF
# Security Scan Report

**Image:** ${IMAGE_REF}
**Scan Date:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Tool Coverage
- Trivy: ${TRIVY_STATUS}
- Docker Scout: ${SCOUT_STATUS}
- Grype: ${GRYPE_STATUS}
- Hadolint: ${HADOLINT_STATUS}
EOF

if [[ -f "${SCAN_RESULTS_DIR}/trivy-report.json" ]] && command -v jq > /dev/null; then
  CRITICAL_COUNT=$(jq '[.Results[]? .Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "${SCAN_RESULTS_DIR}/trivy-report.json")
  HIGH_COUNT=$(jq '[.Results[]? .Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "${SCAN_RESULTS_DIR}/trivy-report.json")
  MEDIUM_COUNT=$(jq '[.Results[]? .Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' "${SCAN_RESULTS_DIR}/trivy-report.json")
  {
    echo
    echo "## Vulnerability Summary (Trivy)"
    echo
    echo "- Critical: ${CRITICAL_COUNT}"
    echo "- High: ${HIGH_COUNT}"
    echo "- Medium: ${MEDIUM_COUNT}"
  } >> "${SCAN_RESULTS_DIR}/security-summary.md"
else
  {
    echo
    echo "## Vulnerability Summary"
    echo
    echo "Trivy JSON output or jq not available; rerun with both installed to capture counts."
  } >> "${SCAN_RESULTS_DIR}/security-summary.md"
fi

echo >> "${SCAN_RESULTS_DIR}/security-summary.md"
echo "## Next Steps" >> "${SCAN_RESULTS_DIR}/security-summary.md"
echo "1. Review the generated reports under ${SCAN_RESULTS_DIR}/" >> "${SCAN_RESULTS_DIR}/security-summary.md"
echo "2. Prioritize remediation for CRITICAL and HIGH vulnerabilities." >> "${SCAN_RESULTS_DIR}/security-summary.md"
echo "3. Regenerate the image after applying package updates." >> "${SCAN_RESULTS_DIR}/security-summary.md"

echo -e "${GREEN} Security scanning completed. Reports stored in ${SCAN_RESULTS_DIR}/ ${NC}"
