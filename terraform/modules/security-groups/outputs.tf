output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "Application tier security group ID"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Database tier security group ID"
  value       = aws_security_group.db.id
}
