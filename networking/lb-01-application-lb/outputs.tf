output "load_balancer_ip" {
  description = "Application Load Balancer 외부 IP 주소"
  value       = google_compute_global_forwarding_rule.shop.ip_address
}

output "shop_url" {
  description = "쇼핑몰 접속 URL"
  value       = "http://${google_compute_global_forwarding_rule.shop.ip_address}"
}

output "mig_name" {
  description = "Managed Instance Group 이름"
  value       = google_compute_region_instance_group_manager.shop.name
}

output "ssh_command" {
  description = "IAP를 통한 인스턴스 SSH 접속 명령 (인스턴스명은 GCP 콘솔에서 확인)"
  value       = "gcloud compute ssh <INSTANCE_NAME> --tunnel-through-iap --project=${var.project_id} --zone=<ZONE>"
}
