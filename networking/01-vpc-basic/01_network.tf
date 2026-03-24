# 01_network.tf

# ── VPC ──────────────────────────────────────────────
resource "google_compute_network" "main" {
  name                    = "vpc-network-lab"
  auto_create_subnetworks = false # 수동으로 서브넷 제어
  routing_mode            = "GLOBAL"
}

# ── 서브넷 3개 ────────────────────────────────────────

# Public: Web tier (External LB 백엔드 VM)
resource "google_compute_subnetwork" "public" {
  name                     = "subnet-public"
  ip_cidr_range            = var.subnets["public"]
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

# Private: App tier (Internal LB 백엔드 VM)
resource "google_compute_subnetwork" "private" {
  name                     = "subnet-private"
  ip_cidr_range            = var.subnets["private"]
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

# Data: Analytics VM 배치 + PGA(BigQuery) 접근용
resource "google_compute_subnetwork" "data" {
  name                     = "subnet-data"
  ip_cidr_range            = var.subnets["data"]
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true # PGA: BigQuery 접근용
}

# ── Cloud Router (NAT용) ──────────────────────────────
resource "google_compute_router" "main" {
  name    = "router-network-lab"
  region  = var.region
  network = google_compute_network.main.id
}