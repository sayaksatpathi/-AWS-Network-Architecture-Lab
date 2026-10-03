# ── Application Load Balancer ──────────────────────────────────────────────────
# Internet-facing. Deployed across both public subnets (multi-AZ).
# TLS is terminated HERE — the private application tier receives plain HTTP.
resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  access_logs {
    bucket  = ""
    prefix  = ""
    enabled = false
  }

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# ── Target Group ─────────────────────────────────────────────────────────────
# Routes to private EC2 instances.
# Health checks confirm each target is serving requests before sending traffic.
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-app-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-app-tg"
  }
}

# ── HTTP Listener (redirect to HTTPS) ─────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.create_tls ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.create_tls ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.create_tls ? [] : [1]
      content {
        target_group {
          arn = aws_lb_target_group.app.arn
        }
      }
    }
  }
}

# ── HTTPS Listener (when TLS is configured) ────────────────────────────────────
resource "aws_lb_listener" "https" {
  count = var.create_tls ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
