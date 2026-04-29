output "db_endpoint" {
  description = "RDS instance hostname (injected into pods as DB_HOST)"
  value       = aws_db_instance.main.address
}

output "db_name" {
  description = "Database schema name"
  value       = aws_db_instance.main.db_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the full DB credentials JSON"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_security_group_id" {
  description = "Security group ID of the RDS instance"
  value       = aws_security_group.rds.id
}
