output "artifact_registry_repo" {
  description = "Docker 이미지 푸시 경로 (Cloud Build에서 사용)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/litellm/proxy"
}

output "service_account_email" {
  description = "Cloud Run 서비스 계정"
  value       = google_service_account.litellm_runner.email
}

output "cloud_build_sa" {
  description = "Cloud Build 서비스 계정 (권한 확인용)"
  value       = local.cb_sa
}

output "next_step" {
  description = "Terraform 완료 후 실행할 명령"
  value       = "gcloud builds submit --config cloudbuild.yaml ."
}
