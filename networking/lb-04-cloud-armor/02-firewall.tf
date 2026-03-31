# Global Application LB 헬스체크 허용
resource "google_compute_firewall" "allow_health_check" {
  name    = "armor-allow-health-check"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web-server"]
}

# Cloud IAP SSH 접속
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "armor-allow-iap-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["web-server"]
}
