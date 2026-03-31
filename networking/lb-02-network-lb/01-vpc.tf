# ────────────────────────────────────────────────────────────────────
# VPC 네트워크
# ────────────────────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = "game-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "game-subnet"
  ip_cidr_range = "10.20.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ────────────────────────────────────────────────────────────────────
# Cloud NAT: 인스턴스 외부 IP 없이 인터넷 접근 (패키지 설치용)
# ────────────────────────────────────────────────────────────────────
resource "google_compute_router" "router" {
  name    = "game-router"
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "game-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
