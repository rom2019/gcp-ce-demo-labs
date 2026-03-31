# lb-01: Application Load Balancer — 쇼핑몰 웹 앱 배포

> **소요 시간:** 약 60분  
> **난이도:** ⭐⭐ (기초~중급)

## 개요

Google Cloud **Global External Application Load Balancer (EXTERNAL_MANAGED)**를 사용하여 쇼핑몰 웹 애플리케이션을 고가용성으로 배포합니다.

**Regional Managed Instance Group(MIG)**에 nginx 기반 쇼핑몰 앱을 올리고, Application LB가 트래픽을 자동으로 분산하는 과정을 실습합니다.

---

## 아키텍처

```
인터넷
  │
  ▼
┌─────────────────────────────────────────────┐
│  Global Forwarding Rule  (VIP :80)          │
│  shop-lb-rule                               │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  Target HTTP Proxy                          │
│  shop-http-proxy                            │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  URL Map (경로 기반 라우팅)                   │
│  shop-url-map                               │
│  default → shop-backend-service             │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  Backend Service                            │
│  shop-backend-service                       │
│  protocol: HTTP  port_name: http            │
│  health_check: /health (10초 간격)           │
└──────────────┬──────────────────────────────┘
               │
      ┌────────┴────────┐
      ▼                 ▼
┌──────────┐      ┌──────────┐    ← Regional MIG (us-central1)
│shop-0001 │      │shop-0002 │    ← 존(a/b/c/f)에 자동 분산
│ nginx:80 │      │ nginx:80 │
│ (zone-a) │      │ (zone-b) │
└──────────┘      └──────────┘
      │
      │ Cloud NAT
      ▼
  인터넷 (패키지 설치용)
```

---

## 트래픽 흐름

```
사용자 브라우저
  → (TCP:80) Global Forwarding Rule (VIP)
  → Target HTTP Proxy
  → URL Map (/* → shop-backend-service)
  → Backend Service (헬스체크 통과한 인스턴스로만 전달)
  → MIG 인스턴스 중 하나 (Round-robin / CPU utilization 기반)
  → nginx → /var/www/html/index.html 응답
```

---

## 핵심 개념

| 구성 요소 | 역할 | 주요 설정 |
|-----------|------|-----------|
| **Global Forwarding Rule** | 인터넷의 진입점 (VIP) | port 80, EXTERNAL_MANAGED |
| **Target HTTP Proxy** | HTTP 프로토콜 처리 | URL Map 참조 |
| **URL Map** | 경로 기반 라우팅 | `/*` → 쇼핑몰 백엔드 |
| **Backend Service** | 백엔드 그룹 관리 | UTILIZATION 모드, 타임아웃 30초 |
| **Health Check** | 인스턴스 상태 확인 | `GET /health` 10초 간격, 3회 실패 시 비정상 |
| **Regional MIG** | VM 자동 관리 | 2~10개, 존 자동 분산 |
| **Auto Scaler** | 부하 기반 자동 확장 | CPU 70% 임계값 |
| **Cloud NAT** | 외부 IP 없이 인터넷 출구 | 패키지 설치, API 호출용 |
| **Cloud IAP** | 외부 IP 없이 SSH 접속 | 35.235.240.0/20 |

---

## 파일 구조

| 파일 | 설명 | GCP 콘솔 경로 |
|------|------|---------------|
| `providers.tf` | Terraform 공급자, API 활성화, 조직 정책 설정 | - |
| `variables.tf` | 변수 선언 | - |
| `outputs.tf` | 출력값 (LB IP, URL 등) | - |
| `01-vpc.tf` | VPC, 서브넷, Cloud NAT | VPC network |
| `02-firewall.tf` | 방화벽 규칙 (헬스체크, IAP) | VPC > Firewall |
| `03-instance-template.tf` | 인스턴스 템플릿 + 시작 스크립트 | Compute > Instance templates |
| `04-mig.tf` | Regional MIG + Auto Scaler | Compute > Instance groups |
| `05-load-balancer.tf` | 헬스체크, 백엔드, URL Map, 프록시, 포워딩 룰 | Network services > Load balancing |

---

## 배포 방법

### 1. 사전 조건

```bash
# gcloud 인증
gcloud auth application-default login

# 프로젝트 설정
gcloud config set project YOUR_PROJECT_ID
```

### 2. Terraform 초기화 & 배포

```bash
# 변수 파일 생성
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars  # project_id 수정

# 초기화
terraform init

# 배포 계획 확인
terraform plan

# 배포 (약 5~8분 소요)
terraform apply
```

### 3. 접속 확인

```bash
# LB IP 확인
terraform output load_balancer_ip
terraform output shop_url

# LB가 준비될 때까지 대기 (최대 5분)
# 아래 명령으로 반복 확인
LB_IP=$(terraform output -raw load_balancer_ip)
watch -n 5 "curl -s -o /dev/null -w '%{http_code}' http://$LB_IP/health"
```

> **참고:** `terraform apply` 완료 후 LB가 완전히 활성화되고 헬스체크가 통과될 때까지 약 3~5분이 소요됩니다.

---

## 실습 시나리오

### 1단계: 쇼핑몰 접속 및 로드밸런싱 확인

```bash
LB_IP=$(terraform output -raw load_balancer_ip)

# 브라우저에서 접속
echo "http://$LB_IP"

# curl로 반복 호출 → 인스턴스명이 바뀌는지 확인 (로드밸런싱 분산 확인)
for i in {1..10}; do
  curl -s "http://$LB_IP" | grep "인스턴스명"
  echo "---"
done
```

### 2단계: 헬스체크 확인

```bash
# 헬스체크 엔드포인트 직접 호출 (LB 통해서)
curl -v "http://$LB_IP/health"

# GCP 콘솔에서 확인:
# Network services > Load balancing > shop-url-map > Backends
# → 각 인스턴스 헬스 상태 확인
```

### 3단계: MIG 인스턴스 확인

```bash
# 인스턴스 목록 조회
gcloud compute instances list --filter="name:shop-" --project=YOUR_PROJECT_ID

# IAP를 통한 SSH 접속 (외부 IP 없음)
gcloud compute ssh INSTANCE_NAME \
  --tunnel-through-iap \
  --project=YOUR_PROJECT_ID \
  --zone=ZONE

# 접속 후 nginx 로그 확인
sudo tail -f /var/log/nginx/access.log
```

### 4단계: 자동 복구(Auto Healing) 테스트

```bash
# nginx 강제 중지 (인스턴스 내에서)
sudo systemctl stop nginx

# 헬스체크 실패 → 약 30초 후 LB가 해당 인스턴스로 트래픽 차단
# 약 3분 후 MIG가 인스턴스 자동 교체

# GCP 콘솔에서 확인:
# Compute Engine > Instance groups > shop-mig > Monitoring
```

### 5단계: Auto Scaling 테스트 (부하 테스트)

```bash
# 부하 테스트 도구 설치 (로컬 또는 테스트 VM)
sudo apt-get install -y apache2-utils

# 부하 발생 (1000 요청, 동시 50)
ab -n 1000 -c 50 "http://$LB_IP/"

# 또는 hey 사용
hey -n 5000 -c 100 "http://$LB_IP/"

# GCP 콘솔에서 스케일 아웃 확인:
# Compute Engine > Instance groups > shop-mig > Monitoring
```

---

## 주요 출력값

```bash
terraform output
```

| 출력 | 설명 |
|------|------|
| `load_balancer_ip` | LB 외부 IP 주소 |
| `shop_url` | 쇼핑몰 접속 URL |
| `mig_name` | MIG 이름 |
| `ssh_command` | IAP SSH 접속 명령 예시 |

---

## GCP 콘솔 확인 경로

| 항목 | 경로 |
|------|------|
| Load Balancer | Network services > Load balancing > Frontends |
| Backend 상태 | Network services > Load balancing > shop-url-map > Backends |
| 인스턴스 그룹 | Compute Engine > Instance groups > shop-mig |
| 오토스케일러 | Compute Engine > Instance groups > shop-mig > Details |
| 방화벽 규칙 | VPC network > Firewall > shop-allow-* |
| Cloud NAT | Network services > Cloud NAT > shop-nat |

---

## 트러블슈팅

### LB 타입 조직 정책 오류

`terraform apply` 시 아래 오류가 발생하는 경우:

```
Error: Constraint constraints/compute.restrictLoadBalancerCreationForTypes violated
→ GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS is not allowed
```

**원인:** GCP 조직 레벨에서 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` LB 생성을 제한하는 정책이 적용되어 있습니다.

**해결 방법 (택1):**

1. **org 관리자에게 요청 (권장)** — org 레벨 정책이 강제 적용 중이면 프로젝트 레벨 override가 불가합니다. org 관리자에게 해당 프로젝트에서 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` 허용을 요청하세요.

2. **프로젝트 레벨 override 시도** — `providers.tf`의 `google_project_organization_policy.lb_types` 리소스가 이를 시도합니다. org 정책이 강제 적용이 아닌 경우 자동으로 해결됩니다.

3. **Classic LB로 대체** — org 정책 해제가 어려운 경우, `05-load-balancer.tf`와 포워딩 룰의 `load_balancing_scheme`을 `"EXTERNAL"`로 변경하면 Classic Application LB로 동일하게 동작합니다. (기능 차이 없음, Google 권장은 EXTERNAL_MANAGED)

---

## 리소스 정리

```bash
terraform destroy
```

> **주의:** `terraform destroy`는 모든 리소스를 삭제합니다. 실습이 끝난 후 반드시 실행하세요.

---

## 학습 포인트

1. **Application LB 구성 요소** — Forwarding Rule → Proxy → URL Map → Backend Service의 계층 구조 이해
2. **헬스체크의 역할** — 비정상 인스턴스로의 트래픽 자동 차단 + MIG 자동 복구
3. **Regional MIG** — 단일 존 장애에도 서비스 지속 (멀티 존 분산)
4. **EXTERNAL_MANAGED 모드** — Google 권장 최신 Global Application LB 방식 (`load_balancing_scheme`)
5. **보안 설계** — 인스턴스에 외부 IP 없음 (Cloud NAT + IAP만 허용)
6. **Auto Scaling** — CPU 기반 자동 확장/축소로 비용 최적화
