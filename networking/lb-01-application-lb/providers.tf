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
# 조직 정책: LB 타입 제한 해제 (EXTERNAL_MANAGED 허용)
#
# GCP 조직에 따라 constraints/compute.restrictLoadBalancerCreationForTypes
# 정책으로 GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS LB 생성이 차단될 수 있습니다.
#
# 이 리소스는 프로젝트 레벨에서 모든 LB 타입을 허용하도록 override 합니다.
# org 레벨 정책이 강제(enforced) 적용된 경우에는 override 가 불가하며,
# org 관리자에게 해당 constraint 해제를 요청해야 합니다.
#
# 필요 권한: roles/orgpolicy.policyAdmin (프로젝트 레벨)
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
