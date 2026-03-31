output "load_balancer_ip" {
  description = "Network Load Balancer 외부 IP (VIP)"
  value       = google_compute_forwarding_rule.game.ip_address
}

output "game_server_url" {
  description = "게임 서버 상태 페이지 URL"
  value       = "http://${google_compute_forwarding_rule.game.ip_address}"
}

output "mig_name" {
  description = "Managed Instance Group 이름"
  value       = google_compute_region_instance_group_manager.game.name
}

output "ssh_command" {
  description = "IAP를 통한 SSH 접속 명령"
  value       = "gcloud compute ssh <INSTANCE_NAME> --tunnel-through-iap --project=${var.project_id} --zone=<ZONE>"
}
