# 02_firewall.tf

locals {
  vpc_name = google_compute_network.main.name # "vpc-network-lab"
}

# ── 기본 차단 (명시적 deny-all) ──────────────────────
# GCP 기본값이 이미 deny-all 이지만, 명시적으로 선언해서
# "의도적으로 막았다"는 것을 코드로 표현
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "${local.vpc_name}-deny-all-ingress"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 65534 # 가장 낮은 우선순위 (숫자 클수록 낮음)

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# ── IAP → 모든 VM SSH ────────────────────────────────
# IAP 터널 IP 범위(35.235.240.0/20)에서 SSH 허용
# Bastion 포함 모든 VM에 적용 (tag 없이 전체)
resource "google_compute_firewall" "allow_iap_ssh" {
  name      = "${local.vpc_name}-allow-iap-ssh"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.gcp_ip_ranges["iap"]
}

# ── External LB → Frontend VM ───────────────────────
# GCP LB 헬스체크 IP + 실제 트래픽 IP 허용
# tag: frontend-vm 이 붙은 VM만 허용
resource "google_compute_firewall" "allow_lb_to_frontend" {
  name      = "${local.vpc_name}-allow-lb-to-frontend"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # GCP LB + 헬스체크 IP 범위
  source_ranges = var.gcp_ip_ranges["load_balancer"]

  target_tags = ["frontend-vm"] # 이 tag 달린 VM만 적용
}

# ── Frontend VM → Internal LB (App VM) ──────────────
# subnet-public → subnet-private 통신 허용
# tag: app-vm 이 붙은 VM만 허용
resource "google_compute_firewall" "allow_frontend_to_app" {
  name      = "${local.vpc_name}-allow-frontend-to-app"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["8080"] # FastAPI 포트
  }

  source_ranges = [var.subnets["public"]]
  target_tags   = ["app-vm"]
}

# ── Proxy 서브넷 → App VM ─────────────────────────────
# Internal LB Proxy 서브넷에서 App VM 으로의 트래픽 허용
resource "google_compute_firewall" "allow_proxy_to_app" {
  name      = "${local.vpc_name}-ingress-proxy-app"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = [var.subnets["proxy"]] # 10.0.4.0/24
  target_tags   = ["app-vm"]
}

# ── Internal LB 헬스체크 → App VM ───────────────────
# Internal LB 헬스체크도 동일한 GCP IP 범위 사용
resource "google_compute_firewall" "allow_healthcheck_to_app" {
  name      = "${local.vpc_name}-allow-healthcheck-to-app"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = var.gcp_ip_ranges["load_balancer"] # 변경

  target_tags = ["app-vm"]
}

# ── App VM → Cloud SQL / Redis ───────────────────────
# subnet-private → PSA 범위 통신 허용
resource "google_compute_firewall" "allow_app_to_data" {
  name      = "${local.vpc_name}-allow-app-to-data"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports = [
      "5432", # PostgreSQL
      "6379", # Redis
    ]
  }

  source_ranges = [var.subnets["private"]]
  target_tags   = ["data-vm"]
}

# ── Analytics VM → 아웃바운드 (Cloud NAT 경유) ────────
# EGRESS 는 GCP 기본값이 allow-all 이라 별도 규칙 불필요
# Cloud NAT 설정으로 제어 (03_nat.tf 에서)