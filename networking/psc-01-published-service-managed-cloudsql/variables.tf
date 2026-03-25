variable "producer_project_id" {
  description = "Cloud SQL 인스턴스를 생성할 GCP 프로젝트 ID"
  type        = string
}

variable "consumer_project_id" {
  description = "PSC Endpoint 및 클라이언트 앱을 생성할 GCP 프로젝트 ID"
  type        = string
}

variable "consumer_project_number" {
  description = "Cloud SQL allowed_consumer_projects 에 등록할 consumer 프로젝트 번호"
  type        = string
}

variable "region" {
  description = "GCP 리전"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "테스트 VM 을 생성할 GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "sql_password" {
  description = <<-EOT
    Cloud SQL postgres 사용자 비밀번호.
    terraform.tfvars 에 평문 저장 대신 환경변수 사용을 권장합니다:
      export TF_VAR_sql_password="your-password"
  EOT
  type        = string
  sensitive   = true
}
