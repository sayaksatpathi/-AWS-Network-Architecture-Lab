data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── IAM Role for EC2 (SSM access — no SSH key required) ───────────────────────
resource "aws_iam_role" "app" {
  name = "${var.project_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app-profile"
  role = aws_iam_role.app.name
}

# ── Launch Template ───────────────────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-app-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.app_sg_id]
  }

  key_name = var.key_pair_name != "" ? var.key_pair_name : null

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    app_port    = var.app_port
    project     = var.project_name
    db_host     = var.db_endpoint
    db_name     = var.db_name
    db_user     = var.db_username
    secret_arn  = var.db_secret_arn
    aws_region  = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-app"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── EC2 Instances (one per AZ) ────────────────────────────────────────────────
# Placed in PRIVATE subnets — no public IPs.
# Traffic reaches them only through the ALB.
resource "aws_instance" "app" {
  count = var.instance_count

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  subnet_id = var.private_app_subnet_ids[count.index % length(var.private_app_subnet_ids)]

  tags = {
    Name = "${var.project_name}-app-${count.index + 1}"
    AZ   = var.private_app_subnet_ids[count.index % length(var.private_app_subnet_ids)]
  }
}

# ── ALB Target Group Attachments ──────────────────────────────────────────────
resource "aws_lb_target_group_attachment" "app" {
  count            = var.instance_count
  target_group_arn = var.target_group_arn
  target_id        = aws_instance.app[count.index].id
  port             = var.app_port
}
