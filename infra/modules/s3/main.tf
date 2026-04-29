# S3 module — transient storage for compressed book PDFs.
#
# The compressor uploads compressed bytes here and sends only the S3 key to SQS.
# The worker downloads the bytes, persists to RDS, then deletes the S3 object.
# SQS has a 256 KB message limit — this pattern handles arbitrarily large PDFs.

locals {
  bucket_name = "digital-library-books-${var.environment}-${var.account_id}"
}

resource "aws_s3_bucket" "books" {
  bucket = local.bucket_name

  # Safety net: delete objects after 1 day in case the worker fails to clean up
  lifecycle_rule {
    id      = "expire-unprocessed-books"
    enabled = true
    prefix  = "books/"

    expiration {
      days = 1
    }
  }

  tags = {
    Name        = local.bucket_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "books" {
  bucket = aws_s3_bucket.books.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "books" {
  bucket = aws_s3_bucket.books.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

