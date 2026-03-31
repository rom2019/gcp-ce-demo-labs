output "frontend_external_ip" {
  description = "Frontend VM 외부 IP (데모 페이지 접속)"
  value       = try(google_compute_instance.frontend.network_interface[0].access_config[0].nat_ip, "pending")
}

output "demo_url" {
  description = "마이크로서비스 데모 페이지 URL"
  value       = try("http://${google_compute_instance.frontend.network_interface[0].access_config[0].nat_ip}", "pending")
}

output "internal_lb_ip" {
  description = "Internal LB VIP (Private IP — VPC 내부에서만 접근 가능)"
  value       = google_compute_forwarding_rule.internal.ip_address
}

output "mig_name" {
  description = "Backend API MIG 이름"
  value       = google_compute_region_instance_group_manager.backend.name
}

output "frontend_ssh_command" {
  description = "Frontend VM IAP SSH 접속 명령"
  value       = "gcloud compute ssh frontend-service --tunnel-through-iap --project=${var.project_id} --zone=${var.region}-a"
}

output "backend_ssh_command" {
  description = "Backend VM IAP SSH 접속 명령"
  value       = "gcloud compute ssh <BACKEND_INSTANCE_NAME> --tunnel-through-iap --project=${var.project_id} --zone=<ZONE>"
}
