output "gke_cluster_name" {
  description = "GKE 클러스터 이름"
  value       = google_container_cluster.producer.name
}

output "gke_get_credentials_cmd" {
  description = "kubectl 설정 명령어"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.producer.name} --region ${var.region} --project ${var.project_id}"
}

output "service_attachment_id" {
  description = "PSC Service Attachment URI (Consumer가 PSC endpoint 생성 시 사용)"
  value       = google_compute_service_attachment.producer_api.id
}

output "psc_endpoint_ip" {
  description = "PSC Endpoint IP - Test VM에서 이 IP로 curl 테스트"
  value       = google_compute_address.psc_endpoint.address
}

output "test_vm_ssh_cmd" {
  description = "Test VM SSH 접속 명령어 (IAP)"
  value       = "gcloud compute ssh consumer-test-vm --tunnel-through-iap --project=${var.project_id} --zone=${var.region}-a"
}

output "test_curl_cmd" {
  description = "PSC 연결 테스트 curl 명령어 (Test VM 내에서 실행)"
  value       = "curl http://${google_compute_address.psc_endpoint.address}"
}
