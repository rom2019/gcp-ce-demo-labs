# NCC Demo: On-Prem Static Routing via Classic VPN + HA VPN Hybrid Spoke

## 계층 구조

```
[sim-onprem-vm: 192.168.1.x]
        |
[sim-onprem-vpc: 192.168.1.0/24]        ← On-prem 시뮬레이션
  Static Routes:
    172.16.1.0/24 → tunnel
    10.0.0.0/8    → tunnel (신규 VPC 자동 커버)
        |
  Classic VPN (IKEv2)
        |
┌──────────────────────────────────────┐
│ Edge Layer                           │
│ [edge-vpc: 172.16.1.0/24]            │
│   edge-cloud-router ASN 65001        │
│   per-peer Custom Adv: 192.168.1.0/24│
└──────────────────────────────────────┘
        |
  HA VPN (BGP Established)
        |
┌──────────────────────────────────────┐
│ Hub Layer                            │
│ [transit-hub-vpc: 10.10.1.0/24]      │
│   transit-hub-cloud-router ASN 65002 │
└──────────────────────────────────────┘
        |
    NCC Hub (Mesh)
        ├── ncc-hybrid-spoke-transit-hub  (Hybrid Spoke)
        ├── ncc-vpc-spoke-transit-hub     (VPC Spoke)
        └── ncc-vpc-spoke-workload-test1  (VPC Spoke)
        |
┌──────────────────────────────────────┐
│ Spoke Layer                          │
│ [workload-test1-vpc: 10.20.1.0/24]   │
│ [workload-prod1-vpc: 10.30.1.0/24]   │ ← 확장 예시
└──────────────────────────────────────┘
```

## 파일 구조

| 파일 | 내용 |
|---|---|
| `variables.tf` | 변수 (CIDR, PSK, region 등) |
| `main.tf` | Provider, API 활성화 |
| `vpc.tf` | VPC 4개 + Subnet |
| `classic_vpn.tf` | Classic VPN + Forwarding Rules + Static Routes |
| `ha_vpn.tf` | Cloud Router + HA VPN + BGP (edge 측만 수동) |
| `ncc.tf` | NCC Hub (Mesh) + Spoke 3개 |
| `firewall.tf` | 방화벽 규칙 |
| `vms.tf` | 테스트 VM 3개 |
| `outputs.tf` | IP 출력 + ping 명령어 |

## 사용 방법

```bash
# 1. Project ID 변경
vi terraform.tfvars

# 2. 초기화
terraform init

# 3. 배포
terraform apply

# 4. ping 테스트 명령어 확인
terraform output ping_test_commands
```

## 신규 Spoke VPC 추가 시 (데모 핵심)

```hcl
# vpc.tf에 추가
resource "google_compute_network" "workload_prod1" {
  name = "workload-prod1-vpc"
  ...
}

# ncc.tf에 추가 (이것만 하면 끝!)
resource "google_network_connectivity_spoke" "vpc_workload_prod1" {
  name = "ncc-vpc-spoke-workload-prod1"
  linked_vpc_network {
    uri = google_compute_network.workload_prod1.self_link
  }
}
```

→ sim-onprem-vpc의 `10.0.0.0/8` supernet이 자동 커버
→ Classic VPN tunnel 수정 불필요
→ edge-cloud-router Custom Advertisement 수정 불필요

## BGP 핵심 포인트

| 터널 | BGP 관리 | 역할 |
|---|---|---|
| tunnel-edge-to-transit-hub-1/2 | edge-cloud-router (수동) | on-prem 경로를 transit-hub에 전달 |
| tunnel-transit-hub-to-edge-1/2 | NCC Hub (자동) | NCC Hub이 on-prem 경로 학습 후 전체 Spoke로 전파 |
