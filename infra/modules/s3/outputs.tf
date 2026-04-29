output "bucket_name" {
  description = "S3 bucket name — inject as S3_BUCKET_NAME in compressor and worker pods"
  value       = aws_s3_bucket.books.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN — used in IAM policy statements"
  value       = aws_s3_bucket.books.arn
}
