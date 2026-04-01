variable "project_id" {
  type        = string
  description = "GCP project ID — pass with -var or terraform.tfvars. No default: prevents silent deploys to wrong project."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "cluster_name" {
  type        = string
  default     = "gke-basics-cluster"
  description = "GKE 클러스터 이름"
}

variable "node_count" {
  type        = number
  default     = 2
  description = "노드 풀의 존(zone)당 노드 수"
}
