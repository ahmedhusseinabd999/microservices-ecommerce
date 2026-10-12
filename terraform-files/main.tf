# Filter available AZs in eu-north-1
data "aws_availability_zones" "available" {
  state = "available"
}

# 1. VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # Set to false for high availability across AZs
  enable_dns_hostnames = true

  # Required tags for AWS Load Balancer Controller auto-discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# 2. EKS Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  # Endpoint visibility
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enables Cluster Creator (your IAM identity) to administer the cluster
  enable_cluster_creator_admin_permissions = true

  # Managed Node Group - T3 Instance Types
  eks_managed_node_groups = {
    primary_nodes = {
      min_size     = 2
      max_size     = 10
      desired_size = 8

      instance_types = ["t3.small", "t3.micro"]
      capacity_type  = "ON_DEMAND"

      # Enable Cluster Autoscaler discovery tags
      tags = {
        Environment                                     = var.environment
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }
    }
  }

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}
