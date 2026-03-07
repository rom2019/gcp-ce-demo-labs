################################################################################
# vpc.tf
#
# [계층 구조]
#   sim-onprem-vpc     192.168.1.0/24  On-prem 시뮬레이션
#   edge-vpc           172.16.1.0/24   Edge Layer (Classic VPN 종단)
#   transit-hub-vpc    10.10.1.0/24    Hub Layer  (NCC 중심, 라우팅 전담)
#   workload-test1-vpc 10.20.1.0/24   Spoke Layer (테스트 워크로드)
################################################################################

# -------------------------------------------------------
# On-prem Simulation
# -------------------------------------------------------
resource "google_compute_network" "sim_onprem" {
  name                    = "sim-onprem-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "[Simulation] Represents on-premises network with static routing only"
  depends_on              = [google_project_service.compute]
}

resource "google_compute_subnetwork" "sim_onprem" {
  name          = "sim-onprem-subnet"
  network       = google_compute_network.sim_onprem.id
  region        = var.region
  ip_cidr_range = var.sim_onprem_cidr
}

# -------------------------------------------------------
# Edge Layer - Classic VPN 종단, on-prem 연결 전담
# -------------------------------------------------------
resource "google_compute_network" "edge" {
  name                    = "edge-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "[Edge Layer] Classic VPN termination - on-prem connectivity"
}

resource "google_compute_subnetwork" "edge" {
  name          = "edge-subnet"
  network       = google_compute_network.edge.id
  region        = var.region
  ip_cidr_range = var.edge_cidr
}

# -------------------------------------------------------
# Hub Layer - NCC 중심, 클라우드 내부 라우팅 전담
# -------------------------------------------------------
resource "google_compute_network" "transit_hub" {
  name                    = "transit-hub-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "[Hub Layer] NCC transit hub - cloud internal routing"
}

resource "google_compute_subnetwork" "transit_hub" {
  name          = "transit-hub-subnet"
  network       = google_compute_network.transit_hub.id
  region        = var.region
  ip_cidr_range = var.transit_hub_cidr
}

# -------------------------------------------------------
# Spoke Layer - 실제 워크로드
# workload-prod1-vpc 추가 시 동일 패턴으로 확장
# -------------------------------------------------------
resource "google_compute_network" "workload_test1" {
  name                    = "workload-test1-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "[Spoke Layer] Test workload VPC - NCC VPC Spoke"
}

resource "google_compute_subnetwork" "workload_test1" {
  name          = "workload-test1-subnet"
  network       = google_compute_network.workload_test1.id
  region        = var.region
  ip_cidr_range = var.workload_test1_cidr
}
