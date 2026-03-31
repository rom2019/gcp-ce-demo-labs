output "psc_endpoint_ip" {
  description = "PSC vpc-sc endpoint IP (restricted.googleapis.com A 레코드 값)"
  value       = google_compute_global_address.psc_endpoint.address
}

output "gcs_bucket_name" {
  description = "VPC-SC 경계 안의 테스트 GCS 버킷"
  value       = google_storage_bucket.test.name
}

output "test_vm_ssh_cmd" {
  description = "Test VM SSH 접속 명령어 (IAP)"
  value       = "gcloud compute ssh psc-vpcsc-test-vm --tunnel-through-iap --project=${var.project_id} --zone=${var.region}-a"
}

output "test_inside_perimeter_cmd" {
  description = "[경계 안] VM에서 실행 - 성공해야 함"
  value       = "gcloud storage objects list gs://${google_storage_bucket.test.name}"
}

output "test_outside_perimeter_cmd" {
  description = "[경계 밖] 로컬에서 실행 - 403 반환해야 함"
  value       = "gcloud storage objects list gs://${google_storage_bucket.test.name} --project=${var.project_id}"
}

output "test_dns_cmd" {
  description = "DNS 확인 (VM 내에서 실행) - restricted.googleapis.com 경유 확인"
  value       = "nslookup storage.googleapis.com && nslookup restricted.googleapis.com"
}
