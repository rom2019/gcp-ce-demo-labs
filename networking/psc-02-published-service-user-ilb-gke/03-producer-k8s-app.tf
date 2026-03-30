# ============================================================
# [03] Producer K8s App
# ============================================================
# K8s Service 를 type: ClusterIP + NEG annotation 으로 생성
# → GKE 가 zone 별 NEG(Network Endpoint Group) 를 자동 생성
# → ILB 는 04-producer-ilb.tf 에서 Terraform 으로 직접 생성 (이름 고정 목적)
#
# ※ networking.gke.io/load-balancer-name annotation 은 GCP forwarding rule
#    이름을 제어하지 않음 → ILB를 직접 Terraform 으로 관리
#
# Console 확인:
#   - Kubernetes Engine > Workloads (Deployment)
#   - Kubernetes Engine > Services & Ingress (Service)
# ============================================================

# REST API 서버 Deployment (학습용 nginx)
resource "kubernetes_deployment" "api" {
  metadata {
    name      = "rest-api"
    namespace = "default"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "rest-api"
      }
    }

    template {
      metadata {
        labels = {
          app = "rest-api"
        }
      }

      spec {
        container {
          name  = "api"
          image = "nginxdemos/hello:latest" # 요청 정보(hostname, IP 등)를 응답에 포함

          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [google_container_cluster.producer]
}

# K8s Service (type: ClusterIP + NEG annotation)
# - type: ClusterIP → GKE 가 ILB를 자동 생성하지 않음
# - cloud.google.com/neg: GKE 가 zone 별 NEG 를 생성하고 pod IP를 자동 등록
#   NEG 이름(producer-api-neg)은 04-producer-ilb.tf 의 data source 에서 참조
resource "kubernetes_service" "api" {
  metadata {
    name      = "rest-api"
    namespace = "default"

    annotations = {
      "cloud.google.com/neg" = jsonencode({
        exposed_ports = {
          "80" = { name = "producer-api-neg" }
        }
      })
    }
  }

  spec {
    selector = {
      app = kubernetes_deployment.api.spec[0].template[0].metadata[0].labels.app
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
