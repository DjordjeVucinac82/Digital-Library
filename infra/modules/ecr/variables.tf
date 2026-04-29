variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "image_names" {
  description = "Names of the Docker images to create ECR repositories for"
  type        = list(string)
  default     = ["frontend", "compressor", "worker"]
}

variable "image_tag_mutability" {
  description = "Whether image tags can be overwritten (MUTABLE) or not (IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}
