# ============================================================
# [03] Producer K8s App + L4 ILB (GKE 자동 생성)
# ============================================================
# K8s Service type: LoadBalancer + Internal annotation
# → GKE 가 L4 ILB(forwarding rule) 를 자동으로 생성
#
# GKE 가 생성하는 forwarding rule 이름은 a<hash> 형태로 자동 생성됨
# → Phase 1 apply 후 gcloud 로 이름 확인 → variables.tf 의 ilb_forwarding_rule_name 에 입력
#
# Console 확인:
#   - Kubernetes Engine > Workloads (Deployment)
#   - Kubernetes Engine > Services & Ingress (Service)
#   - Network services > Load balancing (ILB 확인)
# ============================================================

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
          image = "nginxdemos/hello:latest"

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

# K8s Service - Internal LoadBalancer
# cloud.google.com/load-balancer-type: "Internal" → VPC 내부 전용 L4 ILB 생성
resource "kubernetes_service" "api" {
  metadata {
    name      = "rest-api"
    namespace = "default"

    annotations = {
      "cloud.google.com/load-balancer-type" = "Internal"
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
