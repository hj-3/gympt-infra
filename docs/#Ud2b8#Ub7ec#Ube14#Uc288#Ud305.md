# 트러블슈팅 가이드

## 목차
- [Terraform 문제](#terraform-문제)
- [네트워크 문제](#네트워크-문제)
- [EKS 문제](#eks-문제)
- [데이터베이스 문제](#데이터베이스-문제)
- [성능 문제](#성능-문제)

## Terraform 문제

### State Lock 오류

**증상**:
```
Error: Error acquiring the state lock
Lock Info:
  ID:        abc123-def456-ghi789
  Path:      gympt-tfstate/dev/terraform.tfstate
  Operation: OperationTypeApply
  Who:       user@host
  Version:   1.6.0
  Created:   2024-05-19 10:30:00 UTC
```

**원인**:
- 이전 Terraform 실행이 비정상 종료
- 동시에 여러 사용자가 실행
- 네트워크 문제로 Lock 해제 실패

**해결 방법**:

```bash
# 1. Lock 상태 확인
aws dynamodb scan \
  --table-name gympt-tfstate-lock \
  --region ap-northeast-2

# 2. Lock 소유자 확인
# - 다른 사용자가 실행 중인지 확인
# - 해당 사용자에게 연락

# 3. Lock 강제 해제 (주의!)
terraform force-unlock LOCK_ID

# 4. 재실행
terraform plan
```

**예방**:
- 팀 내 배포 일정 조율
- CI/CD로 자동화
- State Lock 타임아웃 설정

---

### Provider 플러그인 오류

**증상**:
```
Error: Failed to query available provider packages
```

**원인**:
- Provider 버전 충돌
- 캐시 손상
- 네트워크 문제

**해결 방법**:

```bash
# 1. 캐시 삭제
rm -rf .terraform
rm -f .terraform.lock.hcl

# 2. Provider 재설치
terraform init -upgrade

# 3. 특정 버전 지정
terraform init -upgrade -plugin-dir=/path/to/plugins
```

---

### Resource Already Exists 오류

**증상**:
```
Error: Error creating EKS Cluster: ResourceInUseException: 
Cluster already exists: gympt-dev-cluster
```

**원인**:
- State와 실제 리소스 불일치
- 이전 배포의 잔여 리소스
- Import 필요

**해결 방법**:

```bash
# 1. 리소스 확인
aws eks describe-cluster --name gympt-dev-cluster --region ap-northeast-2

# 2. State에 Import
terraform import module.eks.aws_eks_cluster.main gympt-dev-cluster

# 3. Plan 확인
terraform plan

# 또는 리소스 삭제 후 재생성
aws eks delete-cluster --name gympt-dev-cluster --region ap-northeast-2
terraform apply
```

---

### State Drift 감지

**증상**:
```
Note: Objects have changed outside of Terraform
```

**원인**:
- AWS Console에서 수동 변경
- 다른 도구로 변경
- Auto Scaling 등 자동 변경

**해결 방법**:

```bash
# 1. Drift 확인
terraform plan -refresh-only

# 2. State 업데이트
terraform apply -refresh-only

# 3. 변경 사항 적용
terraform plan
terraform apply
```

---

## 네트워크 문제

### RDS 접속 불가

**증상**:
```bash
psql: could not connect to server: Connection timed out
```

**원인**:
- Security Group 규칙 누락
- Network ACL 차단
- 잘못된 서브넷 배치
- DNS 해상도 실패

**해결 방법**:

```bash
# 1. RDS 엔드포인트 확인
aws rds describe-db-instances \
  --db-instance-identifier gympt-dev-postgres \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text

# 2. Security Group 확인
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions'

# 3. VPC 내에서 접근 테스트
# EKS Pod에서 실행:
kubectl run -it --rm psql-test \
  --image=postgres:15 \
  --restart=Never \
  -- psql -h gympt-dev-postgres.xxxxx.ap-northeast-2.rds.amazonaws.com -U gympt_admin -d gympt

# 4. Security Group 규칙 추가
aws ec2 authorize-security-group-ingress \
  --group-id sg-rds \
  --protocol tcp \
  --port 5432 \
  --source-group sg-eks-nodes
```

---

### NAT Gateway 비용 과다

**증상**:
- 예상보다 높은 NAT Gateway 요금
- 데이터 전송 비용 증가

**원인**:
- VPC Endpoints 미사용
- 불필요한 인터넷 트래픽
- S3/DynamoDB 트래픽이 NAT Gateway 경유

**해결 방법**:

```hcl
# 1. Gateway Endpoints 추가 (무료)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.ap-northeast-2.s3"
  route_table_ids = aws_route_table.private[*].id
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.ap-northeast-2.dynamodb"
  route_table_ids = aws_route_table.private[*].id
}

# 2. Interface Endpoints 추가 (ECR)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ap-northeast-2.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ap-northeast-2.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}
```

```bash
# 3. 트래픽 분석
# VPC Flow Logs에서 NAT Gateway 트래픽 확인
aws ec2 describe-flow-logs \
  --filter "Name=resource-id,Values=vpc-xxxxx"
```

---

### EKS Pod가 외부 접근 불가

**증상**:
```
Error: Get "https://api.example.com": dial tcp: i/o timeout
```

**원인**:
- NAT Gateway 미설정
- Route Table 설정 오류
- Security Group Egress 차단

**해결 방법**:

```bash
# 1. NAT Gateway 확인
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'NatGateways[*].[NatGatewayId,State]'

# 2. Route Table 확인
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'RouteTables[*].Routes'

# 3. Security Group Egress 확인
aws ec2 describe-security-groups \
  --group-ids sg-eks-nodes \
  --query 'SecurityGroups[0].IpPermissionsEgress'

# 4. Pod에서 네트워크 테스트
kubectl run -it --rm debug \
  --image=nicolaka/netshoot \
  --restart=Never \
  -- curl -v https://api.example.com
```

---

## EKS 문제

### Pod가 Pending 상태

**증상**:
```
NAME        READY   STATUS    RESTARTS   AGE
my-pod      0/1     Pending   0          5m
```

**원인**:
- 리소스 부족 (CPU/Memory)
- Node Selector 불일치
- Taints/Tolerations 불일치
- PV/PVC 문제

**해결 방법**:

```bash
# 1. Pod 상태 확인
kubectl describe pod my-pod

# Events 섹션 확인:
# - 0/3 nodes are available: insufficient cpu
# - 0/3 nodes are available: 1 node(s) didn't match node selector

# 2. Node 리소스 확인
kubectl top nodes
kubectl describe nodes

# 3. Karpenter/Cluster Autoscaler 확인
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# 4. Node 추가 (수동)
# terraform.tfvars에서 desired_size 증가
node_groups = {
  general = {
    desired_size = 5  # 3에서 5로 증가
  }
}

terraform apply
```

---

### ImagePullBackOff 오류

**증상**:
```
NAME        READY   STATUS             RESTARTS   AGE
my-pod      0/1     ImagePullBackOff   0          2m
```

**원인**:
- ECR 권한 부족
- 이미지 태그 오류
- VPC Endpoints 미설정

**해결 방법**:

```bash
# 1. Pod 이벤트 확인
kubectl describe pod my-pod

# 2. ECR 로그인 확인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com

# 3. 이미지 존재 확인
aws ecr describe-images \
  --repository-name gympt/backend-api \
  --image-ids imageTag=latest

# 4. IRSA 권한 확인
kubectl describe serviceaccount -n backend-api backend-api-sa

# 5. VPC Endpoints 확인 (ECR 접근용)
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'VpcEndpoints[?ServiceName==`com.amazonaws.ap-northeast-2.ecr.dkr`]'
```

---

### Node가 NotReady 상태

**증상**:
```
NAME                              STATUS     ROLES    AGE   VERSION
ip-10-0-11-123.ap-northeast-2...  NotReady   <none>   10m   v1.28.0
```

**원인**:
- kubelet 실패
- CNI 플러그인 오류
- 리소스 부족
- Security Group 문제

**해결 방법**:

```bash
# 1. Node 상태 확인
kubectl describe node ip-10-0-11-123

# 2. Node 로그 확인 (SSM Session Manager)
aws ssm start-session --target i-xxxxx

# Node에서 실행:
sudo journalctl -u kubelet -n 100 --no-pager

# 3. CNI 플러그인 확인
kubectl get pods -n kube-system -l k8s-app=aws-node

# 4. Node 재시작
kubectl drain ip-10-0-11-123 --ignore-daemonsets --delete-emptydir-data
kubectl delete node ip-10-0-11-123

# Auto Scaling Group이 새 노드 자동 생성
```

---

## 데이터베이스 문제

### RDS 성능 저하

**증상**:
- 쿼리 응답 시간 증가
- CPU 사용률 80% 이상
- Connection 부족

**원인**:
- 인덱스 누락
- 비효율적인 쿼리
- 인스턴스 크기 부족
- Connection Pool 설정 오류

**해결 방법**:

```bash
# 1. Performance Insights 확인
# AWS Console > RDS > Performance Insights

# 2. Slow Query Log 확인
aws rds download-db-log-file-portion \
  --db-instance-identifier gympt-dev-postgres \
  --log-file-name slowquery/postgresql.log.2024-05-19

# 3. 현재 연결 수 확인
psql -h gympt-dev-postgres.xxxxx.ap-northeast-2.rds.amazonaws.com \
  -U gympt_admin -d gympt \
  -c "SELECT count(*) FROM pg_stat_activity;"

# 4. 인스턴스 크기 증가
# terraform.tfvars 수정
rds_instance_class = "db.r6i.xlarge"  # db.t3.medium에서 증가

terraform apply

# 5. Read Replica 추가
resource "aws_db_instance" "read_replica" {
  identifier             = "gympt-${var.environment}-postgres-replica"
  replicate_source_db    = aws_db_instance.main.identifier
  instance_class         = var.rds_instance_class
  publicly_accessible    = false
  skip_final_snapshot    = true
  
  tags = var.tags
}
```

---

### ElastiCache 메모리 부족

**증상**:
- Redis 응답 느림
- 메모리 사용률 90% 이상
- Eviction 발생

**원인**:
- 캐시 크기 부족
- TTL 미설정
- 메모리 누수

**해결 방법**:

```bash
# 1. 메모리 사용률 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name DatabaseMemoryUsagePercentage \
  --dimensions Name=CacheClusterId,Value=gympt-dev-redis \
  --start-time 2024-05-19T00:00:00Z \
  --end-time 2024-05-19T23:59:59Z \
  --period 300 \
  --statistics Average

# 2. Eviction 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name Evictions \
  --dimensions Name=CacheClusterId,Value=gympt-dev-redis \
  --start-time 2024-05-19T00:00:00Z \
  --end-time 2024-05-19T23:59:59Z \
  --period 3600 \
  --statistics Sum

# 3. 인스턴스 크기 증가
redis_node_type = "cache.r6g.large"  # cache.t3.medium에서 증가

terraform apply

# 4. 애플리케이션에서 TTL 설정
# Redis 명령어:
SET key value EX 3600  # 1시간 TTL
```

---

## 성능 문제

### EKS Pod CPU/Memory 부족

**증상**:
- Pod가 OOMKilled
- CPU Throttling 발생
- 응답 시간 증가

**해결 방법**:

```yaml
# 1. Resource Limits 증가
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: backend-api
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi

# 2. HPA 설정
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend-api
  minReplicas: 3
  maxReplicas: 30
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

### S3 업로드/다운로드 느림

**증상**:
- S3 전송 속도 느림
- 타임아웃 발생

**원인**:
- 단일 연결 사용
- 멀티파트 업로드 미사용
- Transfer Acceleration 미사용

**해결 방법**:

```python
# 멀티파트 업로드 사용
import boto3
from boto3.s3.transfer import TransferConfig

s3 = boto3.client('s3')

# 멀티파트 설정
config = TransferConfig(
    multipart_threshold=1024 * 25,  # 25MB
    max_concurrency=10,
    multipart_chunksize=1024 * 25,
    use_threads=True
)

# 업로드
s3.upload_file(
    'large-file.mp4',
    'gympt-videos-dev-123456789012',
    'videos/large-file.mp4',
    Config=config
)
```

```hcl
# Transfer Acceleration 활성화
resource "aws_s3_bucket_accelerate_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id
  status = "Enabled"
}
```

---

### CloudWatch Logs 비용 과다

**증상**:
- 예상보다 높은 CloudWatch 요금
- 로그 볼륨 증가

**해결 방법**:

```bash
# 1. 로그 그룹별 사용량 확인
aws logs describe-log-groups \
  --query 'logGroups[*].[logGroupName,storedBytes]' \
  --output table

# 2. 보관 기간 설정
aws logs put-retention-policy \
  --log-group-name /aws/eks/gympt-dev-cluster \
  --retention-in-days 7

# 3. 불필요한 로그 필터링
# FluentBit 설정:
[FILTER]
    Name    grep
    Match   *
    Exclude log level=DEBUG
```

---

**다음**: [인프라 가이드](인프라가이드.md) | [배포 절차](배포절차.md)
