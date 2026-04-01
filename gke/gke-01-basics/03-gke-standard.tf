# 노드 전용 서비스 계정 — 최소 권한 원칙 적용
# 기본 Compute SA는 Editor 권한을 가지므로 프로덕션에서는 절대 사용하면 안 됩니다.
resource "google_service_account" "gke_node" {
  account_id   = "gke-node-sa"
  display_name = "GKE Node Service Account"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

# Regional 클러스터 — location에 region을 지정하면 3개 존에 컨트롤 플레인이 분산됩니다.
# zone을 지정하면 Zonal 클러스터가 되어 컨트롤 플레인이 단일 장애점이 됩니다.
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region # region → Regional cluster (HA)

  # 기본 노드 풀은 커스텀 노드 풀로 대체합니다.
  # 기본 풀을 남겨두면 불필요한 비용이 발생합니다.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.gke_subnet.id

  # 실습 환경에서는 terraform destroy를 쉽게 하기 위해 비활성화
  deletion_protection = false

  private_cluster_config {
    enable_private_nodes    = true  # 노드에 외부 IP 없음 → NAT로 아웃바운드
    enable_private_endpoint = false # 컨트롤 플레인 엔드포인트는 공개 (실습 접근용)
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.gke_node_roles,
  ]
}

# 커스텀 노드 풀 — 노드 사양과 개수를 독립적으로 관리합니다.
resource "google_container_node_pool" "primary_nodes" {
  name    = "primary-pool"
  cluster = google_container_cluster.primary.id

  # Regional 클러스터에서 node_count는 zone당 개수입니다.
  # node_count=2, region=us-central1 → 3 zones × 2 = 총 6개 노드
  node_count = var.node_count

  node_config {
    machine_type    = "e2-medium" # 2 vCPU, 4GB RAM — 입문 실습에 적합
    service_account = google_service_account.gke_node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Workload Identity: Pod가 KSA를 통해 GCP API에 접근 (키 파일 불필요)
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
