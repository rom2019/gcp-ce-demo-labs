# ============================================================
# [01] VPC
# ============================================================
# Console 확인: VPC network > VPC networks
# ============================================================

resource "google_compute_network" "vpc" {
  name                    = "psc-google-apis-vpc"
  auto_create_subnetworks = false

  depends_on = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "psc-google-apis-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  # PSC endpoint로 트래픽이 라우팅되므로 private_ip_google_access 는 불필요
  # 명시적으로 false 로 설정해서 PSC 가 유일한 Google API 접근 경로임을 확인
  private_ip_google_access = false
}

# Test VM 에서 패키지 설치 등 인터넷 접근이 필요한 경우를 위한 Cloud NAT
resource "google_compute_router" "router" {
  name    = "psc-google-apis-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "psc-google-apis-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
