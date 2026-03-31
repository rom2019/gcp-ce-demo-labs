# ============================================================
# [02] Spoke: Dev VPC
# ============================================================
# 핵심 개념:
#   1. VPC Peering (dev ↔ hub)
#      - import_custom_routes = true: hub 의 PSC endpoint(/32) 경로 가져옴
#      - export_custom_routes = true: hub 에서 경로 내보냄
#
#   2. DNS Peering Zone
#      - googleapis.com 쿼리를 hub-vpc 의 private zone 으로 위임
#      - dev-vm 에서 nslookup storage.googleapis.com → 10.0.1.2 반환
#
# Console 확인:
#   Cloud DNS > Zones > dev-googleapis-peering
#   VPC network > VPC network peering > dev-to-hub
# ============================================================

resource "google_compute_network" "dev" {
  name                    = "dev-vpc"
  auto_create_subnetworks = false
  depends_on              = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "dev" {
  name          = "dev-subnet"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.dev.id
}

# VPC Peering: dev → hub
# import_custom_routes: hub 의 PSC endpoint 경로(/32)를 가져와
# dev-vm 이 10.0.1.2 로 패킷을 보낼 수 있게 함
resource "google_compute_network_peering" "dev_to_hub" {
  name                 = "dev-to-hub"
  network              = google_compute_network.dev.id
  peer_network         = google_compute_network.hub.id
  import_custom_routes = true
}

# VPC Peering: hub → dev
# export_custom_routes: PSC endpoint 경로를 dev 에 내보냄
resource "google_compute_network_peering" "hub_to_dev" {
  name                 = "hub-to-dev"
  network              = google_compute_network.hub.id
  peer_network         = google_compute_network.dev.id
  export_custom_routes = true

  depends_on = [google_compute_network_peering.dev_to_hub]
}

# DNS Peering Zone
# googleapis.com 쿼리 → hub-vpc 의 googleapis-hub zone 으로 위임
# hub zone 이 10.0.1.2 반환 → dev-vm 이 PSC endpoint 로 연결
resource "google_dns_managed_zone" "dev_googleapis_peering" {
  name        = "dev-googleapis-peering"
  dns_name    = "googleapis.com."
  description = "googleapis.com DNS 쿼리를 hub-vpc zone 으로 위임"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.dev.id
    }
  }

  peering_config {
    target_network {
      network_url = google_compute_network.hub.id
    }
  }

  depends_on = [
    google_compute_network_peering.dev_to_hub,
    google_compute_network_peering.hub_to_dev,
  ]
}

# Cloud Router + NAT (dnsutils 패키지 설치용)
resource "google_compute_router" "dev" {
  name    = "dev-router"
  region  = var.region
  network = google_compute_network.dev.id
}

resource "google_compute_router_nat" "dev" {
  name                               = "dev-nat"
  router                             = google_compute_router.dev.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# IAP SSH 방화벽
resource "google_compute_firewall" "dev_iap_ssh" {
  name    = "dev-allow-iap-ssh"
  network = google_compute_network.dev.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}
