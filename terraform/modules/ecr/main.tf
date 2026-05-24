locals {
  name_prefix = "${var.project_name}-${var.env}"
  
  repositories = [
    "backend-api",
    "agent-service",
    "posture-analysis-service",
    "report-service",
    "remediation-worker",
    "kvs-consumer-service"
  ]
}

resource "aws_ecr_repository" "main" {
  for_each = toset(local.repositories)
  
  name                 = "${local.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    var.common_tags,
    {
      Name       = "${local.name_prefix}/${each.value}"
      Repository = each.value
    }
  )
}

resource "aws_ecr_lifecycle_policy" "main" {
  for_each   = toset(local.repositories)
  repository = aws_ecr_repository.main[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
