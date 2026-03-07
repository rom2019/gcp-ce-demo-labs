################################################################################
# variables.tf
#
# [계층 구조]
#   On-prem Simulation : sim-onprem-vpc    192.168.1.0/24
#   Edge Layer         : edge-vpc          172.16.1.0/24
#   Hub Layer          : transit-hub-vpc   10.10.1.0/24
#   Spoke Layer        : workload-test1-vpc 10.20.1.0/24
#                        workload-prod1-vpc  10.30.1.0/24  (확장 예시)
################################################################################

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast3"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "asia-northeast3-a"
}

# CIDR 설계
variable "sim_onprem_cidr" {
  description = "Simulated on-premises CIDR"
  type        = string
  default     = "192.168.1.0/24"
}

variable "edge_cidr" {
  description = "Edge VPC CIDR (Classic VPN termination)"
  type        = string
  default     = "172.16.1.0/24"
}

variable "transit_hub_cidr" {
  description = "Transit Hub VPC CIDR (NCC hub layer)"
  type        = string
  default     = "10.10.1.0/24"
}

variable "workload_test1_cidr" {
  description = "Workload Test1 VPC CIDR"
  type        = string
  default     = "10.20.1.0/24"
}

# VPN PSK
variable "classic_vpn_psk" {
  description = "Classic VPN Pre-Shared Key"
  type        = string
  default     = "demo-psk-2024"
  sensitive   = true
}

variable "ha_vpn_psk" {
  description = "HA VPN Pre-Shared Key"
  type        = string
  default     = "ha-psk-2024"
  sensitive   = true
}
