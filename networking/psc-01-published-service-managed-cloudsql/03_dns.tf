# =============================================================================
# Consumer : Private DNS Zone + A Record
# =============================================================================
# 목적:
#   Cloud SQL 의 PSC 전용 DNS 이름(sql_dns_name)을
#   PSC Endpoint IP 로 해석하도록 Private DNS Zone 을 구성합니다.
#
# 흐름:
#   클라이언트 → DNS 쿼리(sql_dns_name)
#             → Private Zone 에서 A record 조회
#             → PSC Endpoint IP 반환
#             → PSC 터널을 통해 Cloud SQL 도달
#
# 참고:
#   dns_name = "sql.goog." 으로 zone 을 생성하면
#   *.sql.goog 형태의 모든 Cloud SQL PSC DNS 이름을 이 zone 에서 처리합니다.
# =============================================================================

resource "google_dns_managed_zone" "psc_sql" {
  provider    = google.consumer
  name        = "psc-01-sql-zone"
  dns_name    = "sql.goog."
  description = "PSC-01 : Cloud SQL PSC 전용 Private DNS Zone"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.consumer.id
    }
  }

  depends_on = [google_project_service.consumer_dns]
}

resource "google_dns_record_set" "psc_sql" {
  provider = google.consumer
  # Cloud SQL 이 제공하는 PSC 전용 DNS 이름을 A record 로 등록
  name         = google_sql_database_instance.producer.dns_name
  managed_zone = google_dns_managed_zone.psc_sql.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.psc_endpoint.address]
}
