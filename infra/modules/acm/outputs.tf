output "certificate_arn" {
  description = "ARN of the validated ACM certificate — annotate on the ALB Ingress"
  # Using the validation resource ARN (not the certificate ARN directly) ensures
  # the output is only available after the cert has been fully validated.
  value = aws_acm_certificate_validation.this.certificate_arn
}
