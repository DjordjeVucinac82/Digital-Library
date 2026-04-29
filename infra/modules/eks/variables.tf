variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID where the cluster runs"
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnet IDs for the frontend node group (public subnets)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Subnet IDs for the backend node group (private subnets)"
  type        = list(string)
}

variable "node_role_arn" {
  description = "IAM role ARN for EKS worker nodes"
  type        = string
}

variable "frontend_instance_type" {
  description = "EC2 instance type for frontend node group"
  type        = string
  default     = "t3.small"
}

variable "backend_instance_type" {
  description = "EC2 instance type for backend node group"
  type        = string
  default     = "t3.medium"
}

variable "frontend_capacity_type" {
  description = "ON_DEMAND or SPOT for frontend nodes"
  type        = string
  default     = "ON_DEMAND"
}

variable "backend_capacity_type" {
  description = "ON_DEMAND or SPOT for backend nodes"
  type        = string
  default     = "ON_DEMAND"
}
