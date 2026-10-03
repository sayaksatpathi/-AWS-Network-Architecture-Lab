resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|"
}

# ── Secrets Manager ───────────────────────────────────────────────────────────
# Store DB credentials in Secrets Manager. The application retrieves them
# at runtime rather than baking them into config files or environment variables.
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project_name}/rds/${var.db_name}"
  description             = "RDS credentials for ${var.project_name}"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    engine   = var.db_engine
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.db_name
  })

  depends_on = [aws_db_instance.this]
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────
# Tells RDS which subnets to place database instances in.
# Always use two subnets in different AZs for potential Multi-AZ.
resource "aws_db_subnet_group" "this" {
  name        = "${var.project_name}-db-subnet-group"
  subnet_ids  = var.private_db_subnet_ids
  description = "Private database subnets for ${var.project_name}"

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ── RDS Parameter Group ────────────────────────────────────────────────────────
resource "aws_db_parameter_group" "this" {
  name        = "${var.project_name}-pg15"
  family      = "postgres15"
  description = "Parameter group for ${var.project_name} PostgreSQL 15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-pg15"
  }
}

# ── RDS Instance ──────────────────────────────────────────────────────────────
# PRIVATE: publicly_accessible = false.
# No route to internet exists in the DB subnet's route table.
# Even if publicly_accessible were true, the NACL and SG would block all traffic
# except from the application security group.
resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-db"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  parameter_group_name   = aws_db_parameter_group.this.name

  allocated_storage     = var.allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = var.multi_az
  publicly_accessible    = false
  deletion_protection    = false
  skip_final_snapshot    = true
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Enable enhanced monitoring
  monitoring_interval = 0

  tags = {
    Name = "${var.project_name}-db"
  }
}
