# PSC-05: Private DNS Hub

## 개요

여러 VPC 에 흩어진 PSC endpoint 의 DNS 해석을 **중앙 Hub VPC 하나에서 통합 관리**하는 패턴입니다.

기업 환경에서는 dev-vpc, staging-vpc, prod-vpc 등 VPC 마다 동일한 DNS zone 을 따로 관리하면
변경 시 모든 VPC 에 반복 작업이 필요합니다. DNS Hub 패턴은 zone 을 hub 에 하나만 두고
spoke VPC 들이 **DNS Peering** 으로 위임받아 이 문제를 해결합니다.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                           GCP Project                              │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Hub VPC (10.0.0.0/24)                                       │  │
│  │                                                              │  │
│  │  PSC Endpoint: 10.0.1.2 ──→ all-apis (Google APIs)          │  │
│  │                                                              │  │
│  │  ┌─────────────────────────────────────────────────────┐    │  │
│  │  │  Private DNS Zone: googleapis-hub                   │    │  │
│  │  │  *.googleapis.com  → 10.0.1.2                       │    │  │
│  │  │  googleapis.com    → 10.0.1.2                       │    │  │
│  │  └─────────────────────────────────────────────────────┘    │  │
│  │                                                              │  │
│  │  [Cloud Router + NAT]   hub-vm                              │  │
│  └───────────┬──────────────────────┬────────────────────────┘  │
│              │ VPC Peering          │ VPC Peering               │
│   (export_custom_routes=true)  (export_custom_routes=true)      │
│              │                      │                            │
│  ┌───────────▼──────────┐  ┌────────▼─────────────────┐        │
│  │  Dev VPC             │  │  Prod VPC                │        │
│  │  (10.1.0.0/24)       │  │  (10.2.0.0/24)           │        │
│  │                      │  │                          │        │
│  │  DNS Peering Zone    │  │  DNS Peering Zone        │        │
│  │  googleapis.com      │  │  googleapis.com          │        │
│  │  → hub-vpc zone 위임  │  │  → hub-vpc zone 위임      │        │
│  │                      │  │                          │        │
│  │  dev-vm              │  │  prod-vm                 │        │
│  └──────────────────────┘  └──────────────────────────┘        │
└────────────────────────────────────────────────────────────────────┘
```

## 문제 → 해결

### 기존 방식 (VPC 마다 개별 관리)
```
dev-vpc   → Private Zone: googleapis.com → 10.1.x.x  (PSC IP)
prod-vpc  → Private Zone: googleapis.com → 10.2.x.x  (PSC IP)
team-vpc  → Private Zone: googleapis.com → 10.3.x.x  (PSC IP)

PSC endpoint IP 변경 시 → 모든 VPC 의 zone 을 각각 수정
신규 VPC 추가 시 → PSC endpoint + DNS zone 을 매번 새로 생성
```

### DNS Hub 패턴
```
hub-vpc   → Private Zone: googleapis.com → 10.0.1.2  ← 딱 하나만 관리

dev-vpc   → DNS Peering Zone → hub-vpc 위임 (zone 없음)
prod-vpc  → DNS Peering Zone → hub-vpc 위임 (zone 없음)
team-vpc  → DNS Peering Zone → hub-vpc 위임 (zone 없음)

IP 변경 시  → hub-vpc zone 하나만 수정하면 모든 spoke 에 자동 반영
신규 VPC 추가 → VPC Peering + DNS Peering zone 만 추가
```

## 핵심 리소스

### 1. Hub: PSC Endpoint + Private DNS Zone

```hcl
# PSC Endpoint
resource "google_compute_global_address" "psc_endpoint" {
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = google_compute_network.hub.id
  address      = "10.0.1.2"
}

resource "google_compute_global_forwarding_rule" "google_apis" {
  name                  = "pscgoogleapis"   # alphanumeric only
  target                = "all-apis"
  load_balancing_scheme = ""
  no_automate_dns_zone  = true
}

# Private DNS Zone (hub 에서만 생성)
resource "google_dns_managed_zone" "googleapis" {
  name       = "googleapis-hub"
  dns_name   = "googleapis.com."
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.hub.id
    }
  }
}
```

### 2. Spoke: VPC Peering + DNS Peering Zone

```hcl
# VPC Peering (양방향 필수)
# spoke → hub: PSC endpoint 경로 가져오기
resource "google_compute_network_peering" "dev_to_hub" {
  import_custom_routes = true   # hub 의 PSC /32 경로 수신
}
# hub → spoke: PSC endpoint 경로 내보내기
resource "google_compute_network_peering" "hub_to_dev" {
  export_custom_routes = true   # PSC /32 경로 송출
}

# DNS Peering Zone (zone 내용 없음, 위임만 함)
resource "google_dns_managed_zone" "dev_googleapis_peering" {
  dns_name   = "googleapis.com."
  visibility = "private"

  peering_config {
    target_network {
      network_url = google_compute_network.hub.id  # hub 으로 위임
    }
  }
}
```

## VPC Peering 에서 custom routes 가 필요한 이유

PSC endpoint IP (10.0.1.2) 는 서브넷에 속하지 않는 **글로벌 주소**입니다.
VPC Peering 은 기본적으로 서브넷 경로만 교환하므로,
PSC endpoint 경로(/32)를 전달하려면 `export/import_custom_routes = true` 가 필요합니다.

```
hub-vpc 의 PSC 경로: 10.0.1.2/32 (custom route)

export_custom_routes = true  →  hub 이 이 경로를 spoke 에 내보냄
import_custom_routes = true  →  spoke 가 이 경로를 받아 10.0.1.2 로 패킷 전송 가능
```

## DNS Peering vs DNS Forwarding

| | DNS Peering | DNS Forwarding |
|--|--|--|
| 설정 | peering_config 블록 | forwarding_config 블록 |
| 연결 방식 | VPC Peering 필요 | VPN/Interconnect 도 가능 |
| 작동 원리 | Cloud DNS 가 직접 위임 | 지정 IP 로 DNS 쿼리 전달 |
| 적합한 환경 | 같은 프로젝트/조직 | Cross-org, On-premises 연계 |

이 예제는 동일 프로젝트 내 허브-스포크 구성이므로 **DNS Peering** 방식을 사용합니다.

## 파일 구조

| 파일 | 설명 |
|------|------|
| `providers.tf` | Google provider, API 활성화, Org Policy, API propagation wait |
| `variables.tf` | 변수 정의 |
| `01-hub-vpc.tf` | Hub VPC, PSC endpoint, Private DNS zone, Cloud Router/NAT |
| `02-spoke-dev-vpc.tf` | Dev VPC, VPC Peering (custom routes), DNS Peering zone |
| `03-spoke-prod-vpc.tf` | Prod VPC, VPC Peering (custom routes), DNS Peering zone |
| `04-test-vms.tf` | hub-vm, dev-vm, prod-vm (dnsutils 설치) |
| `outputs.tf` | SSH 명령어, 테스트 시나리오 |

## 사전 요구사항

```bash
gcloud services enable cloudresourcemanager.googleapis.com iam.googleapis.com \
  --project=<YOUR_PROJECT_ID>
```

## 배포 방법

```bash
cp terraform.tfvars.example terraform.tfvars
# project_id 입력 후

terraform init
terraform apply
```

## 테스트 방법

```bash
# Dev VM 접속
gcloud compute ssh dev-vm --zone=us-central1-a --tunnel-through-iap \
  --project=psc-05-private-dns-hub

# DNS 해석 확인
nslookup storage.googleapis.com
# → Address: 10.0.1.2  ✅ (hub 의 PSC endpoint IP)

nslookup bigquery.googleapis.com
# → Address: 10.0.1.2  ✅ (wildcard *.googleapis.com 적용)
```

## 신규 Spoke 추가 방법

`03-spoke-prod-vpc.tf` 를 복사하여 이름과 IP 대역만 변경합니다:

```bash
cp 03-spoke-prod-vpc.tf 04-spoke-staging-vpc.tf
# prod → staging, 10.2.0.0/24 → 10.3.0.0/24 으로 변경
terraform apply
```

DNS zone 추가/변경은 불필요합니다. hub 의 zone 을 자동으로 참조합니다.

## 주요 포인트

1. **DNS zone 은 hub 에 하나만** — spoke 에는 peering zone 만 존재 (실제 레코드 없음)
2. **VPC Peering + DNS Peering 세트** — DNS Peering 만으로는 패킷이 PSC IP 까지 도달 불가
3. **custom routes 필수** — PSC endpoint IP 는 서브넷 외부 주소, 별도 경로 교환 필요
4. **Non-transitive 주의** — spoke 간 직접 통신 불가 (dev ↔ prod 직접 연결 안됨)

## 리소스 삭제

```bash
terraform destroy
```
