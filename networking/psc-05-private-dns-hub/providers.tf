# ============================================================
# Bootstrap: terraform apply 전 아래 명령어 선행 실행 필요
#   gcloud services enable cloudresourcemanager.googleapis.com iam.googleapis.com \
#     --project=psc-05-private-dns-hub
# ============================================================

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# API 활성화
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "dns.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# API 전파 대기 (60초)
resource "time_sleep" "api_propagation" {
  create_duration = "60s"
  depends_on      = [google_project_service.apis]
}

# Org Policy: Shielded VM 비활성화 (학습용)
resource "google_project_organization_policy" "shielded_vm" {
  project    = var.project_id
  constraint = "constraints/compute.requireShieldedVm"

  boolean_policy {
    enforced = false
  }
}
