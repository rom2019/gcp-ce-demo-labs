# ============================================================
# [04] Test VM
# ============================================================
# 목적: PSC endpoint 를 통한 GCS 접근 검증
#
# 테스트 방법:
#   1. DNS 확인: dig storage.googleapis.com → PSC endpoint IP 응답 확인
#   2. GCS 접근: gsutil ls 또는 curl 로 API 호출
#
# 접속: gcloud compute ssh psc-test-vm --tunnel-through-iap
#
# Console 확인: Compute Engine > VM instances
# ============================================================

# Test VM 전용 Service Account
resource "google_service_account" "test_vm" {
  account_id   = "psc-test-vm-sa"
  display_name = "PSC Test VM Service Account"
  project      = var.project_id
}

# GCS 접근 권한 (테스트용)
resource "google_project_iam_member" "test_vm_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.test_vm.email}"
}

resource "google_compute_instance" "test_vm" {
  name         = "psc-test-vm"
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
    # 외부 IP 없음 → IAP 로만 SSH 접근
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

# IAP SSH 허용 방화벽
resource "google_compute_firewall" "iap_ssh" {
  name    = "psc-google-apis-allow-iap-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]
}
