# outputs.tf

output "web_lb_ip" {
  description = "External LB 공인 IP"
  value       = google_compute_global_address.web_lb_ip.address
}
