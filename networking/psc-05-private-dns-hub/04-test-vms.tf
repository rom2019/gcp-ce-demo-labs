# ============================================================
# [04] Test VMs
# ============================================================
# 테스트 시나리오:
#
#   [DNS 해석 확인]
#   dev-vm  → nslookup storage.googleapis.com → 10.0.1.2 (PSC IP)
#   prod-vm → nslookup storage.googleapis.com → 10.0.1.2 (PSC IP)
#   hub-vm  → nslookup storage.googleapis.com → 10.0.1.2 (PSC IP)
#
#   [DNS Hub 효과 확인]
#   hub-vpc 의 DNS zone 만 존재, spoke 는 peering 으로 위임받음
#   → zone 변경 시 모든 spoke 에 자동 반영
#
# startup script: dnsutils 설치 (nslookup 명령어 사용)
# ============================================================

# Hub VM
resource "google_compute_instance" "hub_vm" {
  name         = "hub-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.hub.id
    subnetwork = google_compute_subnetwork.hub.id
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y dnsutils
  EOF

  tags = ["iap-ssh"]

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_project_organization_policy.shielded_vm,
    google_compute_router_nat.hub,
  ]
}

# Dev VM
resource "google_compute_instance" "dev_vm" {
  name         = "dev-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.dev.id
    subnetwork = google_compute_subnetwork.dev.id
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y dnsutils
  EOF

  tags = ["iap-ssh"]

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_project_organization_policy.shielded_vm,
    google_compute_router_nat.dev,
    google_dns_managed_zone.dev_googleapis_peering,
  ]
}

# Prod VM
resource "google_compute_instance" "prod_vm" {
  name         = "prod-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.prod.id
    subnetwork = google_compute_subnetwork.prod.id
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y dnsutils
  EOF

  tags = ["iap-ssh"]

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_project_organization_policy.shielded_vm,
    google_compute_router_nat.prod,
    google_dns_managed_zone.prod_googleapis_peering,
  ]
}
