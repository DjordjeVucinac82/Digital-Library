variable "environment" {
  description = "Deployment environment (dev, test, prod)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used to make the bucket name globally unique"
  type        = string
}
