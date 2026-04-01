# 이 실습의 핵심은 Ingress 개념이므로 클러스터 운영 부담이 적은 Autopilot 사용
# 노드 관리 없이 k8s 리소스(Deployment, Service, Ingress)에만 집중할 수 있습니다.
resource "google_container_cluster" "primary" {
  name             = var.cluster_name
  location         = var.region
  enable_autopilot = true

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  deletion_protection = false

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  depends_on = [google_project_service.apis]
}
