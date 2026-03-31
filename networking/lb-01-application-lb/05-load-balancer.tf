# ────────────────────────────────────────────────────────────────────
# Global External Application Load Balancer (EXTERNAL_MANAGED)
#
# 구성 요소:
#   [사용자] → [글로벌 포워딩 룰] → [HTTP 프록시]
#             → [URL Map] → [백엔드 서비스] → [MIG]
#
# 헬스체크: 백엔드 서비스 & MIG 자동복구 공용
#
# [주의] org 정책 constraints/compute.restrictLoadBalancerCreationForTypes 가
#        org 레벨에서 GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS 를 차단하는 경우
#        providers.tf 의 google_project_organization_policy.lb_types 가
#        프로젝트 레벨에서 override 되어야 합니다.
#        org 레벨 정책이 강제(enforced) 적용 중이라면 org 관리자에게
#        해당 constraint 해제를 요청하세요.
# ────────────────────────────────────────────────────────────────────

# 1. 헬스체크 (백엔드 서비스 + MIG 자동복구 공용)
resource "google_compute_health_check" "http" {
  name               = "shop-http-health-check"
  check_interval_sec = 10 # 10초마다 체크
  timeout_sec        = 5  # 5초 내 응답 없으면 실패
  healthy_threshold  = 2  # 연속 2회 성공 → 정상
  unhealthy_threshold = 3 # 연속 3회 실패 → 비정상

  http_health_check {
    port         = 80
    request_path = "/health"
  }

  log_config {
    enable = true
  }
}

# 2. 백엔드 서비스: LB가 트래픽을 분산할 백엔드 그룹 설정
resource "google_compute_backend_service" "shop" {
  name                  = "shop-backend-service"
  protocol              = "HTTP"
  port_name             = "http"            # MIG의 named_port와 일치
  load_balancing_scheme = "EXTERNAL_MANAGED" # Global External Application LB (권장)
  timeout_sec           = 30

  backend {
    group           = google_compute_region_instance_group_manager.shop.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [google_compute_health_check.http.id]

  # 액세스 로그 활성화 (전체 샘플링)
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# 3. URL Map: 요청 경로에 따라 백엔드 서비스로 라우팅
#    이 실습에서는 모든 요청을 shop 백엔드로 전달 (단일 백엔드)
resource "google_compute_url_map" "shop" {
  name            = "shop-url-map"
  default_service = google_compute_backend_service.shop.id
}

# 4. HTTP 프록시: URL Map을 참조
resource "google_compute_target_http_proxy" "shop" {
  name    = "shop-http-proxy"
  url_map = google_compute_url_map.shop.id
}

# 5. 글로벌 포워딩 룰: 인터넷 트래픽의 진입점 (VIP)
resource "google_compute_global_forwarding_rule" "shop" {
  name                  = "shop-lb-rule"
  target                = google_compute_target_http_proxy.shop.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"

  depends_on = [google_project_organization_policy.lb_types]
}
