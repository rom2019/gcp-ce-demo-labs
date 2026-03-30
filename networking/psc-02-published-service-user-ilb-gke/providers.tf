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

# 필요한 GCP API 활성화
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",
    "iap.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Org Policy: Shielded VM 강제 비활성화
# GKE Autopilot 노드 생성 시 Shielded VM 정책 충돌 방지
resource "google_project_organization_policy" "shielded_vm" {
  project    = var.project_id
  constraint = "constraints/compute.requireShieldedVm"

  boolean_policy {
    enforced = false
  }
}

# GKE 클러스터 생성 후 kubernetes provider 가 활성화됨
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.producer.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.producer.master_auth[0].cluster_ca_certificate)
}
