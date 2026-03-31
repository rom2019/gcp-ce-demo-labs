# ============================================================
# [02] PSC Endpoint — vpc-sc 번들
# ============================================================
# psc-03 (all-apis) 와의 핵심 차이:
#
#   all-apis  → VPC-SC 우회 가능 (보안 허점)
#   vpc-sc    → VPC-SC 정책 강제 적용 (restricted.googleapis.com)
#
# vpc-sc 번들을 사용하면 트래픽이 반드시 VPC-SC 검사를 통과해야 함
# → Access Level 미충족 시 403 반환
#
# Console 확인: Private Service Connect > Connected endpoints
# ============================================================

resource "google_compute_global_address" "psc_endpoint" {
  name         = "psc-vpcsc-ip"
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = google_compute_network.vpc.id
  address      = "10.0.1.2"

  depends_on = [google_project_service.apis]
}

resource "google_compute_global_forwarding_rule" "google_apis" {
  # PSC Google APIs forwarding rule 이름 규칙: 소문자+숫자만, 하이픈 불가, 1-20자
  name                  = "pscvpcsc"
  target                = "vpc-sc"
  network               = google_compute_network.vpc.id
  ip_address            = google_compute_global_address.psc_endpoint.id
  load_balancing_scheme = ""
  no_automate_dns_zone  = true
}
