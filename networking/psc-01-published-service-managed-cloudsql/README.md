# PSC-01 : Published Service — GCP Managed (Cloud SQL)

## 개요

Cloud SQL을 PSC(Private Service Connect)로 연결하는 패턴입니다.
**Google이 Service Attachment를 자동으로 생성**하는 Managed 서비스 패턴으로,
PSC의 Consumer 측 구성(Endpoint, DNS)을 익히는 데 최적화된 출발점입니다.

## PSC 패턴 분류

```
Published Service — GCP Managed
  └── Producer : Google 자동 관리 (Cloud SQL)
  └── Consumer : 직접 구성 (PSC Endpoint + Private DNS)
```

## 아키텍처

```
[Producer Project]                    [Consumer Project]
  Google Managed VPC                    Consumer VPC (10.10.0.0/24)
  ┌─────────────────────┐              ┌──────────────────────────────┐
  │  Cloud SQL Instance  │              │  PSC Endpoint                │
  │  (PSC 모드)          │◄─ PSC 터널 ─►│  (Forwarding Rule)           │
  │                      │              │  10.10.0.x                   │
  │  Service Attachment  │              │                              │
  │  (Google 자동 생성)  │              │  Private DNS Zone            │
  └─────────────────────┘              │  *.sql.goog → 10.10.0.x     │
                                       │                              │
                                       │  Test VM  (e2-micro)         │
                                       │  IAP SSH → psql 테스트       │
                                       └──────────────────────────────┘
```

## 학습 포인트

| 구성 요소 | 핵심 포인트 |
|---|---|
| `psc_enabled = true` | Google이 Service Attachment 자동 생성 |
| `ipv4_enabled = false` | Public IP 완전 차단, PSC 경로만 허용 |
| `allowed_consumer_projects` | Consumer 프로젝트 번호 등록 → 자동 수락 |
| `load_balancing_scheme = ""` | PSC Endpoint임을 나타내는 핵심 설정 |
| Private DNS Zone | `sql.goog.` zone으로 hostname 접근 |
| IAP SSH | 외부 IP 없이 테스트 VM 접근 |

## psc-02 와의 차이점

| | psc-01 (Managed) | psc-02 (User) |
|---|---|---|
| Service Attachment | Google 자동 생성 | 직접 생성 |
| PSC NAT Subnet | 불필요 | 직접 생성 필요 |
| 연결 수락 | 자동 (`allowed_consumer_projects`) | 수동 (`ACCEPT_MANUAL`) |
| Producer 구성 난이도 | 낮음 | 높음 |

## 파일 구성

```
psc-01-published-service-managed-cloudsql/
├── 01_producer.tf               # Cloud SQL 인스턴스 (PSC 모드)
├── 02_consumer.tf               # VPC, PSC Endpoint (Forwarding Rule)
├── 03_dns.tf                    # Private DNS Zone + A Record
├── 04_test.tf                   # 테스트 VM + Firewall + IAP
├── provider.tf                   # provider 설정 + API 활성화
├── variables.tf              # 변수 선언
├── terraform.tfvars.example  # 값 입력 템플릿
└── README.md
```

## 실습 순서

### 1. 배포

```bash
# tfvars 작성
cp terraform.tfvars.example terraform.tfvars
# 아래 값 입력:
#   producer_project_id, consumer_project_id
#   consumer_project_number
#   iap_member = "user:your-email@gmail.com"

# consumer_project_number 확인
gcloud projects describe <consumer_project_id> --format='value(projectNumber)'

# 배포 (API 활성화 포함, Cloud SQL 생성에 약 10분 소요)
terraform init
terraform plan
terraform apply
```

### 2. 테스트 VM 접속

```bash
# terraform output 으로 SSH 명령어 확인
terraform output test_vm_ssh_command

# IAP 터널로 SSH 접속 (외부 IP 불필요)
gcloud compute ssh psc-01-test-vm \
  --project=<consumer_project_id> \
  --zone=us-central1-a \
  --tunnel-through-iap
```

### 4. PSC 연결 검증

```bash
# VM 내부에서 실행

# 1) DNS 해석 확인 (PSC Endpoint IP 가 반환되어야 함)
dig <sql_dns_name>
# 기대값: terraform output sql_dns_name 의 IP

# 2) 포트 연결 확인
nc -zv <sql_dns_name> 5432
# 기대값: Connection succeeded

# 3) psql 접속
psql "host=<sql_dns_name> port=5432 sslmode=require dbname=postgres user=postgres"
# 비밀번호 입력 후 postgres=# 프롬프트 확인
```

## PSC 연결 상태 확인

```bash
# pscConnectionStatus = ACCEPTED 확인
gcloud compute forwarding-rules describe psc-01-endpoint \
  --region=asia-northeast3 \
  --project=<consumer_project_id> \
  --format='value(pscConnectionStatus)'
```

## 주요 Output

| Output | 설명 |
|---|---|
| `service_attachment_uri` | Google이 자동 생성한 Service Attachment URI |
| `sql_dns_name` | Cloud SQL PSC 전용 DNS 이름 |
| `psc_endpoint_ip` | Consumer VPC 내 PSC Endpoint IP |
| `test_vm_ssh_command` | IAP SSH 접속 명령어 |
| `sql_connection_command` | psql 접속 명령어 |

## 리소스 정리

```bash
terraform destroy
```
