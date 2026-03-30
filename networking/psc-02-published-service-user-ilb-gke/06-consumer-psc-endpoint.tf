# ============================================================
# [06] Consumer PSC Endpoint
# ============================================================
# PSC Endpoint = Consumer 측 핵심 리소스
#
# 구현체: google_compute_forwarding_rule (일반 FR과 동일한 리소스 타입!)
# 일반 FR과의 차이점:
#   - target: service attachment URI 를 지정
#   - load_balancing_scheme: "" (빈 문자열, PSC endpoint 는 LB가 아님)
#   - network/subnetwork: consumer VPC 내 위치
#
# 흐름:
#   Test VM → PSC Endpoint IP → [PSC 터널] → Service Attachment → ILB → Pod
#
# Console 확인: Private Service Connect > Connected endpoints
# ============================================================

# PSC Endpoint에 할당할 내부 고정 IP
resource "google_compute_address" "psc_endpoint" {
  name         = "psc-endpoint-ip"
  region       = var.region
  subnetwork   = google_compute_subnetwork.consumer.id
  address_type = "INTERNAL"
}

# PSC Endpoint (Consumer측 Forwarding Rule)
resource "google_compute_forwarding_rule" "psc_endpoint" {
  name   = "psc-endpoint"
  region = var.region

  # target 에 Service Attachment URI 지정 → 이것이 PSC endpoint 를 일반 FR과 구분짓는 핵심
  target = google_compute_service_attachment.producer_api.id

  network    = google_compute_network.consumer.id
  subnetwork = google_compute_subnetwork.consumer.id

  # 고정 IP 사용 (지정하지 않으면 ephemeral IP 자동 할당)
  ip_address = google_compute_address.psc_endpoint.id

  # PSC endpoint 는 load_balancing_scheme 을 빈 문자열로 지정
  load_balancing_scheme = ""
}
