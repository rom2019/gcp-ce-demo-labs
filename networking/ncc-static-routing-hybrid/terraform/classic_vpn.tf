################################################################################
# classic_vpn.tf
# Classic VPN (Route-based): sim-onprem-vpc ↔ edge-vpc
#
# [Route-based VPN 핵심]
# Traffic Selector는 양쪽 모두 반드시 0.0.0.0/0
#   → local_traffic_selector  = ["0.0.0.0/0"]
#   → remote_traffic_selector = ["0.0.0.0/0"]
#
# Console의 "Remote network IP ranges"는 Traffic Selector가 아님
# → Terraform에서는 별도 google_compute_route로 명시적 선언 필요
#
# Static Routes:
#   sim-onprem-vpc → 172.16.1.0/24  (edge subnet)
#   sim-onprem-vpc → 10.0.0.0/8    (GCP 전체 supernet, 미래 Spoke 자동 커버)
#   edge-vpc       → 192.168.1.0/24 (sim-onprem subnet)
################################################################################

# -------------------------------------------------------
# External IP 예약
# -------------------------------------------------------
resource "google_compute_address" "sim_onprem_classic_vpn_ip" {
  name         = "sim-onprem-classic-vpn-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

resource "google_compute_address" "edge_classic_vpn_ip" {
  name         = "edge-classic-vpn-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

# -------------------------------------------------------
# Classic VPN Gateways
# -------------------------------------------------------
resource "google_compute_vpn_gateway" "sim_onprem_classic" {
  name    = "sim-onprem-classic-vpn-gw"
  network = google_compute_network.sim_onprem.id
  region  = var.region
}

resource "google_compute_vpn_gateway" "edge_classic" {
  name    = "edge-classic-vpn-gw"
  network = google_compute_network.edge.id
  region  = var.region
}

# -------------------------------------------------------
# Forwarding Rules (Classic VPN 필수 3종)
# -------------------------------------------------------

# sim-onprem 측
resource "google_compute_forwarding_rule" "sim_onprem_classic_esp" {
  name        = "sim-onprem-classic-vpn-esp"
  region      = var.region
  ip_address  = google_compute_address.sim_onprem_classic_vpn_ip.address
  ip_protocol = "ESP"
  target      = google_compute_vpn_gateway.sim_onprem_classic.id
}

resource "google_compute_forwarding_rule" "sim_onprem_classic_udp500" {
  name        = "sim-onprem-classic-vpn-udp500"
  region      = var.region
  ip_address  = google_compute_address.sim_onprem_classic_vpn_ip.address
  ip_protocol = "UDP"
  port_range  = "500"
  target      = google_compute_vpn_gateway.sim_onprem_classic.id
}

resource "google_compute_forwarding_rule" "sim_onprem_classic_udp4500" {
  name        = "sim-onprem-classic-vpn-udp4500"
  region      = var.region
  ip_address  = google_compute_address.sim_onprem_classic_vpn_ip.address
  ip_protocol = "UDP"
  port_range  = "4500"
  target      = google_compute_vpn_gateway.sim_onprem_classic.id
}

# edge 측
resource "google_compute_forwarding_rule" "edge_classic_esp" {
  name        = "edge-classic-vpn-esp"
  region      = var.region
  ip_address  = google_compute_address.edge_classic_vpn_ip.address
  ip_protocol = "ESP"
  target      = google_compute_vpn_gateway.edge_classic.id
}

resource "google_compute_forwarding_rule" "edge_classic_udp500" {
  name        = "edge-classic-vpn-udp500"
  region      = var.region
  ip_address  = google_compute_address.edge_classic_vpn_ip.address
  ip_protocol = "UDP"
  port_range  = "500"
  target      = google_compute_vpn_gateway.edge_classic.id
}

resource "google_compute_forwarding_rule" "edge_classic_udp4500" {
  name        = "edge-classic-vpn-udp4500"
  region      = var.region
  ip_address  = google_compute_address.edge_classic_vpn_ip.address
  ip_protocol = "UDP"
  port_range  = "4500"
  target      = google_compute_vpn_gateway.edge_classic.id
}

# -------------------------------------------------------
# VPN Tunnels (Route-based)
# 양쪽 모두 0.0.0.0/0 → Route-based 생성
# -------------------------------------------------------
resource "google_compute_vpn_tunnel" "sim_onprem_to_edge" {
  name          = "tunnel-classic-vpn-sim-onprem-to-edge"
  region        = var.region
  peer_ip       = google_compute_address.edge_classic_vpn_ip.address
  shared_secret = var.classic_vpn_psk

  target_vpn_gateway = google_compute_vpn_gateway.sim_onprem_classic.id

  # Route-based: 반드시 양쪽 모두 0.0.0.0/0
  local_traffic_selector  = ["0.0.0.0/0"]
  remote_traffic_selector = ["0.0.0.0/0"]

  ike_version = 2

  depends_on = [
    google_compute_forwarding_rule.sim_onprem_classic_esp,
    google_compute_forwarding_rule.sim_onprem_classic_udp500,
    google_compute_forwarding_rule.sim_onprem_classic_udp4500,
    google_compute_forwarding_rule.edge_classic_esp,
    google_compute_forwarding_rule.edge_classic_udp500,
    google_compute_forwarding_rule.edge_classic_udp4500,
  ]
}

resource "google_compute_vpn_tunnel" "edge_to_sim_onprem" {
  name          = "tunnel-classic-vpn-edge-to-sim-onprem"
  region        = var.region
  peer_ip       = google_compute_address.sim_onprem_classic_vpn_ip.address
  shared_secret = var.classic_vpn_psk

  target_vpn_gateway = google_compute_vpn_gateway.edge_classic.id

  # Route-based: 반드시 양쪽 모두 0.0.0.0/0
  local_traffic_selector  = ["0.0.0.0/0"]
  remote_traffic_selector = ["0.0.0.0/0"]

  ike_version = 2

  depends_on = [
    google_compute_forwarding_rule.sim_onprem_classic_esp,
    google_compute_forwarding_rule.sim_onprem_classic_udp500,
    google_compute_forwarding_rule.sim_onprem_classic_udp4500,
    google_compute_forwarding_rule.edge_classic_esp,
    google_compute_forwarding_rule.edge_classic_udp500,
    google_compute_forwarding_rule.edge_classic_udp4500,
  ]
}

# -------------------------------------------------------
# Static Routes
# Console의 "Remote network IP ranges" 역할을 Terraform에서 명시적으로 선언
# -------------------------------------------------------

# sim-onprem → edge-vpc subnet
resource "google_compute_route" "sim_onprem_to_edge" {
  name                = "route-sim-onprem-to-edge"
  network             = google_compute_network.sim_onprem.name
  dest_range          = var.edge_cidr # 172.16.1.0/24
  priority            = 1000
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.sim_onprem_to_edge.id
}

# sim-onprem → GCP 전체 supernet
# 새 Spoke VPC 추가 시 이 route 수정 불필요
resource "google_compute_route" "sim_onprem_to_gcp_supernet" {
  name                = "route-sim-onprem-to-gcp-supernet"
  network             = google_compute_network.sim_onprem.name
  dest_range          = "10.0.0.0/8"
  priority            = 1000
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.sim_onprem_to_edge.id
  description         = "Supernet: covers all GCP VPCs. No update needed when new spoke added."
}

# edge → sim-onprem subnet
resource "google_compute_route" "edge_to_sim_onprem" {
  name                = "route-edge-to-sim-onprem"
  network             = google_compute_network.edge.name
  dest_range          = var.sim_onprem_cidr # 192.168.1.0/24
  priority            = 1000
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.edge_to_sim_onprem.id
}
