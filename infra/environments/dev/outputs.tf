# Run `terraform output` after apply to get these values.
# The CD pipeline and INSTRUCTIONS.md reference these outputs.

output "cluster_name" {
  description = "EKS cluster name — use with: aws eks update-kubeconfig --name <value>"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  description = "Map of image name → ECR URL. Use these in K8s Deployment manifests."
  value       = module.ecr.repository_urls
}

output "sqs_queue_url" {
  description = "SQS queue URL — inject as SQS_QUEUE_URL env var in compressor and worker pods"
  value       = module.sqs.queue_url
}

output "db_endpoint" {
  description = "RDS MySQL hostname — inject as DB_HOST env var in worker pod"
  value       = module.rds.db_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN — use in INSTRUCTIONS.md step 7 to pull the DB password"
  value       = module.rds.db_secret_arn
}

output "compressor_irsa_arn" {
  description = "ARN to annotate on the compressor Kubernetes ServiceAccount"
  value       = module.iam.compressor_irsa_arn
}

output "worker_irsa_arn" {
  description = "ARN to annotate on the worker Kubernetes ServiceAccount"
  value       = module.iam.worker_irsa_arn
}

output "lb_controller_irsa_arn" {
  description = "ARN for the AWS Load Balancer Controller Helm values"
  value       = module.iam.lb_controller_irsa_arn
}

output "external_dns_irsa_arn" {
  description = "ARN for the external-dns Helm values"
  value       = module.iam.external_dns_irsa_arn
}

output "cluster_autoscaler_irsa_arn" {
  description = "ARN for the Cluster Autoscaler Helm values"
  value       = module.iam.cluster_autoscaler_irsa_arn
}

output "keda_operator_irsa_arn" {
  description = "ARN for the KEDA operator Helm values"
  value       = module.iam.keda_operator_irsa_arn
}

output "certificate_arn" {
  description = "ACM certificate ARN for dev.444noresponse.com — annotate on the frontend Ingress"
  value       = module.acm.certificate_arn
}

output "s3_bucket_name" {
  description = "S3 bucket for transient compressed books — inject as S3_BUCKET_NAME in pods"
  value       = module.s3.bucket_name
}
