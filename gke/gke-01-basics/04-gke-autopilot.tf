# ────────────────────────────────────────────────────────────────────
# Autopilot 클러스터
#
# Standard와의 핵심 차이:
#   - enable_autopilot = true 한 줄로 전환
#   - google_container_node_pool 리소스 불필요 (GCP가 자동 관리)
#   - 노드 머신 타입/개수 지정 불가
#   - Pod resource requests/limits 필수 (없으면 기본값 자동 적용)
# ────────────────────────────────────────────────────────────────────
resource "google_container_cluster" "autopilot" {
  name             = "gke-autopilot-cluster"
  location         = var.region
  enable_autopilot = true # 이 한 줄이 Standard와의 유일한 차이입니다

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.autopilot_subnet.id

  deletion_protection = false

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false          # 공개 엔드포인트 유지 (실습 접근용)
    master_ipv4_cidr_block  = "172.16.1.0/28" # Standard(172.16.0.0/28)와 겹치지 않게
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "ap-pods"
    services_secondary_range_name = "ap-services"
  }

  depends_on = [google_project_service.apis]
}
