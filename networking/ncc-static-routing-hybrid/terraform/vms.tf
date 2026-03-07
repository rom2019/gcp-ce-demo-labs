################################################################################
# vms.tf
# 테스트 VM
#   sim-onprem-vm      192.168.1.x  on-prem 시뮬레이션
#   transit-hub-vm     10.10.1.x    Hub Layer
#   workload-test1-vm  10.20.1.x    Spoke Layer
#
# External IP 없음 - IAP SSH 사용
################################################################################

data "google_compute_image" "debian" {
  family  = "debian-11"
  project = "debian-cloud"
}

resource "google_compute_instance" "sim_onprem" {
  name         = "sim-onprem-vm"
  machine_type = "e2-micro"
  zone         = var.zone
  description  = "[Simulation] On-premises host"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.sim_onprem.id
  }

  metadata = { enable-oslogin = "TRUE" }
  tags     = ["sim-onprem"]
}

resource "google_compute_instance" "transit_hub" {
  name         = "transit-hub-vm"
  machine_type = "e2-micro"
  zone         = var.zone
  description  = "[Hub Layer] Transit hub VM"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.transit_hub.id
  }

  metadata = { enable-oslogin = "TRUE" }
  tags     = ["transit-hub"]
}

resource "google_compute_instance" "workload_test1" {
  name         = "workload-test1-vm"
  machine_type = "e2-micro"
  zone         = var.zone
  description  = "[Spoke Layer] Test workload VM"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.workload_test1.id
  }

  metadata = { enable-oslogin = "TRUE" }
  tags     = ["workload-test1"]
}


