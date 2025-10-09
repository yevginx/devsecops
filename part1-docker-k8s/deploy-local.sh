#!/bin/bash

# A script to build the multi-lang image and deploy it to a local Minikube cluster.
# This script is designed to be run from its own directory.

set -euo pipefail

# --- Configuration ---
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION_FILE="${SCRIPT_DIR}/VERSION"
readonly IMAGE_NAME="${IMAGE_NAME:-glinsky/devsecops-multilang}"
readonly DOCKERFILE="${DOCKERFILE:-Dockerfile.optimized}"
readonly NAMESPACE="devsecops"

if [[ -z "${IMAGE_TAG:-}" ]]; then
    if [[ ! -f "${VERSION_FILE}" ]]; then
        echo "ERROR: VERSION file not found at ${VERSION_FILE}." >&2
        exit 1
    fi
    IMAGE_TAG_VALUE="$(<"${VERSION_FILE}")"  # shellcheck disable=SC2002
else
    IMAGE_TAG_VALUE="${IMAGE_TAG}"
fi

readonly IMAGE_TAG="${IMAGE_TAG_VALUE}"

# --- Main Logic ---
main() {
    # Ensure the script is run from its containing directory to resolve paths correctly.
    cd "$(dirname "${BASH_SOURCE[0]}")"

    check_dependencies
    start_minikube_if_needed
    build_and_load_image
    deploy_to_kubernetes
    print_summary
}

# --- Helper Functions ---

check_dependencies() {
    echo "INFO: Checking for required tools (docker, minikube, kubectl)..."
    local missing_tools=0
    for tool in docker minikube kubectl; do
        if ! command -v "$tool" &> /dev/null; then
            echo "ERROR: '$tool' is not installed. Please install it and ensure it's in your PATH."
            missing_tools=1
        fi
    done
    if [[ "$missing_tools" -eq 1 ]]; then
        exit 1
    fi
    echo "INFO: All required tools are available."
}

start_minikube_if_needed() {
    if ! minikube status &> /dev/null; then
        echo "INFO: Minikube is not running. Starting it now..."
        minikube start
    else
        echo "INFO: Minikube is already running."
    fi
}

build_and_load_image() {
    echo "INFO: Building Docker image '$IMAGE_NAME:$IMAGE_TAG' from '$DOCKERFILE'..."
    # The build context is now '.', referring to the current directory (part1-docker-k8s)
    docker build -t "$IMAGE_NAME:$IMAGE_TAG" -f "$DOCKERFILE" .

    echo "INFO: Loading image into Minikube's Docker daemon..."
    minikube image load "$IMAGE_NAME:$IMAGE_TAG"
}

deploy_to_kubernetes() {
    echo "INFO: Deploying Kubernetes resources..."

    echo "INFO: Applying application namespace..."
    kubectl apply -f k8s/namespace.yaml

    echo "INFO: Creating monitoring namespace..."
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    echo "INFO: Applying monitoring stack (services, deployments, RBAC)..."
    kubectl apply -f k8s/prometheus-rbac.yaml
    kubectl apply -f k8s/monitoring.yaml

    echo "INFO: Applying application workloads..."
    for manifest in k8s/ingress.yaml k8s/networkpolicy.yaml k8s/poddisruptionbudget.yaml k8s/service.yaml k8s/deployment.yaml k8s/grafana-dashboards.yaml; do
        kubectl apply -f "$manifest"
    done

    echo "INFO: Waiting for deployment 'multilang-dev-env' to become available..."
    # Increased timeout for slower systems
    kubectl rollout status deployment/multilang-dev-env -n "$NAMESPACE" --timeout=5m
}

print_summary() {
    local minikube_ip
    minikube_ip=$(minikube ip)

    echo "-----------------------------------------------------"
    echo "SUCCESS: Deployment completed."
    echo "-----------------------------------------------------"
    echo "Minikube IP: $minikube_ip"
    echo "Namespace:   $NAMESPACE"
    echo ""
    echo "To get a shell inside the pod, run:"
    echo "  kubectl exec -it -n $NAMESPACE deployment/multilang-dev-env -- /bin/bash"
    echo ""
    echo "To clean up the deployment, run:"
    echo "  kubectl delete namespace $NAMESPACE"
    echo "-----------------------------------------------------"
}

# --- Script Entrypoint ---
main
