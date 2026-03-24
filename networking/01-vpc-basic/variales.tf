# variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-northeast3"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "asia-northeast3-a"
}

# ── 네트워크 CIDR ──────────────────────────────────────
variable "subnets" {
  description = "서브넷 CIDR 범위"
  type        = map(string)
  default = {
    public  = "10.0.1.0/24"
    private = "10.0.2.0/24"
    data    = "10.0.3.0/24"
    psa     = "10.100.0.0/16"
    proxy   = "10.0.4.0/24" # Internal LB Proxy 서브넷 추가
  }
}

# ── GCP 고정 IP 범위 ───────────────────────────────────
variable "gcp_ip_ranges" {
  description = "GCP 서비스별 고정 IP 범위"
  type        = map(list(string))
  default = {
    load_balancer = ["130.211.0.0/22", "35.191.0.0/16"]
    iap           = ["35.235.240.0/20"]
  }
}

# ── DB ────────────────────────────────────────────────
variable "db_password" {
  description = "Cloud SQL root password"
  type        = string
  sensitive   = true
}


# variables.tf 에 추가

variable "web_domain" {
  description = "External LB SSL 인증서용 도메인"
  type        = string
  default     = "vpc-basic.gomdols.monster" # 실제 도메인으로 교체
}

variable "internal_lb_ip" {
  description = "Internal LB 고정 내부 IP"
  type        = string
  default     = "10.0.2.100" # subnet-private 범위 안의 IP
}