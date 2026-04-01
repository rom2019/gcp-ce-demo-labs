output "get_credentials_command" {
  description = "kubectl 자격증명 설정 명령어"
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region=${var.region} --project=${var.project_id}"
}

output "ingress_ip_command" {
  description = "Ingress 외부 IP 확인 명령어 (배포 후 실행)"
  value       = "kubectl get ingress demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
