# GKE는 Pod/Service IP를 위해 서브넷에 Secondary IP Range가 반드시 필요합니다.
# Secondary range 없이 클러스터를 생성하면 "ip_allocation_policy required" 오류가 발생합니다.
resource "google_compute_network" "vpc" {
  name                    = "gke-basics-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

# ── Standard 클러스터용 서브넷 ──────────────────────────────────────────
resource "google_compute_subnetwork" "gke_subnet" {
  name          = "gke-standard-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  # Pod IP 대역 — 노드당 /24 블록이 할당됩니다 (/16 → 최대 256개 노드)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.100.0.0/16"
  }

  # Service ClusterIP 대역
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.101.0.0/20"
  }
}

# ── Autopilot 클러스터용 서브넷 ────────────────────────────────────────
# Autopilot도 동일하게 Secondary range가 필요합니다.
# IP 대역이 Standard와 겹치지 않도록 별도 서브넷을 사용합니다.
resource "google_compute_subnetwork" "autopilot_subnet" {
  name          = "gke-autopilot-subnet"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "ap-pods"
    ip_cidr_range = "10.110.0.0/16"
  }

  secondary_ip_range {
    range_name    = "ap-services"
    ip_cidr_range = "10.111.0.0/20"
  }
}

# Private 노드가 외부 인터넷(컨테이너 이미지 pull 등)에 접근하려면 Cloud NAT가 필요합니다.
# ALL_SUBNETWORKS 설정으로 Standard/Autopilot 양쪽 서브넷 모두 커버합니다.
resource "google_compute_router" "router" {
  name    = "gke-basics-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "gke-basics-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
