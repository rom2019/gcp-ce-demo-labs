# ============================================================
# [05] Consumer VPC
# ============================================================
# Console 확인: VPC network > VPC networks
# ============================================================

resource "google_compute_network" "consumer" {
  name                    = "consumer-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "consumer" {
  name          = "consumer-subnet"
  ip_cidr_range = "192.168.0.0/24"
  region        = var.region
  network       = google_compute_network.consumer.id

  private_ip_google_access = true
}
