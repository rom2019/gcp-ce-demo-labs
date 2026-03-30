# ============================================================
# [01] Producer VPC
# ============================================================
# Console 확인: VPC network > VPC networks
# ============================================================

resource "google_compute_network" "producer" {
  name                    = "producer-vpc"
  auto_create_subnetworks = false
}

# GKE 노드/파드/서비스용 서브넷
resource "google_compute_subnetwork" "producer_gke" {
  name          = "producer-gke-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.producer.id

  # GKE Pod IP 대역 (secondary range)
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  # GKE Service(ClusterIP) IP 대역 (secondary range)
  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.30.0.0/16"
  }

  private_ip_google_access = true
}

# PSC NAT 서브넷 (Service Attachment 전용)
# - Consumer → Service Attachment 연결 시 이 서브넷 IP를 SNAT 주소로 사용
# - purpose = "PRIVATE_SERVICE_CONNECT" 로 반드시 지정
# - /28 이면 충분 (최소 권장)
# Console 확인: VPC network > VPC networks > producer-vpc > Subnets 탭
resource "google_compute_subnetwork" "producer_psc_nat" {
  name          = "producer-psc-nat-subnet"
  ip_cidr_range = "10.100.0.0/28"
  region        = var.region
  network       = google_compute_network.producer.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

# Cloud Router (NAT 없이 Private GKE 노드의 아웃바운드 트래픽 처리)
resource "google_compute_router" "producer" {
  name    = "producer-router"
  region  = var.region
  network = google_compute_network.producer.id
}

resource "google_compute_router_nat" "producer" {
  name                               = "producer-nat"
  router                             = google_compute_router.producer.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
