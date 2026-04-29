variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used in IRSA trust policy conditions"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider (for IRSA)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS cluster OIDC provider (without https://)"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS books-compressed queue"
  type        = string
}

variable "sqs_dlq_arn" {
  description = "ARN of the SQS dead-letter queue"
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the DB password"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID — scopes the external-dns write permission to this zone only"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for transient compressed book storage"
  type        = string
}
