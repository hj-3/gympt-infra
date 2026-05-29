locals {
  name_prefix = "${var.project_name}-${var.env}"
}

# -------------------------------------------------------
# KMS Keys (root / worker-auth / recovery)
# -------------------------------------------------------
resource "aws_kms_key" "boundary_root" {
  description             = "${local.name_prefix} Boundary root key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = merge(var.common_tags, { Name = "${local.name_prefix}-boundary-root" })
}

resource "aws_kms_alias" "boundary_root" {
  name          = "alias/${local.name_prefix}-boundary-root"
  target_key_id = aws_kms_key.boundary_root.key_id
}

resource "aws_kms_key" "boundary_worker_auth" {
  description             = "${local.name_prefix} Boundary worker-auth key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = merge(var.common_tags, { Name = "${local.name_prefix}-boundary-worker-auth" })
}

resource "aws_kms_alias" "boundary_worker_auth" {
  name          = "alias/${local.name_prefix}-boundary-worker-auth"
  target_key_id = aws_kms_key.boundary_worker_auth.key_id
}

resource "aws_kms_key" "boundary_recovery" {
  description             = "${local.name_prefix} Boundary recovery key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = merge(var.common_tags, { Name = "${local.name_prefix}-boundary-recovery" })
}

resource "aws_kms_alias" "boundary_recovery" {
  name          = "alias/${local.name_prefix}-boundary-recovery"
  target_key_id = aws_kms_key.boundary_recovery.key_id
}

# -------------------------------------------------------
# IAM Role for EC2
# -------------------------------------------------------
resource "aws_iam_role" "boundary" {
  name = "${local.name_prefix}-boundary-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.common_tags, { Name = "${local.name_prefix}-boundary-role" })
}

resource "aws_iam_role_policy_attachment" "boundary_ssm" {
  role       = aws_iam_role.boundary.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "boundary_kms" {
  name = "${local.name_prefix}-boundary-kms-policy"
  role = aws_iam_role.boundary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey"
      ]
      Resource = [
        aws_kms_key.boundary_root.arn,
        aws_kms_key.boundary_worker_auth.arn,
        aws_kms_key.boundary_recovery.arn,
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "boundary" {
  name = "${local.name_prefix}-boundary-profile"
  role = aws_iam_role.boundary.name
  tags = var.common_tags
}

# -------------------------------------------------------
# Security Group
# -------------------------------------------------------
resource "aws_security_group" "boundary" {
  name        = "${local.name_prefix}-boundary-sg"
  description = "HashiCorp Boundary controller + worker"
  vpc_id      = var.vpc_id

  ingress {
    description = "Boundary API / UI"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Boundary cluster (controller <-> worker)"
    from_port   = 9201
    to_port     = 9201
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Boundary proxy (client sessions)"
    from_port   = 9202
    to_port     = 9202
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${local.name_prefix}-boundary-sg" })
}

# -------------------------------------------------------
# AMI (Amazon Linux 2023)
# -------------------------------------------------------
data "aws_ami" "al2023" {
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

# -------------------------------------------------------
# EC2 Instance
# -------------------------------------------------------
resource "aws_instance" "boundary" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.boundary.id]
  iam_instance_profile        = aws_iam_instance_profile.boundary.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/setup-boundary.sh.tpl", {
    db_password            = var.db_password
    boundary_version       = var.boundary_version
    kms_root_key_id        = aws_kms_key.boundary_root.key_id
    kms_worker_auth_key_id = aws_kms_key.boundary_worker_auth.key_id
    kms_recovery_key_id    = aws_kms_key.boundary_recovery.key_id
    aws_region             = var.aws_region
  })

  user_data_replace_on_change = true

  tags = merge(var.common_tags, { Name = "${local.name_prefix}-boundary" })
}
