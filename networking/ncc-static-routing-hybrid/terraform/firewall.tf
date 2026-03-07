################################################################################
# firewall.tf
# 데모 환경용 방화벽 규칙
# 운영 환경에서는 최소 권한 원칙 적용 필요
################################################################################

locals {
  vpcs = {
    "sim-onprem"     = google_compute_network.sim_onprem.name
    "edge"           = google_compute_network.edge.name
    "transit-hub"    = google_compute_network.transit_hub.name
    "workload-test1" = google_compute_network.workload_test1.name
  }
}

# RFC1918 내부 통신 전체 허용
resource "google_compute_firewall" "allow_internal" {
  for_each = local.vpcs

  name    = "${each.key}-allow-internal"
  network = each.value

  allow { protocol = "all" }

  source_ranges = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
  ]

  description = "Allow all RFC1918 internal traffic"
}

# ICMP 허용 (ping 테스트)
resource "google_compute_firewall" "allow_icmp" {
  for_each = local.vpcs

  name    = "${each.key}-allow-icmp"
  network = each.value

  allow { protocol = "icmp" }

  source_ranges = ["0.0.0.0/0"]
  description   = "Allow ICMP for connectivity testing"
}

# IAP SSH 허용 (External IP 없이 SSH 접속)
resource "google_compute_firewall" "allow_iap_ssh" {
  for_each = local.vpcs

  name    = "${each.key}-allow-iap-ssh"
  network = each.value

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  description   = "Allow SSH via Identity-Aware Proxy"
}
