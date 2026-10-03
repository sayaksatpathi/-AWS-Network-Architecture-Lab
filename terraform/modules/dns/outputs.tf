output "certificate_arn" {
  description = "ACM certificate ARN (empty if TLS not configured)"
  value       = var.create_tls ? aws_acm_certificate.this[0].arn : ""
}

output "app_fqdn" {
  description = "Fully qualified domain name for the application"
  value       = var.create_dns ? "${var.subdomain}.${var.domain_name}" : ""
}
