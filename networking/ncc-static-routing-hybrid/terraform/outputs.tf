################################################################################
# outputs.tf
################################################################################

output "vm_ips" {
  description = "VM Internal IPs"
  value = {
    sim_onprem     = google_compute_instance.sim_onprem.network_interface[0].network_ip
    transit_hub    = google_compute_instance.transit_hub.network_interface[0].network_ip
    workload_test1 = google_compute_instance.workload_test1.network_interface[0].network_ip
  }
}

output "classic_vpn_external_ips" {
  description = "Classic VPN Gateway External IPs"
  value = {
    sim_onprem = google_compute_address.sim_onprem_classic_vpn_ip.address
    edge       = google_compute_address.edge_classic_vpn_ip.address
  }
}

output "ncc_hub_id" {
  description = "NCC Hub ID"
  value       = google_network_connectivity_hub.main.id
}

output "ping_test_commands" {
  description = "검증용 ping 명령어"
  value       = <<-EOT

    # 1. sim-onprem → workload-test1 (핵심 데모 경로)
    gcloud compute ssh sim-onprem-vm --zone=${var.zone} --tunnel-through-iap \
      -- ping -c 4 ${google_compute_instance.workload_test1.network_interface[0].network_ip}

    # 2. workload-test1 → sim-onprem
    gcloud compute ssh workload-test1-vm --zone=${var.zone} --tunnel-through-iap \
      -- ping -c 4 ${google_compute_instance.sim_onprem.network_interface[0].network_ip}

    # 3. workload-test1 → transit-hub
    gcloud compute ssh workload-test1-vm --zone=${var.zone} --tunnel-through-iap \
      -- ping -c 4 ${google_compute_instance.transit_hub.network_interface[0].network_ip}

  EOT
}
