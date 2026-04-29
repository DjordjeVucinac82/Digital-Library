output "repository_urls" {
  description = "Map of image name → ECR repository URL"
  value       = { for k, v in aws_ecr_repository.images : k => v.repository_url }
}

output "registry_id" {
  description = "AWS account ID that owns the ECR registry"
  value       = values(aws_ecr_repository.images)[0].registry_id
}
