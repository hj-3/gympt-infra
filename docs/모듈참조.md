# Terraform 모듈 참조

## 목차
- [네트워크 모듈](#네트워크-모듈)
- [컴퓨팅 모듈](#컴퓨팅-모듈)
- [데이터베이스 모듈](#데이터베이스-모듈)
- [스토리지 모듈](#스토리지-모듈)
- [메시징 모듈](#메시징-모듈)
- [모니터링 모듈](#모니터링-모듈)

## 네트워크 모듈

### VPC 모듈

**위치**: `terraform/modules/vpc`

**기능**:
- VPC 생성 및 관리
- Multi-AZ 서브넷 구성
- NAT Gateway, Internet Gateway
- VPC Flow Logs
- VPC Endpoints

**사용 예시**:
```hcl
module "vpc" {
  source = "../../modules/vpc"
  
  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"
  azs         = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
  
  enable_nat_gateway = true
  enable_flow_logs   = true
  
  tags = {
    Environment = "dev"
    Project     = "gympt"
  }
}
```

**주요 변수**:

| 변수 | 설명 | 타입 | 기본값 | 필수 |
|------|------|------|--------|------|
| environment | 환경 이름 | string | - | Y |
| vpc_cidr | VPC CIDR 블록 | string | 10.0.0.0/16 | N |
| azs | 가용 영역 목록 | list(string) | - | Y |
| enable_nat_gateway | NAT Gateway 활성화 | bool | true | N |
| enable_flow_logs | VPC Flow Logs 활성화 | bool | true | N |

**출력값**:

| 이름 | 설명 |
|------|------|
| vpc_id | VPC ID |
| private_subnet_ids | Private 서브넷 ID 목록 |
| public_subnet_ids | Public 서브넷 ID 목록 |
| database_subnet_ids | Database 서브넷 ID 목록 |
| nat_gateway_ips | NAT Gateway 공인 IP 목록 |

## 컴퓨팅 모듈

### EKS 모듈

**위치**: `terraform/modules/eks`

**기능**:
- EKS Control Plane 생성
- Managed Node Groups
- IRSA (IAM Roles for Service Accounts)
- EKS Add-ons 설치

**사용 예시**:
```hcl
module "eks" {
  source = "../../modules/eks"
  
  cluster_name    = "gympt-dev-cluster"
  cluster_version = "1.28"
  
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  
  node_groups = {
    general = {
      instance_types = ["t3.large"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3
      disk_size      = 50
      labels = {
        workload-type = "general"
      }
      taints = []
    }
    
    gpu = {
      instance_types = ["g5.xlarge"]
      min_size       = 0
      max_size       = 5
      desired_size   = 1
      disk_size      = 100
      labels = {
        workload-type = "gpu"
      }
      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NoSchedule"
      }]
    }
  }
  
  tags = var.tags
}
```

**주요 변수**:

| 변수 | 설명 | 타입 | 기본값 | 필수 |
|------|------|------|--------|------|
| cluster_name | 클러스터 이름 | string | - | Y |
| cluster_version | Kubernetes 버전 | string | 1.28 | N |
| vpc_id | VPC ID | string | - | Y |
| private_subnet_ids | Private 서브넷 ID | list(string) | - | Y |
| node_groups | Node Group 구성 | map(object) | - | Y |

**출력값**:

| 이름 | 설명 |
|------|------|
| cluster_id | 클러스터 ID |
| cluster_endpoint | 클러스터 API 엔드포인트 |
| cluster_certificate_authority_data | CA 인증서 |
| oidc_provider_arn | OIDC Provider ARN |

### Karpenter 모듈

**위치**: `terraform/modules/karpenter`

**기능**:
- Karpenter Controller 설치
- Provisioner 구성
- Node Template 설정

**사용 예시**:
```hcl
module "karpenter" {
  source = "../../modules/karpenter"
  
  cluster_name          = module.eks.cluster_id
  cluster_endpoint      = module.eks.cluster_endpoint
  oidc_provider_arn     = module.eks.oidc_provider_arn
  
  enable_spot_instances = true
  instance_types        = ["t3.large", "t3.xlarge", "c6i.xlarge"]
  
  tags = var.tags
}
```

## 데이터베이스 모듈

### RDS 모듈

**위치**: `terraform/modules/rds`

**기능**:
- PostgreSQL RDS 인스턴스 생성
- Multi-AZ 배포
- 자동 백업 설정
- Parameter Group 관리

**사용 예시**:
```hcl
module "rds" {
  source = "../../modules/rds"
  
  identifier     = "gympt-dev-postgres"
  engine_version = "15.4"
  instance_class = "db.t3.medium"
  
  allocated_storage = 100
  multi_az          = false
  
  database_name  = "gympt"
  master_username = "gympt_admin"
  master_password_secret_arn = aws_secretsmanager_secret.rds_password.arn
  
  vpc_id                     = module.vpc.vpc_id
  database_subnet_ids        = module.vpc.database_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  
  backup_retention_period = 7
  
  tags = var.tags
}
```

**주요 변수**:

| 변수 | 설명 | 타입 | 기본값 | 필수 |
|------|------|------|--------|------|
| identifier | RDS 인스턴스 ID | string | - | Y |
| engine_version | PostgreSQL 버전 | string | 15.4 | N |
| instance_class | 인스턴스 클래스 | string | - | Y |
| allocated_storage | 스토리지 (GB) | number | 100 | N |
| multi_az | Multi-AZ 활성화 | bool | false | N |
| backup_retention_period | 백업 보관 일수 | number | 7 | N |

### DynamoDB 모듈

**위치**: `terraform/modules/dynamodb`

**기능**:
- DynamoDB 테이블 생성
- GSI (Global Secondary Index) 설정
- TTL 설정
- Auto Scaling

**사용 예시**:
```hcl
module "dynamodb" {
  source = "../../modules/dynamodb"
  
  tables = {
    sessions = {
      hash_key       = "sessionId"
      range_key      = null
      billing_mode   = "PAY_PER_REQUEST"
      ttl_enabled    = true
      ttl_attribute  = "expiresAt"
      
      global_secondary_indexes = []
    }
    
    workout_plans = {
      hash_key       = "userId"
      range_key      = "planId"
      billing_mode   = "PAY_PER_REQUEST"
      ttl_enabled    = false
      ttl_attribute  = null
      
      global_secondary_indexes = [{
        name            = "planId-index"
        hash_key        = "planId"
        range_key       = null
        projection_type = "ALL"
      }]
    }
  }
  
  environment = "dev"
  tags        = var.tags
}
```

### ElastiCache 모듈

**위치**: `terraform/modules/elasticache`

**기능**:
- Redis 클러스터 생성
- Multi-AZ 자동 장애 조치
- Parameter Group 설정

**사용 예시**:
```hcl
module "elasticache" {
  source = "../../modules/elasticache"
  
  cluster_id      = "gympt-dev-redis"
  node_type       = "cache.t3.medium"
  num_cache_nodes = 2
  engine_version  = "7.0"
  
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.database_subnet_ids
  security_group_ids = [module.eks.node_security_group_id]
  
  tags = var.tags
}
```

## 스토리지 모듈

### S3 모듈

**위치**: `terraform/modules/s3`

**기능**:
- S3 버킷 생성
- Versioning 설정
- Lifecycle 정책
- CORS 설정
- 암호화

**사용 예시**:
```hcl
module "s3" {
  source = "../../modules/s3"
  
  buckets = {
    videos = {
      versioning_enabled = true
      
      lifecycle_rules = [{
        id                        = "archive-old-videos"
        expiration_days           = 365
        transition_days           = 30
        transition_storage_class  = "STANDARD_IA"
      }]
      
      cors_rules = [{
        allowed_headers = ["*"]
        allowed_methods = ["GET", "PUT", "POST"]
        allowed_origins = ["https://gympt.com"]
      }]
    }
    
    reports = {
      versioning_enabled = true
      lifecycle_rules    = []
      cors_rules         = []
    }
  }
  
  environment = "dev"
  tags        = var.tags
}
```

### ECR 모듈

**위치**: `terraform/modules/ecr`

**기능**:
- ECR 레포지토리 생성
- 이미지 스캔 설정
- Lifecycle 정책

**사용 예시**:
```hcl
module "ecr" {
  source = "../../modules/ecr"
  
  repositories = {
    "gympt/backend-api" = {
      image_tag_mutability = "MUTABLE"
      scan_on_push         = true
      lifecycle_policy     = jsonencode({
        rules = [{
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
        }]
      })
    }
  }
  
  tags = var.tags
}
```

## 메시징 모듈

### SQS 모듈

**위치**: `terraform/modules/sqs`

**기능**:
- SQS 큐 생성
- Dead Letter Queue 설정
- 암호화

**사용 예시**:
```hcl
module "sqs" {
  source = "../../modules/sqs"
  
  queues = {
    posture_analysis = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 1209600  # 14 days
      max_receive_count          = 3
      delay_seconds              = 0
    }
    
    report_generation = {
      visibility_timeout_seconds = 600
      message_retention_seconds  = 1209600
      max_receive_count          = 3
      delay_seconds              = 0
    }
  }
  
  environment = "dev"
  tags        = var.tags
}
```

### EventBridge 모듈

**위치**: `terraform/modules/eventbridge`

**기능**:
- EventBridge 규칙 생성
- 이벤트 패턴 설정
- 타겟 구성

**사용 예시**:
```hcl
module "eventbridge" {
  source = "../../modules/eventbridge"
  
  rules = {
    posture_completed = {
      description = "Trigger when posture analysis is completed"
      
      event_pattern = jsonencode({
        source      = ["gympt.posture-analysis"]
        detail-type = ["Posture Analysis Completed"]
      })
      
      targets = [{
        arn = module.sqs.queue_arns["report_generation"]
      }]
    }
  }
  
  environment = "dev"
  tags        = var.tags
}
```

### Lambda 모듈

**위치**: `terraform/modules/lambda`

**기능**:
- Lambda 함수 생성
- VPC 연결
- 환경 변수 설정

**사용 예시**:
```hcl
module "lambda" {
  source = "../../modules/lambda"
  
  functions = {
    report_generator = {
      runtime     = "python3.11"
      handler     = "index.handler"
      memory_size = 1024
      timeout     = 300
      
      environment = {
        S3_BUCKET = module.s3.bucket_names["reports"]
        DB_HOST   = module.rds.endpoint
      }
      
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.eks.node_security_group_id]
      }
    }
  }
  
  environment = "dev"
  tags        = var.tags
}
```

## 모니터링 모듈

### CloudWatch 모듈

**위치**: `terraform/modules/cloudwatch`

**기능**:
- CloudWatch 알람 생성
- Log Group 관리
- Dashboard 구성

**사용 예시**:
```hcl
module "cloudwatch" {
  source = "../../modules/cloudwatch"
  
  alarms = {
    eks_node_cpu_high = {
      metric_name         = "CPUUtilization"
      namespace           = "AWS/EC2"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      evaluation_periods  = 2
      period              = 300
      statistic           = "Average"
      alarm_actions       = [aws_sns_topic.alerts.arn]
    }
    
    rds_cpu_high = {
      metric_name         = "CPUUtilization"
      namespace           = "AWS/RDS"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      evaluation_periods  = 2
      period              = 300
      statistic           = "Average"
      alarm_actions       = [aws_sns_topic.alerts.arn]
    }
  }
  
  environment = "dev"
  tags        = var.tags
}
```

### KVS 모듈

**위치**: `terraform/modules/kvs`

**기능**:
- Kinesis Video Streams 생성
- 데이터 보관 설정

**사용 예시**:
```hcl
module "kvs" {
  source = "../../modules/kvs"
  
  streams = {
    workout_stream = {
      data_retention_in_hours = 24
      media_type              = "video/h264"
    }
  }
  
  environment = "dev"
  tags        = var.tags
}
```

## 모듈 개발 가이드

### 표준 구조

```
modules/
└── module-name/
    ├── main.tf          # 주요 리소스
    ├── variables.tf     # 입력 변수
    ├── outputs.tf       # 출력값
    ├── versions.tf      # Provider 버전
    └── README.md        # 문서
```

### 변수 정의 예시

```hcl
variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
```

### 출력값 정의 예시

```hcl
output "id" {
  description = "Resource ID"
  value       = aws_resource.main.id
}

output "arn" {
  description = "Resource ARN"
  value       = aws_resource.main.arn
}
```

---

**다음**: [배포 절차](배포절차.md) | [인프라 가이드](인프라가이드.md)
