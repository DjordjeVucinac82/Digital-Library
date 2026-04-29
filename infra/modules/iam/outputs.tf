output "node_role_arn" {
  description = "ARN of the EKS node IAM role — passed to both node groups"
  value       = aws_iam_role.eks_node.arn
}

output "compressor_irsa_arn" {
  description = "ARN of the compressor IRSA role — annotate on the compressor ServiceAccount"
  value       = aws_iam_role.compressor_irsa.arn
}

output "worker_irsa_arn" {
  description = "ARN of the worker IRSA role — annotate on the worker ServiceAccount"
  value       = aws_iam_role.worker_irsa.arn
}

output "lb_controller_irsa_arn" {
  description = "ARN of the LB Controller IRSA role — used in the Helm values for the LB Controller"
  value       = aws_iam_role.lb_controller_irsa.arn
}

output "external_dns_irsa_arn" {
  description = "ARN of the external-dns IRSA role — used in the Helm values for external-dns"
  value       = aws_iam_role.external_dns_irsa.arn
}

output "cluster_autoscaler_irsa_arn" {
  description = "ARN of the Cluster Autoscaler IRSA role — used in the Helm values for cluster-autoscaler"
  value       = aws_iam_role.cluster_autoscaler_irsa.arn
}

output "keda_operator_irsa_arn" {
  description = "ARN of the KEDA operator IRSA role — used in the Helm values for KEDA"
  value       = aws_iam_role.keda_operator_irsa.arn
}
