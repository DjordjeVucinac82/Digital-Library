output "cluster_name" {
  description = "EKS cluster name (used in kubeconfig and kubectl commands)"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — needed to create IRSA trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL without https:// prefix — used in IRSA trust policy conditions"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group — used to allow RDS access from nodes"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
