variable "domain_name" {
  description = "The domain to certify — e.g. 444noresponse.com or dev.444noresponse.com"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for the domain — used to create DNS validation records"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, prod) — used for tagging"
  type        = string
}
