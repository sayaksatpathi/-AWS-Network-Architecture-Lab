output "instance_ids" {
  description = "EC2 instance IDs for the application tier"
  value       = aws_instance.app[*].id
}

output "private_ips" {
  description = "Private IP addresses of application instances"
  value       = aws_instance.app[*].private_ip
}
