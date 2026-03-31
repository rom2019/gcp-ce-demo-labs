# ============================================================
# [01] Producer VPC
# ============================================================
# Producer VM 의 primary NIC(nic0) 가 위치하는 VPC
# Console 확인: VPC network > VPC networks
# ============================================================

resource "google_compute_network" "producer" {
  name                    = "producer-vpc"
  auto_create_subnetworks = false

  depends_on = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "producer" {
  name          = "producer-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.producer.id
}

# IAP SSH 방화벽 (Producer VM 접속용)
resource "google_compute_firewall" "producer_iap_ssh" {
  name    = "producer-allow-iap-ssh"
  network = google_compute_network.producer.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

# Producer VM → Consumer VMs ICMP/TCP 허용 (양방향 테스트용)
resource "google_compute_firewall" "producer_egress_allow" {
  name      = "producer-allow-egress"
  network   = google_compute_network.producer.id
  direction = "EGRESS"

  allow {
    protocol = "all"
  }

  destination_ranges = ["10.1.0.0/24", "10.2.0.0/24"]
}
