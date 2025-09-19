#!/usr/bin/env python3
"""
Kubernetes Operator for Development Environment Management
Custom controller for managing development environment lifecycle
"""

import asyncio
import logging
import os
import json
import yaml
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
from dataclasses import dataclass

import kopf
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class EnvironmentSpec:
    """Environment specification"""
    name: str
    base_image: str
    custom_image: Optional[str]
    resources: Dict[str, str]
    limits: Dict[str, str]
    packages: List[Dict[str, Any]]
    enable_ssh: bool
    enable_jupyter: bool
    enable_vscode: bool
    team: str
    project: str
    ttl_hours: int
    environment_variables: Dict[str, str]

class EnvironmentOperator:
    """
    Kubernetes operator for managing development environments
    """
    
    def __init__(self):
        # Load Kubernetes config
        try:
            config.load_incluster_config()
        except:
            config.load_kube_config()
        
        self.k8s_core = client.CoreV1Api()
        self.k8s_apps = client.AppsV1Api()
        self.k8s_networking = client.NetworkingV1Api()
        self.k8s_custom = client.CustomObjectsApi()
        
        # Configuration
        self.domain_suffix = os.getenv('DOMAIN_SUFFIX', 'dev-platform.company.com')
        self.registry_secret = os.getenv('REGISTRY_SECRET', 'registry-credentials')
        self.storage_class = os.getenv('STORAGE_CLASS', 'gp3')
    
    def create_namespace(self, env_id: str, team: str, project: str) -> str:
        """Create namespace for environment"""
        namespace_name = f"dev-env-{env_id[:8]}"
        
        namespace = client.V1Namespace(
            metadata=client.V1ObjectMeta(
                name=namespace_name,
                labels={
                    "app.kubernetes.io/managed-by": "dev-platform",
                    "dev-platform/environment-id": env_id,
                    "dev-platform/team": team,
                    "dev-platform/project": project,
                    "pod-security.kubernetes.io/enforce": "restricted",
                    "pod-security.kubernetes.io/audit": "restricted",
                    "pod-security.kubernetes.io/warn": "restricted"
                },
                annotations={
                    "dev-platform/created-at": datetime.utcnow().isoformat(),
                    "dev-platform/ttl": "24h"
                }
            )
        )
        
        try:
            self.k8s_core.create_namespace(body=namespace)
            logger.info(f"Created namespace: {namespace_name}")
        except ApiException as e:
            if e.status != 409:  # Already exists
                raise
            logger.info(f"Namespace already exists: {namespace_name}")
        
        return namespace_name
    
    def create_network_policy(self, namespace: str, env_id: str):
        """Create network policy for environment isolation"""
        network_policy = client.V1NetworkPolicy(
            metadata=client.V1ObjectMeta(
                name="dev-env-isolation",
                namespace=namespace,
                labels={
                    "app.kubernetes.io/managed-by": "dev-platform",
                    "dev-platform/environment-id": env_id
                }
            ),
            spec=client.V1NetworkPolicySpec(
                pod_selector=client.V1LabelSelector(
                    match_labels={"dev-platform/environment-id": env_id}
                ),
                policy_types=["Ingress", "Egress"],
                ingress=[
                    # Allow ingress from ingress controller
                    client.V1NetworkPolicyIngressRule(
                        from_=[
                            client.V1NetworkPolicyPeer(
                                namespace_selector=client.V1LabelSelector(
                                    match_labels={"name": "ingress-nginx"}
                                )
                            )
                        ]
                    ),
                    # Allow ingress within same namespace
                    client.V1NetworkPolicyIngressRule(
                        from_=[
                            client.V1NetworkPolicyPeer(
                                namespace_selector=client.V1LabelSelector(
                                    match_labels={"name": namespace}
                                )
                            )
                        ]
                    )
                ],
                egress=[
                    # Allow DNS
                    client.V1NetworkPolicyEgressRule(
                        ports=[
                            client.V1NetworkPolicyPort(protocol="UDP", port=53),
                            client.V1NetworkPolicyPort(protocol="TCP", port=53)
                        ]
                    ),
                    # Allow HTTPS for package downloads
                    client.V1NetworkPolicyEgressRule(
                        ports=[
                            client.V1NetworkPolicyPort(protocol="TCP", port=443),
                            client.V1NetworkPolicyPort(protocol="TCP", port=80)
                        ]
                    ),
                    # Allow egress within same namespace
                    client.V1NetworkPolicyEgressRule(
                        to=[
                            client.V1NetworkPolicyPeer(
                                namespace_selector=client.V1LabelSelector(
                                    match_labels={"name": namespace}
                                )
                            )
                        ]
                    )
                ]
            )
        )
        
        try:
            self.k8s_networking.create_namespaced_network_policy(
                namespace=namespace,
                body=network_policy
            )
            logger.info(f"Created network policy for namespace: {namespace}")
        except ApiException as e:
            if e.status != 409:
                raise
    
    def create_persistent_volume_claim(self, namespace: str, env_id: str, size: str):
        """Create PVC for environment storage"""
        pvc = client.V1PersistentVolumeClaim(
            metadata=client.V1ObjectMeta(
                name="workspace-storage",
                namespace=namespace,
                labels={
                    "app.kubernetes.io/managed-by": "dev-platform",
                    "dev-platform/environment-id": env_id
                }
            ),
            spec=client.V1PersistentVolumeClaimSpec(
                access_modes=["ReadWriteOnce"],
                resources=client.V1ResourceRequirements(
                    requests={"storage": size}
                ),
                storage_class=self.storage_class
            )
        )
        
        try:
            self.k8s_core.create_namespaced_persistent_volume_claim(
                namespace=namespace,
                body=pvc
            )
            logger.info(f"Created PVC for namespace: {namespace}")
        except ApiException as e:
            if e.status != 409:
                raise
    
    def create_deployment(self, namespace: str, spec: EnvironmentSpec, env_id: str):
        """Create deployment for development environment"""
        
        # Build init containers for package installation
        init_containers = []
        
        for pkg_spec in spec.packages:
            if pkg_spec['manager'] == 'apt':
                init_containers.append(
                    client.V1Container(
                        name=f"install-apt-packages",
                        image=spec.custom_image or spec.base_image,
                        command=["/bin/bash", "-c"],
                        args=[f"apt-get update && apt-get install -y {' '.join(pkg_spec['packages'])}"],
                        security_context=client.V1SecurityContext(
                            run_as_user=0,  # Root needed for package installation
                            allow_privilege_escalation=True
                        ),
                        volume_mounts=[
                            client.V1VolumeMount(
                                name="workspace",
                                mount_path="/workspace"
                            )
                        ]
                    )
                )
            elif pkg_spec['manager'] == 'pip':
                init_containers.append(
                    client.V1Container(
                        name=f"install-pip-packages",
                        image=spec.custom_image or spec.base_image,
                        command=["/bin/bash", "-c"],
                        args=[f"pip install {' '.join(pkg_spec['packages'])}"],
                        volume_mounts=[
                            client.V1VolumeMount(
                                name="workspace",
                                mount_path="/workspace"
                            )
                        ]
                    )
                )
        
        # Main container
        container = client.V1Container(
            name="dev-environment",
            image=spec.custom_image or spec.base_image,
            resources=client.V1ResourceRequirements(
                requests={
                    "cpu": spec.resources.get("cpu", "1"),
                    "memory": spec.resources.get("memory", "2Gi")
                },
                limits={
                    "cpu": spec.limits.get("cpu", "2"),
                    "memory": spec.limits.get("memory", "4Gi")
                }
            ),
            env=[
                client.V1EnvVar(name=k, value=v) 
                for k, v in spec.environment_variables.items()
            ] + [
                client.V1EnvVar(name="ENVIRONMENT_ID", value=env_id),
                client.V1EnvVar(name="TEAM", value=spec.team),
                client.V1EnvVar(name="PROJECT", value=spec.project)
            ],
            ports=[
                client.V1ContainerPort(container_port=22, name="ssh"),
                client.V1ContainerPort(container_port=8888, name="jupyter"),
                client.V1ContainerPort(container_port=8080, name="vscode")
            ],
            volume_mounts=[
                client.V1VolumeMount(
                    name="workspace",
                    mount_path="/workspace"
                ),
                client.V1VolumeMount(
                    name="tmp",
                    mount_path="/tmp"
                )
            ],
            security_context=client.V1SecurityContext(
                run_as_non_root=True,
                run_as_user=1000,
                run_as_group=1000,
                allow_privilege_escalation=False,
                read_only_root_filesystem=False,  # Some dev tools need write access
                capabilities=client.V1Capabilities(drop=["ALL"])
            ),
            command=["/bin/bash", "-c"],
            args=["while true; do sleep 30; done"]  # Keep container running
        )
        
        # Add GPU resources if requested
        if spec.resources.get("gpu"):
            container.resources.requests["nvidia.com/gpu"] = spec.resources["gpu"]
            container.resources.limits["nvidia.com/gpu"] = spec.limits.get("gpu", spec.resources["gpu"])
        
        # Pod template
        pod_template = client.V1PodTemplateSpec(
            metadata=client.V1ObjectMeta(
                labels={
                    "app": f"dev-env-{env_id[:8]}",
                    "app.kubernetes.io/managed-by": "dev-platform",
                    "dev-platform/environment-id": env_id,
                    "dev-platform/team": spec.team,
                    "dev-platform/project": spec.project
                },
                annotations={
                    "prometheus.io/scrape": "true",
                    "prometheus.io/port": "9090",
                    "prometheus.io/path": "/metrics"
                }
            ),
            spec=client.V1PodSpec(
                init_containers=init_containers,
                containers=[container],
                volumes=[
                    client.V1Volume(
                        name="workspace",
                        persistent_volume_claim=client.V1PersistentVolumeClaimVolumeSource(
                            claim_name="workspace-storage"
                        )
                    ),
                    client.V1Volume(
                        name="tmp",
                        empty_dir=client.V1EmptyDirVolumeSource(
                            size_limit="1Gi"
                        )
                    )
                ],
                security_context=client.V1PodSecurityContext(
                    run_as_non_root=True,
                    run_as_user=1000,
                    run_as_group=1000,
                    fs_group=1000,
                    seccomp_profile=client.V1SeccompProfile(type="RuntimeDefault")
                ),
                node_selector=self.get_node_selector(spec),
                tolerations=self.get_tolerations(spec),
                termination_grace_period_seconds=30
            )
        )
        
        # Deployment
        deployment = client.V1Deployment(
            metadata=client.V1ObjectMeta(
                name=f"dev-env-{env_id[:8]}",
                namespace=namespace,
                labels={
                    "app.kubernetes.io/managed-by": "dev-platform",
                    "dev-platform/environment-id": env_id
                }
            ),
            spec=client.V1DeploymentSpec(
                replicas=1,
                selector=client.V1LabelSelector(
                    match_labels={"app": f"dev-env-{env_id[:8]}"}
                ),
                template=pod_template,
                strategy=client.V1DeploymentStrategy(
                    type="Recreate"  # Ensure only one instance
                )
            )
        )
        
        try:
            self.k8s_apps.create_namespaced_deployment(
                namespace=namespace,
                body=deployment
            )
            logger.info(f"Created deployment for environment: {env_id}")
        except ApiException as e:
            if e.status != 409:
                raise
    
    def get_node_selector(self, spec: EnvironmentSpec) -> Dict[str, str]:
        """Get node selector based on resource requirements"""
        node_selector = {"kubernetes.io/arch": "amd64"}
        
        # High memory workloads
        memory_limit = spec.limits.get("memory", "0Gi")
        if self.parse_memory(memory_limit) >= 100 * 1024**3:  # 100GB+
            node_selector["workload-type"] = "high-memory"
        # GPU workloads
        elif spec.resources.get("gpu"):
            node_selector["workload-type"] = "gpu"
        # Development workloads
        else:
            node_selector["workload-type"] = "development"
        
        return node_selector
    
    def get_tolerations(self, spec: EnvironmentSpec) -> List[client.V1Toleration]:
        """Get tolerations based on resource requirements"""
        tolerations = []
        
        # High memory workloads
        memory_limit = spec.limits.get("memory", "0Gi")
        if self.parse_memory(memory_limit) >= 100 * 1024**3:  # 100GB+
            tolerations.append(
                client.V1Toleration(
                    key="workload-type",
                    operator="Equal",
                    value="high-memory",
                    effect="NoSchedule"
                )
            )
        # GPU workloads
        elif spec.resources.get("gpu"):
            tolerations.append(
                client.V1Toleration(
                    key="workload-type",
                    operator="Equal",
                    value="gpu",
                    effect="NoSchedule"
                )
            )
        # Development workloads
        else:
            tolerations.append(
                client.V1Toleration(
                    key="workload-type",
                    operator="Equal",
                    value="development",
                    effect="NoSchedule"
                )
            )
        
        return tolerations
    
    def parse_memory(self, memory_str: str) -> int:
        """Parse memory string to bytes"""
        if memory_str.endswith("Gi"):
            return int(memory_str[:-2]) * 1024**3
        elif memory_str.endswith("Mi"):
            return int(memory_str[:-2]) * 1024**2
        elif memory_str.endswith("Ki"):
            return int(memory_str[:-2]) * 1024
        else:
            return int(memory_str)
    
    def create_service(self, namespace: str, env_id: str, spec: EnvironmentSpec):
        """Create service for environment"""
        ports = []
        
        if spec.enable_ssh:
            ports.append(client.V1ServicePort(name="ssh", port=22, target_port=22))
        
        if spec.enable_jupyter:
            ports.append(client.V1ServicePort(name="jupyter", port=8888, target_port=8888))
        
        if spec.enable_vscode:
            ports.append(client.V1ServicePort(name="vscode", port=8080, target_port=8080))
        
        service = client.V1Service(
            metadata=client.V1ObjectMeta(
                name=f"dev-env-{env_id[:8]}-service",
                namespace=namespace,
                labels={
                    "app.kubernetes.io/managed-by": "dev-platform",
                    "dev-platform/environment-id": env_id
                },
                annotations={
                    "service.beta.kubernetes.io/aws-load-balancer-type": "nlb",
                    "service.beta.kubernetes.io/aws-load-balancer-scheme": "internet-facing"
                }
            ),
            spec=client.V1ServiceSpec(
                type="LoadBalancer",
                selector={"app": f"dev-env-{env_id[:8]}"},
                ports=ports,
                session_affinity="ClientIP"
            )
        )
        
        try:
            self.k8s_core.create_namespaced_service(
                namespace=namespace,
                body=service
            )
            logger.info(f"Created service for environment: {env_id}")
        except ApiException as e:
            if e.status != 409:
                raise

# Kopf handlers for CRD events
@kopf.on.create('dev-platform.company.com', 'v1', 'developmentenvironments')
async def create_environment(spec, name, namespace, logger, **kwargs):
    """Handle creation of development environment"""
    logger.info(f"Creating development environment: {name}")
    
    operator = EnvironmentOperator()
    
    # Parse spec
    env_spec = EnvironmentSpec(
        name=spec['name'],
        base_image=spec['baseImage'],
        custom_image=spec.get('customImage'),
        resources=spec['resources'],
        limits=spec['limits'],
        packages=spec.get('packages', []),
        enable_ssh=spec.get('enableSSH', True),
        enable_jupyter=spec.get('enableJupyter', False),
        enable_vscode=spec.get('enableVSCode', False),
        team=spec['team'],
        project=spec['project'],
        ttl_hours=spec.get('ttlHours', 24),
        environment_variables=spec.get('environmentVariables', {})
    )
    
    env_id = kwargs['body']['metadata']['uid']
    
    try:
        # Create namespace
        ns_name = operator.create_namespace(env_id, env_spec.team, env_spec.project)
        
        # Create network policy
        operator.create_network_policy(ns_name, env_id)
        
        # Create PVC
        storage_size = env_spec.resources.get('storage', '10Gi')
        operator.create_persistent_volume_claim(ns_name, env_id, storage_size)
        
        # Create deployment
        operator.create_deployment(ns_name, env_spec, env_id)
        
        # Create service
        operator.create_service(ns_name, env_id, env_spec)
        
        logger.info(f"Successfully created environment: {name}")
        
        return {"status": "created", "namespace": ns_name}
        
    except Exception as e:
        logger.error(f"Failed to create environment {name}: {e}")
        raise

@kopf.on.delete('dev-platform.company.com', 'v1', 'developmentenvironments')
async def delete_environment(spec, name, namespace, logger, **kwargs):
    """Handle deletion of development environment"""
    logger.info(f"Deleting development environment: {name}")
    
    env_id = kwargs['body']['metadata']['uid']
    ns_name = f"dev-env-{env_id[:8]}"
    
    try:
        operator = EnvironmentOperator()
        
        # Delete namespace (cascades to all resources)
        operator.k8s_core.delete_namespace(name=ns_name)
        
        logger.info(f"Successfully deleted environment: {name}")
        
    except ApiException as e:
        if e.status != 404:
            logger.error(f"Failed to delete environment {name}: {e}")
            raise

if __name__ == "__main__":
    kopf.run()
