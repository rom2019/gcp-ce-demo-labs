# ============================================================
# [02] Consumer VPC-A + Network Attachment
# ============================================================
# Network Attachment = "NIC 꽂을 구멍"
# Producer VM 이 이 attachment 를 통해 Consumer VPC-A 에 NIC 를 생성
#
# 핵심 리소스: google_compute_network_attachment
#   - subnetworks: Producer NIC 에 IP 를 할당할 서브넷 지정
#   - connection_preference: ACCEPT_AUTOMATIC (자동 승인, 학습용)
#
# Console 확인:
#   VPC network > Network attachments
# ============================================================

resource "google_compute_network" "consumer_a" {
  name                    = "consumer-a-vpc"
  auto_create_subnetworks = false

  depends_on = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "consumer_a" {
  name          = "consumer-a-subnet"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.consumer_a.id
}

# Network Attachment
# Producer VM 의 nic1 이 이 attachment 를 통해 consumer-a-subnet 의 IP 를 할당받음
resource "google_compute_network_attachment" "consumer_a" {
  name        = "consumer-a-network-attachment"
  region      = var.region
  description = "Consumer VPC-A 의 PSC Interface 진입점"

  # Producer NIC 에 IP 를 할당할 서브넷
  subnetworks = [google_compute_subnetwork.consumer_a.id]

  # ACCEPT_AUTOMATIC: 연결 요청 자동 승인 (학습용)
  # ACCEPT_MANUAL: producer_accept_lists 로 수동 승인 (프로덕션 권장)
  connection_preference = "ACCEPT_AUTOMATIC"
}

# Consumer A → Producer NIC 트래픽 허용
resource "google_compute_firewall" "consumer_a_allow_producer" {
  name    = "consumer-a-allow-producer"
  network = google_compute_network.consumer_a.id

  allow {
    protocol = "all"
  }

  source_ranges = ["10.0.0.0/24"]
}

# IAP SSH (Consumer VM 접속용)
resource "google_compute_firewall" "consumer_a_iap_ssh" {
  name    = "consumer-a-allow-iap-ssh"
  network = google_compute_network.consumer_a.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}
