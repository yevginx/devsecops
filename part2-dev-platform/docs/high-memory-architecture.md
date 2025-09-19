# High-Memory Workload Architecture (100-250GB)

## Overview

This document describes the architecture for supporting high-memory workloads (100-250GB) in the DevSecOps development platform. The solution addresses the challenge of "bringing data to code" rather than "code to data" for large dataset processing.

## Architecture Components

### 1. Memory-Optimized Node Groups

```yaml
# EKS Node Group Configuration
high-memory:
  instance_types: 
    - r5.4xlarge   # 128GB RAM, 16 vCPUs
    - r5.8xlarge   # 256GB RAM, 32 vCPUs  
    - r5.12xlarge  # 384GB RAM, 48 vCPUs
    - r5.16xlarge  # 512GB RAM, 64 vCPUs
    - r5.24xlarge  # 768GB RAM, 96 vCPUs
  
  node_taints:
    - key: workload-type
      value: high-memory
      effect: NoSchedule
  
  node_labels:
    workload-type: high-memory
    memory-optimized: "true"
```

### 2. Data Locality Strategies

#### A. Persistent Volume Strategy
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: large-dataset-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Ti  # 1TB for dataset storage
  storageClassName: gp3-high-iops
```

#### B. Memory-Mapped Files
```python
# Example: Memory-mapped file access for large datasets
import mmap
import numpy as np

def load_large_dataset(file_path):
    """Load large dataset using memory mapping"""
    with open(file_path, 'r+b') as f:
        # Memory-map the file
        mm = mmap.mmap(f.fileno(), 0)
        
        # Create numpy array from memory map
        data = np.frombuffer(mm, dtype=np.float64)
        
        return data, mm

# Usage in development environment
data, mm = load_large_dataset('/workspace/datasets/large_dataset.bin')
# Process data without loading entire file into memory
result = process_chunks(data, chunk_size=1000000)
mm.close()
```

#### C. Distributed Caching Layer
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-cluster
spec:
  serviceName: redis-cluster
  replicas: 6
  template:
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        resources:
          requests:
            memory: 32Gi
            cpu: 4
          limits:
            memory: 32Gi
            cpu: 8
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
```

#### D. S3/MinIO Streaming
```python
# Example: Streaming data from object storage
import boto3
import pandas as pd
from io import BytesIO

def stream_from_s3(bucket, key, chunk_size=1024*1024):
    """Stream large dataset from S3 in chunks"""
    s3 = boto3.client('s3')
    
    response = s3.get_object(Bucket=bucket, Key=key)
    
    for chunk in iter(lambda: response['Body'].read(chunk_size), b''):
        yield chunk

def process_large_csv_from_s3(bucket, key):
    """Process large CSV file from S3 without loading entirely"""
    chunks = []
    
    # Stream and process in chunks
    for chunk_data in stream_from_s3(bucket, key):
        chunk_df = pd.read_csv(BytesIO(chunk_data))
        processed_chunk = process_chunk(chunk_df)
        chunks.append(processed_chunk)
    
    return pd.concat(chunks, ignore_index=True)
```

### 3. Memory Management Configuration

#### Kubernetes Pod Configuration
```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: high-memory-workload
    image: data-science:latest
    resources:
      requests:
        memory: 200Gi
        cpu: 32
      limits:
        memory: 250Gi
        cpu: 48
    env:
    - name: MALLOC_ARENA_MAX
      value: "4"  # Limit memory arenas
    - name: PYTHONMALLOC
      value: "malloc"  # Use system malloc
    - name: OMP_NUM_THREADS
      value: "32"  # Optimize for CPU count
  nodeSelector:
    workload-type: high-memory
  tolerations:
  - key: workload-type
    value: high-memory
    effect: NoSchedule
```

#### System-Level Optimizations
```bash
# Node-level memory optimizations
echo 'vm.swappiness=1' >> /etc/sysctl.conf
echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf
echo 'kernel.shmmax=274877906944' >> /etc/sysctl.conf  # 256GB

# Huge pages configuration
echo 'vm.nr_hugepages=51200' >> /etc/sysctl.conf  # 100GB in 2MB pages
sysctl -p

# NUMA topology awareness
echo 'kernel.numa_balancing=0' >> /etc/sysctl.conf
```

### 4. Monitoring and Alerting

#### Memory Pressure Monitoring
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: high-memory-alerts
spec:
  groups:
  - name: memory.rules
    rules:
    - alert: HighMemoryUsage
      expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage detected"
        description: "Container {{ $labels.container }} is using {{ $value | humanizePercentage }} of memory limit"
    
    - alert: MemoryPressure
      expr: rate(container_memory_failures_total[5m]) > 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Memory allocation failures detected"
        description: "Container {{ $labels.container }} is experiencing memory allocation failures"
    
    - alert: OOMKilled
      expr: increase(kube_pod_container_status_restarts_total[5m]) > 0 and on(pod) kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: "Pod killed due to OOM"
        description: "Pod {{ $labels.pod }} was killed due to out of memory"
```

#### Custom Metrics Collection
```python
# Memory usage metrics collector
from prometheus_client import Gauge, Counter
import psutil
import os

memory_usage_gauge = Gauge('dev_env_memory_usage_bytes', 'Memory usage in bytes', ['env_id'])
memory_pressure_counter = Counter('dev_env_memory_pressure_total', 'Memory pressure events', ['env_id'])

def collect_memory_metrics(env_id):
    """Collect memory metrics for environment"""
    process = psutil.Process(os.getpid())
    memory_info = process.memory_info()
    
    memory_usage_gauge.labels(env_id=env_id).set(memory_info.rss)
    
    # Check for memory pressure indicators
    if memory_info.rss > (200 * 1024**3):  # 200GB threshold
        memory_pressure_counter.labels(env_id=env_id).inc()
```

## Real-World Implementation Examples

### Example 1: Large Dataset Processing Pipeline

```python
"""
Example: Processing 200GB genomics dataset
Scenario: Bioinformatics analysis requiring large reference genomes in memory
"""

import numpy as np
import h5py
from dask import array as da
import zarr

class GenomicsProcessor:
    def __init__(self, reference_path, chunk_size_gb=10):
        self.reference_path = reference_path
        self.chunk_size = chunk_size_gb * 1024**3  # Convert to bytes
        
    def load_reference_genome(self):
        """Load reference genome using memory mapping"""
        # Use HDF5 for efficient access to large genomics data
        self.reference_file = h5py.File(self.reference_path, 'r')
        self.genome_data = self.reference_file['genome']
        
        # Create dask array for distributed processing
        self.genome_array = da.from_array(
            self.genome_data, 
            chunks=(self.chunk_size // 4,)  # 4 bytes per element
        )
        
    def process_samples(self, sample_paths):
        """Process multiple samples against reference"""
        results = []
        
        for sample_path in sample_paths:
            # Stream sample data
            with h5py.File(sample_path, 'r') as sample_file:
                sample_data = da.from_array(sample_file['sample'])
                
                # Perform alignment in chunks
                alignment_result = self.align_to_reference(sample_data)
                results.append(alignment_result)
        
        return results
    
    def align_to_reference(self, sample_data):
        """Align sample to reference genome"""
        # Process in chunks to manage memory
        alignment_scores = da.map_blocks(
            self._align_chunk,
            sample_data,
            self.genome_array,
            dtype=np.float32
        )
        
        return alignment_scores.compute()
```

### Example 2: Machine Learning Model Training

```python
"""
Example: Training large neural network with 150GB dataset
Scenario: Computer vision model training with high-resolution images
"""

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset
import zarr
import numpy as np

class LargeImageDataset(Dataset):
    def __init__(self, zarr_path, transform=None):
        self.data = zarr.open(zarr_path, mode='r')
        self.transform = transform
        
    def __len__(self):
        return self.data.shape[0]
    
    def __getitem__(self, idx):
        # Load single image from zarr array
        image = self.data[idx]
        
        if self.transform:
            image = self.transform(image)
            
        return image

class HighMemoryTrainer:
    def __init__(self, model, dataset_path, batch_size=32):
        self.model = model
        self.dataset = LargeImageDataset(dataset_path)
        
        # Use memory pinning for faster GPU transfer
        self.dataloader = DataLoader(
            self.dataset,
            batch_size=batch_size,
            shuffle=True,
            num_workers=16,
            pin_memory=True,
            persistent_workers=True
        )
        
    def train(self, epochs=100):
        """Train model with memory-efficient loading"""
        self.model.cuda()
        optimizer = torch.optim.AdamW(self.model.parameters())
        
        for epoch in range(epochs):
            for batch_idx, batch in enumerate(self.dataloader):
                batch = batch.cuda(non_blocking=True)
                
                # Forward pass
                output = self.model(batch)
                loss = self.compute_loss(output, batch)
                
                # Backward pass
                optimizer.zero_grad()
                loss.backward()
                optimizer.step()
                
                # Memory cleanup
                if batch_idx % 100 == 0:
                    torch.cuda.empty_cache()
```

## Performance Optimization Strategies

### 1. Memory Pool Management
```python
# Custom memory pool for large allocations
import numpy as np
from numba import cuda

class MemoryPool:
    def __init__(self, pool_size_gb=100):
        self.pool_size = pool_size_gb * 1024**3
        self.pool = np.empty(self.pool_size // 8, dtype=np.float64)
        self.allocated = 0
        
    def allocate(self, size_bytes):
        """Allocate memory from pool"""
        if self.allocated + size_bytes > self.pool_size:
            raise MemoryError("Pool exhausted")
            
        start_idx = self.allocated // 8
        end_idx = start_idx + (size_bytes // 8)
        
        self.allocated += size_bytes
        return self.pool[start_idx:end_idx]
    
    def reset(self):
        """Reset pool for reuse"""
        self.allocated = 0
```

### 2. NUMA-Aware Processing
```python
# NUMA topology awareness
import psutil
import os

def get_numa_topology():
    """Get NUMA node information"""
    numa_nodes = {}
    
    for cpu in range(psutil.cpu_count()):
        numa_node = os.sched_getaffinity(0)  # Simplified
        if numa_node not in numa_nodes:
            numa_nodes[numa_node] = []
        numa_nodes[numa_node].append(cpu)
    
    return numa_nodes

def bind_to_numa_node(node_id):
    """Bind process to specific NUMA node"""
    numa_topology = get_numa_topology()
    if node_id in numa_topology:
        os.sched_setaffinity(0, numa_topology[node_id])
```

## Cost Optimization

### 1. Spot Instance Integration
```yaml
# Use spot instances for cost savings
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: high-memory-spot
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot"]
    - key: node.kubernetes.io/instance-type
      operator: In
      values: ["r5.4xlarge", "r5.8xlarge", "r5.12xlarge"]
  limits:
    resources:
      memory: 2000Gi
  ttlSecondsAfterEmpty: 300
```

### 2. Auto-scaling Based on Memory Pressure
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: memory-based-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: high-memory-workload
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: memory_pressure_events_per_second
      target:
        type: AverageValue
        averageValue: "0.1"
```

## Disaster Recovery and Data Protection

### 1. Snapshot Strategy
```bash
#!/bin/bash
# Automated snapshot creation for large datasets

DATASET_PATH="/workspace/datasets"
SNAPSHOT_BUCKET="s3://dev-platform-snapshots"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create incremental snapshot
aws s3 sync $DATASET_PATH $SNAPSHOT_BUCKET/datasets_$TIMESTAMP/ \
    --storage-class INTELLIGENT_TIERING \
    --exclude "*.tmp" \
    --exclude "*.log"

# Cleanup old snapshots (keep last 7 days)
aws s3api list-objects-v2 \
    --bucket dev-platform-snapshots \
    --prefix "datasets_" \
    --query "Contents[?LastModified<='$(date -d '7 days ago' --iso-8601)'].Key" \
    --output text | xargs -I {} aws s3 rm s3://dev-platform-snapshots/{}
```

### 2. Cross-Region Replication
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: replication-config
data:
  replication.yaml: |
    source_regions: ["us-west-2"]
    target_regions: ["us-east-1", "eu-west-1"]
    replication_schedule: "0 2 * * *"  # Daily at 2 AM
    compression: true
    encryption: true
```

This architecture provides a comprehensive solution for handling 100-250GB memory workloads while maintaining performance, cost efficiency, and reliability.
