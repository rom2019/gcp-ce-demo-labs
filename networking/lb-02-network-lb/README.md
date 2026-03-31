# lb-02: Network Load Balancer — 게임 서버 / 실시간 스트리밍

> **소요 시간:** 약 60분
> **난이도:** ⭐⭐ (기초~중급)

## 개요

Google Cloud **Regional External Passthrough Network Load Balancer (NLB)** 를 사용하여 게임 서버 / 실시간 스트리밍 인프라를 배포합니다.

L4 패스스루(Passthrough) 방식으로 클라이언트 IP를 보존하고, `session_affinity = "CLIENT_IP"` 로 게임 세션을 특정 서버에 고정하는 과정을 실습합니다.

---

## 아키텍처

```
인터넷 (게임 클라이언트)
  │
  ▼ TCP:80 (데모) / TCP:7777 (실제 게임포트 예시)
┌──────────────────────────────────────────────────┐
│  Regional Forwarding Rule  (VIP)                 │
│  game-lb-rule  ← google_compute_forwarding_rule  │
│  [리전 단위 — Global 아님!]                        │
└───────────────────┬──────────────────────────────┘
                    │ Passthrough (프록시 없음)
                    ▼
┌──────────────────────────────────────────────────┐
│  Region Backend Service                          │
│  game-backend-service                            │
│  protocol: TCP                                   │
│  session_affinity: CLIENT_IP  ← 핵심 설정        │
│  balancing_mode: CONNECTION                       │
└───────────────────┬──────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         ▼                     ▼
   ┌──────────┐         ┌──────────┐    ← Regional MIG (us-central1)
   │ game-001 │         │ game-002 │    ← 존(a/b/c/f)에 자동 분산
   │ nginx:80 │         │ nginx:80 │
   │ (zone-a) │         │ (zone-b) │
   └──────────┘         └──────────┘
         │
         │ Cloud NAT
         ▼
     인터넷 (패키지 설치용)
```

---

## 트래픽 흐름

```
게임 클라이언트
  → (TCP:80) Regional Forwarding Rule (VIP)
  → Region Backend Service
    [session_affinity=CLIENT_IP → 동일 IP는 항상 같은 서버로]
  → MIG 인스턴스 (직접 전달, 프록시 없음)
  → nginx → 게임 서버 상태 페이지 응답
```

---

## NLB vs Application LB 핵심 차이

| 항목 | **Network LB** (이 실습) | **Application LB** (lb-01) |
|------|--------------------------|----------------------------|
| OSI 레이어 | **L4 (TCP/UDP)** | L7 (HTTP/HTTPS) |
| 프록시 여부 | **Passthrough** (직접 전달) | Proxy (LB가 HTTP 중개) |
| 클라이언트 IP | **보존** (실제 IP 그대로) | X-Forwarded-For 헤더 |
| 지연시간 | **매우 낮음** | 낮음 |
| 범위 | **리전 (Regional)** | 글로벌 (Global) |
| Forwarding Rule | `google_compute_forwarding_rule` | `google_compute_global_forwarding_rule` |
| Backend | `google_compute_region_backend_service` | `google_compute_backend_service` |
| Health Check | `google_compute_region_health_check` | `google_compute_health_check` |
| 세션 어피니티 | CLIENT_IP | Cookie / CLIENT_IP |
| 프로토콜 | **TCP, UDP, ESP, GRE** | HTTP, HTTPS |
| 사용 사례 | **게임, 스트리밍, VoIP** | 웹앱, REST API |

---

## 자주 하는 실수

### ❌ 실수 1: Regional NLB에 Global Forwarding Rule 사용

```hcl
# 잘못된 예 — 컴파일 오류 또는 잘못된 LB 생성
resource "google_compute_global_forwarding_rule" "game" { ... }

# 올바른 예 — NLB는 반드시 리전 Forwarding Rule
resource "google_compute_forwarding_rule" "game" {
  region = var.region
  ...
}
```

NLB는 **리전 단위** 리소스입니다. Global Forwarding Rule은 Global Application LB / Global Proxy NLB 전용입니다.

### ❌ 실수 2: session_affinity 미설정 → 게임 세션 끊김

```hcl
# 잘못된 예 — 기본값(NONE): 매 연결마다 다른 서버로 분산
resource "google_compute_region_backend_service" "game" {
  protocol = "TCP"
  # session_affinity 없음
}

# 올바른 예 — 게임/스트리밍에서는 CLIENT_IP 필수
resource "google_compute_region_backend_service" "game" {
  protocol         = "TCP"
  session_affinity = "CLIENT_IP"
}
```

게임에서 `session_affinity` 미설정 시: 플레이어의 연결이 다른 서버로 분산되어 **게임 상태(인벤토리, 위치, 진행도) 유실** 발생.

---

## 핵심 개념

| 구성 요소 | 역할 | 주요 설정 |
|-----------|------|-----------|
| **Forwarding Rule** (리전) | 인터넷 진입점 (VIP) | TCP, port 80, EXTERNAL |
| **Region Backend Service** | 백엔드 그룹 + 세션 설정 | session_affinity=CLIENT_IP |
| **Region Health Check** | TCP 헬스체크 | port 80, 10초 간격 |
| **Regional MIG** | VM 자동 관리 | 2~10개, 존 분산 |
| **Cloud NAT** | 인스턴스 외부 IP 없이 인터넷 출구 | 패키지 설치용 |
| **Cloud IAP** | 외부 IP 없이 SSH | 35.235.240.0/20 |

---

## 파일 구조

| 파일 | 설명 | GCP 콘솔 경로 |
|------|------|---------------|
| `providers.tf` | Terraform 공급자, API 활성화, 조직 정책 | - |
| `variables.tf` | 변수 선언 | - |
| `outputs.tf` | 출력값 (NLB IP, URL 등) | - |
| `01-vpc.tf` | VPC, 서브넷, Cloud NAT | VPC network |
| `02-firewall.tf` | 방화벽 (헬스체크, 게임 트래픽, IAP) | VPC > Firewall |
| `03-instance-template.tf` | 인스턴스 템플릿 + 게임 서버 스크립트 | Compute > Instance templates |
| `04-mig.tf` | Regional MIG + Auto Scaler | Compute > Instance groups |
| `05-load-balancer.tf` | TCP 헬스체크, 백엔드 서비스, 포워딩 룰 | Network services > Load balancing |

---

## 배포 방법

### 1. 사전 조건

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Terraform 초기화 & 배포

```bash
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars  # project_id 수정

terraform init
terraform plan
terraform apply  # 약 5~8분 소요
```

### 3. 접속 확인

```bash
LB_IP=$(terraform output -raw load_balancer_ip)

# LB 준비 대기 (최대 3~5분)
watch -n 5 "curl -s -o /dev/null -w '%{http_code}' http://$LB_IP/health"

# 브라우저 접속
echo "http://$LB_IP"
```

---

## 실습 시나리오

### 1단계: 게임 서버 접속 및 NLB 확인

```bash
LB_IP=$(terraform output -raw load_balancer_ip)

# 브라우저에서 접속 → 게임 서버 상태 페이지 확인
echo "http://$LB_IP"
```

페이지에서 확인:
- 연결된 **서버 인스턴스명**과 **존(Zone)**
- 실시간 Players Online / Uptime / Ping 메트릭
- NLB vs Application LB 비교표

### 2단계: Session Affinity 확인

```bash
# 동일 IP에서 반복 호출 → 항상 같은 인스턴스명 응답 확인
for i in {1..10}; do
  curl -s "http://$LB_IP" | grep "game-"
  sleep 1
done
```

> F5 새로고침을 반복해도 동일 서버명이 표시되면 `CLIENT_IP` 세션 어피니티가 정상 동작하는 것입니다.

### 3단계: MIG 인스턴스 확인

```bash
# 인스턴스 목록
gcloud compute instances list --filter="name:game-" --project=YOUR_PROJECT_ID

# IAP SSH 접속
gcloud compute ssh INSTANCE_NAME \
  --tunnel-through-iap \
  --project=YOUR_PROJECT_ID \
  --zone=ZONE

# nginx 로그 (클라이언트 실제 IP 확인 — Passthrough 이므로 실제 IP 노출)
sudo tail -f /var/log/nginx/access.log
```

### 4단계: Passthrough 동작 확인 (클라이언트 IP 보존)

```bash
# nginx 액세스 로그에서 실제 클라이언트 IP 확인
# Application LB였다면 GCP LB IP(130.211.x.x)가 찍히지만
# Passthrough NLB는 실제 클라이언트 IP가 그대로 기록됨
sudo grep -v "130.211\|35.191" /var/log/nginx/access.log | head -20
```

### 5단계: Auto Healing 테스트

```bash
# 인스턴스 내에서 nginx 중지
sudo systemctl stop nginx

# TCP 헬스체크 실패 → LB가 해당 인스턴스 제외 → MIG가 자동 교체
# GCP 콘솔: Compute Engine > Instance groups > game-mig > Monitoring
```

---

## 주요 출력값

| 출력 | 설명 |
|------|------|
| `load_balancer_ip` | NLB 외부 IP (VIP) |
| `game_server_url` | 게임 서버 상태 페이지 URL |
| `mig_name` | MIG 이름 |
| `ssh_command` | IAP SSH 접속 명령 예시 |

---

## GCP 콘솔 확인 경로

| 항목 | 경로 |
|------|------|
| Load Balancer | Network services > Load balancing |
| Forwarding Rule | Network services > Load balancing > Frontends |
| Backend Service | Network services > Load balancing > Backends |
| 인스턴스 그룹 | Compute Engine > Instance groups > game-mig |
| 방화벽 규칙 | VPC network > Firewall > game-allow-* |
| Cloud NAT | Network services > Cloud NAT > game-nat |

---

## 리소스 정리

```bash
terraform destroy
```

---

## 학습 포인트

1. **L4 Passthrough NLB** — 프록시 없이 직접 전달, 클라이언트 IP 보존
2. **리전 vs 글로벌** — NLB는 `google_compute_forwarding_rule` (리전), Application LB는 `google_compute_global_forwarding_rule` (글로벌)
3. **session_affinity = CLIENT_IP** — 게임/스트리밍에서 세션 유지를 위한 필수 설정
4. **TCP 헬스체크** — NLB에는 L4 TCP 헬스체크가 적합 (`google_compute_region_health_check`)
5. **balancing_mode = CONNECTION** — NLB에서 연결 수 기반 분산
6. **보안 설계** — 인스턴스 외부 IP 없음 (Cloud NAT + IAP)
