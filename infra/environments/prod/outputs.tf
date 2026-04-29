output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "db_secret_arn" {
  value = module.rds.db_secret_arn
}

output "compressor_irsa_arn" {
  value = module.iam.compressor_irsa_arn
}

output "worker_irsa_arn" {
  value = module.iam.worker_irsa_arn
}

output "lb_controller_irsa_arn" {
  value = module.iam.lb_controller_irsa_arn
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
  description = "ACM certificate ARN for 444noresponse.com — annotate on the frontend Ingress"
  value       = module.acm.certificate_arn
}

output "s3_bucket_name" {
  description = "S3 bucket for transient compressed books — inject as S3_BUCKET_NAME in pods"
  value       = module.s3.bucket_name
}
