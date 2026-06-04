# 기여 가이드

GYMPT Infrastructure에 기여해 주셔서 감사합니다!

## 🔄 개발 프로세스

### 1. 브랜치 전략

- `main` - Production 환경 배포
- `develop` - Development 환경 배포
- `feature/*` - 새로운 기능
- `fix/*` - 버그 수정
- `docs/*` - 문서 업데이트

### 2. 작업 흐름

```bash
# 1. Fork 및 Clone
git clone https://github.com/YOUR_USERNAME/gympt-infra.git
cd gympt-infra

# 2. Feature 브랜치 생성
git checkout -b feature/add-new-module

# 3. 변경 사항 작업
# ... 코드 작성 ...

# 4. Terraform 검증
./scripts/validate-all.sh

# 5. 커밋
git add .
git commit -m "feat: Add new Terraform module for XYZ"

# 6. Push
git push origin feature/add-new-module

# 7. Pull Request 생성
```

## 📝 커밋 메시지 규칙

### 커밋 타입

- `feat:` - 새로운 기능
- `fix:` - 버그 수정
- `docs:` - 문서 변경
- `refactor:` - 코드 리팩토링
- `test:` - 테스트 추가/수정
- `chore:` - 빌드 또는 도구 변경

### 예시

```
feat: Add DynamoDB module for sessions table

- Implement DynamoDB table with TTL
- Add GSI for planId lookup
- Configure PAY_PER_REQUEST billing
```

## 🧪 코드 품질

### Terraform 스타일 가이드

```bash
# 포맷 확인
terraform fmt -check -recursive

# 자동 포맷팅
terraform fmt -recursive

# 검증
terraform validate

# 보안 스캔
tfsec .
```

### 필수 검증 항목

1. **모듈 구조**
   ```
   modules/
   └── module-name/
       ├── main.tf
       ├── variables.tf
       ├── outputs.tf
       └── README.md
   ```

2. **변수 문서화**
   ```hcl
   variable "example" {
     description = "Clear description of the variable"
     type        = string
     default     = "default-value"
   }
   ```

3. **출력값 정의**
   ```hcl
   output "example_id" {
     description = "The ID of the created resource"
     value       = aws_resource.example.id
   }
   ```

4. **태그 추가**
   ```hcl
   tags = merge(var.tags, {
     Name = "resource-name"
   })
   ```

## 📚 문서 작성

### 모듈 README 구조

```markdown
# Module Name

## 개요
[모듈 설명]

## 사용 예시
\`\`\`hcl
module "example" {
  source = "../../modules/module-name"
  
  # Variables
}
\`\`\`

## 입력 변수
| 이름 | 설명 | 타입 | 기본값 | 필수 |
|------|------|------|--------|------|

## 출력값
| 이름 | 설명 |
|------|------|

## 요구사항
- Terraform >= 1.5
- AWS Provider >= 5.0
```

## 🔍 Pull Request 체크리스트

### 필수 사항

- [ ] Terraform 포맷팅 완료 (`terraform fmt`)
- [ ] Terraform 검증 통과 (`terraform validate`)
- [ ] 보안 스캔 통과 (`tfsec`)
- [ ] README 업데이트
- [ ] 변수 문서화
- [ ] 출력값 정의
- [ ] 태그 추가

### Dev 환경 테스트

- [ ] `terraform plan` 성공
- [ ] `terraform apply` 성공
- [ ] 리소스 생성 확인
- [ ] 기능 테스트 완료
- [ ] `terraform destroy` 성공

### PR 설명

```markdown
## 변경 사항
[무엇을 변경했는지 설명]

## 동기
[왜 변경했는지 설명]

## 테스트
[어떻게 테스트했는지 설명]

## 스크린샷 (선택 사항)
[관련 스크린샷]
```

## 🛡️ 보안 고려사항

### 절대 커밋하지 말 것

- AWS Access Keys
- Secrets / 비밀번호
- `*.tfvars` 파일 (환경별 변수)
- Private Keys (*.pem, *.key)
- 개인 정보

### Secrets 관리

```hcl
# ❌ 잘못된 예시
variable "db_password" {
  default = "hardcoded-password"
}

# ✅ 올바른 예시
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = var.db_password_secret_arn
}
```

## 🔧 로컬 개발 환경 설정

### 1. 도구 설치

```bash
# Terraform
brew install terraform

# AWS CLI
brew install awscli

# tfsec (보안 스캔)
brew install tfsec

# terraform-docs (문서 생성)
brew install terraform-docs
```

### 2. AWS 자격증명 구성

```bash
aws configure
# Access Key ID: [YOUR_KEY]
# Secret Access Key: [YOUR_SECRET]
# Default region: ap-northeast-2
```

### 3. Pre-commit Hook 설정

```bash
# .git/hooks/pre-commit 생성
cat > .git/hooks/pre-commit <<'EOF'
#!/bin/bash
set -e

echo "Running Terraform format check..."
terraform fmt -check -recursive

echo "Running Terraform validation..."
cd terraform/environments/dev
terraform init -backend=false
terraform validate
cd ../../..

echo "Running security scan..."
tfsec .

echo "✓ All checks passed!"
EOF

chmod +x .git/hooks/pre-commit
```

## 🐛 이슈 보고

### 버그 리포트

```markdown
## 버그 설명
[버그에 대한 명확한 설명]

## 재현 단계
1. [첫 번째 단계]
2. [두 번째 단계]
3. ...

## 예상 동작
[예상했던 동작]

## 실제 동작
[실제 발생한 동작]

## 환경
- Terraform 버전:
- AWS 리전:
- OS:
```

### 기능 요청

```markdown
## 기능 설명
[새로운 기능에 대한 설명]

## 동기
[왜 이 기능이 필요한지]

## 제안 사항
[구현 방법 제안]
```

## 📞 도움이 필요하신가요?

- GitHub Issues: 버그 및 기능 요청
- GitHub Discussions: 일반 질문 및 토론
- Email: devops@gympt.com

---

**기여해 주셔서 감사합니다!** 🙏
