# PSC-02: Published Service — GKE + L4 ILB

GCP Private Service Connect (PSC) 학습 예제입니다.
Producer는 GKE 기반 REST API 서버를 L4 ILB로 노출하고, Consumer는 PSC Endpoint로 접근합니다.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Producer VPC (producer-vpc)                                 │
│                                                             │
│  ┌──────────────────────┐                                   │
│  │ GKE Autopilot        │                                   │
│  │  Pod (nginxdemos)    │                                   │
│  │  Pod (nginxdemos)    │                                   │
│  └──────────┬───────────┘                                   │
│             │ K8s Service (LoadBalancer/Internal)           │
│             ▼                                               │
│  ┌──────────────────────┐   ┌──────────────────────────┐   │
│  │ L4 ILB               │   │ PSC NAT Subnet           │   │
│  │ (Forwarding Rule)    │   │ 10.100.0.0/28            │   │
│  │ producer-api-ilb     │   │ purpose=PRIVATE_SERVICE  │   │
│  └──────────┬───────────┘   │        _CONNECT          │   │
│             │               └──────────────────────────┘   │
│             ▼                          │                    │
│  ┌──────────────────────┐             │ SNAT               │
│  │ Service Attachment   │◄────────────┘                    │
│  │ producer-api-sa      │                                   │
│  └──────────┬───────────┘                                   │
└─────────────│───────────────────────────────────────────────┘
              │ PSC (Private Service Connect)
┌─────────────│───────────────────────────────────────────────┐
│ Consumer VPC (consumer-vpc)          │                      │
│             │                        │                      │
│             ▼                        │                      │
│  ┌──────────────────────┐            │                      │
│  │ PSC Endpoint         │            │                      │
│  │ (Forwarding Rule)    │            │                      │
│  │ 192.168.0.x          │            │                      │
│  └──────────┬───────────┘            │                      │
│             │                        │                      │
│             ▼                        │                      │
│  ┌──────────────────────┐            │                      │
│  │ Test VM              │            │                      │
│  │ consumer-test-vm     │            │                      │
│  │ (IAP SSH)            │            │                      │
│  └──────────────────────┘            │                      │
└─────────────────────────────────────────────────────────────┘
```

### 트래픽 흐름

```
Test VM → PSC Endpoint IP → [PSC 터널] → Service Attachment → L4 ILB → GKE Pod
```

---

## 파일 구조

| 파일 | 리소스 | GCP Console 확인 위치 |
|------|--------|-----------------------|
| `01-producer-vpc.tf` | Producer VPC, GKE 서브넷, PSC NAT 서브넷, Cloud NAT | VPC network > VPC networks |
| `02-producer-gke.tf` | GKE Autopilot 클러스터 | Kubernetes Engine > Clusters |
| `03-producer-k8s-app.tf` | K8s Deployment, K8s Service (L4 ILB 자동 생성) | Load balancing / K8s Services |
| `04-producer-service-attachment.tf` | Service Attachment (PSC 노출) | Private Service Connect > Published services |
| `05-consumer-vpc.tf` | Consumer VPC, 서브넷 | VPC network > VPC networks |
| `06-consumer-psc-endpoint.tf` | PSC Endpoint (Forwarding Rule), 고정 IP | Private Service Connect > Connected endpoints |
| `07-consumer-test-vm.tf` | Test VM, IAP SSH 방화벽 | Compute Engine > VM instances |

---

## 핵심 개념

### 1. PSC NAT 서브넷 (`purpose = "PRIVATE_SERVICE_CONNECT"`)

일반 서브넷과 달리 PSC 전용으로 예약된 서브넷입니다.
Consumer 트래픽이 Service Attachment를 통과할 때 이 서브넷 IP 대역으로 SNAT됩니다.

```hcl
resource "google_compute_subnetwork" "producer_psc_nat" {
  purpose = "PRIVATE_SERVICE_CONNECT"  # 이 설정이 핵심
}
```

### 2. Service Attachment

ILB(Forwarding Rule)를 PSC로 "publish"하는 리소스입니다.
Consumer가 PSC Endpoint를 만들 때 이 attachment URI를 target으로 지정합니다.

```hcl
resource "google_compute_service_attachment" "producer_api" {
  target_service        = "...forwardingRules/producer-api-ilb"
  nat_subnets           = [google_compute_subnetwork.producer_psc_nat.id]
  connection_preference = "ACCEPT_AUTOMATIC"  # 자동 승인 (학습용)
}
```

`connection_preference` 옵션:
| 값 | 설명 |
|----|------|
| `ACCEPT_AUTOMATIC` | 모든 Consumer 자동 승인 (학습/테스트용) |
| `ACCEPT_MANUAL` | `consumer_accept_lists`로 프로젝트 단위 접근 제어 (프로덕션 권장) |

### 3. PSC Endpoint = Forwarding Rule (단, `load_balancing_scheme = ""`)

PSC Endpoint는 일반 Forwarding Rule과 **같은 Terraform 리소스**이지만 두 가지가 다릅니다.

```hcl
resource "google_compute_forwarding_rule" "psc_endpoint" {
  target                = google_compute_service_attachment.producer_api.id  # ← SA URI 지정
  load_balancing_scheme = ""  # ← 빈 문자열 (일반 LB와의 차이점)
}
```

### 4. GKE ILB 이름 고정 (`networking.gke.io/load-balancer-name`)

GKE는 `type: LoadBalancer` Service를 감지하면 자동으로 Forwarding Rule을 생성합니다.
이때 이름이 `a<hash>` 형태로 자동 생성되는데, 아래 annotation으로 이름을 고정할 수 있습니다 (GKE 1.24+).

```yaml
annotations:
  cloud.google.com/load-balancer-type: "Internal"
  networking.gke.io/load-balancer-name: "producer-api-ilb"  # 이름 고정 → Terraform에서 참조 가능
```

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
terraform plan
terraform apply
```

> GKE Autopilot 프로비저닝: 약 10~15분 소요

### 3. kubectl 설정

```bash
# outputs 에서 명령어 확인
terraform output gke_get_credentials_cmd

# 실행
gcloud container clusters get-credentials producer-gke \
  --region asia-northeast3 \
  --project <project_id>

# Pod/Service 확인
kubectl get pods
kubectl get svc rest-api-ilb
```

### 4. PSC 연결 테스트

```bash
# Test VM SSH (IAP)
gcloud compute ssh consumer-test-vm \
  --tunnel-through-iap \
  --project=<project_id> \
  --zone=asia-northeast3-a

# VM 내에서 PSC Endpoint IP로 curl
curl http://$(terraform output -raw psc_endpoint_ip)
```

### 5. 리소스 삭제

```bash
terraform destroy
```

---

## GCP Console 확인 포인트

배포 후 아래 순서로 Console을 확인하면 PSC 구성 요소를 직관적으로 이해할 수 있습니다.

1. **VPC network > VPC networks**
   - `producer-vpc` 서브넷 목록에서 `producer-psc-nat-subnet`의 Purpose가 `PRIVATE_SERVICE_CONNECT`인지 확인

2. **Network services > Load balancing**
   - `producer-api-ilb` Internal TCP 로드밸런서 확인
   - 백엔드(GKE Pod)가 Healthy 상태인지 확인

3. **Private Service Connect > Published services**
   - `producer-api-service-attachment` 확인
   - Status가 `Active`인지 확인
   - Connected endpoints 탭에서 Consumer 연결 확인

4. **Private Service Connect > Connected endpoints**
   - `psc-endpoint` 확인
   - Status가 `Accepted`인지 확인

---

## 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `project_id` | GCP 프로젝트 ID | (필수) |
| `region` | GCP 리전 | `asia-northeast3` |

---

## IP 대역 정리

| 용도 | 대역 |
|------|------|
| Producer GKE 노드 서브넷 | `10.10.0.0/24` |
| GKE Pod (secondary) | `10.20.0.0/16` |
| GKE Service/ClusterIP (secondary) | `10.30.0.0/16` |
| PSC NAT 서브넷 | `10.100.0.0/28` |
| Consumer 서브넷 | `192.168.0.0/24` |
| GKE Control Plane | `172.16.0.0/28` |
