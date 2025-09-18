# Pull data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# KMS Key for EBS encryption
resource "aws_kms_key" "ebs_key" {
  description             = "KMS key for EBS encryption - ${var.project_name}"
  deletion_window_in_days = 7

  tags = {
    Name = "${var.project_name}-ebs-key"
  }
}

resource "aws_kms_alias" "ebs_key_alias" {
  name          = "alias/${var.project_name}-ebs-key"
  target_key_id = aws_kms_key.ebs_key.key_id
}

# Launch Template for EC2 Instance
resource "aws_launch_template" "main" {
  name_prefix   = "${var.project_name}-lt-"
  description   = "Launch template for secure Docker-enabled EC2"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  # User data script (base64 encoded)
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region                 = var.aws_region
    project_name           = var.project_name
    docker_compose_version = "v2.39.3"
  }))

  # Metadata options (IMDSv2 enforcement)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # EBS optimization
  ebs_optimized = true

  # Block device mappings
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.ebs_key.arn
      iops                  = 3000
      throughput            = 125
      delete_on_termination = true
    }
  }

  # Instance monitoring
  monitoring {
    # Use variable so you can disable detailed monitoring to save costs in student accounts
    enabled = var.enable_detailed_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-instance"
      Environment = var.environment
      Type        = "docker-host"
      Project     = var.project_name
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "${var.project_name}-root-volume"
      Environment = var.environment
      Project     = var.project_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_core,
    aws_iam_role_policy_attachment.cloudwatch_agent
  ]
}

# EC2 Instance
resource "aws_instance" "main" {
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  subnet_id = aws_subnet.private.id

  tags = {
    Name         = "${var.project_name}-docker-instance"
    Environment  = var.environment
    Project      = var.project_name
    Backup       = "daily"
    # NOTE: EC2 TagSpecifications rejected key with a space ("Patch Group").
    # If you want to associate a custom SSM Patch Group, consider using a tag key without spaces (e.g., PatchGroup)
    # and update SSM targeting accordingly, or rely on the default AL2 baseline used by AWS-RunPatchBaseline.
  }

  lifecycle {
    ignore_changes = [launch_template[0].version]
  }
}

