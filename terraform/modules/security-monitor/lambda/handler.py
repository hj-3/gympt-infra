import json
import logging
import os
import time
import urllib.request
from datetime import datetime, timedelta, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ["AWS_REGION"]
ACCOUNT_ID = os.environ["ACCOUNT_ID"]
GLUE_DB = os.environ["GLUE_DATABASE"]
WORKGROUP = os.environ["ATHENA_WORKGROUP"]
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-west-2")
BEDROCK_MODEL = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
SLACK_SECRET_NAME = os.environ["SLACK_SECRET_NAME"]

KST = timezone(timedelta(hours=9))

# ── 운영 파라미터 (Lambda 환경변수로 코드 수정 없이 변경 가능) ─────────────────
VPC_FLOW_REJECT_THRESHOLD = int(os.environ.get("VPC_FLOW_REJECT_THRESHOLD", "10"))
VPC_FLOW_WINDOW_MINUTES   = int(os.environ.get("VPC_FLOW_WINDOW_MINUTES",   "30"))
WAF_BLOCK_THRESHOLD       = int(os.environ.get("WAF_BLOCK_THRESHOLD",       "5"))
S3_ERROR_THRESHOLD        = int(os.environ.get("S3_ERROR_THRESHOLD",        "5"))
ALB_ERROR_THRESHOLD       = int(os.environ.get("ALB_ERROR_THRESHOLD",       "10"))
SCHEDULE_MIN_LEVEL        = os.environ.get("SCHEDULE_MIN_LEVEL", "HIGH").upper()

LEVEL_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]

SECURITY_EVENTS = {
    "PutUserPolicy", "AttachUserPolicy", "DetachUserPolicy",
    "CreateUser", "DeleteUser", "CreateAccessKey", "DeleteAccessKey",
    "UpdateAssumeRolePolicy", "PutRolePolicy", "AttachRolePolicy",
    "AuthorizeSecurityGroupIngress", "RevokeSecurityGroupIngress",
    "DeleteTrail", "StopLogging", "UpdateTrail", "PutEventSelectors",
    "PutBucketPolicy", "DeleteBucketPolicy", "PutBucketAcl",
    "PutBucketPublicAccessBlock", "DeleteBucketPublicAccessBlock",
    "CreateSecret", "DeleteSecret",
}


def lambda_handler(event, context):
    trigger = _identify_trigger(event)
    logger.info("trigger=%s", trigger)

    if trigger == "cloudtrail":
        findings = _handle_cloudtrail_event(event)
        source_label = "CloudTrail 실시간"
    elif trigger == "console_login":
        findings = _handle_console_login_event(event)
        source_label = "MFA 없는 콘솔 로그인"
    elif trigger == "schedule":
        findings = _handle_scheduled_scan()
        source_label = "정기 스캔 (30분)"
    else:
        logger.warning("unknown trigger source=%s detail-type=%s",
                       event.get("source"), event.get("detail-type"))
        return {"statusCode": 200, "body": "unknown trigger"}

    if not findings:
        logger.info("no findings")
        return {"statusCode": 200, "body": "no findings"}

    analysis = _analyze_with_bedrock(findings, trigger)
    analysis["source"] = source_label
    level = analysis.get("threat_level", "INFO")
    logger.info("bedrock result: threat_level=%s summary=%s", level, str(analysis.get("summary", ""))[:120])

    if _should_alert(analysis, trigger):
        logger.info("sending slack alert")
        _send_to_slack(analysis, findings)
        logger.info("slack sent")
    else:
        logger.info("no alert (level=%s trigger=%s)", level, trigger)

    return {"statusCode": 200, "body": "ok"}


def _identify_trigger(event):
    source = event.get("source", "")
    detail_type = event.get("detail-type", "")
    if source == "aws.events" and detail_type == "Scheduled Event":
        return "schedule"
    if source == "aws.signin":
        return "console_login"
    if source == "aws.cloudtrail":
        return "cloudtrail"
    return "unknown"


def _handle_cloudtrail_event(event):
    detail = event.get("detail", {})
    uid = detail.get("userIdentity", {})
    return {
        "trigger": "cloudtrail_realtime",
        "event_name": detail.get("eventName"),
        "event_source": detail.get("eventSource"),
        "event_time": detail.get("eventTime"),
        "source_ip": detail.get("sourceIPAddress"),
        "user_agent": (detail.get("userAgent") or "")[:200],
        "user_identity": {
            "type": uid.get("type"),
            "arn": uid.get("arn"),
            "username": uid.get("userName"),
        },
        "request_parameters": json.dumps(detail.get("requestParameters") or {})[:500],
        "error_code": detail.get("errorCode"),
        "aws_region": detail.get("awsRegion"),
    }


def _handle_console_login_event(event):
    detail = event.get("detail", {})
    extra = detail.get("additionalEventData", {})
    return {
        "trigger": "console_login_no_mfa",
        "event_time": detail.get("eventTime"),
        "source_ip": detail.get("sourceIPAddress"),
        "user_agent": (detail.get("userAgent") or "")[:200],
        "username": (detail.get("userIdentity") or {}).get("userName", "unknown"),
        "login_result": (detail.get("responseElements") or {}).get("ConsoleLogin", "unknown"),
        "mfa_used": extra.get("MFAUsed", "No"),
    }


def _handle_scheduled_scan():
    results = {}

    # CloudTrail API - 최근 30분 보안 이벤트 직접 조회 (S3 스캔 비용 없음)
    ct_events = _query_cloudtrail_api()
    if ct_events:
        results["cloudtrail"] = {"description": "CloudTrail 보안 이벤트", "events": ct_events}

    # Athena 쿼리 5개 동시 실행 후 결과 취합
    athena_jobs = {
        "waf":        (_build_waf_query(),        "WAF 차단 이벤트"),
        "inspector":  (_build_inspector_query(),   "Inspector 취약점"),
        "vpc_flow":   (_build_vpc_flow_query(),    "VPC Flow REJECT"),
        "s3_access":  (_build_s3_access_query(),   "S3 이상 접근"),
        "alb_access": (_build_alb_access_query(),  "ALB 오류"),
    }

    athena = boto3.client("athena", region_name=AWS_REGION)

    # 쿼리 동시 실행
    query_ids = {}
    for key, (query, desc) in athena_jobs.items():
        try:
            resp = athena.start_query_execution(
                QueryString=query,
                QueryExecutionContext={"Database": GLUE_DB},
                WorkGroup=WORKGROUP,
            )
            query_ids[key] = (resp["QueryExecutionId"], desc)
        except Exception:
            pass

    # 최대 60초 대기
    pending = set(query_ids.keys())
    for _ in range(30):
        if not pending:
            break
        time.sleep(2)
        done_now = set()
        for key in list(pending):
            qid, _ = query_ids[key]
            try:
                st = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]["State"]
                if st in ("SUCCEEDED", "FAILED", "CANCELLED"):
                    done_now.add(key)
            except Exception:
                done_now.add(key)
        pending -= done_now

    # 결과 취합
    for key, (qid, desc) in query_ids.items():
        try:
            st = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]["State"]
            if st != "SUCCEEDED":
                continue
            rows = athena.get_query_results(QueryExecutionId=qid)["ResultSet"]["Rows"]
            if len(rows) <= 1:
                continue
            headers = [c["VarCharValue"] for c in rows[0]["Data"]]
            data = [
                dict(zip(headers, [c.get("VarCharValue", "") for c in r["Data"]]))
                for r in rows[1:]
            ]
            results[key] = {"description": desc, "rows": data}
        except Exception:
            pass

    return {"trigger": "scheduled_scan", "data": results} if results else None


# ── CloudTrail API 조회 ───────────────────────────────────────────────────────

def _query_cloudtrail_api():
    ct = boto3.client("cloudtrail", region_name=AWS_REGION)
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(minutes=30)
    found = []
    try:
        paginator = ct.get_paginator("lookup_events")
        for page in paginator.paginate(
            LookupAttributes=[{"AttributeKey": "ReadOnly", "AttributeValue": "false"}],
            StartTime=start_time,
            EndTime=end_time,
            PaginationConfig={"MaxItems": 100, "PageSize": 50},
        ):
            for ev in page.get("Events", []):
                if ev.get("EventName") in SECURITY_EVENTS:
                    raw = json.loads(ev.get("CloudTrailEvent", "{}"))
                    found.append({
                        "event_name": ev.get("EventName"),
                        "event_time": str(ev.get("EventTime", "")),
                        "username": ev.get("Username", ""),
                        "source_ip": raw.get("sourceIPAddress", ""),
                        "error_code": raw.get("errorCode", ""),
                    })
    except Exception as e:
        return [{"error": str(e)}]
    return found or None


# ── Athena 쿼리 빌더 ──────────────────────────────────────────────────────────

def _build_waf_query():
    # partition projection 적용 - 현재+이전 시간 파티션만 스캔
    now = datetime.now(timezone.utc)
    prev = now - timedelta(hours=1)
    return f"""
SELECT action, httprequest.clientip AS client_ip, terminatingruleid,
       COUNT(*) AS block_count
FROM "{GLUE_DB}"."waf_alb_logs"
WHERE (
    (year='{now.year}' AND month='{now.month:02d}' AND day='{now.day:02d}' AND hour='{now.hour:02d}')
    OR
    (year='{prev.year}' AND month='{prev.month:02d}' AND day='{prev.day:02d}' AND hour='{prev.hour:02d}')
  )
  AND action = 'BLOCK'
  AND from_unixtime("timestamp" / 1000) > current_timestamp - interval '30' minute
GROUP BY action, httprequest.clientip, terminatingruleid
HAVING COUNT(*) >= {WAF_BLOCK_THRESHOLD}
ORDER BY block_count DESC
LIMIT 10
"""


def _build_inspector_query():
    # partition projection 적용
    # Firehose 버퍼링 최대 5분 + 스케줄 주기 30분 고려해 3시간 윈도우
    now = datetime.now(timezone.utc)
    hours = [now - timedelta(hours=i) for i in range(3)]
    partition_conds = " OR ".join(
        f"(year='{h.year}' AND month='{h.month:02d}' AND day='{h.day:02d}' AND hour='{h.hour:02d}')"
        for h in hours
    )
    return f"""
SELECT detail.severity, detail.title, detail.inspectorscore,
       detail.fixavailable, detail.exploitavailable,
       detail.packagevulnerabilitydetails.vulnerabilityid AS vulnerability_id
FROM "{GLUE_DB}"."inspector_findings"
WHERE ({partition_conds})
  AND detail.severity IN ('HIGH', 'CRITICAL')
ORDER BY detail.inspectorscore DESC
LIMIT 10
"""


def _build_vpc_flow_query():
    now = datetime.now(timezone.utc)
    yesterday = now - timedelta(days=1)
    partition_conds = (
        f"(year='{now.year}' AND month='{now.month:02d}' AND day='{now.day:02d}')"
        f" OR (year='{yesterday.year}' AND month='{yesterday.month:02d}' AND day='{yesterday.day:02d}')"
    )
    return f"""
SELECT srcaddr, dstaddr, dstport, COUNT(*) AS reject_count
FROM "{GLUE_DB}"."vpc_flow_logs"
WHERE ({partition_conds})
  AND action = 'REJECT'
  AND start > to_unixtime(current_timestamp - interval '{VPC_FLOW_WINDOW_MINUTES}' minute)
GROUP BY srcaddr, dstaddr, dstport
HAVING COUNT(*) >= {VPC_FLOW_REJECT_THRESHOLD}
ORDER BY reject_count DESC
LIMIT 10
"""


_MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

def _build_s3_access_query():
    now = datetime.now(timezone.utc)
    yesterday = now - timedelta(days=1)
    today_pat    = f"{now.day:02d}/{_MONTHS[now.month-1]}/{now.year}"
    yesterday_pat = f"{yesterday.day:02d}/{_MONTHS[yesterday.month-1]}/{yesterday.year}"
    return f"""
SELECT remote_ip, requester, operation, error_code, COUNT(*) AS count
FROM "{GLUE_DB}"."s3_access_logs"
WHERE error_code IS NOT NULL
  AND error_code NOT IN ('-', '')
  AND (request_datetime LIKE '%{today_pat}%' OR request_datetime LIKE '%{yesterday_pat}%')
GROUP BY remote_ip, requester, operation, error_code
HAVING COUNT(*) >= {S3_ERROR_THRESHOLD}
ORDER BY count DESC
LIMIT 10
"""


def _build_alb_access_query():
    now = datetime.now(timezone.utc)
    yesterday = now - timedelta(days=1)
    partition_conds = (
        f"(year='{now.year}' AND month='{now.month:02d}' AND day='{now.day:02d}')"
        f" OR (year='{yesterday.year}' AND month='{yesterday.month:02d}' AND day='{yesterday.day:02d}')"
    )
    return f"""
SELECT client_ip, request_verb, elb_status_code, COUNT(*) AS count
FROM "{GLUE_DB}"."alb_access_logs"
WHERE ({partition_conds})
  AND elb_status_code >= 400
GROUP BY client_ip, request_verb, elb_status_code
HAVING COUNT(*) >= {ALB_ERROR_THRESHOLD}
ORDER BY count DESC
LIMIT 10
"""


# ── Bedrock 분석 ──────────────────────────────────────────────────────────────

def _analyze_with_bedrock(findings, trigger):
    bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)
    findings_str = json.dumps(findings, ensure_ascii=False, default=str)
    if len(findings_str) > 6000:
        findings_str = findings_str[:6000] + "\n...(생략)"

    prompt = f"""당신은 GYMPT 플랫폼(AWS/EKS 기반 피트니스 서비스)의 클라우드 보안 분석가입니다.
다음 보안 로그 데이터를 분석하세요.

{findings_str}

아래 JSON 형식으로만 응답하세요 (다른 텍스트 없이):
{{
  "threat_level": "CRITICAL|HIGH|MEDIUM|LOW|INFO",
  "summary": "발생 상황 2-3문장 요약",
  "analysis": "원인 분석 및 공격 패턴 설명",
  "runbook": ["조치 단계 1", "조치 단계 2", "조치 단계 3"]
}}

위협 레벨 기준:
- CRITICAL: 계정 탈취·데이터 유출·인프라 파괴 임박
- HIGH: 권한 상승·악성 접근·대량 WAF 차단·심각 취약점
- MEDIUM: 비정상 접근 패턴·의심스러운 API 호출·중간 위험 취약점
- LOW: 소수 오류·일반 설정 변경·경미한 취약점
- INFO: 정상 운영 범위, 이상 없음"""

    try:
        resp = bedrock.invoke_model(
            modelId=BEDROCK_MODEL,
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 1024,
                "messages": [{"role": "user", "content": prompt}],
            }),
            contentType="application/json",
            accept="application/json",
        )
        text = json.loads(resp["body"].read())["content"][0]["text"].strip()
        s, e = text.find("{"), text.rfind("}") + 1
        if s >= 0 and e > s:
            return json.loads(text[s:e])
        logger.warning("bedrock response has no JSON: %s", text[:200])
    except Exception as exc:
        logger.error("bedrock error: %s", exc)

    return {
        "threat_level": "INFO",
        "summary": f"분석 오류 발생 ({trigger})",
        "analysis": str(findings)[:300],
        "runbook": ["AWS 콘솔에서 CloudTrail 직접 확인", "보안 담당자에게 수동 보고"],
    }


def _should_alert(analysis, trigger):
    level = analysis.get("threat_level", "INFO")
    if trigger == "schedule":
        try:
            min_idx = LEVEL_ORDER.index(SCHEDULE_MIN_LEVEL)
            cur_idx = LEVEL_ORDER.index(level) if level in LEVEL_ORDER else len(LEVEL_ORDER) - 1
        except ValueError:
            min_idx, cur_idx = 1, len(LEVEL_ORDER) - 1
        return cur_idx <= min_idx
    return level in ("CRITICAL", "HIGH", "MEDIUM", "LOW")


# ── Slack 전송 ────────────────────────────────────────────────────────────────

def _format_findings_text(findings):
    if not findings:
        return "데이터 없음"
    trigger = findings.get("trigger", "")

    if trigger == "cloudtrail_realtime":
        uid = findings.get("user_identity", {})
        lines = [
            f"• 이벤트: `{findings.get('event_name', '-')}`",
            f"• 서비스: {findings.get('event_source', '-')}",
            f"• 사용자: {uid.get('arn') or uid.get('username') or '-'}",
            f"• 소스 IP: {findings.get('source_ip', '-')}",
            f"• 시각: {findings.get('event_time', '-')}",
        ]
        if findings.get("request_parameters") and findings["request_parameters"] != "{}":
            lines.append(f"• 파라미터: `{findings['request_parameters'][:200]}`")
        if findings.get("error_code"):
            lines.append(f"• 에러: {findings['error_code']}")
        return "\n".join(lines)

    if trigger == "console_login_no_mfa":
        return "\n".join([
            f"• 사용자: {findings.get('username', '-')}",
            f"• 소스 IP: {findings.get('source_ip', '-')}",
            f"• MFA 사용: {findings.get('mfa_used', 'No')}",
            f"• 로그인 결과: {findings.get('login_result', '-')}",
            f"• 시각: {findings.get('event_time', '-')}",
        ])

    if trigger == "scheduled_scan":
        data = findings.get("data", {})
        parts = []
        if "cloudtrail" in data:
            events = data["cloudtrail"].get("events", [])[:3]
            if events:
                parts.append("*[CloudTrail]*")
                for ev in events:
                    parts.append(f"• `{ev.get('event_name')}` | {ev.get('username', '-')} | {ev.get('source_ip', '-')}")
        if "vpc_flow" in data:
            rows = data["vpc_flow"].get("rows", [])[:3]
            if rows:
                parts.append("*[VPC Flow REJECT]*")
                for r in rows:
                    parts.append(f"• {r.get('srcaddr','-')} → {r.get('dstaddr','-')}:{r.get('dstport','-')} | {r.get('reject_count','-')}건")
        if "waf" in data:
            rows = data["waf"].get("rows", [])[:3]
            if rows:
                parts.append("*[WAF BLOCK]*")
                for r in rows:
                    parts.append(f"• {r.get('client_ip','-')} | {r.get('terminatingruleid','-')} | {r.get('block_count','-')}건")
        if "s3_access" in data:
            rows = data["s3_access"].get("rows", [])[:3]
            if rows:
                parts.append("*[S3 이상 접근]*")
                for r in rows:
                    parts.append(f"• {r.get('requester','-')} | `{r.get('operation','-')}` | {r.get('error_code','-')} | {r.get('count','-')}건")
        if "alb_access" in data:
            rows = data["alb_access"].get("rows", [])[:3]
            if rows:
                parts.append("*[ALB 오류]*")
                for r in rows:
                    parts.append(f"• {r.get('client_ip','-')} | {r.get('request_verb','-')} {r.get('elb_status_code','-')} | {r.get('count','-')}건")
        if "inspector" in data:
            rows = data["inspector"].get("rows", [])[:3]
            if rows:
                parts.append("*[Inspector 취약점]*")
                for r in rows:
                    parts.append(f"• [{r.get('detail.severity','-')}] {str(r.get('detail.title','-'))[:60]}")
        return "\n".join(parts) if parts else "데이터 없음"

    return str(findings)[:300]


def _get_webhook_url():
    sm = boto3.client("secretsmanager", region_name=AWS_REGION)
    return sm.get_secret_value(SecretId=SLACK_SECRET_NAME)["SecretString"]


def _send_to_slack(analysis, findings=None):
    level = analysis.get("threat_level", "INFO")
    level_cfg = {
        "CRITICAL": ("🚨", "#FF0000"),
        "HIGH":     ("🔴", "#FF6600"),
        "MEDIUM":   ("🟡", "#FFCC00"),
        "LOW":      ("🟢", "#00CC00"),
        "INFO":     ("ℹ️",  "#0099FF"),
    }
    emoji, color = level_cfg.get(level, ("ℹ️", "#0099FF"))
    runbook = "\n".join(f"{i+1}. {s}" for i, s in enumerate(analysis.get("runbook", [])))
    now_kst = datetime.now(KST).strftime("%Y-%m-%d %H:%M KST")
    findings_text = _format_findings_text(findings)

    payload = {
        "attachments": [{
            "color": color,
            "blocks": [
                {
                    "type": "header",
                    "text": {"type": "plain_text", "text": f"{emoji} GYMPT Security Monitor — {level}"},
                },
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": f"*발생 위치*\n{analysis.get('source', '-')}"},
                },
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": f"*발생 이벤트*\n{findings_text}"},
                },
                {"type": "divider"},
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": f"*요약*\n{analysis.get('summary', '')}"},
                },
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": f"*원인 분석*\n{analysis.get('analysis', '')}"},
                },
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": f"*대응*\n{runbook}"},
                },
                {"type": "divider"},
                {
                    "type": "context",
                    "elements": [{
                        "type": "mrkdwn",
                        "text": f"분석 시각: {now_kst} | 계정: {ACCOUNT_ID}",
                    }],
                },
            ],
        }]
    }

    url = _get_webhook_url()
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=10)
