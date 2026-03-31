# ============================================================
# [01] VPC
# ============================================================
# Console 확인: VPC network > VPC networks
# ============================================================

resource "google_compute_network" "vpc" {
  name                    = "psc-vpcsc-vpc"
  auto_create_subnetworks = false

  depends_on = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "psc-vpcsc-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  # PSC endpoint 가 유일한 Google API 접근 경로임을 강제
  private_ip_google_access = false
}

resource "google_compute_router" "router" {
  name    = "psc-vpcsc-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "psc-vpcsc-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
