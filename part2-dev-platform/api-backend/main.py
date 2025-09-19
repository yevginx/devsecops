"""
DevSecOps Development Platform API
FastAPI backend for managing development environments
"""

from fastapi import FastAPI, HTTPException, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from enum import Enum
import asyncio
import logging
from datetime import datetime, timedelta
import uuid
import json

# Kubernetes client
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Prometheus client for metrics
from prometheus_client import Counter, Histogram, Gauge, generate_latest

app = FastAPI(
    title="DevSecOps Development Platform API",
    description="API for managing multi-tenant development environments",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer()

# Metrics
environment_requests = Counter('dev_environment_requests_total', 'Total environment requests')
environment_creation_time = Histogram('dev_environment_creation_seconds', 'Environment creation time')
active_environments = Gauge('dev_environments_active', 'Number of active environments')
resource_utilization = Gauge('dev_environment_resource_utilization', 'Resource utilization', ['environment_id', 'resource_type'])

# Models
class BaseImageType(str, Enum):
    UBUNTU_20_04 = "ubuntu:20.04"
    UBUNTU_22_04 = "ubuntu:22.04"
    CENTOS_8 = "centos:8"
    ALPINE_LATEST = "alpine:latest"
    PYTHON_3_11 = "python:3.11"
    JUPYTER_DATASCIENCE = "jupyter/datascience-notebook"
    CUSTOM = "custom"

class PackageManager(str, Enum):
    APT = "apt"
    YUM = "yum"
    CONDA = "conda"
    PIP = "pip"
    NPM = "npm"

class ResourceRequest(BaseModel):
    cpu: str = Field(default="1", description="CPU request (e.g., '1', '500m')")
    memory: str = Field(default="2Gi", description="Memory request (e.g., '2Gi', '512Mi')")
    gpu: Optional[str] = Field(default=None, description="GPU request (e.g., '1')")
    storage: str = Field(default="10Gi", description="Storage request")

class ResourceLimit(BaseModel):
    cpu: str = Field(default="2", description="CPU limit")
    memory: str = Field(default="4Gi", description="Memory limit")
    gpu: Optional[str] = Field(default=None, description="GPU limit")

class PackageSpec(BaseModel):
    manager: PackageManager
    packages: List[str]

class EnvironmentSpec(BaseModel):
    name: str = Field(..., description="Environment name")
    base_image: BaseImageType
    custom_image: Optional[str] = Field(default=None, description="Custom image URL if base_image is 'custom'")
    packages: List[PackageSpec] = Field(default=[], description="Packages to install")
    resources: ResourceRequest = Field(default_factory=ResourceRequest)
    limits: ResourceLimit = Field(default_factory=ResourceLimit)
    enable_ssh: bool = Field(default=True, description="Enable SSH access")
    enable_jupyter: bool = Field(default=False, description="Enable Jupyter notebook")
    enable_vscode: bool = Field(default=False, description="Enable VS Code server")
    environment_variables: Dict[str, str] = Field(default={}, description="Environment variables")
    team: str = Field(..., description="Team name for resource segregation")
    project: str = Field(..., description="Project name")
    ttl_hours: int = Field(default=24, description="Time to live in hours")

class EnvironmentStatus(str, Enum):
    PENDING = "pending"
    CREATING = "creating"
    RUNNING = "running"
    STOPPING = "stopping"
    STOPPED = "stopped"
    ERROR = "error"

class Environment(BaseModel):
    id: str
    spec: EnvironmentSpec
    status: EnvironmentStatus
    created_at: datetime
    updated_at: datetime
    expires_at: datetime
    ssh_endpoint: Optional[str] = None
    jupyter_url: Optional[str] = None
    vscode_url: Optional[str] = None
    resource_usage: Dict[str, Any] = {}

class EnvironmentMetrics(BaseModel):
    environment_id: str
    cpu_usage_percent: float
    memory_usage_percent: float
    memory_usage_bytes: int
    network_rx_bytes: int
    network_tx_bytes: int
    storage_usage_bytes: int
    last_activity: datetime
    is_idle: bool

# In-memory storage (replace with database in production)
environments: Dict[str, Environment] = {}
metrics_store: Dict[str, EnvironmentMetrics] = {}

# Kubernetes client setup
try:
    config.load_incluster_config()
except:
    config.load_kube_config()

k8s_apps_v1 = client.AppsV1Api()
k8s_core_v1 = client.CoreV1Api()
k8s_networking_v1 = client.NetworkingV1Api()

# Authentication (simplified - implement proper auth in production)
async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    # Implement proper JWT validation here
    return {"username": "demo_user", "teams": ["engineering", "data-science"]}

@app.get("/")
async def root():
    return {"message": "DevSecOps Development Platform API", "version": "1.0.0"}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.utcnow()}

@app.post("/environments", response_model=Environment)
async def create_environment(
    spec: EnvironmentSpec,
    background_tasks: BackgroundTasks,
    user: dict = Depends(get_current_user)
):
    """Create a new development environment"""
    environment_requests.inc()
    
    # Generate unique ID
    env_id = str(uuid.uuid4())
    
    # Create environment object
    environment = Environment(
        id=env_id,
        spec=spec,
        status=EnvironmentStatus.PENDING,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
        expires_at=datetime.utcnow() + timedelta(hours=spec.ttl_hours)
    )
    
    environments[env_id] = environment
    active_environments.inc()
    
    # Start environment creation in background
    background_tasks.add_task(create_k8s_environment, env_id)
    
    return environment

@app.get("/environments", response_model=List[Environment])
async def list_environments(
    team: Optional[str] = None,
    status: Optional[EnvironmentStatus] = None,
    user: dict = Depends(get_current_user)
):
    """List development environments"""
    result = list(environments.values())
    
    if team:
        result = [env for env in result if env.spec.team == team]
    
    if status:
        result = [env for env in result if env.status == status]
    
    return result

@app.get("/environments/{env_id}", response_model=Environment)
async def get_environment(env_id: str, user: dict = Depends(get_current_user)):
    """Get environment details"""
    if env_id not in environments:
        raise HTTPException(status_code=404, detail="Environment not found")
    
    return environments[env_id]

@app.delete("/environments/{env_id}")
async def delete_environment(
    env_id: str,
    background_tasks: BackgroundTasks,
    user: dict = Depends(get_current_user)
):
    """Delete a development environment"""
    if env_id not in environments:
        raise HTTPException(status_code=404, detail="Environment not found")
    
    environment = environments[env_id]
    environment.status = EnvironmentStatus.STOPPING
    environment.updated_at = datetime.utcnow()
    
    # Start deletion in background
    background_tasks.add_task(delete_k8s_environment, env_id)
    
    return {"message": "Environment deletion started"}

@app.get("/environments/{env_id}/metrics", response_model=EnvironmentMetrics)
async def get_environment_metrics(env_id: str, user: dict = Depends(get_current_user)):
    """Get environment resource metrics"""
    if env_id not in environments:
        raise HTTPException(status_code=404, detail="Environment not found")
    
    if env_id not in metrics_store:
        # Return default metrics if not available
        return EnvironmentMetrics(
            environment_id=env_id,
            cpu_usage_percent=0.0,
            memory_usage_percent=0.0,
            memory_usage_bytes=0,
            network_rx_bytes=0,
            network_tx_bytes=0,
            storage_usage_bytes=0,
            last_activity=datetime.utcnow(),
            is_idle=True
        )
    
    return metrics_store[env_id]

@app.post("/environments/{env_id}/scale")
async def scale_environment(
    env_id: str,
    resources: ResourceRequest,
    user: dict = Depends(get_current_user)
):
    """Scale environment resources"""
    if env_id not in environments:
        raise HTTPException(status_code=404, detail="Environment not found")
    
    environment = environments[env_id]
    environment.spec.resources = resources
    environment.updated_at = datetime.utcnow()
    
    # Update Kubernetes deployment
    await update_k8s_resources(env_id, resources)
    
    return {"message": "Environment scaling initiated"}

@app.get("/metrics")
async def get_prometheus_metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

@app.get("/base-images")
async def get_base_images():
    """Get available base images"""
    return {
        "images": [
            {"name": "Ubuntu 20.04", "value": "ubuntu:20.04", "description": "Ubuntu 20.04 LTS"},
            {"name": "Ubuntu 22.04", "value": "ubuntu:22.04", "description": "Ubuntu 22.04 LTS"},
            {"name": "CentOS 8", "value": "centos:8", "description": "CentOS 8"},
            {"name": "Alpine Linux", "value": "alpine:latest", "description": "Alpine Linux (minimal)"},
            {"name": "Python 3.11", "value": "python:3.11", "description": "Python 3.11 with pip"},
            {"name": "Jupyter Data Science", "value": "jupyter/datascience-notebook", "description": "Jupyter with data science packages"},
            {"name": "Custom", "value": "custom", "description": "Specify custom image URL"}
        ]
    }

# Background tasks
async def create_k8s_environment(env_id: str):
    """Create Kubernetes resources for the environment"""
    try:
        environment = environments[env_id]
        environment.status = EnvironmentStatus.CREATING
        environment.updated_at = datetime.utcnow()
        
        # Create namespace
        namespace_name = f"dev-env-{env_id[:8]}"
        await create_namespace(namespace_name, environment.spec.team)
        
        # Create deployment
        await create_deployment(env_id, namespace_name)
        
        # Create service
        await create_service(env_id, namespace_name)
        
        # Create ingress if needed
        if environment.spec.enable_jupyter or environment.spec.enable_vscode:
            await create_ingress(env_id, namespace_name)
        
        # Update DNS for SSH access
        if environment.spec.enable_ssh:
            ssh_endpoint = await create_ssh_endpoint(env_id, namespace_name)
            environment.ssh_endpoint = ssh_endpoint
        
        environment.status = EnvironmentStatus.RUNNING
        environment.updated_at = datetime.utcnow()
        
    except Exception as e:
        logging.error(f"Failed to create environment {env_id}: {str(e)}")
        environment.status = EnvironmentStatus.ERROR
        environment.updated_at = datetime.utcnow()

async def delete_k8s_environment(env_id: str):
    """Delete Kubernetes resources for the environment"""
    try:
        namespace_name = f"dev-env-{env_id[:8]}"
        
        # Delete namespace (this will delete all resources in it)
        k8s_core_v1.delete_namespace(name=namespace_name)
        
        # Clean up DNS
        await cleanup_dns_endpoint(env_id)
        
        # Remove from storage
        if env_id in environments:
            del environments[env_id]
            active_environments.dec()
        
        if env_id in metrics_store:
            del metrics_store[env_id]
            
    except Exception as e:
        logging.error(f"Failed to delete environment {env_id}: {str(e)}")

async def create_namespace(name: str, team: str):
    """Create Kubernetes namespace"""
    namespace = client.V1Namespace(
        metadata=client.V1ObjectMeta(
            name=name,
            labels={
                "team": team,
                "managed-by": "dev-platform"
            }
        )
    )
    k8s_core_v1.create_namespace(body=namespace)

async def create_deployment(env_id: str, namespace: str):
    """Create Kubernetes deployment"""
    environment = environments[env_id]
    spec = environment.spec
    
    # Build container image
    image = spec.custom_image if spec.base_image == BaseImageType.CUSTOM else spec.base_image.value
    
    # Container definition
    container = client.V1Container(
        name="dev-environment",
        image=image,
        resources=client.V1ResourceRequirements(
            requests={
                "cpu": spec.resources.cpu,
                "memory": spec.resources.memory
            },
            limits={
                "cpu": spec.limits.cpu,
                "memory": spec.limits.memory
            }
        ),
        env=[
            client.V1EnvVar(name=k, value=v) 
            for k, v in spec.environment_variables.items()
        ],
        command=["/bin/bash", "-c", "while true; do sleep 30; done"]
    )
    
    # Add GPU resources if requested
    if spec.resources.gpu:
        container.resources.requests["nvidia.com/gpu"] = spec.resources.gpu
        container.resources.limits["nvidia.com/gpu"] = spec.limits.gpu or spec.resources.gpu
    
    # Pod template
    template = client.V1PodTemplateSpec(
        metadata=client.V1ObjectMeta(
            labels={
                "app": f"dev-env-{env_id[:8]}",
                "environment-id": env_id,
                "team": spec.team,
                "project": spec.project
            }
        ),
        spec=client.V1PodSpec(
            containers=[container],
            node_selector={"workload-type": "development"}
        )
    )
    
    # Deployment
    deployment = client.V1Deployment(
        metadata=client.V1ObjectMeta(name=f"dev-env-{env_id[:8]}"),
        spec=client.V1DeploymentSpec(
            replicas=1,
            selector=client.V1LabelSelector(
                match_labels={"app": f"dev-env-{env_id[:8]}"}
            ),
            template=template
        )
    )
    
    k8s_apps_v1.create_namespaced_deployment(namespace=namespace, body=deployment)

async def create_service(env_id: str, namespace: str):
    """Create Kubernetes service"""
    service = client.V1Service(
        metadata=client.V1ObjectMeta(name=f"dev-env-{env_id[:8]}-service"),
        spec=client.V1ServiceSpec(
            selector={"app": f"dev-env-{env_id[:8]}"},
            ports=[
                client.V1ServicePort(name="ssh", port=22, target_port=22),
                client.V1ServicePort(name="jupyter", port=8888, target_port=8888),
                client.V1ServicePort(name="vscode", port=8080, target_port=8080)
            ]
        )
    )
    
    k8s_core_v1.create_namespaced_service(namespace=namespace, body=service)

async def create_ingress(env_id: str, namespace: str):
    """Create Kubernetes ingress"""
    # Implementation for ingress creation
    pass

async def create_ssh_endpoint(env_id: str, namespace: str) -> str:
    """Create SSH endpoint and return the connection string"""
    # Implementation for SSH endpoint creation
    return f"ssh dev-env-{env_id[:8]}.dev-platform.company.com"

async def cleanup_dns_endpoint(env_id: str):
    """Clean up DNS endpoint"""
    # Implementation for DNS cleanup
    pass

async def update_k8s_resources(env_id: str, resources: ResourceRequest):
    """Update Kubernetes deployment resources"""
    # Implementation for resource updates
    pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
