# =============================================================================
# Producer : Cloud SQL (PSC 모드)
# =============================================================================
# 핵심 설정:
#   psc_enabled = true
#     → Google 이 Service Attachment 를 자동 생성합니다.
#       직접 google_compute_service_attachment 를 만들 필요가 없습니다.
#       (psc-02 와의 가장 큰 차이점)
#
#   ipv4_enabled = false
#     → Public IP 를 완전히 차단합니다.
#       PSC 경로 외에는 접근 불가능합니다.
#
#   allowed_consumer_projects
#     → Consumer 프로젝트 번호를 등록하면,
#       해당 프로젝트에서 PSC Endpoint 를 생성하는 즉시 자동 수락됩니다.
#       (psc-02 의 ACCEPT_MANUAL / consumer_accept_lists 와 비교)
# =============================================================================

resource "google_sql_database_instance" "producer" {
  provider         = google.producer
  name             = "psc-01-sql"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = [var.consumer_project_number]
      }
      ipv4_enabled = false
    }

    backup_configuration {
      enabled = false
    }
  }

  deletion_protection = false

  # sqladmin API 가 활성화된 후 생성
  depends_on = [google_project_service.producer_sqladmin]
}

# -----------------------------------------------------------------------------
# Cloud SQL : postgres 사용자 비밀번호 설정
# -----------------------------------------------------------------------------
# 포인트:
#   google_sql_user 로 기본 postgres 유저의 비밀번호를 Terraform 에서 관리합니다.
#   비밀번호는 variables.tf 의 var.sql_password 로 주입합니다.
#   terraform.tfvars 에 평문으로 저장하지 말고 아래 중 하나를 권장합니다:
#     - Secret Manager 연동 (운영 환경)
#     - TF_VAR_sql_password 환경변수 사용 (학습 환경)
#       export TF_VAR_sql_password="your-password"

resource "google_sql_user" "postgres" {
  provider = google.producer
  name     = "postgres"
  instance = google_sql_database_instance.producer.name
  password = var.sql_password
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "service_attachment_uri" {
  description = <<-EOT
    Google 이 자동 생성한 Service Attachment URI.
    consumer.tf 의 google_compute_forwarding_rule.target 에 자동으로 참조됩니다.
    확인 명령어:
      gcloud sql instances describe psc-01-sql --project=<producer_project_id>
  EOT
  value       = google_sql_database_instance.producer.psc_service_attachment_link
}

output "sql_dns_name" {
  description = <<-EOT
    Cloud SQL PSC 전용 DNS 이름.
    dns.tf 의 google_dns_record_set.name 에 자동으로 참조됩니다.
    예시: abcd1234.xxxx.asia-northeast3.sql.goog.
  EOT
  value       = google_sql_database_instance.producer.dns_name
}
