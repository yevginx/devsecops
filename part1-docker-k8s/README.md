# DevSecOps Multi-Language Development Environment

This project demonstrates a complete DevSecOps pipeline with Docker, Kubernetes, security scanning, and monitoring.

## Requirements Fulfilled

### 1. Multi-Language Docker Image
- **Files**: `Dockerfile`, `requirements-*.txt`
- **Languages**: Python 2.7, Python 3.x, R
- **Registry**: [glinsky/devsecops-multilang](https://hub.docker.com/r/glinsky/devsecops-multilang)
- **Tag management**: default tag stored in `VERSION` (override with `IMAGE_TAG` when running scripts)

```bash
# Build and push
./build.sh
```

### 2. Build Time Analysis
- **Files**: `Dockerfile.optimized`, `build-metrics.csv`
- **Report**: `docs/BUILD_ANALYSIS_REPORT.md`
- **Latest measurements (2025-09-20)**: 14m13s fresh build, 3s cached rebuild (see CSV for raw data)
- **Optimisations tracked**: Multi-stage builds, layer caching, parallel installs

### 3. Security Scanning & CVE Analysis
- **Files**: `scan.sh`, `security-reports/`
- **Tools**: Trivy, Docker Scout, Grype
- **Report**: `docs/CVE_SECURITY_REPORT.md`

```bash
# Run security scans
./scan.sh
# Optional: scan a specific tag or digest
# ./scan.sh --tag sha256:...
```

**Key Findings**:
- 1 CRITICAL and 13 HIGH severity CVEs detected (`security-reports/trivy-report.json`)
- Ubuntu 20.04 base image and legacy Python 2 packages contribute most issues  
- Secret scan flags originate from bundled R documentation examples (false positives)
- **Remediation focus**: Refresh the base image, retire Python 2 stacks, and upgrade vulnerable dependencies

### 4. Kubernetes Deployment
- **Files**: `k8s/deployment.yaml`, `k8s/namespace.yaml`
- **Features**: 
  - Resource limits/requests
  - Security contexts
  - Health checks
  - Multi-replica deployment
  - Node affinity supporting amd64 and arm64 clusters

```bash
# Deploy to Kubernetes
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
```

### 5. Service Exposure
- **Files**: `k8s/service.yaml`, `k8s/ingress.yaml`
- **Types**: NodePort, LoadBalancer, Ingress
- **Security**: NetworkPolicy for traffic control
- **Endpoint**: Simple Python HTTP server on port 8080 for smoke testing

```bash
# Expose service
kubectl apply -f k8s/service.yaml
minikube service multilang-dev-service -n devsecops --url
# Or open http://$(minikube ip):30080 for the built-in smoke-test page
```

### 6. CI/CD Pipeline
- **File**: `.github/workflows/devsecops-pipeline.yml`
- **Features**:
  - Static analysis (Hadolint + Checkov SARIF uploads)
  - Multi-arch build & push with version + SHA tags
  - Trivy and Docker Scout scans (fail on critical issues)
  - Vulnerability summary gate (JSON + artifacts)
  - Deployment manifest bundle with image digest substitution

### 7. Monitoring Implementation
- **Files**: `k8s/monitoring.yaml`, `k8s/prometheus-rbac.yaml`
- **Stack**: Prometheus + Grafana + kube-state-metrics + node-exporter
- **Dashboards**: Custom DevSecOps dashboard with resource metrics

```bash
# Deploy monitoring
kubectl apply -f k8s/prometheus-rbac.yaml
kubectl apply -f k8s/monitoring.yaml

# Access Grafana
minikube service grafana-service -n monitoring
# Login: admin/admin
```

## Quick Start

### Prerequisites
- Docker
- Kubernetes (minikube/kind)
- kubectl
- GitHub account (for CI/CD)

### Local Development
```bash
# 1. Build image
./build.sh            # optionally add --push to publish ${IMAGE_TAG}

# 2. Run security scan
./scan.sh

# 3. Deploy to Kubernetes
kubectl apply -f k8s/

# 4. Setup monitoring
kubectl apply -f k8s/prometheus-rbac.yaml
kubectl apply -f k8s/monitoring.yaml

# 5. Access services
minikube service multilang-dev-service -n devsecops
minikube service grafana-service -n monitoring
```

### CI/CD Setup
1. Fork this repository
2. Add Docker Hub credentials to GitHub Secrets:
   - `DOCKER_USERNAME`
   - `DOCKER_PASSWORD`
3. Push to trigger pipeline

## Monitoring & Observability

### Metrics Collected
- **Application**: Custom Python/R application metrics
- **Infrastructure**: CPU, Memory, Disk, Network
- **Kubernetes**: Pod status, resource utilization
- **Security**: CVE scan results, compliance metrics

### Dashboards
- **DevSecOps Overview**: Resource utilization, pod health
- **Security Dashboard**: CVE trends, scan results
- **Performance**: Application response times, throughput

### Alerting
- High CPU/Memory usage
- Pod restart loops
- Security vulnerabilities detected
- Deployment failures

## Security Best Practices

### Container Security
- Non-root user execution
- Read-only root filesystem
- Security contexts
- Resource limits
- Network policies

### Supply Chain Security
- Base image scanning
- Dependency vulnerability checks
- SBOM generation
- Signed container images
- Admission controllers

### Runtime Security
- Pod security standards
- Network segmentation
- RBAC implementation
- Audit logging
- Monitoring & alerting

## Performance Optimizations

### Build Time Improvements
- Multi-stage builds: 49% faster
- Layer caching: Reduced rebuild times
- Parallel package installation
- Optimized package manager usage

### Runtime Optimizations
- Resource requests/limits tuning
- Horizontal Pod Autoscaling
- Efficient base images
- Application-level caching

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Developer     │    │   GitHub        │    │   Docker Hub    │
│   Workstation   │───▶│   Actions       │───▶│   Registry      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   DevSecOps │  │  Monitoring │  │      Security           │ │
│  │   Workload  │  │   Stack     │  │      Policies           │ │
│  │             │  │             │  │                         │ │
│  │ • Python 2  │  │ • Prometheus│  │ • NetworkPolicy         │ │
│  │ • Python 3  │  │ • Grafana   │  │ • PodSecurityStandard   │ │
│  │ • R         │  │ • Alerting  │  │ • RBAC                  │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Documentation

- [`BUILD_ANALYSIS_REPORT.md`](docs/BUILD_ANALYSIS_REPORT.md) - Build optimisation analysis
- [`CVE_SECURITY_REPORT.md`](docs/CVE_SECURITY_REPORT.md) - Security vulnerability assessment
- [`MONITORING_STRATEGY.md`](docs/MONITORING_STRATEGY.md) - Monitoring implementation guide

## Interview Talking Points

1. **DevSecOps Integration**: Security scanning in CI/CD pipeline
2. **Container Optimization**: Build time and size improvements
3. **Kubernetes Security**: Pod security, RBAC, network policies
4. **Observability**: Comprehensive monitoring with Prometheus/Grafana
5. **Automation**: Full CI/CD pipeline with GitHub Actions
6. **Best Practices**: Industry-standard security and operational practices

## Troubleshooting

### Common Issues
- **Build failures**: Check Docker daemon and permissions
- **K8s deployment issues**: Verify cluster connectivity and RBAC
- **Monitoring not working**: Ensure all services are running and accessible
- **CI/CD failures**: Check GitHub secrets and permissions

### Useful Commands
```bash
# Check pod status
kubectl get pods -n devsecops

# View logs
kubectl logs -f deployment/multilang-dev-env -n devsecops

# Port forward for local access
kubectl port-forward svc/multilang-dev-service 8080:8080 -n devsecops

# Monitor resources
kubectl top pods -n devsecops
```

---

**Author**: Evgeny Glinsky  
**Date**: September 2025  
**Purpose**: DevSecOps Technical Assessment
