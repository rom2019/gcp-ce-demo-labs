# 03_nat.tf

# ── Cloud NAT ─────────────────────────────────────────
resource "google_compute_router_nat" "main" {
  name   = "nat-network-lab"
  router = google_compute_router.main.name
  region = var.region

  # 공인 IP를 GCP가 자동 할당 (고정 IP 불필요)
  nat_ip_allocate_option = "AUTO_ONLY"

  # 모든 서브넷의 VM에 NAT 적용
  # source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # 전체 서브넷 대신 특정 서브넷만 NAT 적용
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  # public, private 만 NAT 적용 (data 제외)
  subnetwork {
    name                    = google_compute_subnetwork.public.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  # NAT 로그 활성화 (트러블슈팅용)
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}