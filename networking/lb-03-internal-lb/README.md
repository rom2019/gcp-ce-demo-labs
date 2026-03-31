# Lab 03 — Internal Load Balancer (마이크로서비스 내부 통신)

## 시나리오

**Frontend VM → Internal LB → Backend API MIG (3대)**

외부에서는 Frontend VM 의 외부 IP 로만 접근 가능하고, Backend API 서버는 외부 IP 없이 Internal LB 를 통해서만 접근할 수 있는 마이크로서비스 아키텍처를 구성합니다.

```
브라우저
  │
  ▼ HTTP (외부 IP)
Frontend VM (nginx Reverse Proxy)
  │
  ▼ HTTP → nginx proxy → Internal LB VIP (10.30.1.5)
Regional Internal Passthrough NLB
  │
  ├─▶ backend-api-xxx-1 (외부 IP 없음)
  ├─▶ backend-api-xxx-2 (외부 IP 없음)
  └─▶ backend-api-xxx-3 (외부 IP 없음)
```

## 학습 목표

- **Internal LB 의 본질** — VIP 가 Private IP 이므로 VPC 내부에서만 접근 가능
- **헬스체크 방화벽 규칙의 중요성** — Internal LB 도 GCP 헬스체크 프로브(130.211.x.x, 35.191.x.x)를 허용해야 동작
- **서브넷 분리** — Frontend(10.30.0.0/24) / Backend(10.30.1.0/24) 로 역할 구분
- **Cloud NAT** — 외부 IP 없는 Backend VM 이 패키지 설치를 위해 Cloud NAT 사용
- **메타데이터 주입** — Terraform 이 Internal LB VIP 를 Frontend VM 메타데이터로 전달

## 자주 하는 실수

| 실수 | 결과 | 올바른 방법 |
|------|------|------------|
| 헬스체크 방화벽 미설정 | Backend 모두 UNHEALTHY, LB 트래픽 0 | `source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]` 허용 |
| `target_tags` 없는 헬스체크 방화벽 | VPC 전체 VM 에 적용됨 | `target_tags = ["backend-api"]` 지정 |
| Backend VM 에 외부 IP 할당 | 보안 취약, 마이크로서비스 패턴 위반 | `access_config` 블록 제거 (Cloud NAT 사용) |
| Internal LB 에 `port_range` 사용 | 오류 — Internal LB 는 `ports` 리스트 사용 | `ports = ["80"]` |
| `load_balancing_scheme = "INTERNAL"` + `balancing_mode = "RATE"` | 오류 | Internal LB 는 `balancing_mode = "CONNECTION"` |

## 아키텍처

```
┌─────────────────────────────── micro-vpc ───────────────────────────────┐
│                                                                          │
│  frontend-subnet (10.30.0.0/24)                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  frontend-service VM                                            │    │
│  │  - 외부 IP: 34.173.20.191 (브라우저 접속)                        │    │
│  │  - nginx: / → index.html, /api → proxy → Internal LB           │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                         │                                                │
│                         ▼ nginx proxy                                    │
│  backend-subnet (10.30.1.0/24)                                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Internal LB VIP: 10.30.1.5 (Private IP — VPC 내부 전용)        │    │
│  │         │                                                        │    │
│  │  ┌──────┴───────────────────────────────────┐                   │    │
│  │  ▼              ▼                  ▼         │                   │    │
│  │  backend-api-1  backend-api-2  backend-api-3 │                   │    │
│  │  (외부 IP 없음 — Cloud NAT 으로만 아웃바운드)  │                   │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  Cloud NAT (micro-nat) — Backend VM 인터넷 출구                           │
└──────────────────────────────────────────────────────────────────────────┘
```

## 리소스 구성

| 파일 | 리소스 | 설명 |
|------|--------|------|
| `providers.tf` | APIs, org policies | Compute API, vmExternalIpAccess 정책 |
| `01-vpc.tf` | VPC, 2개 서브넷, Cloud NAT | Frontend/Backend 서브넷 분리 |
| `02-firewall.tf` | 4개 방화벽 규칙 | 헬스체크, 내부통신, Frontend HTTP, IAP SSH |
| `03-backend-template.tf` | Instance Template | Backend API — `/api`, `/health` 엔드포인트 |
| `04-mig.tf` | Regional MIG (3대) | Auto-healing, 오토스케일러 없음 |
| `05-load-balancer.tf` | Regional Internal NLB | Health Check + Backend Service + Forwarding Rule |
| `06-frontend.tf` | Frontend VM | nginx + 데모 HTML, ILB VIP 메타데이터 주입 |

## 핵심 Terraform 코드

### Internal LB Forwarding Rule

```hcl
resource "google_compute_forwarding_rule" "internal" {
  name                  = "backend-api-ilb-rule"
  region                = var.region
  load_balancing_scheme = "INTERNAL"   # Private IP 만 할당
  ip_protocol           = "TCP"
  ports                 = ["80"]       # port_range 가 아닌 ports 리스트
  backend_service       = google_compute_region_backend_service.api.id
  network               = google_compute_network.vpc.id
  subnetwork            = google_compute_subnetwork.backend.id  # VIP 할당 서브넷
}
```

### 헬스체크 방화벽 (Internal LB 필수)

```hcl
resource "google_compute_firewall" "allow_health_check" {
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]  # GCP 헬스체크 프로브 IP
  target_tags   = ["backend-api"]  # Backend VM 에만 적용
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}
```

### Frontend VM — Internal LB VIP 메타데이터 주입

```hcl
resource "google_compute_instance" "frontend" {
  metadata = {
    "ilb-ip" = google_compute_forwarding_rule.internal.ip_address
  }
}
# startup script 에서: ILB_IP=$(curl .../instance/attributes/ilb-ip)
# nginx proxy_pass 에 ILB_IP 주입
```

## 실습 시작

### 1. 사전 준비

```bash
gcloud config set project lb-03-internal-lb
gcloud auth application-default set-quota-project lb-03-internal-lb
```

### 2. Terraform 배포

```bash
cd networking/lb-03-internal-lb
terraform init
terraform apply
```

### 3. 데모 페이지 접속

```bash
terraform output demo_url
# http://34.173.20.191
```

브라우저에서 접속 후 **"Backend API 호출"** 버튼을 눌러 요청이 Internal LB 를 통해 3개의 Backend 서버로 분산되는 것을 확인합니다.

### 4. Backend API 직접 확인

```bash
# Frontend VM 에서 Internal LB VIP 직접 호출
gcloud compute ssh frontend-service --tunnel-through-iap \
  --project=lb-03-internal-lb --zone=us-central1-a \
  -- curl -s http://10.30.1.5/api | python3 -m json.tool
```

응답 예시:
```json
{
  "server": "backend-api-xxxx",
  "zone": "us-central1-a",
  "ip": "10.30.1.x",
  "status": "healthy"
}
```

### 5. 로드밸런싱 확인 (여러 Backend 서버 응답)

```bash
gcloud compute ssh frontend-service --tunnel-through-iap \
  --project=lb-03-internal-lb --zone=us-central1-a \
  -- 'for i in $(seq 1 9); do curl -s http://10.30.1.5/api | grep -o '"'"'backend-api-[a-z0-9-]*'"'"'; done'
```

### 6. Backend VM 목록 확인

```bash
gcloud compute instances list --project=lb-03-internal-lb \
  --filter="name~backend-api" \
  --format="table(name,zone,networkInterfaces[0].networkIP,status)"
```

> Backend VM 은 외부 IP 가 없으므로 직접 SSH 접속은 IAP 를 통해서만 가능합니다.

### 7. MIG 헬스 상태 확인

```bash
gcloud compute backend-services get-health backend-api-service \
  --region=us-central1 \
  --project=lb-03-internal-lb
```

모든 Backend 가 `HEALTHY` 상태여야 트래픽이 분산됩니다.

## 보안 검증

### Backend 외부 접근 불가 확인

```bash
# Backend VM IP 목록 확인 (외부 IP 없음)
gcloud compute instances list --project=lb-03-internal-lb \
  --filter="name~backend-api" \
  --format="table(name,networkInterfaces[0].accessConfigs[0].natIP)"

# 결과: natIP 컬럼이 비어 있음 → 외부 IP 없음
```

### Internal LB VIP 는 VPC 외부에서 접근 불가

```bash
# 외부에서 직접 시도 → 연결 안 됨 (Private IP)
curl --connect-timeout 5 http://10.30.1.5/api
# curl: (28) Connection timed out after 5000 milliseconds
```

## 오류 트러블슈팅

### Backend 가 모두 UNHEALTHY 인 경우

```bash
# 헬스체크 방화벽 규칙 확인
gcloud compute firewall-rules describe micro-allow-health-check \
  --project=lb-03-internal-lb

# source_ranges 에 130.211.0.0/22 와 35.191.0.0/16 이 있어야 함
# target_tags 에 backend-api 가 있어야 함
```

### 데모 페이지에서 API 호출 실패

nginx 가 Internal LB VIP 로 제대로 프록시하는지 확인:

```bash
gcloud compute ssh frontend-service --tunnel-through-iap \
  --project=lb-03-internal-lb --zone=us-central1-a \
  -- cat /etc/nginx/sites-available/default
# proxy_pass http://10.30.1.5/api; 가 있어야 함
```

### 조직 정책 오류 (`vmExternalIpAccess`)

`providers.tf` 에 이미 org policy override 가 포함되어 있습니다:

```hcl
resource "google_project_organization_policy" "vm_external_ip" {
  project    = var.project_id
  constraint = "constraints/compute.vmExternalIpAccess"
  list_policy {
    allow { all = true }
  }
}
```

조직 정책이 강하게 enforced 되어 있는 경우 프로젝트 레벨 override 가 안 될 수 있습니다. 이 경우 조직 관리자에게 문의하거나 Frontend VM 의 `access_config` 를 제거하고 IAP 터널로 접속합니다.

## 정리

```bash
terraform destroy
```

## 관련 GCP 문서

- [Regional Internal passthrough Network Load Balancer](https://cloud.google.com/load-balancing/docs/internal)
- [Health check firewall rules](https://cloud.google.com/load-balancing/docs/health-checks#fw-rule)
- [Cloud NAT overview](https://cloud.google.com/nat/docs/overview)
