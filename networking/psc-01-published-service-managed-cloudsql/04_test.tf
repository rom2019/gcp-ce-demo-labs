# =============================================================================
# 테스트 환경 : Consumer VPC 내 클라이언트 VM
# =============================================================================
# 목적:
#   PSC Endpoint 를 통해 Cloud SQL 에 실제로 접근할 수 있는지 검증합니다.
#   이 파일의 리소스는 학습/테스트 용도이며 운영 환경에서는 제거합니다.
#
# 네트워크 흐름:
#   [apt-get]  test-vm → Cloud NAT → 인터넷 (패키지 설치)
#   [nc/dig]   test-vm → PSC Endpoint IP → PSC 터널 → Cloud SQL
#
# Cloud NAT 역할:
#   Public IP 없는 VM 의 outbound 인터넷 트래픽을 허용합니다.
#   apt-get 패키지 설치에만 사용되며, Cloud SQL 접근은 PSC 터널을 사용합니다.
# =============================================================================

# -----------------------------------------------------------------------------
# Cloud NAT : VM outbound 인터넷 접근 (apt-get 패키지 설치용)
# -----------------------------------------------------------------------------

resource "google_compute_router" "nat_router" {
  provider = google.consumer
  name     = "psc-01-nat-router"
  region   = var.region
  network  = google_compute_network.consumer.id
}

resource "google_compute_router_nat" "nat" {
  provider                           = google.consumer
  name                               = "psc-01-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# -----------------------------------------------------------------------------
# Firewall : IAP SSH 허용
# -----------------------------------------------------------------------------

resource "google_compute_firewall" "allow_iap_ssh" {
  provider = google.consumer
  name     = "psc-01-allow-iap-ssh"
  network  = google_compute_network.consumer.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google IAP 고정 IP 대역
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["psc-test"]
}

# -----------------------------------------------------------------------------
# Firewall : PSC Endpoint 접근 허용 (egress)
# -----------------------------------------------------------------------------
# GCP 기본 egress 는 allow-all 이므로 생략 가능
# 학습 목적으로 명시적 선언

resource "google_compute_firewall" "allow_psc_egress" {
  provider  = google.consumer
  name      = "psc-01-allow-psc-egress"
  network   = google_compute_network.consumer.id
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  allow {
    protocol = "icmp"
  }

  destination_ranges = ["${google_compute_address.psc_endpoint.address}/32"]
  target_tags        = ["psc-test"]
}

# -----------------------------------------------------------------------------
# 테스트 VM
# -----------------------------------------------------------------------------
# startup-script 로 테스트 도구 자동 설치:
#   - dnsutils      : dig (DNS 해석 확인)
#   - netcat-openbsd: nc  (TCP 연결 확인)
#   - postgresql-client: psql (실제 DB 접속)

resource "google_compute_instance" "test_vm" {
  provider     = google.consumer
  name         = "psc-01-test-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["psc-test"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.consumer.id
    # access_config 없음 → 외부 IP 없음
    # outbound 인터넷은 Cloud NAT 가 처리
  }

  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      apt-get update -q
      apt-get install -y dnsutils netcat-openbsd postgresql-client
    EOF
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Cloud NAT 준비 후 VM 생성 → startup-script apt-get 정상 동작 보장
  depends_on = [
    google_compute_router_nat.nat,
    google_project_service.consumer_compute,
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "test_vm_ssh_command" {
  description = "테스트 VM SSH 접속 명령어 (IAP 터널)"
  value       = "gcloud compute ssh ${google_compute_instance.test_vm.name} --project=${var.consumer_project_id} --zone=${var.zone} --tunnel-through-iap"
}

output "test_commands" {
  description = "VM 내부에서 실행할 PSC 연결 확인 명령어 (순서대로 실행)"
  value       = <<-EOT
    # 1. DNS 해석 확인 → PSC Endpoint IP 가 반환되어야 함
    dig ${google_sql_database_instance.producer.dns_name}

    # 2. TCP 연결 확인 → "succeeded" 가 나와야 함
    nc -zv ${google_sql_database_instance.producer.dns_name} 5432

    # 3. psql 접속
    PGPASSWORD=$TF_VAR_sql_password psql "host=${google_sql_database_instance.producer.dns_name} port=5432 sslmode=require dbname=postgres user=postgres"
  EOT
}
