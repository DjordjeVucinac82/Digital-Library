# EKS module — creates the cluster, two node groups, and the OIDC provider.
#
# Node groups:
#   frontend  → public subnets  (t3.small)  — serves nginx + React
#   backend   → private subnets (t3.medium) — runs compressor + worker
#
# Node group labels (role=frontend / role=backend) are used by Kubernetes
# nodeSelector in Deployments to control pod placement.
#
# The OIDC provider is required for IRSA — IAM Roles for Service Accounts.
# Without it, pod-level IAM permissions (SQS, Secrets Manager) won't work.

terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ─── EKS Cluster ──────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name    = var.cluster_name
  version = var.cluster_version

  # Cluster role allows EKS control plane to manage AWS resources on your behalf
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_public_access  = true  # dev: allow kubectl from your laptop
    endpoint_private_access = true  # pods can reach the API server internally

    # Control which IPs can reach the public endpoint.
    # Restrict this to your office/VPN IP in production.
    public_access_cidrs = ["0.0.0.0/0"]
  }

  # Enable control-plane logging for observability
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# ─── Cluster IAM role ─────────────────────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── EKS Addons ───────────────────────────────────────────────────────────────

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  # Uses the latest available version for the cluster's K8s version
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"

  # coredns needs worker nodes to be running before it can be scheduled
  depends_on = [aws_eks_node_group.backend]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
}

# ─── Frontend node group (public subnets) ─────────────────────────────────────

resource "aws_eks_node_group" "frontend" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-frontend"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.public_subnet_ids

  instance_types = [var.frontend_instance_type]
  capacity_type  = var.frontend_capacity_type

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  # Kubernetes label used by nodeSelector in the frontend Deployment
  labels = {
    role = "frontend"
  }

  tags = {
    Name        = "${var.cluster_name}-frontend"
    Environment = var.environment

    # Cluster Autoscaler discovers node groups via these tags
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }

  # Cluster Autoscaler owns DesiredCapacity at runtime — Terraform must not reset it
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_eks_cluster.main]
}

# ─── Backend node group (private subnets) ─────────────────────────────────────

resource "aws_eks_node_group" "backend" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-backend"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = [var.backend_instance_type]
  capacity_type  = var.backend_capacity_type

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  # Kubernetes label used by nodeSelector in compressor and worker Deployments
  labels = {
    role = "backend"
  }

  tags = {
    Name        = "${var.cluster_name}-backend"
    Environment = var.environment

    # Cluster Autoscaler discovers node groups via these tags
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_eks_cluster.main]
}

# ─── OIDC provider (for IRSA) ─────────────────────────────────────────────────

# Fetch the TLS certificate from the EKS OIDC issuer endpoint.
# The thumbprint is required to register the OIDC provider with IAM.
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name        = "${var.cluster_name}-oidc"
    Environment = var.environment
  }
}
