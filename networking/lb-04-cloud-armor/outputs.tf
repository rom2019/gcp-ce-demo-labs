output "load_balancer_ip" {
  description = "Global LB IP (Cloud Armor 가 앞에서 보호)"
  value       = google_compute_global_forwarding_rule.web.ip_address
}

output "demo_url" {
  description = "WAF 데모 페이지 URL"
  value       = "http://${google_compute_global_forwarding_rule.web.ip_address}"
}

output "security_policy_name" {
  description = "Cloud Armor 보안 정책 이름"
  value       = google_compute_security_policy.main.name
}

output "mig_name" {
  description = "Backend MIG 이름"
  value       = google_compute_region_instance_group_manager.web.name
}

output "ssh_command" {
  description = "Backend VM IAP SSH 접속 명령"
  value       = "gcloud compute ssh <INSTANCE_NAME> --tunnel-through-iap --project=${var.project_id} --zone=<ZONE>"
}

output "blocked_ip" {
  description = "현재 차단 중인 IP (Rule 1000)"
  value       = var.blocked_ip
}
