terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ────────────────────────────────────────────────────────────────────
# 필수 API 활성화
# ────────────────────────────────────────────────────────────────────
locals {
  required_apis = [
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "container.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  service            = each.value
  disable_on_destroy = false
}

# ────────────────────────────────────────────────────────────────────
# 조직 정책 오버라이드
# ────────────────────────────────────────────────────────────────────
resource "google_project_organization_policy" "shielded_vm" {
  project    = var.project_id
  constraint = "constraints/compute.requireShieldedVm"
  boolean_policy {
    enforced = false
  }
}

resource "google_project_organization_policy" "lb_types" {
  project    = var.project_id
  constraint = "constraints/compute.restrictLoadBalancerCreationForTypes"
  list_policy {
    allow {
      all = true
    }
  }
}

resource "google_project_organization_policy" "require_os_login" {
  project    = var.project_id
  constraint = "constraints/compute.requireOsLogin"
  boolean_policy {
    enforced = false
  }
}
