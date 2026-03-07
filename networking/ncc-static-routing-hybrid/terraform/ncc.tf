################################################################################
# ncc.tf
# NCC Hub (Mesh) + Spokes
#
# [Spoke 구성]
# 1. ncc-hybrid-spoke-transit-hub (Hybrid Spoke)
#    - tunnel-transit-hub-to-edge-1/2 터널 등록
#    - NCC Hub이 edge-cloud-router와 BGP → 192.168.1.0/24 학습
#    - Import filter: ALL_IPV4 → hub가 VPC Spoke 경로 수신
#
# 2. ncc-vpc-spoke-transit-hub (VPC Spoke)
#    - transit-hub-vpc NCC 등록
#
# 3. ncc-vpc-spoke-workload-test1 (VPC Spoke)
#    - workload-test1-vpc NCC 등록
#    - 추가 Spoke는 동일 패턴으로 확장
#
# [새 Spoke VPC 추가 시]
#   - NCC VPC Spoke 등록만 하면 자동 통신
#   - sim-onprem-vpc의 10.0.0.0/8 supernet이 자동 커버
#   - edge-cloud-router Custom Advertisement 수정 불필요
#   - Classic VPN tunnel 수정 불필요
################################################################################

resource "google_network_connectivity_hub" "main" {
  provider    = google-beta
  name        = "ncc-demo-hub"
  description = "Demo NCC Hub - on-prem static routing via Classic VPN + HA VPN Hybrid Spoke"

  preset_topology = "MESH"
}

# -------------------------------------------------------
# Spoke 1: Hybrid Spoke (transit-hub → edge 터널)
# NCC Hub이 edge-cloud-router와 BGP를 맺어 192.168.1.0/24 학습
# -------------------------------------------------------
resource "google_network_connectivity_spoke" "hybrid_transit_hub" {
  provider    = google-beta
  name        = "ncc-hybrid-spoke-transit-hub"
  location    = var.region
  hub         = google_network_connectivity_hub.main.id
  description = "Hybrid Spoke: NCC Hub peers with edge-cloud-router via transit-hub-to-edge tunnels"

  linked_vpn_tunnels {
    uris = [
      google_compute_vpn_tunnel.transit_hub_to_edge_1.self_link,
      google_compute_vpn_tunnel.transit_hub_to_edge_2.self_link,
    ]
    site_to_site_data_transfer = true
    # Import filter: NCC Hub로부터 VPC Spoke 경로(10.10.1.0/24, 10.20.1.0/24 등) 수신
    include_import_ranges = ["ALL_IPV4_RANGES"]
  }
}

# -------------------------------------------------------
# Spoke 2: transit-hub-vpc VPC Spoke
# -------------------------------------------------------
resource "google_network_connectivity_spoke" "vpc_transit_hub" {
  provider    = google-beta
  name        = "ncc-vpc-spoke-transit-hub"
  location    = "global"
  hub         = google_network_connectivity_hub.main.id
  description = "VPC Spoke: transit-hub-vpc"

  linked_vpc_network {
    uri = google_compute_network.transit_hub.self_link
  }
}

# -------------------------------------------------------
# Spoke 3: workload-test1-vpc VPC Spoke
# 추가 workload VPC는 동일 패턴으로 확장
# -------------------------------------------------------
resource "google_network_connectivity_spoke" "vpc_workload_test1" {
  provider    = google-beta
  name        = "ncc-vpc-spoke-workload-test1"
  location    = "global"
  hub         = google_network_connectivity_hub.main.id
  description = "VPC Spoke: workload-test1-vpc"
  linked_vpc_network {
    uri = google_compute_network.workload_test1.self_link
  }
}

