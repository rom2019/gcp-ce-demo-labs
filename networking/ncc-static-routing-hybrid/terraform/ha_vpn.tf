################################################################################
# ha_vpn.tf
# HA VPN: edge-vpc ↔ transit-hub-vpc
#
# [검증된 BGP 설계]
#
# tunnel-edge-to-transit-hub-1/2 (edge → transit-hub):
#   - edge-cloud-router 수동 BGP 세션
#   - per-peer Custom Advertisement: 192.168.1.0/24 추가
#     → transit-hub-cloud-router가 on-prem 경로 학습
#
# tunnel-transit-hub-to-edge-1/2 (transit-hub → edge):
#   - NCC Hybrid Spoke로 등록 (ncc.tf 참고)
#   - transit-hub-cloud-router (Default) BGP 세션 보유
#   - NCC Hub이 이 터널을 통해 edge-cloud-router와 BGP
#   - NCC Hub → 192.168.1.0/24 학습 → 전체 Spoke로 전파
#
# BGP IP 설계:
#   Tunnel 1: edge 169.254.1.1 ↔ transit-hub 169.254.1.2
#   Tunnel 2: edge 169.254.2.1 ↔ transit-hub 169.254.2.2
################################################################################

/*
=========================================================================================================
  [ARCHITECTURE REFERENCE] HA VPN & BGP Configuration (Edge ↔ Hub)
=========================================================================================================
  [Edge Layer] edge-vpc : 172.16.1.0/24           |  [Hub Layer] transit-hub-vpc : 10.10.1.0/24
  Cloud Router : edge-cloud-router                |  Cloud Router : 	transit-hub-cloud-router
  Local ASN    : 65001                            |  Local ASN    : 65002
=========================================================================================================
  TUNNEL 1 (Active)
---------------------------------------------------------------------------------------------------------
  Tunnel Name  : tunnel-edge-to-transithub-1         |  Tunnel Name  : tunnel-transithub-to-edge-1
  VPN GW IP    : 35.242.114.78 (Local)               |  VPN GW IP    : 34.183.16.186 (Local)
  Remote Peer  : 34.183.16.186                       |  Remote Peer  : 35.242.114.78
  Peer ASN     : 65002                               |  Peer ASN     : 65001
  BGP IP       : 169.254.1.1 (Local)                 |  BGP IP       : 169.254.1.2 (Local)
  BGP Peer IP  : 169.254.1.2                         |  BGP Peer IP  : 169.254.1.1
  Routes       : Custom (Default + 192.168.1.0/24)   |  Routes       : Default
=========================================================================================================
  TUNNEL 2 (Active)
---------------------------------------------------------------------------------------------------------
  Tunnel Name  : tunnel-edge-to-transithub-2     |  Tunnel Name  : tunnel-transithub-to-edge-2
  VPN GW IP    : 35.220.78.96 (Local)                |  VPN GW IP    : 34.184.19.214 (Local)
  Remote Peer  : 34.184.19.214                       |  Remote Peer  : 35.220.78.96
  Peer ASN     : 65002                               |  Peer ASN     : 65001
  BGP IP       : 169.254.2.1 (Local)                 |  BGP IP       : 169.254.2.2 (Local)
  BGP Peer IP  : 169.254.2.2                         |  BGP Peer IP  : 169.254.2.1
  Routes       : Custom (Default + 192.168.1.0/24)   |  Routes       : Default
=========================================================================================================
*/


# -------------------------------------------------------
# Cloud Routers
# -------------------------------------------------------
resource "google_compute_router" "edge" {
  name    = "edge-cloud-router"
  network = google_compute_network.edge.id
  region  = var.region

  bgp {
    asn            = 65001
    advertise_mode = "DEFAULT"
    # per-peer Custom Advertisement로 192.168.1.0/24 추가 (bgp peer 설정 참고)
  }
}

resource "google_compute_router" "transit_hub" {
  name    = "transit-hub-cloud-router"
  network = google_compute_network.transit_hub.id
  region  = var.region

  bgp {
    asn            = 65002
    advertise_mode = "DEFAULT"
  }
}

# -------------------------------------------------------
# HA VPN Gateways
# -------------------------------------------------------
resource "google_compute_ha_vpn_gateway" "edge" {
  name    = "edge-ha-vpn-gw"
  network = google_compute_network.edge.id
  region  = var.region
}

resource "google_compute_ha_vpn_gateway" "transit_hub" {
  name    = "transit-hub-ha-vpn-gw"
  network = google_compute_network.transit_hub.id
  region  = var.region
}


# -------------------------------------------------------
# HA VPN Tunnels
# -------------------------------------------------------

# edge → transit-hub
resource "google_compute_vpn_tunnel" "edge_to_transit_hub_1" {
  name                  = "tunnel-edge-to-transit-hub-1"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.edge.id
  vpn_gateway_interface = 0
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.transit_hub.id
  shared_secret         = var.ha_vpn_psk
  router                = google_compute_router.edge.id
  ike_version           = 2
}

resource "google_compute_vpn_tunnel" "edge_to_transit_hub_2" {
  name                  = "tunnel-edge-to-transit-hub-2"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.edge.id
  vpn_gateway_interface = 1
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.transit_hub.id
  shared_secret         = var.ha_vpn_psk
  router                = google_compute_router.edge.id
  ike_version           = 2
}

# transit-hub → edge 
resource "google_compute_vpn_tunnel" "transit_hub_to_edge_1" {
  name                  = "tunnel-transit-hub-to-edge-1"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.transit_hub.id
  vpn_gateway_interface = 0
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.edge.id
  shared_secret         = var.ha_vpn_psk
  router                = google_compute_router.transit_hub.id
  ike_version           = 2
}

resource "google_compute_vpn_tunnel" "transit_hub_to_edge_2" {
  name                  = "tunnel-transit-hub-to-edge-2"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.transit_hub.id
  vpn_gateway_interface = 1
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.edge.id
  shared_secret         = var.ha_vpn_psk
  router                = google_compute_router.transit_hub.id
  ike_version           = 2
}


# -------------------------------------------------------
# BGP Sessions - edge 측 수동 설정
# per-peer Custom Advertisement로 192.168.1.0/24 추가
#
# transit-hub 측 BGP는 NCC Hub이 자동 관리 → 수동 설정 금지
# -------------------------------------------------------

# edge - interface 1
resource "google_compute_router_interface" "edge_if_1" {
  name       = "edge-if-1"
  router     = google_compute_router.edge.name
  region     = var.region
  ip_range   = "169.254.1.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.edge_to_transit_hub_1.name
}

resource "google_compute_router_peer" "edge_peer_1" {
  name                      = "bgp-edge-to-transit-hub-1"
  router                    = google_compute_router.edge.name
  region                    = var.region
  interface                 = google_compute_router_interface.edge_if_1.name
  peer_ip_address           = "169.254.1.2"
  peer_asn                  = 65002
  advertised_route_priority = 100

  # per-peer Custom Advertisement: on-prem 경로 추가
  advertise_mode    = "CUSTOM"
  advertised_groups = ["ALL_SUBNETS"]
  advertised_ip_ranges {
    range       = var.sim_onprem_cidr # 192.168.1.0/24
    description = "on-prem subnet"
  }
}

# edge - interface 2
resource "google_compute_router_interface" "edge_if_2" {
  name       = "edge-if-2"
  router     = google_compute_router.edge.name
  region     = var.region
  ip_range   = "169.254.2.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.edge_to_transit_hub_2.name
}

resource "google_compute_router_peer" "edge_peer_2" {
  name                      = "bgp-edge-to-transit-hub-2"
  router                    = google_compute_router.edge.name
  region                    = var.region
  interface                 = google_compute_router_interface.edge_if_2.name
  peer_ip_address           = "169.254.2.2"
  peer_asn                  = 65002
  advertised_route_priority = 100

  # per-peer Custom Advertisement: on-prem 경로 추가
  advertise_mode    = "CUSTOM"
  advertised_groups = ["ALL_SUBNETS"]
  advertised_ip_ranges {
    range       = var.sim_onprem_cidr # 192.168.1.0/24
    description = "on-prem subnet"
  }
}

# -------------------------------------------------------
# BGP Sessions - transit-hub 측 수동 설정
# tunnel-transit-hub-to-edge-1/2 에 BGP 세션 추가
# NCC Hybrid Spoke는 이 BGP 세션을 통해 경로를 학습
#
# BGP IP (edge 측과 반대):
#   Tunnel 1: transit-hub 169.254.1.2 ↔ edge 169.254.1.1
#   Tunnel 2: transit-hub 169.254.2.2 ↔ edge 169.254.2.1
# -------------------------------------------------------

# transit-hub - interface 1
resource "google_compute_router_interface" "transit_hub_if_1" {
  name       = "transit-hub-if-1"
  router     = google_compute_router.transit_hub.name
  region     = var.region
  ip_range   = "169.254.1.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.transit_hub_to_edge_1.name
}

resource "google_compute_router_peer" "transit_hub_peer_1" {
  name                      = "bgp-transit-hub-to-edge-1"
  router                    = google_compute_router.transit_hub.name
  region                    = var.region
  interface                 = google_compute_router_interface.transit_hub_if_1.name
  peer_ip_address           = "169.254.1.1"
  peer_asn                  = 65001
  advertised_route_priority = 100
}

# transit-hub - interface 2
resource "google_compute_router_interface" "transit_hub_if_2" {
  name       = "transit-hub-if-2"
  router     = google_compute_router.transit_hub.name
  region     = var.region
  ip_range   = "169.254.2.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.transit_hub_to_edge_2.name
}

resource "google_compute_router_peer" "transit_hub_peer_2" {
  name                      = "bgp-transit-hub-to-edge-2"
  router                    = google_compute_router.transit_hub.name
  region                    = var.region
  interface                 = google_compute_router_interface.transit_hub_if_2.name
  peer_ip_address           = "169.254.2.1"
  peer_asn                  = 65001
  advertised_route_priority = 100
}
