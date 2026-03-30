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
│  │ a<hash> (자동 생성)  │   │ purpose=PRIVATE_SERVICE  │   │
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
│ Consumer VPC (consumer-vpc)                                 │
│             │                                               │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │ PSC Endpoint         │                                   │
│  │ (Forwarding Rule)    │                                   │
│  │ 192.168.0.x          │                                   │
│  └──────────┬───────────┘                                   │
│             │                                               │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │ Test VM              │                                   │
│  │ consumer-test-vm     │                                   │
│  │ (IAP SSH)            │                                   │
│  └──────────────────────┘                                   │
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
| `providers.tf` | Provider 설정, API 활성화, Org Policy (Shielded VM 비활성화) | - |
| `01-producer-vpc.tf` | Producer VPC, GKE 서브넷, PSC NAT 서브넷, Cloud NAT | VPC network > VPC networks |
| `02-producer-gke.tf` | GKE Autopilot 클러스터 | Kubernetes Engine > Clusters |
| `03-producer-k8s-app.tf` | K8s Deployment, K8s Service → GKE가 L4 ILB 자동 생성 | Load balancing / K8s Services |
| `04-producer-service-attachment.tf` | Service Attachment (Phase 2) | Private Service Connect > Published services |
| `05-consumer-vpc.tf` | Consumer VPC, 서브넷 | VPC network > VPC networks |
| `06-consumer-psc-endpoint.tf` | PSC Endpoint Forwarding Rule, 고정 IP (Phase 2) | Private Service Connect > Connected endpoints |
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
  target_service        = "...forwardingRules/<ilb_name>"
  nat_subnets           = [google_compute_subnetwork.producer_psc_nat.id]
  connection_preference = "ACCEPT_AUTOMATIC"
  enable_proxy_protocol = false
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
  target                = google_compute_service_attachment.producer_api[0].id  # ← SA URI 지정
  load_balancing_scheme = ""  # ← 빈 문자열 (일반 LB와의 차이점)
}
```

### 4. GKE L4 ILB forwarding rule 이름은 예측 불가

GKE는 `type: LoadBalancer` + `cloud.google.com/load-balancer-type: Internal` Service를 감지하면
자동으로 L4 ILB forwarding rule을 `a<hash>` 형태로 생성합니다.

`networking.gke.io/load-balancer-name` annotation은 이 이름을 제어하지 않습니다.

따라서 이 예제는 **두 단계 apply** 방식을 사용합니다.
- Phase 1: GKE + K8s 앱 배포 → ILB 자동 생성
- Phase 2: ILB 이름 확인 후 `ilb_forwarding_rule_name` 변수 설정 → Service Attachment + PSC Endpoint 생성

### 5. GKE L4 ILB 백엔드는 NEG 사용 불가

GKE L4 ILB의 백엔드로는 `GCE_VM_IP_PORT` 타입 NEG(컨테이너 네이티브)를 사용할 수 없습니다.
해당 NEG 타입은 L7(HTTP/HTTPS) LB 전용입니다.

| NEG 타입 | 사용 가능한 LB |
|----------|--------------|
| `GCE_VM_IP_PORT` (컨테이너 네이티브) | L7 ILB (HTTP/HTTPS) 전용 |
| `GCE_VM_IP` | L4 ILB (TCP/UDP) |

GKE가 K8s LoadBalancer Service로 L4 ILB를 생성할 때는 내부적으로 Instance Group을 백엔드로 사용합니다.

---

## 사용 방법

### 1. 준비

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 에 project_id, region 입력
```

### 2. Phase 1 — GKE + K8s 앱 + ILB 배포

```bash
terraform init
terraform apply
```

> GKE Autopilot 프로비저닝: 약 10~15분 소요
> Service Attachment와 PSC Endpoint는 이 단계에서 생성되지 않음 (`count = 0`)

### 3. kubectl 설정 및 확인

```bash
# credentials 설정
$(terraform output -raw gke_get_credentials_cmd)

# Pod / Service 확인
kubectl get pods
kubectl get svc rest-api
```

### 4. ILB forwarding rule 이름 확인

```bash
$(terraform output -raw ilb_lookup_cmd)
```

출력 예시:
```
NAME                    IP_ADDRESS    BACKEND_SERVICE
a1b2c3d4e5f6a7b8c9d0   10.10.0.5     ...
```

### 5. Phase 2 — Service Attachment + PSC Endpoint 배포

`terraform.tfvars`에 ILB 이름 추가:
```hcl
ilb_forwarding_rule_name = "a1b2c3d4e5f6a7b8c9d0"  # 4번에서 확인한 이름
```

```bash
terraform apply
```

### 6. PSC 연결 테스트

```bash
# Test VM SSH (IAP)
$(terraform output -raw test_vm_ssh_cmd)

# VM 내에서 PSC Endpoint IP로 curl
curl http://<psc_endpoint_ip>
```

### 7. 리소스 삭제

```bash
terraform destroy
```

---

## GCP Console 확인 포인트

배포 후 아래 순서로 Console을 확인하면 PSC 구성 요소를 직관적으로 이해할 수 있습니다.

1. **VPC network > VPC networks**
   - `producer-vpc` 서브넷 목록에서 `producer-psc-nat-subnet`의 Purpose가 `PRIVATE_SERVICE_CONNECT`인지 확인

2. **Network services > Load balancing**
   - `a<hash>` 이름의 Internal TCP 로드밸런서 확인 (GKE가 자동 생성)
   - 백엔드(GKE Node Instance Group)가 Healthy 상태인지 확인

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
| `ilb_forwarding_rule_name` | GKE가 생성한 ILB forwarding rule 이름 (Phase 2 필수) | `""` |

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
