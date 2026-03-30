# ============================================================
# [03] Private DNS Zone
# ============================================================
# PSC for Google APIs 에서 DNS 설정이 핵심
#
# VM 이 storage.googleapis.com 을 조회하면:
#   1. VPC 내 Cloud DNS 가 Private Zone 을 먼저 확인
#   2. Private Zone 의 A 레코드: *.googleapis.com → PSC endpoint IP
#   3. 트래픽이 인터넷이 아닌 PSC 터널로 라우팅됨
#
# no_automate_dns_zone = true 로 설정했으므로 직접 DNS 관리
#
# Console 확인: Network services > Cloud DNS
# ============================================================

# googleapis.com Private DNS Zone
resource "google_dns_managed_zone" "googleapis" {
  name        = "googleapis-com"
  dns_name    = "googleapis.com."
  description = "PSC Google APIs private zone - *.googleapis.com → PSC endpoint IP"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }

  depends_on = [google_project_service.apis]
}

# Wildcard A record: *.googleapis.com → PSC endpoint IP
# storage.googleapis.com, bigquery.googleapis.com 등 모든 서브도메인 커버
resource "google_dns_record_set" "googleapis_wildcard" {
  name         = "*.googleapis.com."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis.name
  rrdatas      = [google_compute_global_address.psc_endpoint.address]
}

# Root A record: googleapis.com → PSC endpoint IP
resource "google_dns_record_set" "googleapis_root" {
  name         = "googleapis.com."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis.name
  rrdatas      = [google_compute_global_address.psc_endpoint.address]
}
