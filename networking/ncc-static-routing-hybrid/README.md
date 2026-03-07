# NCC: Bridging On-Prem Static Routing via Classic VPN + HA VPN Hybrid Spoke

## Problem Statement

온프레미스 장비가 **Static Routing만 지원** (BGP 불가)할 때 Network Connectivity Center(NCC)에 연결하는 Workaround 데모입니다.
BGP를 지원하는 Router Appliance Spoke(NVA) 방식이 이상적이지만, 레거시 장비 교체 없이 NCC의 Mesh 토폴로지를 활용하고 싶은 고객을 위한 솔루션입니다.

---

## Architecture

```
[sim-onprem-vm: 192.168.1.x]
        |
[sim-onprem-vpc: 192.168.1.0/24]   ← On-prem 시뮬레이션
  Static Routes:
    172.16.1.0/24 → tunnel
    10.0.0.0/8    → tunnel          ← Supernet: 신규 VPC 자동 커버
        |
  Classic VPN (IKEv2, Route-based)
        |
┌─────────────────────────────────────────┐
│ Edge Layer                              │
│ edge-vpc (172.16.1.0/24)                │
│   edge-cloud-router ASN 65001           │
│   per-peer Custom Adv: 192.168.1.0/24   │ ← on-prem 경로를 NCC Hub으로 광고
└─────────────────────────────────────────┘
        |
  HA VPN (BGP Established)
        |
┌─────────────────────────────────────────┐
│ Hub Layer                               │
│ transit-hub-vpc (10.10.1.0/24)          │
│   transit-hub-cloud-router ASN 65002    │
└─────────────────────────────────────────┘
        |
    NCC Hub (Mesh)
        ├── ncc-hybrid-spoke-transit-hub   ← tunnel-transit-hub-to-edge 등록
        ├── ncc-vpc-spoke-transit-hub
        └── ncc-vpc-spoke-workload-test1
        |
[workload-test1-vpc: 10.20.1.0/24]        ← Spoke Layer
```

---

## Layer 설명

| Layer | VPC | CIDR | 역할 |
|---|---|---|---|
| On-prem 시뮬레이션 | `sim-onprem-vpc` | `192.168.1.0/24` | 레거시 on-prem 장비 시뮬레이션 |
| Edge | `edge-vpc` | `172.16.1.0/24` | Classic VPN 종단, on-prem 연결 전담 |
| Hub | `transit-hub-vpc` | `10.10.1.0/24` | NCC 중심, 클라우드 내부 라우팅 전담 |
| Spoke | `workload-test1-vpc` | `10.20.1.0/24` | 실제 워크로드 |

---

## Demo Points

### 1. Static Routing 장비 변경 없이 NCC 연결
Classic VPN (Route-based) + HA VPN Hybrid Spoke 조합으로 BGP 없이도 NCC Hub에 on-prem 경로 전파 가능

### 2. 신규 VPC 추가 시 자동 통신
`10.0.0.0/8` Supernet 덕분에 새 Spoke VPC를 NCC에 등록하는 것만으로 on-prem과 자동 통신
→ Classic VPN 터널 수정 불필요, Static Route 수정 불필요

### 3. 이 방식의 한계
BGP 지원 장비로 교체 가능하다면 **Router Appliance Spoke(NVA + FRR)** 방식이 더 완전한 자동화 가능
→ [`ncc-router-appliance-spoke`](../ncc-router-appliance-spoke) 참고

---

## Key Learnings

| 항목 | 핵심 |
|---|---|
| Classic VPN Route-based | `local/remote_traffic_selector = ["0.0.0.0/0"]` 필수, Static Route 별도 선언 |
| edge-cloud-router | per-peer Custom Advertisement로 `192.168.1.0/24` 명시 추가 |
| Hybrid Spoke 터널 방향 | `transit-hub-to-edge` 터널로 등록해야 NCC Hub이 edge-cloud-router와 BGP |
| Hybrid Spoke Import filter | `ALL_IPV4_RANGES` 설정해야 VPC Spoke 경로 수신 |
| NCC Spoke 추가 | VPC Spoke 등록만 하면 on-prem 포함 전체 통신 자동 |

---

## Prerequisites

- GCP Project (데모 리소스용)
- GCS Bucket (tfstate 저장용, 별도 프로젝트 가능)
- Terraform >= 1.3.0
- `gcloud` CLI 설치 및 인증 완료

---

## Quick Start

### 1. tfstate 버킷 생성 (최초 1회)

```bash
gcloud storage buckets create gs://YOUR_PROJECT_ID-tfstate \
  --location=asia-northeast3 \
  --uniform-bucket-level-access
```

### 2. backend 설정

```bash
cd terraform
cp backend.tf.example backend.tf
# backend.tf에서 bucket 이름 수정
```

### 3. 변수 설정

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars에서 project_id 수정
```

### 4. 배포

```bash
terraform init
terraform plan
terraform apply
```

### 5. 검증

```bash
# ping 명령어 확인
terraform output ping_test_commands

# sim-onprem-vm → workload-test1-vm
gcloud compute ssh sim-onprem-vm \
  --zone=asia-northeast3-a \
  --tunnel-through-iap \
  -- ping -c 4 <workload-test1-vm IP>
```

### 6. 리소스 삭제

```bash
terraform destroy
```

---

## File Structure

```
ncc-static-routing-hybrid/
├── README.md
├── docs/
│   └── demo-guide.md          ← Console 단계별 가이드 (Terraform 없이 재현)
└── terraform/
    ├── main.tf                ← Provider, API 활성화
    ├── variables.tf           ← 변수 선언
    ├── vpc.tf                 ← VPC 4개
    ├── classic_vpn.tf         ← Classic VPN (Route-based)
    ├── ha_vpn.tf              ← HA VPN + Cloud Router + BGP
    ├── ncc.tf                 ← NCC Hub + Spoke 3개
    ├── firewall.tf            ← 방화벽 규칙
    ├── vms.tf                 ← 테스트 VM 3개
    ├── outputs.tf             ← IP 출력 + ping 명령어
    ├── backend.tf.example     ← GCS backend 설정 예시
    └── terraform.tfvars.example
```

---

## Adding a New Workload VPC

신규 VPC 추가 시 아래만 작업하면 on-prem 포함 전체 통신 자동:

```hcl
# vpc.tf에 추가
resource "google_compute_network" "workload_prod1" {
  name = "workload-prod1-vpc"
  ...
}

# ncc.tf에 추가 (이것만 하면 끝!)
resource "google_network_connectivity_spoke" "vpc_workload_prod1" {
  name = "ncc-vpc-spoke-workload-prod1"
  hub  = google_network_connectivity_hub.main.id
  linked_vpc_network {
    uri = google_compute_network.workload_prod1.self_link
  }
}
```

---

