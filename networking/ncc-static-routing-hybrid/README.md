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
    ├─ 172.16.1.0/24 → tunnel-classic-vpn-sim-onprem-to-edge
    └─ 10.0.0.0/8    → tunnel-classic-vpn-sim-onprem-to-edge (Supernet)
        |
  Classic VPN (IKEv2, Route-based, Traffic Selectors: 0.0.0.0/0)
        |
┌────────────────────────────────────────────────────────┐
│ Edge Layer                                             │
│ [edge-vpc: 172.16.1.0/24]                              │
│                                                        │
│   Static Route:                                        │
│     └─ 192.168.1.0/24 → tunnel-classic-vpn-edge-to-sim-onprem
│                                                        │
│   edge-cloud-router (ASN: 65001)                       │
│     └─ BGP Peer Adv: CUSTOM (ALL_SUBNETS + 192.168.1.0/24)
└────────────────────────────────────────────────────────┘
        |
  HA VPN (BGP Established)
        |
┌────────────────────────────────────────────────────────┐
│ Hub Layer                                              │
│ [transit-hub-vpc: 10.10.1.0/24]                        │
│                                                        │
│   transit-hub-cloud-router (ASN: 65002)                │
│     └─ BGP Peer Adv: DEFAULT                           │
└────────────────────────────────────────────────────────┘
        |
    NCC Hub (Mesh: ncc-demo-hub)
        ├── ncc-hybrid-spoke-transit-hub (Import: ALL_IPV4_RANGES)
        │      └─ Linked: tunnel-transit-hub-to-edge-1 & 2
        ├── ncc-vpc-spoke-transit-hub
        │      └─ Linked: transit-hub-vpc
        └── ncc-vpc-spoke-workload-test1
               └─ Linked: workload-test1-vpc
        |
┌────────────────────────────────────────────────────────┐
│ Spoke Layer                                            │
│ [workload-test1-vpc: 10.20.1.0/24]                     │
│ [workload-prod1-vpc: 10.30.1.0/24] ← (확장 예시)         │
└────────────────────────────────────────────────────────┘

** HA VPN & BGP Configuration (Edge ↔ Hub) **
=========================================================================================================
  [ARCHITECTURE REFERENCE] HA VPN & BGP Configuration (Edge ↔ Hub)
=========================================================================================================
  [Edge Layer] edge-vpc : 172.16.1.0/24           |  [Hub Layer] transit-hub-vpc : 10.10.1.0/24
  Cloud Router : edge-cloud-router                |  Cloud Router : 	transit-hub-cloud-router
  Local ASN    : 65001                            |  Local ASN    : 65002
=========================================================================================================
  TUNNEL 1 (Active)
---------------------------------------------------------------------------------------------------------
  Tunnel Name  : tunnel-edge-to-transithub-1         |  Tunnel Name  : tunnel-transithub-to-edge-1
  VPN GW IP    : 35.242.114.78 (Local)               |  VPN GW IP    : 34.183.16.186 (Local)
  Remote Peer  : 34.183.16.186                       |  Remote Peer  : 35.242.114.78
  Peer ASN     : 65002                               |  Peer ASN     : 65001
  BGP IP       : 169.254.1.1 (Local)                 |  BGP IP       : 169.254.1.2 (Local)
  BGP Peer IP  : 169.254.1.2                         |  BGP Peer IP  : 169.254.1.1
  Routes       : Custom (Default + 192.168.1.0/24)   |  Routes       : Default
=========================================================================================================
  TUNNEL 2 (Active)
---------------------------------------------------------------------------------------------------------
  Tunnel Name  : tunnel-edge-to-transithub-2     |  Tunnel Name  : tunnel-transithub-to-edge-2
  VPN GW IP    : 35.220.78.96 (Local)                |  VPN GW IP    : 34.184.19.214 (Local)
  Remote Peer  : 34.184.19.214                       |  Remote Peer  : 35.220.78.96
  Peer ASN     : 65002                               |  Peer ASN     : 65001
  BGP IP       : 169.254.2.1 (Local)                 |  BGP IP       : 169.254.2.2 (Local)
  BGP Peer IP  : 169.254.2.2                         |  BGP Peer IP  : 169.254.2.1
  Routes       : Custom (Default + 192.168.1.0/24)   |  Routes       : Default
=========================================================================================================

```

---
## Layer 설명

| Layer | VPC | CIDR | 핵심 역할 |
|---|---|---|---|
| **On-prem (Sim)** | `sim-onprem-vpc` | `192.168.1.0/24` | 정적 라우팅(Static Routing)만 지원하는 레거시 온프레미스 환경 시뮬레이션 |
| **Edge Layer** | `edge-vpc` | `172.16.1.0/24` | 외부(On-prem)와의 Classic VPN 종단점. 수동 설정을 통해 On-prem 경로를 Hub로 전달 |
| **Hub Layer** | `transit-hub-vpc` | `10.10.1.0/24` | NCC(Network Connectivity Center)가 위치하는 중앙 네트워크 허브. Edge와 Spoke 간의 트래픽 라우팅 전담 |
| **Spoke Layer** | `workload-test1-vpc` | `10.20.1.0/24` | 실제 애플리케이션 및 워크로드가 배포되는 환경. NCC VPC Spoke로 연결됨 |

---

## Demo Points

### 1. 장비 교체 없이 NCC의 Mesh 라우팅 이점 활용
온프레미스 라우터가 BGP를 지원하지 않더라도, 클라우드 내부에 Edge Layer(Classic VPN ↔ HA VPN)를 두어 NCC Hub과 BGP 세션을 맺게 함으로써 정적 라우팅 환경을 동적 라우팅(NCC) 환경으로 매끄럽게 연결합니다.

### 2. 신규 Workload VPC 확장 시 구성 변경 최소화 (Supernetting)
온프레미스 측 라우팅 테이블에 GCP 전체 대역을 포괄하는 슈퍼넷(`10.0.0.0/8`)을 향하도록 정적 라우트(Static Route)를 미리 선언해 두었습니다. 이로 인해 새로운 Spoke VPC가 추가되더라도 온프레미스 장비나 Classic VPN 터널의 설정을 전혀 수정할 필요 없이 즉시 통신이 가능합니다.


---

## Key Learnings

| 핵심 항목 | Terraform 구현 가이드 및 주의사항 |
|---|---|
| **Edge Router BGP 광고** | Edge 측 Cloud Router는 Hub 방향으로 자신의 대역(`ALL_SUBNETS`)뿐만 아니라, 온프레미스 대역(`192.168.1.0/24`)을 수동으로 추가하여(Custom Advertisement) 광고해야 합니다. |
| **Hybrid Spoke 라우트 수신** | Hub가 학습한 다른 VPC Spoke들의 경로(예: `10.20.1.0/24`)를 Edge 측으로 전달하기 위해서는, Hybrid Spoke 설정 시 Import Filter를 반드시 `ALL_IPV4_RANGES`로 설정해야 합니다. |