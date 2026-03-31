# ────────────────────────────────────────────────────────────────────
# 방화벽 규칙
# ────────────────────────────────────────────────────────────────────

# Passthrough NLB 헬스체크 허용
# NLB 헬스체크도 Application LB 와 동일한 GCP IP 범위 사용
resource "google_compute_firewall" "allow_health_check" {
  name        = "game-allow-health-check"
  network     = google_compute_network.vpc.id
  description = "NLB 헬스체크 허용 (TCP:80)"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["game-server"]
}

# 게임 클라이언트 트래픽 허용 (NLB VIP 경유)
# Passthrough NLB 는 클라이언트 IP 를 보존하므로 0.0.0.0/0 허용 필요
resource "google_compute_firewall" "allow_game_traffic" {
  name        = "game-allow-traffic"
  network     = google_compute_network.vpc.id
  description = "게임 서버 트래픽 허용 (HTTP 데모: 80, 실제 게임포트 예시: 7777)"

  allow {
    protocol = "tcp"
    ports    = ["80", "7777"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["game-server"]
}

# Cloud IAP SSH 접속 허용
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "game-allow-iap-ssh"
  network     = google_compute_network.vpc.id
  description = "Cloud IAP SSH 허용"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["game-server"]
}
