# ============================================================
# [04] Producer Service Attachment  [Phase 2]
# ============================================================
# ilb_forwarding_rule_name 변수가 설정된 경우에만 생성 (count)
#
# Console 확인: Private Service Connect > Published services
# ============================================================

resource "google_compute_service_attachment" "producer_api" {
  count = var.ilb_forwarding_rule_name != "" ? 1 : 0

  name        = "producer-api-service-attachment"
  region      = var.region
  description = "PSC Service Attachment for REST API on GKE"

  # GKE 가 자동 생성한 L4 ILB forwarding rule (variables.tf 의 ilb_forwarding_rule_name 으로 전달)
  target_service = "projects/${var.project_id}/regions/${var.region}/forwardingRules/${var.ilb_forwarding_rule_name}"

  nat_subnets = [google_compute_subnetwork.producer_psc_nat.id]

  # ACCEPT_AUTOMATIC: 모든 Consumer 자동 승인 (학습용)
  # 프로덕션에서는 ACCEPT_MANUAL + consumer_accept_lists 로 접근 제어
  connection_preference = "ACCEPT_AUTOMATIC"

  enable_proxy_protocol = false
}
