# ============================================================
# Outputs
# ============================================================

output "psc_endpoint_ip" {
  description = "PSC Endpoint IP (hub-vpc)"
  value       = "10.0.1.2"
}

output "ssh_hub_vm" {
  description = "Hub VM SSH (IAP)"
  value       = "gcloud compute ssh hub-vm --zone=${var.region}-a --tunnel-through-iap --project=${var.project_id}"
}

output "ssh_dev_vm" {
  description = "Dev VM SSH (IAP)"
  value       = "gcloud compute ssh dev-vm --zone=${var.region}-a --tunnel-through-iap --project=${var.project_id}"
}

output "ssh_prod_vm" {
  description = "Prod VM SSH (IAP)"
  value       = "gcloud compute ssh prod-vm --zone=${var.region}-a --tunnel-through-iap --project=${var.project_id}"
}

output "test_scenario" {
  description = "DNS Hub 테스트 시나리오"
  value       = <<-EOT
    ============================================================
    [테스트 시나리오]

    1. DNS 해석 확인 (각 VM 에서 실행):
       nslookup storage.googleapis.com
       → 기대값: 10.0.1.2 (hub-vpc 의 PSC endpoint IP)

       nslookup bigquery.googleapis.com
       → 기대값: 10.0.1.2 (wildcard *.googleapis.com 적용)

    2. DNS Hub 효과 검증:
       - hub-vpc 의 zone (googleapis-hub) 만 존재
       - dev-vpc, prod-vpc 는 DNS Peering 으로 hub zone 참조
       - zone 변경 시 모든 spoke 에 자동 반영

    3. 신규 spoke 추가 시:
       - 03-spoke-prod-vpc.tf 를 복사해서 이름/IP 만 변경
       - VPC Peering + DNS Peering zone 만 추가하면 완료
    ============================================================
  EOT
}
