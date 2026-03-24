# 04_psa.tf

# ── PSA 전용 IP 범위 예약 ──────────────────────────────
# Cloud SQL, Memorystore 가 이 범위에서 Private IP 를 받아감
resource "google_compute_global_address" "psa_range" {
  name          = "psa-range-network-lab"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = split("/", var.subnets["psa"])[1] # "16"
  address       = split("/", var.subnets["psa"])[0] # "10.100.0.0"
  network       = google_compute_network.main.id
}

# ── Google 서비스 테넌트 VPC 와 Peering ────────────────
# 이 Peering 을 통해 Cloud SQL 인스턴스가
# 10.100.x.x 대역 IP 를 받고 내 VM 과 통신
resource "google_service_networking_connection" "psa_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]
  depends_on              = [google_project_service.servicenetworking]
}