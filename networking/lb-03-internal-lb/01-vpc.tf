# ────────────────────────────────────────────────────────────────────
# VPC: 서브넷을 분리하여 Frontend / Backend 역할 명확화
# ────────────────────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = "micro-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

# Frontend 서브넷 (프론트엔드 VM 배치)
resource "google_compute_subnetwork" "frontend" {
  name          = "frontend-subnet"
  ip_cidr_range = "10.30.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Backend 서브넷 (Backend API VM + Internal LB VIP 배치)
resource "google_compute_subnetwork" "backend" {
  name          = "backend-subnet"
  ip_cidr_range = "10.30.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# ────────────────────────────────────────────────────────────────────
# Cloud NAT: 외부 IP 없는 VM들의 인터넷 출구 (패키지 설치용)
# ────────────────────────────────────────────────────────────────────
resource "google_compute_router" "router" {
  name    = "micro-router"
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "micro-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
