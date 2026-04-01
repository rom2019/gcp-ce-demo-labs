# Lab 01 — GKE Basics: Standard vs Autopilot 직접 비교

## 시나리오

팀에서 GKE를 도입하려는데 Standard와 Autopilot 중 무엇을 선택해야 할지 고민 중입니다.
이 실습에서는 두 클러스터를 **동일한 앱으로 직접 배포하고 비교**하며, 각 모드의 차이를 몸으로 체득합니다.

## 학습 목표

- Standard와 Autopilot 클러스터의 구조적 차이 이해
- `kubectl get nodes`로 노드 가시성 차이 직접 확인
- 동일한 앱을 두 클러스터에 배포하며 동작 방식 비교
- 언제 어떤 클러스터 타입을 선택해야 하는지 판단 기준 습득

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│  gke-basics-vpc                                                 │
│                                                                 │
│  ┌──────────────────────────┐  ┌──────────────────────────┐    │
│  │  Standard Cluster        │  │  Autopilot Cluster       │    │
│  │  gke-standard-subnet     │  │  gke-autopilot-subnet    │    │
│  │  10.0.0.0/24             │  │  10.1.0.0/24             │    │
│  │                          │  │                          │    │
│  │  Node Pool (직접 관리)    │  │  Nodes (GCP 자동 관리)   │    │
│  │  e2-medium × 6 nodes     │  │  Pod 배포 시 자동 프로비전│    │
│  │  kubectl get nodes → 6개 │  │  kubectl get nodes → ?개 │    │
│  └──────────────────────────┘  └──────────────────────────┘    │
│                                                                 │
│  Cloud NAT (두 서브넷 모두 커버)                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Standard vs Autopilot 핵심 차이

| 항목 | Standard | Autopilot |
|------|----------|-----------|
| **노드 관리** | 직접 관리 (node pool 설정) | GCP 완전 자동 관리 |
| **노드 가시성** | `kubectl get nodes` → 노드 목록 보임 | 노드 목록 보이지만 SSH 불가 |
| **노드 개수** | 직접 지정 (node_count) | Pod 수요에 따라 자동 증감 |
| **비용 모델** | VM 비용 (노드가 있으면 과금) | Pod 리소스 사용량 기준 과금 |
| **resource requests** | 선택사항 | **필수** (미설정 시 기본값 자동 적용) |
| **privileged container** | 허용 | 기본 차단 (보안 강화) |
| **Terraform 코드** | node pool 리소스 필요 | `enable_autopilot = true` 한 줄 |
| **적합한 케이스** | 노드 커스터마이징 필요, 비용 최적화 | 운영 부담 최소화, 빠른 시작 |

## 실습 시작

### Step 0: 사전 조건

```bash
gcloud version
kubectl version --client
terraform version
gcloud config set project YOUR_PROJECT_ID
```

### Step 1: 인프라 배포 (Standard + Autopilot 동시)

```bash
cd gke/gke-01-basics

terraform init
terraform apply -var="project_id=YOUR_PROJECT_ID"
# Standard 클러스터 ~12분, Autopilot 클러스터 ~10분 (병렬 생성)
```

배포 완료 후 두 클러스터의 접속 명령어 확인:

```bash
terraform output standard_get_credentials
terraform output autopilot_get_credentials
```

---

### Step 2: [비교 1] 노드 가시성

**Standard 클러스터에 연결:**

```bash
gcloud container clusters get-credentials gke-basics-cluster \
  --region=us-central1 --project=YOUR_PROJECT_ID

kubectl get nodes
# 결과: 6개 노드 (e2-medium, 2/zone × 3 zones)
# NAME                                         STATUS   ROLES    AGE
# gke-gke-basics-cluster-primary-pool-xxx-xxx  Ready    <none>   5m
# ...
```

**Autopilot 클러스터에 연결:**

```bash
gcloud container clusters get-credentials gke-autopilot-cluster \
  --region=us-central1 --project=YOUR_PROJECT_ID

kubectl get nodes
# 결과: Pod 배포 전에는 노드가 없거나 system 노드만 보임
# Autopilot은 워크로드 없이는 사용자 노드를 프로비전하지 않습니다.
```

> **핵심 관찰:** Standard는 항상 6개 노드가 존재(비용 발생). Autopilot은 필요할 때만 노드 생성.

---

### Step 3: [비교 2] 앱 배포 및 노드 변화 관찰

**Standard에 앱 배포:**

```bash
gcloud container clusters get-credentials gke-basics-cluster \
  --region=us-central1 --project=YOUR_PROJECT_ID

kubectl apply -f k8s/
kubectl get pods -o wide   # 어느 노드에 배포됐는지 확인
kubectl get nodes          # 노드 수 변화 없음 (이미 존재)
```

**Autopilot에 앱 배포 (노드 생성 과정 관찰):**

```bash
gcloud container clusters get-credentials gke-autopilot-cluster \
  --region=us-central1 --project=YOUR_PROJECT_ID

kubectl get nodes          # 배포 전 노드 확인
kubectl apply -f k8s/

# Pod가 Pending → ContainerCreating → Running 되는 동안 노드 변화 관찰
kubectl get pods -w &
kubectl get nodes -w
# Autopilot이 Pod 수요에 맞춰 노드를 자동 프로비전하는 것을 확인!
```

> **핵심 관찰:** Autopilot은 Pod를 배포하는 순간 필요한 노드를 자동 생성합니다.

---

### Step 4: [비교 3] resource requests 동작 차이

**resource requests 없는 Deployment 시도:**

```bash
# requests/limits 없는 임시 Deployment 생성
kubectl create deployment no-resources \
  --image=us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0

kubectl get pods
# Standard: 정상 실행됨
# Autopilot: 실행은 되지만 GCP가 기본값(0.5 CPU, 2Gi memory)을 자동 적용
```

Autopilot에서 실제 적용된 requests 확인:

```bash
kubectl get pod <POD_NAME> -o jsonpath='{.spec.containers[0].resources}' | jq .
# requests가 자동으로 설정된 것을 확인
```

정리:
```bash
kubectl delete deployment no-resources
```

> **핵심 관찰:** Autopilot은 resource requests를 반드시 명시해야 비용 예측이 가능합니다.

---

### Step 5: [비교 4] 스케일링 동작 차이

**두 클러스터에서 각각 실행:**

```bash
# replicas를 10으로 늘림
kubectl scale deployment hello-app --replicas=10
kubectl get pods -w

# Standard: 기존 6개 노드에 배치 (노드 추가 없음, 리소스 부족 시 Pending)
# Autopilot: 노드를 자동으로 추가 프로비전하여 모든 Pod를 Running 상태로 만듦
kubectl get nodes -w
```

---

### Step 6: 외부 접근 확인 (두 클러스터 동일)

```bash
# 각 클러스터에서 실행
kubectl get service hello-app-lb --watch
# EXTERNAL-IP 발급 대기

EXTERNAL_IP=$(kubectl get service hello-app-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP
# Hello, world! Version: 1.0.0 Hostname: hello-app-xxxxx
```

---

### Step 7: HPA 비교

```bash
kubectl get hpa
kubectl describe hpa hello-app-hpa

# Standard: HPA가 Pod 수 조절 → 노드는 고정
# Autopilot: HPA가 Pod 수 조절 → 노드도 자동으로 함께 조절
```

---

## 자주 하는 실수

| 실수 | 결과 | 올바른 방법 |
|------|------|-------------|
| Autopilot에 `node_pool` 리소스 정의 | `Error: autopilot clusters cannot have node pools` | `enable_autopilot = true` 시 node pool 리소스 삭제 |
| 두 클러스터의 master CIDR 동일하게 설정 | CIDR 충돌 오류 | Standard: `172.16.0.0/28`, Autopilot: `172.16.1.0/28` |
| Autopilot에 privileged container 배포 | Pod가 `Forbidden` 오류로 실행 거부 | Autopilot 보안 정책 준수 (privileged: false) |
| Autopilot Pod에 resource requests 미설정 | GCP가 기본값 적용 → 예상보다 높은 비용 | 항상 CPU/memory requests 명시 |
| Secondary range IP 대역 겹침 | IP 충돌로 클러스터 생성 실패 | 서브넷별 독립된 IP 대역 사용 |

## Standard vs Autopilot 선택 기준

**Standard를 선택해야 할 때:**
- GPU, 고메모리 노드 등 특수 머신 타입 필요
- 노드 레벨 커스터마이징 (DaemonSet, 노드 OS 설정)
- 비용 최적화를 직접 컨트롤하고 싶을 때
- Spot VM으로 비용 절감이 필요할 때

**Autopilot을 선택해야 할 때:**
- 인프라 관리 부담을 최소화하고 싶을 때
- 워크로드 변동이 크고 예측이 어려울 때
- 보안 기본값이 강화된 환경이 필요할 때
- 소규모 팀에서 GKE를 빠르게 도입하고 싶을 때

## 오류 트러블슈팅

| 오류 | 원인 | 해결 |
|------|------|------|
| `Error 403: API not enabled` | API 활성화 타이밍 | `depends_on` 확인 후 재시도 |
| `Error 412: organizationPolicy` | Org Policy 미적용 | `terraform apply -target=google_project_organization_policy.*` 먼저 실행 |
| Autopilot Pod `Pending` 장시간 | 노드 프로비전 중 (정상) | 최대 2-3분 대기 |
| `forbidden: violates PodSecurity` | Autopilot 보안 정책 | `securityContext.privileged: true` 제거 |
| Service `EXTERNAL-IP` `<pending>` | LB 생성 중 | 2-3분 대기 후 재확인 |

## 정리

```bash
# Kubernetes 리소스 삭제 (각 클러스터에서 실행)
kubectl delete -f k8s/

# Terraform 인프라 삭제
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

## 관련 GCP 문서

- [Standard vs Autopilot 비교](https://cloud.google.com/kubernetes-engine/docs/concepts/choose-cluster-mode)
- [Autopilot 개요](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview)
- [Autopilot 리소스 요청](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests)
- [GKE 클러스터 만들기](https://cloud.google.com/kubernetes-engine/docs/how-to/creating-a-regional-cluster)
