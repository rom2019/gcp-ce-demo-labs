# ============================================================
# Outputs
# ============================================================

# Producer VM 접속 명령어
output "ssh_producer_vm" {
  description = "Producer VM SSH (IAP)"
  value       = "gcloud compute ssh producer-vm --zone=${var.region}-a --tunnel-through-iap --project=${var.project_id}"
}

# Consumer VM 접속 명령어
output "ssh_consumer_a_vm" {
  description = "Consumer-A VM SSH (IAP)"
  value       = "gcloud compute ssh consumer-a-vm --zone=${var.region}-a --tunnel-through-iap --project=${var.project_id}"
}

output "ssh_consumer_b_vm" {
  description = "Consumer-B VM SSH (IAP)"
  value       = "gcloud compute ssh consumer-b-vm --zone=${var.region}-a --tunnel-through-iap --project=${var.project_id}"
}

# Producer NIC IP 확인 명령어
# nic1 = Consumer-A 서브넷 IP, nic2 = Consumer-B 서브넷 IP
output "get_producer_nic_ips" {
  description = "Producer VM 의 NIC IP 확인 (nic1=consumer-a, nic2=consumer-b)"
  value       = "gcloud compute instances describe producer-vm --zone=${var.region}-a --project=${var.project_id} --format='table(networkInterfaces[].networkIP)'"
}

# 테스트 시나리오 안내
output "test_scenario" {
  description = "연결 테스트 시나리오"
  value       = <<-EOT
    ============================================================
    [테스트 시나리오]

    1. Producer NIC IP 확인:
       ${format("gcloud compute instances describe producer-vm --zone=%s-a --project=%s --format='table(networkInterfaces[].networkIP)'", var.region, var.project_id)}

    2. Consumer → Producer (nginx 응답 확인):
       # consumer-a-vm 에서 실행
       curl http://<producer-nic1-ip>   → "Hello from Producer VM (PSC Interface)"

       # consumer-b-vm 에서 실행
       curl http://<producer-nic2-ip>   → "Hello from Producer VM (PSC Interface)"

    3. Producer → Consumer (양방향 확인):
       # producer-vm 에서 실행
       ping <consumer-a-vm-ip>
       ping <consumer-b-vm-ip>
    ============================================================
  EOT
}
