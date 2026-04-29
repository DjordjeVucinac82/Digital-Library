variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used to tag subnets for ALB auto-discovery"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Frontend nodes and ALB land here."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Backend nodes and RDS land here."
  type        = list(string)
}

variable "azs" {
  description = "Availability zones to deploy into"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Saves cost in dev; not HA."
  type        = bool
  default     = false
}
