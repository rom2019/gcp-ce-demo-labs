# ── Standard 클러스터 ────────────────────────────────────────────────
output "standard_cluster_name" {
  description = "Standard 클러스터 이름"
  value       = google_container_cluster.primary.name
}

output "standard_get_credentials" {
  description = "Standard 클러스터 kubectl 자격증명 설정"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region=${var.region} --project=${var.project_id}"
}

# ── Autopilot 클러스터 ───────────────────────────────────────────────
output "autopilot_cluster_name" {
  description = "Autopilot 클러스터 이름"
  value       = google_container_cluster.autopilot.name
}

output "autopilot_get_credentials" {
  description = "Autopilot 클러스터 kubectl 자격증명 설정"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.autopilot.name} --region=${var.region} --project=${var.project_id}"
}

# ── 비교 참고 ────────────────────────────────────────────────────────
output "comparison_note" {
  description = "두 클러스터 비교 포인트"
  value       = "Standard: node_count=${var.node_count}/zone × 3 zones = ${var.node_count * 3} nodes visible | Autopilot: kubectl get nodes → GCP 관리 노드 (Pod 배포 전 0개)"
}
