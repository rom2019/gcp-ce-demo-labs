# 10_psc.tf

# ── Cloud SQL PSC 엔드포인트 ───────────────────────────
# Cloud SQL 인스턴스의 PSC 서비스 연결 이름 가져오기
data "google_sql_database_instance" "main" {
  name = google_sql_database_instance.main.name
}

# ── PSC용 내부 IP 예약 ─────────────────────────────────
resource "google_compute_address" "psc_sql" {
  name         = "psc-sql-endpoint"
  region       = var.region
  subnetwork   = google_compute_subnetwork.private.id
  address_type = "INTERNAL"
  address      = "10.0.2.200" # subnet-private 안의 고정 IP
}

# ── PSC Forwarding Rule (엔드포인트 생성) ──────────────
resource "google_compute_forwarding_rule" "psc_sql" {
  name                  = "psc-sql-forwarding-rule"
  region                = var.region
  network               = google_compute_network.main.id
  subnetwork            = google_compute_subnetwork.private.id
  ip_address            = google_compute_address.psc_sql.id
  load_balancing_scheme = "" # PSC는 빈 문자열
  target                = data.google_sql_database_instance.main.psc_service_attachment_link
}
