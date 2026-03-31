# ============================================================
# [04] Producer VM (Multi-homed)
# ============================================================
# 이 예제의 핵심: Producer VM 이 NIC 3개를 가짐
#
#   nic0: producer-vpc  (primary, 외부 트래픽/IAP SSH)
#   nic1: consumer-a-vpc (network_attachment 로 꽂힘)
#   nic2: consumer-b-vpc (network_attachment 로 꽂힘)
#
# nic1/nic2 의 IP 는 각 Consumer 서브넷에서 자동 할당됨
# → Consumer VM 은 이 IP 로 직접 통신 가능 (양방향 L3)
#
# Console 확인:
#   Compute Engine > VM instances > producer-vm > Network interfaces
# ============================================================

resource "google_compute_instance" "producer" {
  name         = "producer-vm"
  machine_type = "e2-standard-4"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  # nic0: Producer VPC (primary)
  # 외부 트래픽과 IAP SSH 는 이 인터페이스를 통함
  network_interface {
    network    = google_compute_network.producer.id
    subnetwork = google_compute_subnetwork.producer.id
  }

  # nic1: Consumer VPC-A (PSC Interface)
  # network_attachment 를 통해 consumer-a-subnet 의 IP 자동 할당
  network_interface {
    network_attachment = google_compute_network_attachment.consumer_a.id
  }

  # nic2: Consumer VPC-B (PSC Interface)
  # network_attachment 를 통해 consumer-b-subnet 의 IP 자동 할당
  network_interface {
    network_attachment = google_compute_network_attachment.consumer_b.id
  }

  # nginx 설치: Consumer VM 에서 curl 로 연결 테스트
  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    echo "Hello from Producer VM (PSC Interface)" > /var/www/html/index.html
    systemctl start nginx
  EOF

  tags = ["producer"]

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_compute_network_attachment.consumer_a,
    google_compute_network_attachment.consumer_b,
    google_project_organization_policy.shielded_vm,
  ]
}
