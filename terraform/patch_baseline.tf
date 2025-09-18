# Patch Baseline untuk Amazon Linux
resource "aws_ssm_patch_baseline" "amazon_linux" {
  name             = "${var.project_name}-amazon-linux-baseline"
  description      = "Patch baseline for Amazon Linux instances - ${var.project_name}"
  operating_system = "AMAZON_LINUX_2"

  approval_rule {
    approve_after_days  = 0
    compliance_level    = "HIGH"
    enable_non_security = false

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security"]
    }
  }

  tags = {
    Name        = "${var.project_name}-patch-baseline"
    Environment = var.environment
  }

  # Workaround for AWS provider tags_all inconsistency when using provider default_tags
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Patch Group
resource "aws_ssm_patch_group" "main" {
  baseline_id = aws_ssm_patch_baseline.amazon_linux.id
  patch_group = "${var.project_name}-patch-group"
}

# Maintenance Window
resource "aws_ssm_maintenance_window" "main" {
  name        = "${var.project_name}-maintenance-window"
  description = "Maintenance window for ${var.project_name} instances"
  schedule    = "cron(0 2 ? * SUN *)" # Sunday 2 AM
  duration    = 3
  cutoff      = 1

  tags = {
    Name        = "${var.project_name}-maintenance-window"
    Environment = var.environment
  }

  # Workaround for AWS provider tags_all inconsistency when using provider default_tags
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Maintenance Window Target
resource "aws_ssm_maintenance_window_target" "main" {
  window_id     = aws_ssm_maintenance_window.main.id
  name          = "${var.project_name}-target"
  description   = "Target for ${var.project_name} maintenance window"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Project"
    values = [var.project_name]
  }

  targets {
    key    = "tag:Environment"
    values = [var.environment]
  }
}

# Maintenance Window Task
resource "aws_ssm_maintenance_window_task" "install_patches" {
  window_id        = aws_ssm_maintenance_window.main.id
  name             = "${var.project_name}-install-patches"
  description      = "Install security patches for ${var.project_name}"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance_window_role.arn
  max_concurrency  = "1"
  max_errors       = "0"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.main.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
    }
  }
}

# IAM Role untuk Maintenance Window
resource "aws_iam_role" "maintenance_window_role" {
  name = "${var.project_name}-maintenance-window-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })

  # Workaround for AWS provider tags_all inconsistency when using provider default_tags
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_iam_role_policy_attachment" "maintenance_window_policy" {
  role       = aws_iam_role.maintenance_window_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

