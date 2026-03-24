# External HTTPS LB 구성요소
#   Forwarding Rule (공인 IP + 포트)
#     → Target HTTPS Proxy
#       → URL Map
#         → Backend Service
#           → NEG (Web MIG 연결)
#             → Health Check
# 
# Internal HTTP LB 구성요소
#   Forwarding Rule (내부 IP + 포트)
#     → Target HTTP Proxy
#       → URL Map
#         → Backend Service
#           → NEG (App MIG 연결)
#             → Health Check
# 08_loadbalancer.tf
# ════════════════════════════════════════
# External HTTPS LB
# ════════════════════════════════════════

# ── 공인 IP ────────────────────────────
resource "google_compute_global_address" "web_lb_ip" {
  name = "ip-web-lb"
}

# ── 헬스체크 ───────────────────────────
resource "google_compute_health_check" "web" {
  name               = "hc-web"
  check_interval_sec = 10
  timeout_sec        = 5

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# ── Backend Service ────────────────────
resource "google_compute_backend_service" "web" {
  name                  = "bs-web"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.web.id]

  backend {
    group           = google_compute_instance_group_manager.web.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# ── URL Map ────────────────────────────
resource "google_compute_url_map" "web" {
  name            = "urlmap-web"
  default_service = google_compute_backend_service.web.id
}

# ── HTTP → HTTPS 리다이렉트용 URL Map ──
resource "google_compute_url_map" "web_redirect" {
  name = "urlmap-web-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# ── SSL 인증서 (관리형) ────────────────
# 도메인이 없으면 self-signed 로 대체
resource "google_compute_managed_ssl_certificate" "web" {
  name = "ssl-web"

  managed {
    domains = [var.web_domain]
  }
}

# ── Target HTTPS Proxy ─────────────────
resource "google_compute_target_https_proxy" "web" {
  name             = "proxy-https-web"
  url_map          = google_compute_url_map.web.id
  ssl_certificates = [google_compute_managed_ssl_certificate.web.id]
}

# ── Target HTTP Proxy (리다이렉트용) ───
resource "google_compute_target_http_proxy" "web_redirect" {
  name    = "proxy-http-redirect"
  url_map = google_compute_url_map.web_redirect.id
}

# ── Forwarding Rule HTTPS ──────────────
resource "google_compute_global_forwarding_rule" "web_https" {
  name                  = "fr-web-https"
  target                = google_compute_target_https_proxy.web.id
  port_range            = "443"
  ip_address            = google_compute_global_address.web_lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ── Forwarding Rule HTTP (리다이렉트) ──
resource "google_compute_global_forwarding_rule" "web_http" {
  name                  = "fr-web-http"
  target                = google_compute_target_http_proxy.web_redirect.id
  port_range            = "80"
  ip_address            = google_compute_global_address.web_lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}


# ════════════════════════════════════════
# Internal HTTP LB
# ════════════════════════════════════════

# ── 헬스체크 ───────────────────────────
resource "google_compute_region_health_check" "app" {
  name               = "hc-app"
  region             = var.region
  check_interval_sec = 10
  timeout_sec        = 5

  http_health_check {
    port         = 8080
    request_path = "/health"
  }
}

# ── Backend Service ────────────────────
resource "google_compute_region_backend_service" "app" {
  name                  = "bs-app"
  region                = var.region
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "INTERNAL_MANAGED"
  health_checks         = [google_compute_region_health_check.app.id]

  backend {
    group           = google_compute_instance_group_manager.app.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0 # 명시적으로 추가
  }
}

# ── URL Map ────────────────────────────
resource "google_compute_region_url_map" "app" {
  name            = "urlmap-app"
  region          = var.region
  default_service = google_compute_region_backend_service.app.id
}

# ── Target HTTP Proxy ──────────────────
resource "google_compute_region_target_http_proxy" "app" {
  name    = "proxy-http-app"
  region  = var.region
  url_map = google_compute_region_url_map.app.id
}

# ── Forwarding Rule (내부 고정 IP) ─────
resource "google_compute_forwarding_rule" "app" {
  name                  = "fr-app"
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  target                = google_compute_region_target_http_proxy.app.id
  port_range            = "8080"
  network               = google_compute_network.main.id
  subnetwork            = google_compute_subnetwork.private.id
  ip_address            = var.internal_lb_ip # 고정 내부 IP
}

# ── LB 전용 Proxy 서브넷 ───────────────
# Internal LB 는 Proxy 서브넷이 필요
resource "google_compute_subnetwork" "proxy" {
  name          = "subnet-proxy"
  ip_cidr_range = var.subnets["proxy"]
  region        = var.region
  network       = google_compute_network.main.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}