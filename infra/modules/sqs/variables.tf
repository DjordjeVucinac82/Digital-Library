variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "queue_name" {
  description = "Base name for the SQS queue (without environment suffix)"
  type        = string
  default     = "books-compressed"
}

variable "message_retention_seconds" {
  description = "How long SQS retains an undelivered message (seconds). Default = 4 days."
  type        = number
  default     = 345600
}

variable "visibility_timeout_seconds" {
  description = "How long a message is invisible after being received. Set >= your worker processing time."
  type        = number
  default     = 60
}

variable "max_receive_count" {
  description = "Number of times a message can be received before being moved to the DLQ"
  type        = number
  default     = 3
}
