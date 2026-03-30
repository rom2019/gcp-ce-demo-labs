# PSC-03: Google APIs — all-apis endpoint

GCP Private Service Connect (PSC) 를 통해 Google APIs (GCS 등) 에 프라이빗하게 접근하는 예제입니다.

---

## psc-02 와의 핵심 차이점

| 구분 | psc-02 (Published Service) | psc-03 (Google APIs) |
|------|---------------------------|----------------------|
| 대상 | 사용자가 만든 서비스 | Google 관리 API |
| Forwarding Rule | Regional | **Global** |
| Target | Service Attachment URI | **`all-apis`** (고정 문자열) |
| Producer 구성 | 필요 (GKE, ILB 등) | 불필요 (Google이 관리) |
| DNS 설정 | 불필요 | **필수** |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ VPC (psc-google-apis-vpc)                                   │
│                                                             │
│  ┌──────────────────────┐                                   │
│  │ Test VM              │                                   │
│  │ (IAP SSH)            │                                   │
│  └──────────┬───────────┘                                   │
│             │ storage.googleapis.com 조회                   │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │ Cloud DNS            │                                   │
│  │ Private Zone         │                                   │
│  │ *.googleapis.com     │                                   │
│  │   → PSC endpoint IP  │                                   │
│  └──────────┬───────────┘                                   │
│             │                                               │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │ PSC Endpoint         │                                   │
│  │ Global Forwarding Rule│                                  │
│  │ target = "all-apis"  │                                   │
│  └──────────┬───────────┘                                   │
└─────────────│───────────────────────────────────────────────┘
              │ PSC 터널
              ▼
     Google APIs (GCS, BigQuery 등)
```

### 트래픽 흐름

```
Test VM
  → DNS 조회: storage.googleapis.com
  → Cloud DNS Private Zone: PSC endpoint IP 반환
  → PSC endpoint (Global Forwarding Rule, target=all-apis)
  → [PSC 터널]
  → Google APIs (GCS)
```

---

## 파일 구조

| 파일 | 리소스 | GCP Console 확인 위치 |
|------|--------|-----------------------|
| `providers.tf` | Provider 설정, API 활성화, Org Policy | - |
| `01-vpc.tf` | VPC, 서브넷, Cloud NAT | VPC network > VPC networks |
| `02-psc-endpoint.tf` | PSC Global Address, Global Forwarding Rule | Private Service Connect > Connected endpoints |
| `03-dns.tf` | googleapis.com Private DNS Zone + A 레코드 | Network services > Cloud DNS |
| `04-test-vm.tf` | Test VM, Service Account, IAP 방화벽 | Compute Engine > VM instances |

---

## 핵심 개념

### 1. `all-apis` vs `vpc-sc` 번들

| 번들 | 허용 범위 | 용도 |
|------|----------|------|
| `all-apis` | 모든 Google API | 일반 프라이빗 접근 |
| `vpc-sc` | VPC Service Controls 범위 내 API만 | 보안 강화 (규정 준수) |

이 예제는 `all-apis` 를 사용합니다.

### 2. Global vs Regional Forwarding Rule

PSC for Google APIs 는 **Global** Forwarding Rule 을 사용합니다.
psc-02 의 Published Service 는 Regional 을 사용한다는 점에서 차이가 있습니다.

```hcl
# psc-02: Regional (특정 리전의 서비스)
resource "google_compute_forwarding_rule" ...

# psc-03: Global (Google API 는 글로벌 서비스)
resource "google_compute_global_forwarding_rule" ...
```

### 3. DNS 설정이 핵심

PSC endpoint IP 를 DNS 로 연결하지 않으면 VM 이 `storage.googleapis.com` 을 조회할 때
공인 IP 로 라우팅됩니다. Private DNS Zone 으로 이를 override 합니다.

```
[ DNS Private Zone 없을 때 ]
dig storage.googleapis.com → 142.250.x.x (Google 공인 IP)

[ DNS Private Zone 있을 때 ]
dig storage.googleapis.com → 10.x.x.x (PSC endpoint IP)
```

### 4. `private_ip_google_access = false`

이 예제에서는 서브넷의 `private_ip_google_access` 를 **false** 로 설정합니다.
PSC endpoint 가 유일한 Google API 접근 경로인지 검증하기 위함입니다.

`private_ip_google_access = true` 로 설정하면 PSC 없이도 Google API 에 접근할 수 있어
PSC 테스트 결과가 불명확해집니다.

### 5. `no_automate_dns_zone = true`

Forwarding Rule 생성 시 GCP 가 DNS Zone 을 자동 생성하는 기능을 비활성화합니다.
`03-dns.tf` 에서 직접 DNS 를 관리함으로써 구성 요소를 명시적으로 학습합니다.

---

## 사용 방법

### 1. 준비

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 에 project_id 입력
```

### 2. 배포

```bash
terraform init
terraform apply
```

### 3. 접속 및 테스트

```bash
# Test VM SSH (IAP)
$(terraform output -raw test_vm_ssh_cmd)
```

VM 내에서:

```bash
# 1. DNS 확인 - PSC endpoint IP 가 응답으로 와야 함
dig storage.googleapis.com
# → ANSWER SECTION 에 PSC endpoint IP 가 표시되면 성공

# 2. GCS 버킷 목록 조회
gsutil ls

# 3. curl 로 직접 API 호출
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://storage.googleapis.com/storage/v1/b?project=<project_id>"
```

### 4. 리소스 삭제

```bash
terraform destroy
```

---

## GCP Console 확인 포인트

1. **Private Service Connect > Connected endpoints**
   - `psc-google-apis` endpoint 확인
   - Target: `all-apis`
   - Status: `Accepted`

2. **Network services > Cloud DNS**
   - `googleapis-com` Private Zone 확인
   - A 레코드: `*.googleapis.com` → PSC endpoint IP

3. **VPC network > VPC networks > psc-google-apis-vpc**
   - 서브넷 `private_ip_google_access` 가 비활성화되어 있는지 확인

---

## 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `project_id` | GCP 프로젝트 ID | (필수) |
| `region` | GCP 리전 | `us-central1` |

---

## IP 대역 정리

| 용도 | 대역 |
|------|------|
| VPC 서브넷 | `10.0.0.0/24` |
| PSC endpoint IP | 자동 할당 (VPC 레벨) |
