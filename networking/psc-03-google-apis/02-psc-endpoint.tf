# ============================================================
# [02] PSC Endpoint for Google APIs
# ============================================================
# psc-02 와의 핵심 차이점:
#   - Regional → Global (address, forwarding rule 모두 global)
#   - target: Service Attachment URI → "all-apis" (고정 문자열)
#   - 별도의 Producer 구성 불필요 (Google이 관리)
#
# Console 확인: Private Service Connect > Connected endpoints
# ============================================================

# PSC Endpoint IP (Global Internal Address)
# - address_type = "INTERNAL": VPC 내부 IP
# - purpose = "PRIVATE_SERVICE_CONNECT": PSC 전용
# - network 레벨 주소 (subnet 에 속하지 않음)
resource "google_compute_global_address" "psc_endpoint" {
  name         = "psc-google-apis-ip"
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = google_compute_network.vpc.id

  # PSC Google APIs endpoint 는 subnet 에 속하지 않는 VPC 레벨 IP 를 사용
  # 기존 subnet(10.0.0.0/24) 과 겹치지 않는 IP 를 명시적으로 지정
  address = "10.0.1.2"

  depends_on = [google_project_service.apis]
}

# PSC Endpoint Forwarding Rule (Global)
# - target = "all-apis": 모든 Google API 에 대한 PSC 번들
#   (storage, bigquery, pubsub 등 전체 포함)
# - load_balancing_scheme = "": psc-02 와 동일하게 빈 문자열
# - no_automate_dns_zone = true: DNS 를 03-dns.tf 에서 직접 관리
resource "google_compute_global_forwarding_rule" "google_apis" {
  # PSC Google APIs forwarding rule 이름 규칙: 소문자+숫자만, 하이픈 불가, 1-20자
  name                  = "pscgoogleapis"
  target                = "all-apis"
  network               = google_compute_network.vpc.id
  ip_address            = google_compute_global_address.psc_endpoint.id
  load_balancing_scheme = ""
  no_automate_dns_zone  = true
}
