# =============================================================================
# PSC-01 : Published Service — GCP Managed (Cloud SQL)
# =============================================================================
# 목적:
#   Google 이 Service Attachment 를 자동 생성하는 Managed 서비스(Cloud SQL)를
#   PSC 로 연결하는 가장 기본적인 패턴을 실습합니다.
#
# 학습 포인트:
#   - PSC Endpoint (Forwarding Rule) 의 load_balancing_scheme = "" 의미
#   - Cloud SQL PSC 모드에서 Service Attachment URI 를 직접 만들지 않고 조회하는 방법
#   - allowed_consumer_projects 로 자동 수락되는 흐름
#   - Private DNS zone 으로 hostname 접근하는 방법
#
# 리소스 구성:
#   Producer (producer_project):
#     - google_project_service         (API 활성화)
#     - google_sql_database_instance   (PSC 모드, public IP 없음)
#   Consumer (consumer_project):
#     - google_project_service         (API 활성화)
#     - google_compute_network
#     - google_compute_subnetwork
#     - google_compute_address         (PSC Endpoint 전용 내부 IP)
#     - google_compute_forwarding_rule (PSC Endpoint)
#     - google_dns_managed_zone        (Private DNS)
#     - google_dns_record_set
# =============================================================================

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Producer 프로젝트용 provider
provider "google" {
  alias   = "producer"
  project = var.producer_project_id
  region  = var.region
}

# Consumer 프로젝트용 provider
provider "google" {
  alias   = "consumer"
  project = var.consumer_project_id
  region  = var.region
}

# =============================================================================
# API 활성화
# =============================================================================
# disable_on_destroy = false
#   → terraform destroy 시 API 를 비활성화하지 않습니다.
#     다른 리소스가 같은 API 를 사용 중일 수 있기 때문에 기본값으로 권장합니다.

# Producer 프로젝트 — Cloud SQL API
resource "google_project_service" "producer_sqladmin" {
  provider           = google.producer
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

# Consumer 프로젝트 — Compute Engine API (VPC, Forwarding Rule)
resource "google_project_service" "consumer_compute" {
  provider           = google.consumer
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Consumer 프로젝트 — Cloud DNS API (Private DNS Zone)
resource "google_project_service" "consumer_dns" {
  provider           = google.consumer
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}



# ── Organization Policy  ─────────────────────────────────────────
resource "google_project_organization_policy" "shielded_vm" {
  project    = var.producer_project_id
  constraint = "constraints/compute.requireShieldedVm"

  boolean_policy {
    enforced = false
  }
}