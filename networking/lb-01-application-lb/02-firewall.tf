# ────────────────────────────────────────────────────────────────────
# 방화벽 규칙
# ────────────────────────────────────────────────────────────────────

# Application LB 헬스체크 IP 범위에서의 트래픽 허용
# GCP 헬스체크 IP 범위는 고정값 (130.211.0.0/22, 35.191.0.0/16)
resource "google_compute_firewall" "allow_health_check" {
  name        = "shop-allow-health-check"
  network     = google_compute_network.vpc.id
  description = "Application LB 헬스체크 허용 (필수)"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["shop-backend"]
}

# Cloud IAP를 통한 SSH 접속 허용 (외부 IP 없이 VM 접속)
# gcloud compute ssh --tunnel-through-iap 명령 사용
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "shop-allow-iap-ssh"
  network     = google_compute_network.vpc.id
  description = "Cloud IAP를 통한 SSH 접속 허용"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["shop-backend"]
}
