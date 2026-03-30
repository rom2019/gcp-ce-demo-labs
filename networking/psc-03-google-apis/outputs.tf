output "psc_endpoint_ip" {
  description = "PSC Google APIs endpoint IP (DNS A 레코드 값)"
  value       = google_compute_global_address.psc_endpoint.address
}

output "test_vm_ssh_cmd" {
  description = "Test VM SSH 접속 명령어 (IAP)"
  value       = "gcloud compute ssh psc-test-vm --tunnel-through-iap --project=${var.project_id} --zone=${var.region}-a"
}

output "test_dns_cmd" {
  description = "DNS 확인 명령어 (VM 내에서 실행) - PSC endpoint IP 가 응답으로 와야 함"
  value       = "dig storage.googleapis.com"
}

output "test_gcs_cmd" {
  description = "GCS 접근 테스트 명령어 (VM 내에서 실행)"
  value       = "gsutil ls"
}

output "test_curl_cmd" {
  description = "curl 로 GCS API 직접 호출 (VM 내에서 실행)"
  value       = "curl -H \"Authorization: Bearer $(gcloud auth print-access-token)\" https://storage.googleapis.com/storage/v1/b?project=${var.project_id}"
}
