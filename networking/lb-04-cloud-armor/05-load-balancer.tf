# ────────────────────────────────────────────────────────────────────
# Global External Application Load Balancer (EXTERNAL_MANAGED)
#
# Cloud Armor 는 Application LB 에만 연결 가능
# → load_balancing_scheme = "EXTERNAL_MANAGED" 필수
# ────────────────────────────────────────────────────────────────────

# 1. 글로벌 HTTP 헬스체크
resource "google_compute_health_check" "http" {
  name = "armor-web-health-check"

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

# 2. 글로벌 Backend Service — Cloud Armor 정책 연결
resource "google_compute_backend_service" "web" {
  name                  = "armor-web-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30

  backend {
    group           = google_compute_region_instance_group_manager.web.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [google_compute_health_check.http.id]

  # [핵심] Cloud Armor 보안 정책 연결
  security_policy = google_compute_security_policy.main.id

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# 3. URL Map
resource "google_compute_url_map" "web" {
  name            = "armor-web-url-map"
  default_service = google_compute_backend_service.web.id
}

# 4. HTTP Target Proxy
resource "google_compute_target_http_proxy" "web" {
  name    = "armor-web-http-proxy"
  url_map = google_compute_url_map.web.id
}

# 5. Global Forwarding Rule
resource "google_compute_global_forwarding_rule" "web" {
  name                  = "armor-web-forwarding-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.web.id
}
