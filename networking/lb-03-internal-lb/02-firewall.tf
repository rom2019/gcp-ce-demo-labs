# ────────────────────────────────────────────────────────────────────
# 방화벽 규칙
# ────────────────────────────────────────────────────────────────────

# [핵심 학습] Internal LB 헬스체크 허용
# GCP 헬스체크 프로브는 외부 IP(130.211.x.x, 35.191.x.x)에서 발신됨
# → Internal LB 라도 이 방화벽 룰 없으면 헬스체크 실패, 트래픽 전달 안 됨
# → target_tags = ["backend-api"] 로 백엔드 VM 에만 적용
resource "google_compute_firewall" "allow_health_check" {
  name        = "micro-allow-health-check"
  network     = google_compute_network.vpc.id
  description = "Internal LB 헬스체크 허용 — 이 룰 없으면 백엔드 헬스체크 실패"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["backend-api"] # 백엔드 VM 에만 적용
}

# Frontend → Internal LB → Backend 내부 통신 허용
resource "google_compute_firewall" "allow_internal" {
  name        = "micro-allow-internal"
  network     = google_compute_network.vpc.id
  description = "VPC 내부 서브넷 간 통신 허용 (Frontend → Backend)"

  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }

  source_ranges = ["10.30.0.0/16"] # VPC 전체 대역
  target_tags   = ["backend-api"]
}

# Frontend VM 외부 접속 허용 (데모 페이지 접속)
resource "google_compute_firewall" "allow_frontend_http" {
  name        = "micro-allow-frontend-http"
  network     = google_compute_network.vpc.id
  description = "Frontend 데모 페이지 외부 접속 허용"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["frontend"]
}

# IAP SSH 접속 (Frontend + Backend 모두)
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "micro-allow-iap-ssh"
  network     = google_compute_network.vpc.id
  description = "Cloud IAP SSH 허용"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["frontend", "backend-api"]
}
