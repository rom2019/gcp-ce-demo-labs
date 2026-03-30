terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# GKE 클러스터 생성 후 kubernetes provider 가 활성화됨
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.producer.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.producer.master_auth[0].cluster_ca_certificate)
}
