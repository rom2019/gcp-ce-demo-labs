# =============================================================================
# Consumer : VPC + PSC Endpoint (Forwarding Rule)
# =============================================================================
# 핵심 설정:
#   load_balancing_scheme = ""
#     → 일반 Forwarding Rule 과 PSC Endpoint 를 구분하는 유일한 차이.
#       빈 문자열이어야 PSC Endpoint 로 동작합니다.
#
#   target = ...psc_service_attachment_link
#     → psc-01 은 Cloud SQL 이 자동 생성한 URI 를 직접 참조합니다.
#       psc-02 는 직접 만든 google_compute_service_attachment.id 를 참조합니다.
# =============================================================================

# -----------------------------------------------------------------------------
# Consumer VPC
# -----------------------------------------------------------------------------

resource "google_compute_network" "consumer" {
  provider                = google.consumer
  name                    = "psc-01-consumer-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.consumer_compute]
}

resource "google_compute_subnetwork" "consumer" {
  provider      = google.consumer
  name          = "psc-01-consumer-subnet"
  network       = google_compute_network.consumer.id
  region        = var.region
  ip_cidr_range = "10.10.0.0/24"
}

# -----------------------------------------------------------------------------
# PSC Endpoint
# -----------------------------------------------------------------------------

# PSC Endpoint 에 할당할 고정 내부 IP
resource "google_compute_address" "psc_endpoint" {
  provider     = google.consumer
  name         = "psc-01-endpoint-ip"
  region       = var.region
  subnetwork   = google_compute_subnetwork.consumer.id
  address_type = "INTERNAL"
}

# PSC Endpoint (= Forwarding Rule)
resource "google_compute_forwarding_rule" "psc_endpoint" {
  provider = google.consumer
  name     = "psc-01-endpoint"
  region   = var.region

  # PSC Endpoint 는 load_balancing_scheme 을 반드시 "" 으로 설정
  load_balancing_scheme = ""

  # Cloud SQL 이 자동 생성한 Service Attachment URI 를 target 으로 지정
  target = google_sql_database_instance.producer.psc_service_attachment_link

  network    = google_compute_network.consumer.id
  ip_address = google_compute_address.psc_endpoint.id
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "psc_endpoint_ip" {
  description = <<-EOT
    PSC Endpoint 에 할당된 내부 IP 주소.
    dns.tf 의 A record 값으로 자동 참조됩니다.
    클라이언트는 이 IP 또는 DNS hostname 으로 Cloud SQL 에 접근합니다.
  EOT
  value       = google_compute_address.psc_endpoint.address
}
