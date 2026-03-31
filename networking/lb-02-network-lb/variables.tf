variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "GCP 리전 (기본값: us-central1)"
  type        = string
  default     = "us-central1"
}
