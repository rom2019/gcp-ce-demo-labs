# ============================================================
# [04] Producer L4 ILB (Terraform 직접 생성)
# ============================================================
# GKE 가 03 에서 NEG 를 생성한 뒤, 이 파일의 리소스를 apply 해야 함
#
# ※ 두 단계 apply 필요:
#   1단계: terraform apply -target=kubernetes_service.api
#          → GKE 가 NEG(producer-api-neg) 를 zone 별로 생성
#   2단계: terraform apply
#          → ILB, Service Attachment, Consumer 리소스 생성
#
# Console 확인: Network services > Load balancing
# ============================================================

# GKE 가 생성한 NEG 를 zone 별로 조회
# cloud.google.com/neg annotation 의 name 과 반드시 일치해야 함
data "google_compute_network_endpoint_group" "api" {
  for_each = toset(local.gke_zones)

  name = "producer-api-neg"
  zone = each.value
}

# L4 ILB 헬스체크 (HTTP /  port 80)
resource "google_compute_health_check" "api" {
  name = "producer-api-hc"

  http_health_check {
    port = 80
  }
}

# GCP 헬스체크 probe IP 에서 오는 트래픽 허용
# 35.191.0.0/16, 130.211.0.0/22 → GCP 공식 헬스체크 IP 대역
resource "google_compute_firewall" "producer_health_check" {
  name    = "producer-allow-health-check"
  network = google_compute_network.producer.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

# Regional Backend Service (INTERNAL = L4 ILB 용)
# NEG 를 백엔드로 사용 → pod IP 로 직접 로드밸런싱 (container-native LB)
resource "google_compute_region_backend_service" "api_ilb" {
  name                  = "producer-api-backend"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  protocol              = "TCP"
  health_checks         = [google_compute_health_check.api.id]

  dynamic "backend" {
    for_each = data.google_compute_network_endpoint_group.api
    content {
      group          = backend.value.id
      balancing_mode = "CONNECTION"
    }
  }

  depends_on = [google_compute_firewall.producer_health_check]
}

# L4 ILB Forwarding Rule
# - 이름을 직접 지정(producer-api-ilb) → 05-producer-service-attachment.tf 에서 참조
# - load_balancing_scheme = "INTERNAL" → VPC 내부 전용
resource "google_compute_forwarding_rule" "api_ilb" {
  name                  = "producer-api-ilb"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.api_ilb.id
  network               = google_compute_network.producer.id
  subnetwork            = google_compute_subnetwork.producer_gke.id
  ip_protocol           = "TCP"
  ports                 = ["80"]
}
