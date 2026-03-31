variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "org_id" {
  description = "GCP 조직 ID (VPC-SC Access Policy 생성에 필요)"
  type        = string
}

variable "region" {
  description = "GCP 리전"
  type        = string
  default     = "us-central1"
}
