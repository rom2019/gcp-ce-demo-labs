# ============================================================
# [05] Consumer VMs
# ============================================================
# 테스트 시나리오:
#
#   [Consumer → Producer]
#   consumer-vm-a → curl http://<producer-nic1-ip>   → nginx 응답
#   consumer-vm-b → curl http://<producer-nic2-ip>   → nginx 응답
#
#   [Producer → Consumer] (양방향 확인)
#   producer-vm → ping <consumer-vm-a-ip>
#   producer-vm → ping <consumer-vm-b-ip>
#
# Producer NIC IP 확인:
#   GCP Console > Compute Engine > producer-vm > Network interfaces
#   또는: terraform output producer_nic_ips
# ============================================================

# Consumer VM - A
resource "google_compute_instance" "consumer_a" {
  name         = "consumer-a-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.consumer_a.id
    subnetwork = google_compute_subnetwork.consumer_a.id
  }

  tags = ["iap-ssh"]

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_project_organization_policy.shielded_vm,
  ]
}

# Consumer VM - B
resource "google_compute_instance" "consumer_b" {
  name         = "consumer-b-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.consumer_b.id
    subnetwork = google_compute_subnetwork.consumer_b.id
  }

  tags = ["iap-ssh"]

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_project_organization_policy.shielded_vm,
  ]
}
