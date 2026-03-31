# Lab 04 — Cloud Armor + LB 통합 (WAF & DDoS 보호)

## 시나리오

**브라우저 → Cloud Armor → Global LB → Backend MIG**

Global External Application LB 앞에 Cloud Armor 보안 정책을 배치하여 WAF, DDoS 방어, IP 차단, Rate Limiting 을 실습합니다.

```
브라우저
  │
  ▼ HTTP (34.144.229.129)
Cloud Armor Security Policy
  ├─ Rule 1000: IP Blocklist (DENY 403)
  ├─ Rule 2000: Rate Limiting (THROTTLE → 429)
  ├─ Rule 3000: SQLi WAF (DENY 403)
  ├─ Rule 4000: XSS WAF (DENY 403)
  ├─ Rule 5000: LFI WAF (DENY 403)
  ├─ Rule 6000: RCE WAF (DENY 403)
  └─ Rule 2147483647: Default ALLOW
  │
  ▼
Global External Application LB (EXTERNAL_MANAGED)
  │
  ├─▶ armor-web-xxx-1 (us-central1, 외부 IP 없음)
  └─▶ armor-web-xxx-2 (us-central1, 외부 IP 없음)
```

## 학습 목표

- **Cloud Armor 연결 방식** — Application LB 의 Backend Service 에 `security_policy` 로 연결
- **Pre-configured WAF 규칙** — OWASP CRS 기반 `sqli-stable`, `xss-stable`, `lfi-stable`, `rce-stable`
- **규칙 우선순위** — 낮은 숫자가 먼저 평가, 매칭 즉시 적용 후 나머지 규칙 스킵
- **Rate Limiting** — `throttle` 액션으로 분당 100회 초과 IP 에 429 반환
- **Adaptive Protection** — L7 DDoS 비정상 트래픽 자동 탐지
- **Cloud Armor 티어** — Standard 티어 필요 (WAF, Rate Limiting)

## ⚠️ 비용 안내 (Cloud Armor Standard)

| 항목 | 가격 |
|------|------|
| 보안 정책 | $5 / 정책 / 월 |
| WAF 규칙 평가 | $0.75 / 백만 요청 |
| Adaptive Protection | $0.05 / 보호된 백엔드 서비스 / 시간 |

> 실습 후 `terraform destroy` 로 즉시 정리하면 비용 최소화 가능

## 자주 하는 실수

| 실수 | 결과 | 올바른 방법 |
|------|------|------------|
| Cloud Armor 를 Network LB 에 연결 시도 | 불가 — Network LB 는 지원 안 함 | Application LB (`EXTERNAL_MANAGED`) 에만 연결 가능 |
| `evaluatePreconfiguredExpr` 를 Free tier 에서 사용 | 403 오류 — Standard tier 필요 | Cloud Armor Standard 구독 후 사용 |
| `throttle` 액션에 `rate_limit_options` 누락 | Terraform 오류 | `throttle` 액션은 `rate_limit_options` 블록 필수 |
| 규칙 우선순위 중복 | Terraform 오류 | 각 규칙마다 고유한 priority 값 사용 |
| Default rule (2147483647) 없음 | 모든 요청 차단 | Default rule 은 반드시 포함 |

## 아키텍처

```
┌──────────────────────────────────── GCP ────────────────────────────────────┐
│                                                                              │
│  Cloud Armor (web-security-policy)                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Priority 1000  → DENY 403  (IP Blocklist)                           │   │
│  │  Priority 2000  → THROTTLE  (Rate Limit: 100 req/min per IP)        │   │
│  │  Priority 3000  → DENY 403  (sqli-stable)                            │   │
│  │  Priority 4000  → DENY 403  (xss-stable)                             │   │
│  │  Priority 5000  → DENY 403  (lfi-stable)                             │   │
│  │  Priority 6000  → DENY 403  (rce-stable)                             │   │
│  │  Priority 2147483647 → ALLOW (default)                               │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                         │                                                    │
│  Global Application LB (EXTERNAL_MANAGED)                                    │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Forwarding Rule → Target HTTP Proxy → URL Map → Backend Service     │   │
│  │  Backend Service: security_policy = web-security-policy              │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                         │                                                    │
│  armor-vpc (10.40.0.0/24) — Cloud NAT                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  armor-web-1 (외부 IP 없음)   armor-web-2 (외부 IP 없음)             │   │
│  │  Python HTTP server — WAF 데모 페이지                                │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 리소스 구성

| 파일 | 리소스 | 설명 |
|------|--------|------|
| `providers.tf` | APIs, org policies | Compute API, LB 타입 제한 해제 |
| `01-vpc.tf` | VPC, 서브넷, Cloud NAT | armor-vpc, 10.40.0.0/24 |
| `02-firewall.tf` | 헬스체크, IAP SSH | tag: web-server |
| `03-instance-template.tf` | Instance Template | Python HTTP 서버, WAF 데모 페이지 |
| `04-mig.tf` | Regional MIG (2대) | Auto-healing |
| `05-load-balancer.tf` | Global External Application LB | Backend Service 에 Cloud Armor 연결 |
| `06-cloud-armor.tf` | Cloud Armor Security Policy | WAF + Rate Limit + Blocklist + Adaptive Protection |

## 핵심 Terraform 코드

### Cloud Armor 정책 — Backend Service 에 연결

```hcl
resource "google_compute_backend_service" "web" {
  load_balancing_scheme = "EXTERNAL_MANAGED"

  # Cloud Armor 연결 — 이 한 줄로 모든 요청에 보안 정책 적용
  security_policy = google_compute_security_policy.main.id
}
```

### Pre-configured WAF 규칙

```hcl
rule {
  action   = "deny(403)"
  priority = 3000
  match {
    expr {
      expression = "evaluatePreconfiguredExpr('sqli-stable')"
    }
  }
}
```

### Rate Limiting

```hcl
rule {
  action   = "throttle"
  priority = 2000
  match {
    versioned_expr = "SRC_IPS_V1"
    config { src_ip_ranges = ["*"] }
  }
  rate_limit_options {
    conform_action = "allow"
    exceed_action  = "deny(429)"
    rate_limit_threshold {
      count        = 100
      interval_sec = 60
    }
    enforce_on_key = "IP"
  }
}
```

### Adaptive Protection (L7 DDoS)

```hcl
adaptive_protection_config {
  layer_7_ddos_defense_config {
    enable = true
  }
}
```

## 실습 시작

### 1. 사전 준비

```bash
gcloud config set project lb-04-cloud-armor
gcloud auth application-default set-quota-project lb-04-cloud-armor
```

### 2. Terraform 배포

```bash
cd networking/lb-04-cloud-armor
terraform init
terraform apply
```

### 3. 데모 페이지 접속

```bash
terraform output demo_url
# http://34.144.229.129
```

> LB 프로비저닝 완료까지 약 3~5분 소요. 그 전에는 "503 Service Unavailable" 이 정상.

### 4. WAF 테스트 (브라우저)

데모 페이지에서 각 버튼 클릭:
- **정상 요청** → HTTP 200 OK
- **SQL Injection** → HTTP 403 (Cloud Armor 차단)
- **XSS** → HTTP 403 (Cloud Armor 차단)
- **LFI** → HTTP 403 (Cloud Armor 차단)
- **RCE** → HTTP 403 (Cloud Armor 차단)

### 5. WAF 테스트 (curl)

```bash
LB_IP=$(terraform output -raw load_balancer_ip)

# 정상 요청 → 200
curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/"

# SQLi → 403
curl -s -o /dev/null -w "%{http_code}" \
  "http://$LB_IP/api/info?q=%27+OR+%271%27%3D%271"

# XSS → 403
curl -s -o /dev/null -w "%{http_code}" \
  "http://$LB_IP/api/info?q=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"

# LFI → 403
curl -s -o /dev/null -w "%{http_code}" \
  "http://$LB_IP/api/info?path=..%2F..%2Fetc%2Fpasswd"
```

### 6. IP 차단 테스트

본인 IP 를 차단하려면:

```bash
MY_IP=$(curl -s https://ifconfig.me)
terraform apply -var="blocked_ip=$MY_IP"

# 적용 후 접속 시도 → 403
curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/"

# 원복
terraform apply
```

### 7. 보안 정책 규칙 확인

```bash
gcloud compute security-policies describe web-security-policy \
  --project=lb-04-cloud-armor
```

### 8. Cloud Armor 로그 확인

```bash
gcloud logging read \
  'resource.type="http_load_balancer" AND jsonPayload.enforcedSecurityPolicy.name="web-security-policy"' \
  --project=lb-04-cloud-armor \
  --format="table(timestamp, jsonPayload.enforcedSecurityPolicy.outcome, jsonPayload.enforcedSecurityPolicy.priority, httpRequest.remoteIp)" \
  --limit=20
```

## 오류 트러블슈팅

### WAF 테스트에서 403 이 아닌 200 이 반환되는 경우

Cloud Armor Standard 티어 구독 여부 확인:

```bash
gcloud compute security-policies describe web-security-policy \
  --project=lb-04-cloud-armor \
  --format="value(type)"
```

`CLOUD_ARMOR` 가 출력되면 정상. WAF 규칙이 적용되지 않는다면 약간의 전파 시간(1~2분)이 필요할 수 있음.

### "503 Service Unavailable" 응답

Backend VM 이 아직 HEALTHY 상태가 되지 않은 것. 헬스체크 상태 확인:

```bash
gcloud compute backend-services get-health armor-web-backend \
  --global \
  --project=lb-04-cloud-armor
```

모든 백엔드가 `HEALTHY` 가 될 때까지 대기 (최대 3분).

### `invalid_rapt` 인증 오류

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project lb-04-cloud-armor
```

## 정리

```bash
terraform destroy
```

## 관련 GCP 문서

- [Cloud Armor overview](https://cloud.google.com/armor/docs/cloud-armor-overview)
- [Pre-configured WAF rules](https://cloud.google.com/armor/docs/waf-rules)
- [Rate limiting](https://cloud.google.com/armor/docs/rate-limiting-overview)
- [Adaptive Protection](https://cloud.google.com/armor/docs/adaptive-protection-overview)
