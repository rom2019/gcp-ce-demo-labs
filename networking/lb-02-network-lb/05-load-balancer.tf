# ────────────────────────────────────────────────────────────────────
# Regional External Passthrough Network Load Balancer
# (Backend Service 방식 — Google 권장 최신 방식)
#
# 구성 요소:
#   [클라이언트] → [Forwarding Rule (리전 VIP)]
#               → [Region Backend Service] → [MIG 인스턴스]
#
# Application LB 와의 핵심 차이:
#   - 프록시 없음 (Passthrough): L4 직접 전달, 클라이언트 IP 보존
#   - 리전 단위 (global_forwarding_rule 아님)
#   - named_port 불필요
#   - session_affinity = CLIENT_IP → 게임 세션 유지 핵심 설정
# ────────────────────────────────────────────────────────────────────

# 1. TCP 헬스체크 (리전) — NLB 는 L4 TCP 헬스체크가 자연스러움
resource "google_compute_region_health_check" "tcp" {
  name   = "game-tcp-health-check"
  region = var.region

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 80
  }

  log_config {
    enable = true
  }

  depends_on = [google_project_service.apis]
}

# 2. Region Backend Service
#    load_balancing_scheme = "EXTERNAL" → Passthrough NLB
#    protocol = "TCP"
#    session_affinity = "CLIENT_IP" → 같은 클라이언트 IP는 항상 같은 서버로 (게임 세션 유지)
#    balancing_mode = "CONNECTION" → 연결 수 기반 분산
resource "google_compute_region_backend_service" "game" {
  name                  = "game-backend-service"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  session_affinity      = "CLIENT_IP" # 핵심: 게임 세션 유지

  backend {
    group          = google_compute_region_instance_group_manager.game.instance_group
    balancing_mode = "CONNECTION"
  }

  health_checks = [google_compute_region_health_check.tcp.id]

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# 3. Regional Forwarding Rule — 인터넷 진입점 (VIP)
#
#    [자주 하는 실수] google_compute_global_forwarding_rule 사용 → 오류
#    NLB 는 반드시 google_compute_forwarding_rule (리전) 사용
resource "google_compute_forwarding_rule" "game" {
  name                  = "game-lb-rule"
  region                = var.region
  backend_service       = google_compute_region_backend_service.game.id
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "80"

  depends_on = [google_project_organization_policy.lb_types]
}
