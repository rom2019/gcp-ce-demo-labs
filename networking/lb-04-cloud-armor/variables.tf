variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
  default     = "lb-04-cloud-armor"
}

variable "region" {
  description = "배포 리전"
  type        = string
  default     = "us-central1"
}

variable "blocked_ip" {
  description = <<-EOT
    차단할 IP (blocklist 데모용)
    본인 IP 를 입력하면 접속 차단 테스트 가능:
      terraform apply -var='blocked_ip=<YOUR_IP>'
    기본값은 RFC 5737 TEST-NET (실제 트래픽 없음)
  EOT
  type    = string
  default = "192.0.2.1"
}
