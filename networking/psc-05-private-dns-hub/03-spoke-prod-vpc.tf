# ============================================================
# [03] Spoke: Prod VPC
# ============================================================
# dev-vpc 와 동일한 구조 (다른 IP 대역: 10.2.0.0/24)
# 신규 spoke 추가 시 이 파일을 복사해서 이름/IP 만 변경하면 됨
#
# Console 확인:
#   Cloud DNS > Zones > prod-googleapis-peering
#   VPC network > VPC network peering > prod-to-hub
# ============================================================

resource "google_compute_network" "prod" {
  name                    = "prod-vpc"
  auto_create_subnetworks = false
  depends_on              = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "prod" {
  name          = "prod-subnet"
  ip_cidr_range = "10.2.0.0/24"
  region        = var.region
  network       = google_compute_network.prod.id
}

# VPC Peering: prod → hub
resource "google_compute_network_peering" "prod_to_hub" {
  name                 = "prod-to-hub"
  network              = google_compute_network.prod.id
  peer_network         = google_compute_network.hub.id
  import_custom_routes = true
}

# VPC Peering: hub → prod
resource "google_compute_network_peering" "hub_to_prod" {
  name                 = "hub-to-prod"
  network              = google_compute_network.hub.id
  peer_network         = google_compute_network.prod.id
  export_custom_routes = true

  depends_on = [google_compute_network_peering.prod_to_hub]
}

# DNS Peering Zone
resource "google_dns_managed_zone" "prod_googleapis_peering" {
  name        = "prod-googleapis-peering"
  dns_name    = "googleapis.com."
  description = "googleapis.com DNS 쿼리를 hub-vpc zone 으로 위임"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.prod.id
    }
  }

  peering_config {
    target_network {
      network_url = google_compute_network.hub.id
    }
  }

  depends_on = [
    google_compute_network_peering.prod_to_hub,
    google_compute_network_peering.hub_to_prod,
  ]
}

# Cloud Router + NAT
resource "google_compute_router" "prod" {
  name    = "prod-router"
  region  = var.region
  network = google_compute_network.prod.id
}

resource "google_compute_router_nat" "prod" {
  name                               = "prod-nat"
  router                             = google_compute_router.prod.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# IAP SSH 방화벽
resource "google_compute_firewall" "prod_iap_ssh" {
  name    = "prod-allow-iap-ssh"
  network = google_compute_network.prod.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}
