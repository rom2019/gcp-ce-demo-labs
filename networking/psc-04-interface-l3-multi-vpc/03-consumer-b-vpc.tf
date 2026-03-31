# ============================================================
# [03] Consumer VPC-B + Network Attachment
# ============================================================
# Consumer VPC-A 와 동일한 구조 (다른 IP 대역)
# Producer VM 의 nic2 가 이 attachment 를 통해 연결
#
# Console 확인:
#   VPC network > Network attachments
# ============================================================

resource "google_compute_network" "consumer_b" {
  name                    = "consumer-b-vpc"
  auto_create_subnetworks = false

  depends_on = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "consumer_b" {
  name          = "consumer-b-subnet"
  ip_cidr_range = "10.2.0.0/24"
  region        = var.region
  network       = google_compute_network.consumer_b.id
}

resource "google_compute_network_attachment" "consumer_b" {
  name        = "consumer-b-network-attachment"
  region      = var.region
  description = "Consumer VPC-B 의 PSC Interface 진입점"

  subnetworks           = [google_compute_subnetwork.consumer_b.id]
  connection_preference = "ACCEPT_AUTOMATIC"
}

resource "google_compute_firewall" "consumer_b_allow_producer" {
  name    = "consumer-b-allow-producer"
  network = google_compute_network.consumer_b.id

  allow {
    protocol = "all"
  }

  # 10.0.0.0/24: producer primary NIC → consumer (양방향)
  # 10.2.0.0/24: consumer-b-vm → producer nic2 (같은 서브넷 내 통신)
  source_ranges = ["10.0.0.0/24", "10.2.0.0/24"]
}

resource "google_compute_firewall" "consumer_b_iap_ssh" {
  name    = "consumer-b-allow-iap-ssh"
  network = google_compute_network.consumer_b.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}
