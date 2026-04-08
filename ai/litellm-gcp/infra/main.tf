terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─────────────────────────────────────────
# APIs 활성화
# ─────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ─────────────────────────────────────────
# Artifact Registry
# ─────────────────────────────────────────
resource "google_artifact_registry_repository" "litellm" {
  repository_id = "litellm"
  location      = var.region
  format        = "DOCKER"
  description   = "LiteLLM proxy Docker images"
  depends_on    = [google_project_service.apis]
}



# ─────────────────────────────────────────
# Service Account (Cloud Run용)
# ─────────────────────────────────────────
resource "google_service_account" "litellm_runner" {
  account_id   = "litellm-runner"
  display_name = "LiteLLM Cloud Run SA"
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.litellm_runner.email}"
}

resource "google_project_iam_member" "vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.litellm_runner.email}"
}

# ─────────────────────────────────────────
# Cloud Build SA 권한 (terraform apply로 한번에 처리)
# ─────────────────────────────────────────
data "google_project" "project" {}

locals {
  cb_sa = "${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "cb_run_admin" {
  project    = var.project_id
  role       = "roles/run.admin"
  member     = "serviceAccount:${local.cb_sa}"
  depends_on = [google_project_service.apis]
}

resource "google_service_account_iam_member" "cb_sa_user" {
  service_account_id = google_service_account.litellm_runner.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.cb_sa}"
}

# ─────────────────────────────────────────
# Secrets
# ─────────────────────────────────────────
resource "google_secret_manager_secret" "litellm_master_key" {
  secret_id = "litellm-master-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "litellm_master_key" {
  secret      = google_secret_manager_secret.litellm_master_key.id
  secret_data = var.litellm_master_key
}

resource "google_secret_manager_secret" "anthropic_api_key" {
  count     = var.anthropic_api_key != "" ? 1 : 0
  secret_id = "anthropic-api-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "anthropic_api_key" {
  count       = var.anthropic_api_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.anthropic_api_key[0].id
  secret_data = var.anthropic_api_key
}

resource "google_secret_manager_secret" "openai_api_key" {
  count     = var.openai_api_key != "" ? 1 : 0
  secret_id = "openai-api-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "openai_api_key" {
  count       = var.openai_api_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.openai_api_key[0].id
  secret_data = var.openai_api_key
}

# ─────────────────────────────────────────
# NOTE: Cloud Run은 Terraform이 관리하지 않습니다.
# Cloud Run은 이미지가 Artifact Registry에 존재해야 생성 가능한데,
# 이미지는 Cloud Build가 만들기 때문에 순환 의존성이 발생합니다.
# → cloudbuild.yaml이 이미지 빌드 후 Cloud Run을 직접 생성/배포합니다.
# ─────────────────────────────────────────


# 1. Cloud Build 전용 서비스 계정 생성
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "litellm-cloudbuild-sa"
  display_name = "LiteLLM Cloud Build Service Account"
}

# 2. 빌드에 필요한 권한 부여 (이미지 푸시, 로그 기록 등)
resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/logging.logWriter",         # 빌드 로그 기록
    "roles/artifactregistry.writer",  # 이미지 푸시
    "roles/run.developer",            # Cloud Run 배포 권한
    "roles/iam.serviceAccountUser"    # 서비스 계정 사용 권한
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# 3. 소스 코드(GCS)를 읽기 위한 권한 추가 (에러 해결 핵심)
resource "google_project_iam_member" "storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}