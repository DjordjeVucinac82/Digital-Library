# ACM module — requests a certificate for a domain and validates it via Route 53.
#
# How it works:
#   1. aws_acm_certificate  — requests the cert (DNS validation method)
#   2. aws_route53_record   — creates the CNAME records ACM needs to verify ownership
#   3. aws_acm_certificate_validation — waits until ACM marks the cert as ISSUED
#
# The output certificate_arn is only populated after validation completes, so
# any downstream resource (e.g. an Ingress annotation) will wait automatically.

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # Replace the old cert before destroying so there is no downtime window
  lifecycle {
    create_before_destroy = true
  }

  tags = { Environment = var.environment }
}

# ACM provides one CNAME record per domain that must be added to Route 53
# to prove we own the domain. for_each handles the case where a cert covers
# multiple SANs (not used here, but correct practice).
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.hosted_zone_id
}

# Waits until ACM confirms all validation records are present and the cert is ISSUED.
# This can take up to 2 minutes after the CNAME records are created.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
