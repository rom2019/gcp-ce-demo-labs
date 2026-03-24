# 05_database.tf

# ── Cloud SQL PostgreSQL ───────────────────────────────
resource "google_sql_database_instance" "main" {
  name             = "sql-network-lab"
  database_version = "POSTGRES_15"
  region           = var.region

  # terraform destroy 시 삭제 가능하도록 (학습용)
  deletion_protection = false

  settings {
    tier = "db-f1-micro" # 학습용 최소 사양

    # ── Private IP 설정 (PSA) ──────────────────────────
    ip_configuration {
      ipv4_enabled                                  = false # 공인 IP 차단
      private_network                               = google_compute_network.main.id
      enable_private_path_for_google_cloud_services = true

      # PSC 활성화 추가
      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = [var.project_id]
      }
    }



    backup_configuration {
      enabled = false # 학습용이라 백업 비활성화
    }

    availability_type = "ZONAL" # 학습용 단일 존 (프로덕션은 REGIONAL)
  }

  depends_on = [google_service_networking_connection.psa_connection]
}

# ── Cloud SQL Database ─────────────────────────────────
resource "google_sql_database" "main" {
  name     = "labdb"
  instance = google_sql_database_instance.main.name
}

# ── Cloud SQL User ─────────────────────────────────────
resource "google_sql_user" "main" {
  name     = "labuser"
  instance = google_sql_database_instance.main.name
  password = var.db_password
}

# ── Memorystore Redis ──────────────────────────────────
resource "google_redis_instance" "main" {
  name           = "redis-network-lab"
  tier           = "BASIC" # 학습용 (프로덕션은 STANDARD_HA)
  memory_size_gb = 1
  region         = var.region

  # ── Private IP 설정 (PSA) ──────────────────────────
  location_id        = var.zone
  authorized_network = google_compute_network.main.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  reserved_ip_range  = google_compute_global_address.psa_range.name

  redis_version = "REDIS_7_0"

  depends_on = [google_service_networking_connection.psa_connection]
}