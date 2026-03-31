# ============================================================
# [03] Private DNS — restricted.googleapis.com
# ============================================================
# psc-03 (all-apis) 와의 DNS 차이:
#
#   psc-03:   *.googleapis.com → PSC IP  (직접 A 레코드)
#   psc-03b:  *.googleapis.com
#               → CNAME → restricted.googleapis.com
#               → A record → PSC IP
#
# CNAME 방식을 사용하면:
#   - 클라이언트가 restricted.googleapis.com 을 경유함을 명시적으로 표현
#   - VPC-SC 적용 엔드포인트임을 DNS 레벨에서 확인 가능
#
# Console 확인: Network services > Cloud DNS
# ============================================================

resource "google_dns_managed_zone" "googleapis" {
  name        = "googleapis-com"
  dns_name    = "googleapis.com."
  description = "PSC vpc-sc private zone - storage → restricted.googleapis.com → PSC IP"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }

  depends_on = [google_project_service.apis]
}

# restricted.googleapis.com A record → PSC endpoint IP
# vpc-sc 번들의 실제 엔드포인트
resource "google_dns_record_set" "restricted" {
  name         = "restricted.googleapis.com."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis.name
  rrdatas      = [google_compute_global_address.psc_endpoint.address]
}

# *.googleapis.com CNAME → restricted.googleapis.com
# storage.googleapis.com 포함 모든 서브도메인 커버
resource "google_dns_record_set" "wildcard" {
  name         = "*.googleapis.com."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis.name
  rrdatas      = ["restricted.googleapis.com."]
}
