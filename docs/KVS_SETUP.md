# Amazon Kinesis Video Streams (KVS) 설정 가이드

## 개요

GYMPT 프로젝트에서는 실시간 운동 영상 스트리밍을 위해 Amazon Kinesis Video Streams를 사용합니다.

## 아키텍처

```
Frontend (Browser) <--WebRTC--> KVS Signaling Channel <--> kvs-consumer-service (EKS)
                                           |
                                           v
                                    KVS Video Stream
                                           |
                                           v
                              posture-analysis-service (GPU)
```

## Terraform으로 생성되는 리소스

### 1. KVS Video Stream
- **리소스**: `aws_kinesis_video_stream.main["workout-sessions"]`
- **이름**: `prod-workout-sessions`
- **보관 기간**: 24시간
- **용도**: 운동 세션 영상 데이터 저장 및 스트리밍

```hcl
resource "aws_kinesis_video_stream" "main" {
  name                    = "prod-workout-sessions"
  data_retention_in_hours = 24
}
```

**생성된 ARN**:
```
arn:aws:kinesisvideo:ap-northeast-2:337112169365:stream/prod-workout-sessions/1779643398796
```

### 2. IAM Roles

#### Producer Role (영상 업로드용)
- **Role 이름**: `prod-kvs-producer-role`
- **서비스 계정**: `kvs-producer-sa` (Kubernetes namespace: `prod`)
- **권한**:
  - `kinesisvideo:PutMedia` - 영상 데이터 업로드
  - `kinesisvideo:DescribeStream` - 스트림 정보 조회
  - `kinesisvideo:GetDataEndpoint` - 데이터 엔드포인트 획득
  - WebRTC 관련 권한 (SignalingChannel)

#### Consumer Role (영상 소비용)
- **Role 이름**: `prod-kvs-consumer-role`
- **서비스 계정**: `kvs-consumer-sa` (Kubernetes namespace: `prod`)
- **권한**:
  - `kinesisvideo:GetMedia` - 영상 데이터 읽기
  - `kinesisvideo:GetMediaForFragmentList` - 특정 프래그먼트 읽기
  - `kinesisvideo:ListFragments` - 프래그먼트 목록 조회
  - WebRTC 관련 권한 (ConnectAsMaster, ConnectAsViewer)

### 3. CloudWatch Alarms

#### PutMedia Errors
- **이름**: `prod-kvs-workout-sessions-put-media-errors`
- **메트릭**: `PutMedia.Errors`
- **임계값**: 10개 이상의 에러 (5분간)
- **용도**: 영상 업로드 실패 모니터링

#### Incoming Bytes Low
- **이름**: `prod-kvs-workout-sessions-incoming-bytes-low`
- **메트릭**: `PutMedia.IncomingBytes`
- **임계값**: 1000 바이트 미만 (5분간)
- **용도**: 스트림 데이터 유입 저하 감지

## 수동 생성 필요 리소스

### KVS WebRTC Signaling Channel

**왜 수동 생성이 필요한가?**

Terraform AWS Provider (v5.x)는 `aws_kinesis_video_signaling_channel` 리소스를 지원하지 않습니다. WebRTC 실시간 양방향 통신을 위해서는 Signaling Channel이 필수적이므로 AWS CLI를 통해 수동으로 생성해야 합니다.

#### 생성 명령어

```bash
aws kinesisvideo create-signaling-channel \
  --channel-name prod-live-sessions-signaling \
  --region ap-northeast-2 \
  --output json
```

#### 생성된 리소스

```json
{
  "ChannelARN": "arn:aws:kinesisvideo:ap-northeast-2:337112169365:channel/prod-live-sessions-signaling/1779644737658"
}
```

#### 설정 값 설명

| 설정 | 값 | 설명 |
|------|-----|------|
| `channel-name` | `prod-live-sessions-signaling` | 환경별 네이밍 규칙: `{environment}-live-sessions-signaling` |
| `region` | `ap-northeast-2` | 서울 리전 (모든 리소스와 동일 리전 사용) |

#### Dev 환경 생성 시

```bash
aws kinesisvideo create-signaling-channel \
  --channel-name dev-live-sessions-signaling \
  --region ap-northeast-2 \
  --output json
```

## Terraform 적용 절차

### 1. 초기 설정

```bash
cd gympt-infra/terraform/environments/prod
terraform init
```

### 2. KVS 모듈 추가 확인

`main.tf`에 다음 모듈이 포함되어 있는지 확인:

```hcl
module "kvs" {
  source = "../../modules/kvs"

  environment           = local.env
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  kvs_namespace         = "prod"

  streams = {
    workout-sessions = {
      retention_hours = 24
    }
  }

  webrtc_channels = {
    live-sessions = {
      enabled = true
    }
  }

  tags = local.common_tags
}
```

### 3. Plan 실행

```bash
terraform plan
```

**예상 변경사항**:
- `+` 7개 리소스 생성 (Stream 1개, IAM 4개, CloudWatch Alarm 2개)

### 4. Apply 실행

```bash
terraform apply -auto-approve
```

### 5. Signaling Channel 수동 생성

Terraform apply 완료 후 AWS CLI로 생성:

```bash
aws kinesisvideo create-signaling-channel \
  --channel-name prod-live-sessions-signaling \
  --region ap-northeast-2
```

### 6. 생성 확인

#### KVS Stream 확인
```bash
aws kinesisvideo list-streams --region ap-northeast-2
```

#### Signaling Channel 확인
```bash
aws kinesisvideo list-signaling-channels --region ap-northeast-2
```

#### IAM Role 확인
```bash
aws iam get-role --role-name prod-kvs-producer-role
aws iam get-role --role-name prod-kvs-consumer-role
```

## Kubernetes 서비스 계정 설정

### Producer ServiceAccount (Frontend → KVS)

`gympt-gitops/charts/frontend/templates/serviceaccount.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kvs-producer-sa
  namespace: prod
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::337112169365:role/prod-kvs-producer-role
```

### Consumer ServiceAccount (KVS → Backend)

`gympt-gitops/charts/kvs-consumer-service/templates/serviceaccount.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kvs-consumer-sa
  namespace: prod
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::337112169365:role/prod-kvs-consumer-role
```

## 애플리케이션 설정

### 환경 변수

kvs-consumer-service에서 사용하는 환경 변수:

```yaml
env:
  - name: AWS_REGION
    value: "ap-northeast-2"
  - name: KVS_STREAM_NAME
    value: "prod-workout-sessions"
  - name: KVS_SIGNALING_CHANNEL_NAME
    value: "prod-live-sessions-signaling"
```

### Frontend WebRTC 설정

`frontend/src/lib/kvs-config.ts`:

```typescript
export const kvsConfig = {
  region: 'ap-northeast-2',
  signalingChannelName: 'prod-live-sessions-signaling',
  streamName: 'prod-workout-sessions',
};
```

## 비용 최적화

### 데이터 보관 기간
- **현재 설정**: 24시간
- **권장**: 운동 세션은 당일만 필요하므로 24시간이 적절
- **변경 시**: `retention_hours` 값 수정 후 `terraform apply`

### 스트림 개수
- **현재**: 1개 (workout-sessions)
- **추가 필요 시**: `streams` 맵에 추가

```hcl
streams = {
  workout-sessions = {
    retention_hours = 24
  }
  training-sessions = {
    retention_hours = 48
  }
}
```

## 트러블슈팅

### 1. Terraform 리소스 타입 오류

**오류**:
```
Error: Invalid resource type "aws_kinesisvideo_stream"
Did you mean "aws_kinesis_video_stream"?
```

**해결**: 언더스코어 위치 수정
- ❌ `aws_kinesisvideo_stream`
- ✅ `aws_kinesis_video_stream`

### 2. Signaling Channel 권한 에러

**증상**: WebRTC 연결 실패

**확인 사항**:
1. Signaling Channel이 생성되었는지 확인
2. IAM Role의 권한에 `kinesisvideo:ConnectAsMaster` 포함 여부
3. ServiceAccount annotation이 올바른 Role ARN을 가리키는지 확인

### 3. 스트림 연결 타임아웃

**확인 사항**:
1. Security Group에서 HTTPS(443) 허용 여부
2. KVS 엔드포인트에 대한 네트워크 접근 가능 여부
3. IRSA (IAM Roles for Service Accounts) 설정 확인

```bash
# Pod에서 IAM Role이 정상 할당되었는지 확인
kubectl exec -it <pod-name> -n prod -- env | grep AWS
```

## 참고 문서

- [Amazon KVS Developer Guide](https://docs.aws.amazon.com/kinesisvideostreams/latest/dg/what-is-kinesis-video.html)
- [WebRTC Signaling Channels](https://docs.aws.amazon.com/kinesisvideostreams/latest/dg/kvswebrtc-how-it-works.html)
- [Terraform AWS Provider - Kinesis Video](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_video_stream)
- [EKS IRSA (IAM Roles for Service Accounts)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

## 변경 이력

| 날짜 | 환경 | 변경 내용 | 담당자 |
|------|------|-----------|--------|
| 2026-05-25 | prod | KVS 모듈 최초 생성, Signaling Channel 수동 생성 | System |

## 다음 환경 배포 체크리스트

새로운 환경(예: staging, dev)에 KVS를 배포할 때 체크리스트:

- [ ] Terraform 모듈 추가 (`module "kvs"`)
- [ ] 환경 이름 변경 (`environment = "staging"`)
- [ ] Namespace 변경 (`kvs_namespace = "staging"`)
- [ ] `terraform init && terraform plan` 실행
- [ ] `terraform apply` 실행
- [ ] AWS CLI로 Signaling Channel 수동 생성
  ```bash
  aws kinesisvideo create-signaling-channel \
    --channel-name {environment}-live-sessions-signaling \
    --region ap-northeast-2
  ```
- [ ] ServiceAccount YAML에 Role ARN 업데이트
- [ ] 애플리케이션 환경 변수 업데이트 (stream name, channel name)
- [ ] 연결 테스트 수행
