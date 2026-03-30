# ============================================================
# [03] Producer K8s App + L4 ILB
# ============================================================
# GKE가 K8s Service(type: LoadBalancer) 를 감지하면
# 자동으로 L4 ILB(Internal Forwarding Rule) 를 생성함
#
# Console 확인:
#   - Kubernetes Engine > Workloads (Deployment)
#   - Kubernetes Engine > Services & Ingress (Service)
#   - Network services > Load balancing (ILB 확인)
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

# K8s Service (type: LoadBalancer + Internal)
# - cloud.google.com/load-balancer-type: "Internal" → L4 ILB 생성 (외부 LB 아님)
# - networking.gke.io/load-balancer-name: GKE 1.24+ 에서 forwarding rule 이름 지정
#   → 이 이름이 04-producer-service-attachment.tf 에서 target_service 로 참조됨
resource "kubernetes_service" "api_ilb" {
  metadata {
    name      = "rest-api-ilb"
    namespace = "default"

    annotations = {
      "cloud.google.com/load-balancer-type"  = "Internal"
      "networking.gke.io/load-balancer-name" = "producer-api-ilb"
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

    type = "LoadBalancer"
  }
}
