output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB (use this for Route 53 alias or direct testing)"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (needed for Route 53 alias records)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "http_listener_arn" {
  value = aws_lb_listener.http.arn
}
