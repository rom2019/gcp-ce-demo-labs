variable "project_id" {
  type        = string
  description = "GCP project ID — pass with -var or terraform.tfvars. No default: prevents silent deploys to wrong project."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "cluster_name" {
  type    = string
  default = "gke-ingress-cluster"
}
