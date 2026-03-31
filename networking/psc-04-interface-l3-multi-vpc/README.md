# PSC-04: PSC Interface (L3) - Multi-VPC

## 개요

**PSC Interface** 는 Producer VM 의 NIC 를 Consumer VPC 에 직접 삽입하는 방식으로,
L3 수준의 양방향 통신을 제공합니다. Load Balancer 없이 IP 레벨에서 직접 통신합니다.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GCP Project                              │
│                                                                 │
│  ┌──────────────────┐      ┌───────────────────────────────┐   │
│  │  Producer VPC    │      │  Consumer VPC-A (10.1.0.0/24) │   │
│  │  (10.0.0.0/24)  │      │                               │   │
│  │                  │      │  ┌─────────────────────────┐  │   │
│  │  ┌────────────┐  │      │  │  Network Attachment     │  │   │
│  │  │producer-vm │  │      │  │  consumer-a-attachment  │  │   │
│  │  │            │  │      │  └──────────┬──────────────┘  │   │
│  │  │ nic0 (pri) │  │      │             │ nic1             │   │
│  │  │ 10.0.0.x   │  │      │  consumer-a-vm (10.1.0.x)    │   │
│  │  │            ├──┼──────┼─────────────┘                 │   │
│  │  │ nic2       │  │      └───────────────────────────────┘   │
│  │  │ 10.2.0.x   │  │                                          │
│  │  └──────┬─────┘  │      ┌───────────────────────────────┐   │
│  │         │        │      │  Consumer VPC-B (10.2.0.0/24) │   │
│  └─────────┼────────┘      │                               │   │
│            │               │  ┌─────────────────────────┐  │   │
│            │               │  │  Network Attachment     │  │   │
│            │               │  │  consumer-b-attachment  │  │   │
│            │               │  └──────────┬──────────────┘  │   │
│            └───────────────┼─────────────┘ nic2             │   │
│                            │  consumer-b-vm (10.2.0.x)     │   │
│                            └───────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## PSC Interface vs PSC Endpoint 비교

| 항목 | PSC Endpoint (psc-02) | PSC Interface (psc-04) |
|------|----------------------|------------------------|
| 통신 방향 | Consumer → Producer (단방향) | 양방향 (L3) |
| 구현 방식 | Forwarding Rule → Service Attachment | Network Attachment → NIC |
| Load Balancer | 필요 (Producer 측) | 불필요 |
| IP 위치 | Consumer VPC 내 별도 IP | Consumer 서브넷에서 NIC IP 할당 |
| 사용 사례 | Published Service (SaaS) | 긴밀한 서비스 통합, 관리형 서비스 |

## 핵심 리소스

### `google_compute_network_attachment`
Consumer VPC 에 Producer NIC 를 삽입할 수 있는 "구멍"을 만드는 리소스.

```hcl
resource "google_compute_network_attachment" "consumer_a" {
  name                  = "consumer-a-network-attachment"
  region                = var.region
  subnetworks           = [google_compute_subnetwork.consumer_a.id]
  connection_preference = "ACCEPT_AUTOMATIC"  # 학습용 (프로덕션: ACCEPT_MANUAL)
}
```

### Producer VM Multi-homed NIC
```hcl
resource "google_compute_instance" "producer" {
  network_interface {
    network    = google_compute_network.producer.id  # nic0: primary
    subnetwork = google_compute_subnetwork.producer.id
  }
  network_interface {
    network_attachment = google_compute_network_attachment.consumer_a.id  # nic1
  }
  network_interface {
    network_attachment = google_compute_network_attachment.consumer_b.id  # nic2
  }
}
```

## 파일 구조

| 파일 | 설명 |
|------|------|
| `providers.tf` | Google provider, API 활성화, Org Policy, API propagation wait |
| `variables.tf` | 변수 정의 |
| `01-producer-vpc.tf` | Producer VPC (10.0.0.0/24), IAP SSH 방화벽 |
| `02-consumer-a-vpc.tf` | Consumer VPC-A (10.1.0.0/24) + Network Attachment |
| `03-consumer-b-vpc.tf` | Consumer VPC-B (10.2.0.0/24) + Network Attachment |
| `04-producer-vm.tf` | Producer VM (NIC 3개: nic0/nic1/nic2) + nginx |
| `05-consumer-vms.tf` | Consumer-A VM, Consumer-B VM |
| `outputs.tf` | SSH 명령어, NIC IP 확인 명령어, 테스트 시나리오 |

## 사전 요구사항

### Bootstrap (최초 1회)
새 프로젝트에서는 Terraform 실행 전 필수 API 를 먼저 활성화해야 합니다:

```bash
gcloud services enable cloudresourcemanager.googleapis.com iam.googleapis.com \
  --project=<YOUR_PROJECT_ID>
```

## 배포 방법

```bash
# 1. tfvars 설정
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 에 project_id 입력

# 2. 초기화 및 배포
terraform init
terraform apply
```

## 테스트 방법

### 1. Producer NIC IP 확인
```bash
gcloud compute instances describe producer-vm \
  --zone=us-central1-a \
  --format='table(networkInterfaces[].networkIP)'
```

결과 예시:
```
NETWORK_IP
10.0.0.2   ← nic0 (producer-vpc)
10.1.0.2   ← nic1 (consumer-a-vpc)
10.2.0.2   ← nic2 (consumer-b-vpc)
```

### 2. Consumer → Producer (nginx 응답 확인)

```bash
# consumer-a-vm 에서 실행
gcloud compute ssh consumer-a-vm --zone=us-central1-a --tunnel-through-iap
curl http://10.1.0.2   # → "Hello from Producer VM (PSC Interface)"

# consumer-b-vm 에서 실행
gcloud compute ssh consumer-b-vm --zone=us-central1-a --tunnel-through-iap
curl http://10.2.0.2   # → "Hello from Producer VM (PSC Interface)"
```

### 3. Producer → Consumer (양방향 확인)

```bash
# producer-vm 에서 실행
gcloud compute ssh producer-vm --zone=us-central1-a --tunnel-through-iap
ping 10.1.0.3   # consumer-a-vm IP
ping 10.2.0.3   # consumer-b-vm IP
```

## 주요 포인트

1. **Network Attachment = "NIC 꽂을 구멍"**
   - Consumer 가 자신의 VPC 에 구멍을 만들고, Producer 가 NIC 를 꽂음
   - `ACCEPT_AUTOMATIC`: 자동 승인 (학습용)
   - `ACCEPT_MANUAL`: 수동 승인 + `producer_accept_lists` 지정 (프로덕션 권장)

2. **IP 할당 위치**
   - Producer nic1 의 IP 는 consumer-a-subnet (10.1.0.0/24) 에서 할당
   - Producer nic2 의 IP 는 consumer-b-subnet (10.2.0.0/24) 에서 할당
   - Consumer VM 은 이 IP 로 직접 curl/ping 가능

3. **방화벽 규칙**
   - Consumer VPC 의 방화벽에서 Producer 서브넷 (10.0.0.0/24) 을 source_ranges 로 허용
   - Producer VM 은 egress 허용 (destination: consumer CIDRs)

4. **실제 사용 사례**
   - Google Cloud SQL, Memorystore, Vertex AI 등 Google Managed Service 가 이 방식으로 고객 VPC 에 NIC 를 삽입
   - ISV 가 관리형 서비스를 고객 VPC 에 직접 연결할 때 사용

## 리소스 삭제

```bash
terraform destroy
```
