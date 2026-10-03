# ── DNS Module ────────────────────────────────────────────────────────────────
# This module is only provisioned when create_dns = true AND a valid
# Route 53 hosted zone exists for the domain_name.

data "aws_route53_zone" "this" {
  count        = var.create_dns ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

# ── ACM Certificate ───────────────────────────────────────────────────────────
# Must be in the same region as the ALB (not us-east-1 for non-CloudFront ALBs).
resource "aws_acm_certificate" "this" {
  count             = var.create_tls ? 1 : 0
  domain_name       = "${var.subdomain}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cert"
  }
}

# DNS validation record for ACM
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in (var.create_tls ? aws_acm_certificate.this[0].domain_validation_options : []) :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.create_tls ? 1 : 0
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ── Route 53 Alias Record → ALB ───────────────────────────────────────────────
# An alias record resolves the subdomain to the ALB's DNS name.
# Traffic flow:
#   User types app.example.com
#   → Route 53 returns ALB DNS name
#   → Client connects to ALB IP(s)
#   → ALB forwards to private application
resource "aws_route53_record" "app" {
  count   = var.create_dns ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "${var.subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
