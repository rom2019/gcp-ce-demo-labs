# ============================================================
# [02] Producer GKE Cluster (Autopilot)
# ============================================================
# Console 확인: Kubernetes Engine > Clusters
# ============================================================

resource "google_container_cluster" "producer" {
  name     = "producer-gke"
  location = var.region

  # Autopilot: 노드 관리를 GCP가 담당 (학습에 집중하기 좋음)
  enable_autopilot = true

  network    = google_compute_network.producer.id
  subnetwork = google_compute_subnetwork.producer_gke.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Private 노드 + Public API endpoint
  # - enable_private_nodes: 노드에 외부 IP 없음 (Cloud NAT로 아웃바운드)
  # - enable_private_endpoint: false → kubectl을 외부에서 사용 가능
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  deletion_protection = false
}
