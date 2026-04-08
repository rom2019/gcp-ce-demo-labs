# LiteLLM on GCP — 빠른 구성 (Cloud Run + Secret Manager)

OpenAI 호환 API 게이트웨이를 GCP Cloud Run에 배포합니다.  
Vertex AI(Gemini), Anthropic, OpenAI 등 여러 LLM 프로바이더를 단일 엔드포인트로 통합합니다.

## 역할 분리

| 담당 | 관리 리소스 |
|------|------------|
| **Terraform** | API 활성화, Artifact Registry, Service Account, IAM, Secret Manager |
| **Cloud Build** | Docker 이미지 빌드 → Artifact Registry 푸시 → Cloud Run 생성/배포 |

> Cloud Run은 이미지가 먼저 존재해야 생성 가능하므로 Terraform이 아닌 Cloud Build가 담당합니다.

## 아키텍처

```
terraform apply
  └─▶ Artifact Registry / SA / IAM / Secrets 생성

gcloud builds submit / git push
  └─▶ Cloud Build
        ├─▶ Docker 빌드 → Artifact Registry
        └─▶ Cloud Run 생성 또는 업데이트 (LiteLLM Proxy :4000)
              ├─▶ Vertex AI / Gemini   (SA 인증, API키 불필요)
              ├─▶ Anthropic Claude      (Secret Manager)
              └─▶ OpenAI GPT            (Secret Manager)
```

## 사전 준비

| 항목 | 확인 방법 |
|------|-----------|
| gcloud CLI 설치 | `gcloud version` |
| Terraform >= 1.5 | `terraform version` |
| GCP 프로젝트 | `gcloud config get-value project` |

> Docker는 로컬에서 빌드하지 않으므로 설치 불필요합니다.

## 배포 방법

### Step 1. tfvars 설정

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 편집
```

```hcl
project_id          = "my-gcp-project"
region              = "asia-northeast3"
litellm_master_key  = "sk-my-key-1234"
anthropic_api_key   = "sk-ant-..."   # 미사용 시 "" 로 유지
openai_api_key      = "sk-..."        # 미사용 시 "" 로 유지
```

### Step 2. Terraform으로 인프라 생성 (최초 1회)

```bash
cd infra
terraform init
terraform apply
```

Terraform이 완료되면 `next_step` output으로 다음 명령을 안내해줍니다.

### Step 3. Cloud Build로 빌드 & 배포

```bash
# 프로젝트 루트에서 실행
gcloud builds submit --config cloudbuild.yaml .
```

Cloud Build가 순서대로 처리합니다:
1. `./app` 디렉토리 기준으로 Docker 이미지 빌드
2. Artifact Registry에 푸시 (`SHORT_SHA` + `latest` 태그)
3. Cloud Run 서비스 생성 또는 이미지 교체 (Secret 마운트 포함)

빌드 로그는 Cloud Console → Cloud Build → 기록에서 확인할 수 있습니다.

### Step 4. (선택) git push 자동 배포 트리거

```bash
gcloud builds triggers create github \
  --repo-name=litellm-gcp \
  --repo-owner=<YOUR_GITHUB_ID> \
  --branch-pattern="^main$" \
  --build-config=cloudbuild.yaml \
  --name=litellm-deploy-on-push
```

설정 후에는 `git push origin main` 만으로 자동 빌드 & 배포됩니다.

### Step 5. 동작 확인

```bash
export LITELLM_URL=$(gcloud run services describe litellm-proxy \
  --region=asia-northeast3 --format='value(status.url)')
export LITELLM_MASTER_KEY="sk-my-key-1234"

# 헬스 체크
curl $LITELLM_URL/health/liveliness

# 사용 가능한 모델 목록
curl $LITELLM_URL/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# 채팅 테스트 (Gemini Flash)
curl $LITELLM_URL/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gemini-1.5-flash", "messages": [{"role": "user", "content": "안녕하세요!"}]}'
```

### Step 6. Admin UI 접근

```
https://<LITELLM_URL>/ui
```
- Username: `admin`
- Password: `$LITELLM_MASTER_KEY`

## 파일 구조

```
litellm-gcp/
├── app/
│   ├── Dockerfile        # LiteLLM 이미지 빌드
│   └── config.yaml       # 모델 라우팅 설정
├── infra/
│   ├── main.tf           # API / AR / SA / IAM / Secrets
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── cloudbuild.yaml        # 빌드 + Cloud Run 배포
└── README.md
```

## 모델 추가

`app/config.yaml` 수정 후 Cloud Build 재실행:

```bash
gcloud builds submit --config cloudbuild.yaml .
```

## 팀별 가상 API 키 발급

```bash
curl -X POST $LITELLM_URL/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_id": "team-a",
    "max_budget": 50,
    "models": ["gemini-1.5-flash", "gpt-4o-mini"]
  }'
```

## 리소스 삭제

```bash
# Cloud Run 서비스 먼저 삭제
gcloud run services delete litellm-proxy --region=asia-northeast3

# 나머지 인프라 삭제
cd infra && terraform destroy
```

> ⚠️ Artifact Registry 이미지는 terraform destroy로 삭제되지 않습니다. 필요 시 콘솔에서 수동 삭제하세요.

## .gitignore 권장 항목

```
infra/terraform.tfvars
infra/.terraform/
infra/.terraform.lock.hcl
infra/*.tfstate
infra/*.tfstate.backup
```


#### 삽질기.. 이게 최선일까??
--
gcloud builds submit --config cloudbuild.yaml . \                                 
  --service-account="projects/litellm-test-492702/serviceAccounts/litellm-cloudbuild-sa@litellm-test-492702.iam.gserviceaccount.com"                                          

gcloud builds 명령어 위처럼..


DB 추가해야함.

IAP (Identity Aware Proxy) 는 메뉴얼로 했음.