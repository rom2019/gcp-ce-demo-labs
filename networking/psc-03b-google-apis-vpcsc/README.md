# PSC-03b: Google APIs — vpc-sc + VPC Service Controls

PSC `vpc-sc` 번들과 VPC Service Controls를 함께 사용하여 GCS 버킷을 보호하는 예제입니다.
경계 밖에서 접근 시 403, 경계 안에서 PSC endpoint를 통한 접근 시 성공하는 시나리오를 검증합니다.

---

## psc-03 (all-apis) 와의 차이

| 구분 | psc-03 (all-apis) | psc-03b (vpc-sc) |
|------|-------------------|-----------------|
| PSC target | `all-apis` | `vpc-sc` |
| VPC-SC 적용 | 우회 가능 | 강제 적용 |
| DNS 엔드포인트 | `*.googleapis.com` A record | `restricted.googleapis.com` A + CNAME |
| 접근 제어 | 없음 | Access Level (Service Account 기반) |
| 경계 밖 접근 | 허용 | **403 ACCESS_DENIED** |

> **핵심**: `all-apis`를 사용하면 VPC-SC 경계를 우회할 수 있습니다.
> 보안이 필요한 환경에서는 반드시 `vpc-sc`를 사용해야 합니다.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ VPC-SC Perimeter                                                │
│                                                                 │
│  ┌──────────────────────┐   ┌──────────────────────────────┐   │
│  │ VPC (psc-vpcsc-vpc)  │   │ GCS Bucket                   │   │
│  │                      │   │ (restricted service)         │   │
│  │  Test VM             │   └──────────────────────────────┘   │
│  │  SA: psc-test-vm-sa  │                                      │
│  │  (Access Level 충족) │                                      │
│  └──────────┬───────────┘                                      │
│             │ nslookup storage.googleapis.com                  │
│             │  → CNAME → restricted.googleapis.com             │
│             │  → A → 10.0.1.2 (PSC IP)                        │
│             ▼                                                   │
│  ┌──────────────────────┐                                      │
│  │ PSC Endpoint         │                                      │
│  │ target = "vpc-sc"    │                                      │
│  └──────────┬───────────┘                                      │
└─────────────│───────────────────────────────────────────────────┘
              │ PSC 터널 + VPC-SC 검사
              ▼
         Google APIs (GCS)
              ▲
              │ 403 ACCESS_DENIED
              │
     로컬 머신 (경계 밖, Access Level 미충족)
```

### 트래픽 흐름

```
[성공] VM → DNS(CNAME) → restricted.googleapis.com → PSC → VPC-SC(Access Level OK) → GCS
[실패] 로컬 → storage.googleapis.com → VPC-SC(Access Level 없음) → 403
```

---

## 파일 구조

| 파일 | 리소스 | GCP Console 확인 위치 |
|------|--------|-----------------------|
| `providers.tf` | Provider, API 활성화, Org Policy | - |
| `01-vpc.tf` | VPC, 서브넷, Cloud NAT | VPC network > VPC networks |
| `02-psc-endpoint.tf` | PSC Global Address, Global FR (`vpc-sc`) | Private Service Connect > Connected endpoints |
| `03-dns.tf` | googleapis.com Private Zone + CNAME + A 레코드 | Network services > Cloud DNS |
| `04-gcs-bucket.tf` | 테스트 GCS 버킷, 테스트 파일 | Cloud Storage > Buckets |
| `05-vpc-sc.tf` | Access Policy, Access Level, Service Perimeter | Security > VPC Service Controls |
| `06-test-vm.tf` | Test VM, Service Account, IAP 방화벽 | Compute Engine > VM instances |

---

## 핵심 개념

### 1. VPC-SC 3대 구성 요소

```
Access Policy  ─── 조직 레벨 컨테이너 (scoped: 이 프로젝트에만 적용)
    │
    ├── Access Level  ─── "경계 안"으로 인정할 조건
    │       조건: psc-test-vm-sa Service Account
    │
    └── Service Perimeter  ─── 보호 범위
            restricted_services: storage.googleapis.com
            resources: 이 프로젝트
            access_levels: (위의 Access Level)
```

### 2. DNS — CNAME 방식 (psc-03과 차이)

```
psc-03:   storage.googleapis.com → (A) → 10.0.1.2
psc-03b:  storage.googleapis.com → (CNAME) → restricted.googleapis.com → (A) → 10.0.1.2
```

CNAME을 사용하면 트래픽이 `restricted.googleapis.com`을 경유함을 명시적으로 표현합니다.

### 3. Scoped Access Policy

이 예제는 조직 레벨이 아닌 **프로젝트 스코프** Access Policy를 사용합니다.

```hcl
resource "google_access_context_manager_access_policy" "policy" {
  parent = "organizations/${var.org_id}"
  title  = "psc-03b-demo-policy"
  scopes = ["projects/${project_number}"]  # 이 프로젝트에만 적용
}
```

조직의 기존 Access Policy와 충돌 없이 독립적으로 동작합니다.

---

## 사용 방법

### 1. 준비

```bash
cp terraform.tfvars.example terraform.tfvars
# project_id, org_id 입력
```

```bash
# org_id 확인
gcloud organizations list
```

### 2. 배포

```bash
terraform init
terraform apply
```

### 3. 테스트

#### [경계 밖] 로컬 머신에서 — 403 확인

```bash
$(terraform output -raw test_outside_perimeter_cmd)
# → ERROR 403: Request is prohibited by organization's policy. accessPolicies/...
```

#### [경계 안] Test VM에서 — 성공 확인

```bash
# VM SSH 접속
$(terraform output -raw test_vm_ssh_cmd)

# VM 내에서 DNS 확인
nslookup storage.googleapis.com
# → CNAME → restricted.googleapis.com → 10.0.1.2

# GCS 접근 테스트
gcloud storage objects list gs://$(terraform output -raw gcs_bucket_name)
# → hello.txt 파일이 출력되면 성공
```

### 4. 리소스 삭제

> VPC-SC Perimeter 삭제 후 다른 리소스를 삭제해야 오류가 없습니다.

```bash
terraform destroy
```

---

## GCP Console 확인 포인트

1. **Security > VPC Service Controls**
   - Access Policy: `psc-03b-demo-policy` (scoped)
   - Service Perimeter: `psc-perimeter` → `storage.googleapis.com` 보호 확인
   - Access Level: `psc-vm-access` → SA 조건 확인

2. **Private Service Connect > Connected endpoints**
   - `pscvpcsc` endpoint, target: `vpc-sc` 확인

3. **Network services > Cloud DNS**
   - `googleapis-com` Private Zone
   - `restricted.googleapis.com` A record → `10.0.1.2`
   - `storage.googleapis.com` CNAME → `restricted.googleapis.com`

---

## 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `project_id` | GCP 프로젝트 ID | (필수) |
| `org_id` | GCP 조직 ID | (필수) |
| `region` | GCP 리전 | `us-central1` |

---

## IP 대역 정리

| 용도 | 대역 |
|------|------|
| VPC 서브넷 | `10.0.0.0/24` |
| PSC endpoint IP | `10.0.1.2` |
