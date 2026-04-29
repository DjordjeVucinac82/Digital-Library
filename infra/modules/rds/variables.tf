variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the RDS instance will be placed"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets for the DB subnet group"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group ID whose members can connect to RDS on port 3306 (backend node SG)"
  type        = string
}

variable "db_name" {
  description = "Name of the database schema to create"
  type        = string
  default     = "library"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "library"
}

variable "instance_class" {
  description = "RDS instance class (e.g. db.t3.micro for dev, db.t3.small for prod)"
  type        = string
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for HA (recommended for prod, not needed for dev)"
  type        = bool
  default     = false
}

variable "allocated_storage" {
  description = "Allocated storage in GiB"
  type        = number
  default     = 20
}
