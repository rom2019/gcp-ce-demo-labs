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
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  service            = each.value
  disable_on_destroy = false
}

# ────────────────────────────────────────────────────────────────────
# 조직 정책: Shielded VM 요구 비활성화 (실습 편의)
# ────────────────────────────────────────────────────────────────────
resource "google_project_organization_policy" "shielded_vm" {
  project    = var.project_id
  constraint = "constraints/compute.requireShieldedVm"
  boolean_policy {
    enforced = false
  }
}

# ────────────────────────────────────────────────────────────────────
# 조직 정책: LB 타입 제한 해제
#
# constraints/compute.restrictLoadBalancerCreationForTypes 정책으로
# 특정 LB 타입이 차단된 경우 프로젝트 레벨에서 override 시도.
# org 레벨 강제 적용(enforced) 시에는 org 관리자에게 요청 필요.
# ────────────────────────────────────────────────────────────────────
resource "google_project_organization_policy" "lb_types" {
  project    = var.project_id
  constraint = "constraints/compute.restrictLoadBalancerCreationForTypes"
  list_policy {
    allow {
      all = true
    }
  }
}
