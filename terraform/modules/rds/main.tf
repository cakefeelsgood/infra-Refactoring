locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "rds"
    }
  )
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.identifier}-subnet-group"
  description = "Private data subnet group for ${local.name_prefix} PostgreSQL RDS"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, {
    Name = "${var.identifier}-subnet-group"
    Role = "rds-subnet-group"
  })
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.identifier}-parameter-group"
  family      = var.parameter_group_family
  description = "Parameter group for ${local.name_prefix} PostgreSQL RDS"

  dynamic "parameter" {
    for_each = var.parameters

    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = merge(local.tags, {
    Name = "${var.identifier}-parameter-group"
    Role = "rds-parameter-group"
  })
}

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.database_name
  username = var.master_username

  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.this.name

  port                = var.port
  publicly_accessible = false
  multi_az            = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : var.final_snapshot_identifier

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = true
  copy_tags_to_snapshot      = true
  delete_automated_backups   = var.delete_automated_backups

  performance_insights_enabled = var.performance_insights_enabled

  tags = merge(local.tags, {
    Name = var.identifier
    Role = "postgresql-rds"
  })
}
