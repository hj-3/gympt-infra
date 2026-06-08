# Boundary 접속 가이드 (팀원용)

Bastion 없이 GymPT 내부 인프라(RDS · Redis · EKS)에 접속하는 HashiCorp Boundary 사용 가이드.
모든 접속은 **개인 계정으로 인증**되고 **세션이 감사 기록**됩니다.

---

## 0. admin(ysh)에게 받을 정보

- **Controller 주소**: `http://<IP>:9200`
  - Controller EC2는 평소 비용 절감을 위해 **중지** 상태일 수 있고, 재시작 시 **public IP가 바뀝니다**. 접속 전 admin에게 현재 IP를 확인하세요.
- **로그인 아이디**: 본인 (`ysh` / `khj` / `kms` / `ksw`)
- **초기 비밀번호**: admin이 전달 (Secrets Manager `gympt/prod/boundary-team` 보관)
- **본인 account-id** (비밀번호 변경에 필요):

  | 아이디 | 역할 | account-id |
  |---|---|---|
  | ysh | 보안 | `acctpw_dziND3yiaQ` |
  | khj | PM | `acctpw_lU0YXqaLaO` |
  | kms | infra | `acctpw_imSup4kpfN` |
  | ksw | CI/CD | `acctpw_xP78PQgblr` |

---

## 1. 클라이언트 설치

| OS | 명령 |
|---|---|
| macOS | `brew install hashicorp/tap/boundary` |
| Windows | `choco install boundary` (또는 [공식 다운로드](https://developer.hashicorp.com/boundary/install)) |
| Linux | [바이너리 다운로드](https://developer.hashicorp.com/boundary/install) → `/usr/local/bin` |

설치 확인: `boundary version`

---

## 2. Controller 주소 설정

```bash
# macOS / Linux
export BOUNDARY_ADDR="http://<Controller-IP>:9200"
```
```powershell
# Windows PowerShell
$env:BOUNDARY_ADDR = "http://<Controller-IP>:9200"
```

---

## 3. 로그인

```bash
boundary authenticate password -auth-method-id ampw_Xs1W5XlvlI -login-name <본인아이디>
# Password: <초기 비밀번호 입력>
```

---

## 4. 최초 비밀번호 변경 (필수)

```bash
boundary accounts change-password -id <본인 account-id>
# Current password: <초기 비밀번호>
# New password:     <새 비밀번호>
```

> 변경 후에는 admin이 준 초기 비밀번호가 무효가 됩니다. 본인이 정한 새 비밀번호로 로그인하세요.

---

## 5. 리소스 접속 (connect)

접근 가능한 target 목록 확인:
```bash
boundary targets list -scope-id p_31JIWHrEG2
```

### RDS PostgreSQL
```bash
boundary connect -target-id ttcp_kL0F3WQBWp -listen-port 15432
# 다른 터미널에서:
psql -h 127.0.0.1 -p 15432 -U gymptadmin -d gympt
```

### ElastiCache Redis
```bash
boundary connect -target-id ttcp_e3ZCGpMwWs -listen-port 16379
# 다른 터미널에서:
redis-cli -h 127.0.0.1 -p 16379 -a <redis-비밀번호>
```

### EKS API (kubectl)
```bash
boundary connect -target-id ttcp_ZlTARNVciv -listen-port 8443
```

> 접속을 끝내려면 `connect`를 실행한 터미널에서 **Ctrl + C**.

---

## 참고

- **target id**는 재생성 시 바뀔 수 있으니 항상 `boundary targets list`로 확인하세요.
- **Controller IP**는 EC2 재시작마다 변경됩니다 → admin에게 확인.
- 권한: 4명 모두 `rds-access` role로 위 3개 target에 connect 가능 (공통). 권한 변경이 필요하면 admin에게 요청.
- 문제 발생 시 admin(ysh)에게 문의.
