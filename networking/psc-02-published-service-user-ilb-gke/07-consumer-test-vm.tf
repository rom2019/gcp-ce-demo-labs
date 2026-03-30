# ============================================================
# [07] Consumer Test VM
# ============================================================
# 목적: PSC Endpoint IP 로 curl 테스트
#
# 접속 방법 (외부 IP 없음):
#   gcloud compute ssh consumer-test-vm \
#     --tunnel-through-iap \
#     --project=<project_id> \
#     --zone=asia-northeast3-a
#
# 테스트:
#   curl http://<psc_endpoint_ip>
#
# Console 확인: Compute Engine > VM instances
# ============================================================

resource "google_compute_instance" "test_vm" {
  name         = "consumer-test-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.consumer.id
    subnetwork = google_compute_subnetwork.consumer.id
    # 외부 IP 없음 → IAP 를 통해서만 SSH 접근
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  tags = ["iap-ssh"]

  metadata = {
    enable-oslogin = "TRUE"
  }
}

# IAP SSH 허용 방화벽 규칙
# IAP IP 대역: 35.235.240.0/20
resource "google_compute_firewall" "consumer_iap_ssh" {
  name    = "consumer-allow-iap-ssh"
  network = google_compute_network.consumer.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]
}
