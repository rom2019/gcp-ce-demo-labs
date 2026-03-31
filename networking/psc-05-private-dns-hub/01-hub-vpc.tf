# ============================================================
# [01] Hub VPC
# ============================================================
# DNS 중앙 관리 허브
#
# 핵심 개념:
#   - PSC Endpoint 하나 (Google APIs)
#   - Private DNS Zone 하나 (googleapis.com → PSC IP)
#   - 이 Zone 을 모든 spoke VPC 가 DNS Peering 으로 참조
#   → DNS 변경은 이 Zone 하나만 수정하면 됨
#
# Console 확인:
#   Cloud DNS > Zones > googleapis-hub
#   VPC network > Private Service Connect
# ============================================================

resource "google_compute_network" "hub" {
  name                    = "hub-vpc"
  auto_create_subnetworks = false
  depends_on              = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "hub" {
  name          = "hub-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.hub.id
}

# PSC Endpoint IP
# hub-subnet (10.0.0.0/24) 과 겹치지 않는 별도 IP 사용
resource "google_compute_global_address" "psc_endpoint" {
  name         = "psc-endpoint-ip"
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = google_compute_network.hub.id
  address      = "10.0.1.2"

  depends_on = [time_sleep.api_propagation]
}

# PSC Forwarding Rule → Google APIs
# 주의: 이름은 alphanumeric only (하이픈 사용 불가)
resource "google_compute_global_forwarding_rule" "google_apis" {
  name                  = "pscgoogleapis"
  target                = "all-apis"
  network               = google_compute_network.hub.id
  ip_address            = google_compute_global_address.psc_endpoint.id
  load_balancing_scheme = ""
  no_automate_dns_zone  = true
}

# ============================================================
# Private DNS Zone: googleapis.com
# spoke VPC 들은 이 zone 을 DNS Peering 으로 참조
# → zone 하나만 관리하면 모든 spoke 에 자동 반영
# ============================================================
resource "google_dns_managed_zone" "googleapis" {
  name        = "googleapis-hub"
  dns_name    = "googleapis.com."
  description = "PSC endpoint DNS - hub 에서 중앙 관리, spoke 는 DNS Peering 으로 참조"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.hub.id
    }
  }

  depends_on = [time_sleep.api_propagation]
}

# *.googleapis.com → PSC IP
resource "google_dns_record_set" "googleapis_wildcard" {
  name         = "*.googleapis.com."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis.name
  rrdatas      = [google_compute_global_address.psc_endpoint.address]
}

# googleapis.com (root) → PSC IP
resource "google_dns_record_set" "googleapis_root" {
  name         = "googleapis.com."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis.name
  rrdatas      = [google_compute_global_address.psc_endpoint.address]
}

# Cloud Router + NAT (hub-vm 인터넷 접근용)
resource "google_compute_router" "hub" {
  name    = "hub-router"
  region  = var.region
  network = google_compute_network.hub.id
}

resource "google_compute_router_nat" "hub" {
  name                               = "hub-nat"
  router                             = google_compute_router.hub.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# IAP SSH 방화벽
resource "google_compute_firewall" "hub_iap_ssh" {
  name    = "hub-allow-iap-ssh"
  network = google_compute_network.hub.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}
