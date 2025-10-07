# Dev Platform on EKS (Part 2)

This module adapts the AWS multi-tenant JupyterHub reference into an opinionated developer platform that satisfies the Part 2 requirements of the DevSecOps evaluation. Running `./deploy.sh` provisions the VPC, EKS control plane, autoscaling data-plane (Karpenter + managed node group), storage, observability stack, JupyterHub control plane, and secure file transfer access.

## Provisioning Workflow
- Update `terraform.tfvars` (or copy `terraform.tfvars.example`) with AWS region, optional SNS topic for alerts, and Transfer Family DNS/SSH settings. Provide at least one SSH public key under `transfer_users` to enable SFTP access.
- Execute `./deploy.sh`. The script runs targeted Terraform applies (`vpc`, `eks`) before the full plan to minimise blast radius. Re-run to reconcile drift.
- After bootstrap, apply your AWS auth ConfigMap as in Part 1 (command recorded in `outputs.tf`).
- Destroy the environment with `./cleanup.sh` when finished.

_Note_: `terraform init`/`terraform validate` require network access to Terraform Registry. If the evaluation environment blocks outbound traffic, run these commands from a networked workstation before invoking `deploy.sh`.

## Developer Experience in JupyterHub
The landing page exposes curated spawner profiles that satisfy "select base image, packages, and resources" requirements:

| Profile | Base image options | Package bundles | Resource selector |
|---------|-------------------|-----------------|-------------------|
| General Purpose (CPU) | SciPy, Data Science, custom Python2/3/R image from Part 1 | Minimal, Data Science, MLOps, Geospatial (conda) | Small / Medium / Large (2-8 CPU, 8-32 Gi) |
| Memory Optimized | SciPy, PySpark 3.5.0, R | Minimal, In-memory analytics | r6i.16xlarge / r6i.32xlarge (256-512 Gi RAM) |
| GPU – NVIDIA G5 | NVIDIA PyTorch/TensorFlow/RAPIDS | Minimal, Inference | 1–2 GPUs with time slicing & CPU/RAM presets |
| GPU – NVIDIA MIG | PyTorch CUDA 11.8, TensorFlow | 1g/2g/3g MIG slice selector | Fixed CPU/RAM with MIG quotas |
| Trainium & Inferentia | NeuronX PyTorch / TensorFlow | Minimal | Accelerator-specific tolerations & quotas |

Implementation details:
- `profile_options` map directly to KubeSpawner overrides so each dropdown rewrites container image, environment variables, CPU/memory/GPU requests, and node selectors.
- Package bundles set `JUPYTER_PRELOAD_{PIP,CONDA}_PACKAGES`; a pod lifecycle hook installs bundles on spawn.
- Resource selectors enforce request/limit pairs and align with taints/labels on the matching Karpenter node pools.
- Idle notebooks are culled after 30 minutes (configurable) which triggers pod deletion and, in turn, Karpenter scale-down events.

## Autoscaling & Multi-tenancy Guardrails
- Managed node group hosts critical system add-ons; all user workloads land on Karpenter-managed pools segregated by label/taint (`karpenter`, `memory-optimized`, `gpu-ts`, `gpu-mig`, `inferentia`, `trainium`).
- Each profile sets tolerations and selectors to keep workloads on the right hardware tier.
- Karpenter node pools specify disruption policies, TTL consolidation, and per-pool resource limits so scale-out remains bounded and scale-in is aggressive once pods terminate.

## Observability & Utilisation Tracking
- Prometheus scrapes JupyterHub hub metrics, Kubecost, and GPU plugin exporters. Additional recording/alerting rules compare requested vs actual CPU/memory per notebook (`jupyterhub:pod_*_utilization`).
- Alertmanager (optional) publishes idle/underutilised/OOM alerts to the configured SNS topic for downstream routing (email, Slack, PagerDuty, etc.).
- Grafana ships with auto-discovered dashboards; the added metrics make it trivial to chart utilisation. Kubecost reuses the Prometheus datasource for spend and allocation reporting.
- Fluent Bit ships logs to CloudWatch for long-term retention and incident response.

## Secure File Transfer & DNS Automation
- AWS Transfer Family (SFTP) exposes the same EFS share that backs user home directories. Users upload/download notebooks via their SSH keys without needing cluster credentials.
- Terraform provisions IAM roles, CloudWatch logging, security groups, and (optionally) a Route53 record (`transfer_hostname`) pointing at the managed endpoint.
- Adjust `transfer_allowed_cidrs` to restrict ingress, or disable the feature entirely by setting `enable_transfer_server = false`.

## Handling 100–250 GiB In-memory Analytics
I modelled this on a previous engagement where we needed to compute geospatial joins over ~180 GiB parquet datasets. We staged the data on S3, pre-warmed Arrow datasets into memory, and ran Dask + Rapids on GPU-backed notebooks.

For this platform:
1. Users choose the **Memory Optimized** profile (`r6i.16xlarge` or `r6i.32xlarge`) which guarantees 256–512 Gi of RAM and pins to memory-optimised pools.
2. Data locality is achieved by caching source data on the EFS home volume or streaming from S3 using `fsspec` with multipart prefetch. The lifecycle hook can add `pyarrow`, `polars`, and `dask` automatically.
3. If GPU acceleration is preferred, the MIG profile allocates dedicated GPU slices and exposes RAPIDS images.
4. Monitoring: the Prometheus alerts fire when working set memory approaches the requested threshold, while OOMKilled alerts capture kernel terminations. Grafana visualisations (CPU/memory panels) highlight sustained pressure and inform right-sizing decisions.

## Monitoring Idle & Underutilised Resources
- `JupyterHubUserIdle30m` and `JupyterHubUserUnderutilized` alerts surface pods eligible for automated culling; Alertmanager can forward to Slack/SNS.
- Idle culling removes named servers and works with Karpenter’s consolidation to return nodes to zero when notebooks go quiet.
- Kubecost enriches metrics with cost allocation so product owners can analyse underused capacity.

## CI/CD Touchpoints
While the evaluation repo uses a CLI workflow, the Terraform layout is CI-friendly. Suggested extensions:
1. Add a GitHub Actions workflow running `terraform fmt`, `terraform validate`, and (optionally) `tfsec` on pull requests.
2. Use Atlantis or Spacelift to gate `terraform apply` with plan reviews.
3. Build/publish the custom multi-runtime notebook image from Part 1 via the same pipeline and update `profile_options` image tags automatically.

## Next Steps
- Populate `transfer_users` with real SSH keys and tighten `transfer_allowed_cidrs`.
- Wire Alertmanager SNS into Slack or PagerDuty for actionable notifications.
- Extend Grafana with an opinionated dashboard (upload JSON via UI) and pre-built exploration notebooks that ingest the Prometheus/Kubecost APIs.

---

**Author**: Evgeny Glinsky  
**Date**: September 2025  
**Purpose**: DevSecOps Technical Assessment