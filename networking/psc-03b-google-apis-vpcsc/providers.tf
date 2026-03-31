terraform {
  required_version = ">= 1.9"

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

  # 조직 레벨 API (accesscontextmanager 등) 사용 시 quota project 명시 필요
  user_project_override = true
  billing_project       = var.project_id
}

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "dns.googleapis.com",
    "storage.googleapis.com",
    "iap.googleapis.com",
    "accesscontextmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# API 활성화 후 전파 대기
resource "time_sleep" "api_propagation" {
  create_duration = "60s"
  depends_on      = [google_project_service.apis]
}

resource "google_project_organization_policy" "shielded_vm" {
  project    = var.project_id
  constraint = "constraints/compute.requireShieldedVm"

  boolean_policy {
    enforced = false
  }
}
