# ============================================================
# [06] Test VM
# ============================================================
# 테스트 시나리오:
#
#   [경계 안] VM (SA: psc-test-vm-sa) → PSC endpoint → GCS
#     → Access Level 충족 → 200 OK
#
#   [경계 밖] 로컬 머신 → storage.googleapis.com → GCS
#     → Access Level 미충족 → 403 ACCESS_DENIED
#
# 접속: gcloud compute ssh psc-vpcsc-test-vm --tunnel-through-iap
# Console 확인: Compute Engine > VM instances
# ============================================================

resource "google_service_account" "test_vm" {
  account_id   = "psc-test-vm-sa"
  display_name = "PSC VPC-SC Test VM Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "test_vm_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.test_vm.email}"
}

resource "google_compute_instance" "test_vm" {
  name         = "psc-vpcsc-test-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
  }

  service_account {
    email  = google_service_account.test_vm.email
    scopes = ["cloud-platform"]
  }

  tags = ["iap-ssh"]

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_project_service.apis,
    google_project_organization_policy.shielded_vm,
  ]
}

resource "google_compute_firewall" "iap_ssh" {
  name    = "psc-vpcsc-allow-iap-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]
}
