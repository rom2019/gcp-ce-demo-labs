# ============================================================
# [04] Producer Service Attachment
# ============================================================
# Service Attachment = PSC의 핵심 Producer 측 리소스
#
# 역할:
#   - ILB(forwarding rule)를 PSC로 노출(publish)
#   - Consumer가 PSC endpoint를 만들 때 이 attachment URI를 타겟으로 지정
#
# 흐름:
#   Consumer PSC Endpoint(FR) → Service Attachment → ILB(FR) → GKE Pod
#
# Console 확인: Private Service Connect > Published services
# ============================================================

resource "google_compute_service_attachment" "producer_api" {
  name        = "producer-api-service-attachment"
  region      = var.region
  description = "PSC Service Attachment for REST API on GKE"

  # 연결 대상: 04-producer-ilb.tf 에서 Terraform 으로 직접 생성한 L4 ILB forwarding rule
  target_service = google_compute_forwarding_rule.api_ilb.id

  # PSC 전용 NAT 서브넷 (01에서 생성)
  # Consumer 트래픽이 이 서브넷 IP를 SNAT 주소로 사용
  nat_subnets = [google_compute_subnetwork.producer_psc_nat.id]

  # ACCEPT_AUTOMATIC: 모든 Consumer의 연결 요청을 자동 승인 (학습용)
  # 프로덕션에서는 ACCEPT_MANUAL + consumer_accept_lists 로 접근 제어
  connection_preference = "ACCEPT_AUTOMATIC"

  # Proxy Protocol 비활성화 (L4 ILB 사용 시 일반적으로 false)
  # true 로 설정하면 Consumer IP 정보를 Proxy Protocol 헤더로 전달 (HTTP/TCP 앱에서 원본 IP 확인 가능)
  enable_proxy_protocol = false

  depends_on = [google_compute_forwarding_rule.api_ilb]
}
