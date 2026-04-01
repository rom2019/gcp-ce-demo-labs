# Lab 02 — GKE Ingress: 단일 IP로 멀티 서비스 노출 (Path 기반 라우팅)

## 시나리오

쇼핑몰 서비스를 GKE에 배포합니다. Frontend(웹)와 Backend(API) 두 서비스를 운영해야 하는데, 서비스마다 외부 IP를 발급하면 비용이 증가하고 URL이 제각각이라 관리가 어렵습니다.
Ingress를 사용해 **외부 IP 1개**로 경로에 따라 두 서비스로 트래픽을 분산합니다.

## 학습 목표

- LoadBalancer Service와 Ingress의 구조적 차이 이해
- GKE Ingress → Google Cloud HTTP(S) LB 자동 생성 원리 파악
- Path 기반 라우팅으로 단일 IP에서 멀티 서비스 노출
- NodePort vs LoadBalancer Service 타입 차이 체감

## 아키텍처

```
인터넷
  │
  ▼
┌─────────────────────────────────────────────┐
│  Google Cloud HTTP(S) Load Balancer         │
│  (GKE Ingress가 자동 생성)                   │
│  외부 IP: 1개                               │
│                                             │
│  Path 라우팅 규칙                            │
│  /      → frontend-svc                      │
│  /api/* → backend-svc                       │
└──────────┬──────────────────┬───────────────┘
           │                  │
           ▼                  ▼
   ┌───────────────┐  ┌───────────────┐
   │ frontend-svc  │  │ backend-svc   │
   │ (NodePort)    │  │ (NodePort)    │
   └──────┬────────┘  └──────┬────────┘
          │                  │
          ▼                  ▼
   ┌────────────┐    ┌────────────┐
   │ frontend   │    │ backend    │
   │ Pod × 2    │    │ Pod × 2    │
   │ (v1.0)     │    │ (v2.0)     │
   └────────────┘    └────────────┘

[비교] LoadBalancer Service 방식:
  frontend-lb → 외부 IP #1
  backend-lb  → 외부 IP #2
  → 외부 IP 2개, URL 제각각, 비용 2배
```

## LoadBalancer vs Ingress 핵심 차이

| 항목 | LoadBalancer Service | Ingress |
|------|---------------------|---------|
| **외부 IP** | 서비스당 1개 | 전체 1개 |
| **LB 타입** | L4 Network LB | L7 HTTP(S) LB |
| **라우팅** | IP:Port 기반 | Path/Host 기반 |
| **TLS** | 서비스별 개별 설정 | Ingress에서 중앙 설정 |
| **비용** | 서비스 수 × LB 비용 | LB 1개 비용 |
| **서비스 타입** | LoadBalancer | NodePort (Ingress 백엔드) |
| **적합한 케이스** | 단일 서비스, TCP/UDP | 멀티 서비스, HTTP/HTTPS |

## 자주 하는 실수

| 실수 | 결과 | 올바른 방법 |
|------|------|-------------|
| Ingress 백엔드 Service를 ClusterIP로 설정 | Ingress가 백엔드 등록 실패 | Service 타입을 `NodePort`로 설정 |
| `pathType: Exact`로 `/api` 설정 | `/api/users` 등 하위 경로 불일치 | `pathType: Prefix` 사용 |
| Ingress IP가 `<pending>` 상태에서 조급하게 확인 | LB 프로비전 중 (5-10분 소요) | `kubectl get ingress -w`로 대기 |
| `/` 경로를 마지막에 정의 | 모든 요청이 `/`로 매칭될 수 있음 | 구체적인 경로(`/api`)를 먼저, `/`는 마지막 |

## 핵심 k8s 코드

### 1. NodePort Service — Ingress 백엔드 필수 조건

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
spec:
  type: NodePort     # ← ClusterIP가 아닌 NodePort!
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 8080
```

### 2. Ingress — Path 기반 라우팅

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  annotations:
    kubernetes.io/ingress.class: "gce"  # GCP HTTP(S) LB 생성
spec:
  rules:
  - http:
      paths:
      - path: /api        # 구체적인 경로 먼저
        pathType: Prefix
        backend:
          service:
            name: backend-svc
            port:
              number: 80
      - path: /           # 기본 경로는 마지막
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80
```

## 실습 시작

### Step 0: 사전 조건

```bash
gcloud config set project YOUR_PROJECT_ID
```

### Step 1: 인프라 배포

```bash
cd gke/gke-02-ingress

terraform init
terraform apply -var="project_id=YOUR_PROJECT_ID"
# Autopilot 클러스터 생성 약 10분 소요
```

### Step 2: kubectl 연결

```bash
gcloud container clusters get-credentials gke-ingress-cluster \
  --region=us-central1 --project=YOUR_PROJECT_ID

kubectl get nodes
```

### Step 3: [비교 1] LoadBalancer 방식 먼저 체험

```bash
# Deployment 배포
kubectl apply -f k8s/01-deployments.yaml
kubectl get pods -w   # Running 확인 후 Ctrl+C

# LoadBalancer Service 배포 → 외부 IP 2개 발급
kubectl apply -f k8s/04-lb-comparison.yaml

# 외부 IP 2개 확인 (각 서비스마다 별도 IP)
kubectl get service -l mode=lb-compare --watch
# NAME          TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)
# frontend-lb   LoadBalancer   10.101.x.x   34.x.x.x        80:xxxxx/TCP
# backend-lb    LoadBalancer   10.101.x.x   35.x.x.x        80:xxxxx/TCP
```

각 IP로 접근해 응답 확인:
```bash
FRONTEND_IP=$(kubectl get svc frontend-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
BACKEND_IP=$(kubectl get svc backend-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl http://$FRONTEND_IP   # Hello, world! Version: 1.0.0
curl http://$BACKEND_IP    # Hello, world! Version: 2.0.0
```

> **핵심 관찰:** 외부 IP 2개, URL이 달라 클라이언트가 두 IP를 모두 알아야 함.

LoadBalancer 정리:
```bash
kubectl delete -f k8s/04-lb-comparison.yaml
```

---

### Step 4: [비교 2] Ingress 방식으로 전환

```bash
# NodePort Service + Ingress 배포
kubectl apply -f k8s/02-services.yaml
kubectl apply -f k8s/03-ingress.yaml

# Ingress 생성 확인 (외부 IP 발급까지 5-10분)
kubectl get ingress demo-ingress --watch
# NAME           CLASS    HOSTS   ADDRESS        PORTS   AGE
# demo-ingress   <none>   *       34.x.x.x      80      8m
```

---

### Step 5: Path 기반 라우팅 검증

```bash
INGRESS_IP=$(kubectl get ingress demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# 루트 경로 → frontend (v1.0)
curl http://$INGRESS_IP/
# Hello, world! Version: 1.0.0 Hostname: frontend-xxx

# /api 경로 → backend (v2.0)
curl http://$INGRESS_IP/api
# Hello, world! Version: 2.0.0 Hostname: backend-xxx
```

> **핵심 관찰:** 외부 IP 1개로 경로에 따라 다른 서비스로 라우팅!

---

### Step 6: Ingress 상세 확인

```bash
# Ingress 라우팅 규칙 확인
kubectl describe ingress demo-ingress

# GCP 콘솔에서 HTTP(S) LB 확인
# Navigation → Network services → Load balancing
# GKE가 자동으로 생성한 LB, Backend services, Health checks 확인
```

---

### Step 7: 백엔드 Health Check 확인

GKE Ingress는 각 Service의 백엔드 Pod에 대해 자동으로 Health Check를 생성합니다.

```bash
# Pod 상태 확인
kubectl get pods -o wide

# 특정 Pod의 헬스체크 엔드포인트 확인
kubectl exec -it <POD_NAME> -- wget -qO- http://localhost:8080/
```

## 오류 트러블슈팅

| 오류 | 원인 | 해결 |
|------|------|------|
| Ingress `ADDRESS`가 계속 비어있음 | LB 프로비전 중 | 최대 10분 대기, `kubectl describe ingress` 이벤트 확인 |
| `curl` 응답 502 Bad Gateway | Backend Pod 아직 준비 안됨 | `kubectl get pods` Ready 상태 확인 |
| `/api` 경로가 frontend로 라우팅됨 | 경로 순서 문제 | 구체적 경로(`/api`)를 `/`보다 먼저 정의 |
| Autopilot에서 `spec.ingressClassName: gce` 설정 시 Ingress 이벤트 없음 | GKE Autopilot에 `gce` IngressClass 리소스가 등록되지 않음 | `kubernetes.io/ingress.class: "gce"` annotation 방식 사용 |
| Autopilot에서 NEG 404 오류 | NodePort Service는 Autopilot NEG와 호환 안됨 | Service를 `ClusterIP`로 변경 + `cloud.google.com/neg: '{"ingress": true}'` annotation 추가 |
| `Error 403: API not enabled` | API 활성화 타이밍 | `depends_on` 확인 후 재시도 |
| `Error 412: organizationPolicy` | Org Policy 미적용 | `terraform apply -target=google_project_organization_policy.*` 먼저 실행 |

## 정리

```bash
kubectl delete -f k8s/

terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

## 관련 GCP 문서

- [GKE Ingress 개요](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)
- [GKE Ingress로 HTTP(S) LB 구성](https://cloud.google.com/kubernetes-engine/docs/tutorials/http-balancer)
- [Ingress vs LoadBalancer Service 비교](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress#comparison)
- [Path 기반 라우팅](https://cloud.google.com/kubernetes-engine/docs/how-to/load-balance-ingress#path_rules)
