variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "GCP 리전"
  type        = string
  default     = "asia-northeast3"
}

# GKE Autopilot이 pods를 배포하는 zone 목록
# NEG(Network Endpoint Group)는 zone 별로 생성되므로 조회에 필요
# null이면 region-a, b, c 를 자동으로 사용
variable "gke_zones" {
  description = "GKE 가용 영역 목록 (null이면 region-a/b/c 자동 사용)"
  type        = list(string)
  default     = null
}

locals {
  gke_zones = var.gke_zones != null ? var.gke_zones : [
    "${var.region}-a",
    "${var.region}-b",
    "${var.region}-c",
  ]
}
