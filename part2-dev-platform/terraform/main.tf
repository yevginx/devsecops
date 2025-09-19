# DevSecOps Development Platform Infrastructure
# Terraform configuration for multi-tenant development environments

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "DevSecOps-Platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DevOps-Team"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "devsecops-platform"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

# VPC Configuration
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs for compliance
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# EKS Cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # OIDC Identity provider
  cluster_identity_providers = {
    sts = {
      client_id = "sts.amazonaws.com"
    }
  }

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    # General purpose nodes
    general = {
      name = "general"
      
      instance_types = ["t3.large"]
      
      min_size     = 2
      max_size     = 10
      desired_size = 3

      disk_size = 50
      disk_type = "gp3"

      labels = {
        workload-type = "general"
      }

      taints = []
    }

    # Development environment nodes
    development = {
      name = "development"
      
      instance_types = ["t3.xlarge", "t3.2xlarge"]
      
      min_size     = 1
      max_size     = 20
      desired_size = 2

      disk_size = 100
      disk_type = "gp3"

      labels = {
        workload-type = "development"
      }

      taints = [
        {
          key    = "workload-type"
          value  = "development"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    # High-memory nodes for large datasets
    high-memory = {
      name = "high-memory"
      
      instance_types = ["r5.4xlarge", "r5.8xlarge", "r5.12xlarge"]
      
      min_size     = 0
      max_size     = 5
      desired_size = 0

      disk_size = 200
      disk_type = "gp3"

      labels = {
        workload-type = "high-memory"
        memory-optimized = "true"
      }

      taints = [
        {
          key    = "workload-type"
          value  = "high-memory"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    # GPU nodes for ML workloads
    gpu = {
      name = "gpu"
      
      instance_types = ["g4dn.xlarge", "g4dn.2xlarge"]
      
      min_size     = 0
      max_size     = 3
      desired_size = 0

      disk_size = 100
      disk_type = "gp3"

      labels = {
        workload-type = "gpu"
        accelerator = "nvidia-tesla-t4"
      }

      taints = [
        {
          key    = "workload-type"
          value  = "gpu"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.platform_admin.arn
      username = "platform-admin"
      groups   = ["system:masters"]
    },
  ]

  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      username = "root"
      groups   = ["system:masters"]
    },
  ]

  tags = {
    Environment = var.environment
  }
}

# IAM Role for Platform Administration
resource "aws_iam_role" "platform_admin" {
  name = "${var.cluster_name}-platform-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "platform_admin_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.platform_admin.name
}

# S3 Bucket for Environment Data Storage
resource "aws_s3_bucket" "environment_data" {
  bucket = "${var.cluster_name}-environment-data-${random_string.bucket_suffix.result}"
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "environment_data" {
  bucket = aws_s3_bucket.environment_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "environment_data" {
  bucket = aws_s3_bucket.environment_data.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.environment_data.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "environment_data" {
  bucket = aws_s3_bucket.environment_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# KMS Key for encryption
resource "aws_kms_key" "environment_data" {
  description             = "KMS key for environment data encryption"
  deletion_window_in_days = 7

  tags = {
    Name = "${var.cluster_name}-environment-data"
  }
}

resource "aws_kms_alias" "environment_data" {
  name          = "alias/${var.cluster_name}-environment-data"
  target_key_id = aws_kms_key.environment_data.key_id
}

# RDS for Platform Database
resource "aws_db_subnet_group" "platform" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${var.cluster_name} DB subnet group"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.cluster_name}-rds"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "platform" {
  identifier = "${var.cluster_name}-db"

  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id           = aws_kms_key.environment_data.arn

  db_name  = "platform"
  username = "platform_admin"
  password = random_password.db_password.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.platform.name

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "${var.cluster_name} Platform Database"
  }
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

# ElastiCache Redis for Caching
resource "aws_elasticache_subnet_group" "platform" {
  name       = "${var.cluster_name}-cache-subnet"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_name}-redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_replication_group" "platform" {
  replication_group_id       = "${var.cluster_name}-redis"
  description                = "Redis cluster for platform caching"

  node_type            = "cache.t3.micro"
  port                 = 6379
  parameter_group_name = "default.redis7"

  num_cache_clusters = 2

  subnet_group_name  = aws_elasticache_subnet_group.platform.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  tags = {
    Name = "${var.cluster_name} Redis Cluster"
  }
}

# Route53 for DNS Management
resource "aws_route53_zone" "platform" {
  name = "dev-platform.internal"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = {
    Name = "${var.cluster_name} Internal DNS"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "platform_api" {
  name              = "/aws/eks/${var.cluster_name}/platform-api"
  retention_in_days = 30

  tags = {
    Application = "platform-api"
  }
}

resource "aws_cloudwatch_log_group" "environment_logs" {
  name              = "/aws/eks/${var.cluster_name}/environments"
  retention_in_days = 7

  tags = {
    Application = "development-environments"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = module.eks.cluster_iam_role_name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for environment data"
  value       = aws_s3_bucket.environment_data.bucket
}

output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.platform.endpoint
  sensitive   = true
}

output "database_password" {
  description = "RDS instance password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_replication_group.platform.primary_endpoint_address
}

output "vpc_id" {
  description = "ID of the VPC where resources are created"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}
