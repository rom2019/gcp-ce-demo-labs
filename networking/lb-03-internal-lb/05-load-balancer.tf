# ────────────────────────────────────────────────────────────────────
# Regional Internal Passthrough Network Load Balancer
#
# load_balancing_scheme = "INTERNAL"
# → VIP 는 Private IP 만 할당 (인터넷에서 접근 불가)
# → 동일 VPC 내 Frontend VM 에서만 접근 가능
#
# 구성:
#   Frontend VM
#     → Internal Forwarding Rule (VIP: 10.30.1.x)
#     → Internal Region Backend Service
#     → Backend API MIG (3대)
# ────────────────────────────────────────────────────────────────────

# 1. HTTP 헬스체크 (리전) — /health 엔드포인트 확인
resource "google_compute_region_health_check" "http" {
  name   = "backend-api-health-check"
  region = var.region

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/health"
  }

  depends_on = [google_project_service.apis]
}

# 2. Internal Region Backend Service
resource "google_compute_region_backend_service" "api" {
  name                  = "backend-api-service"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"

  backend {
    group          = google_compute_region_instance_group_manager.backend.instance_group
    balancing_mode = "CONNECTION"
  }

  health_checks = [google_compute_region_health_check.http.id]

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# 3. Internal Forwarding Rule — Private VIP 할당
#
# [핵심] load_balancing_scheme = "INTERNAL"
#   → ip_address 는 backend-subnet 의 Private IP 범위에서 자동 할당
#   → 인터넷에서 이 IP 로 접근 불가
#   → 동일 VPC 내부에서만 라우팅 가능
resource "google_compute_forwarding_rule" "internal" {
  name                  = "backend-api-ilb-rule"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  ip_protocol           = "TCP"
  ports                 = ["80"]
  backend_service       = google_compute_region_backend_service.api.id
  network               = google_compute_network.vpc.id
  subnetwork            = google_compute_subnetwork.backend.id # VIP 할당 서브넷
}
